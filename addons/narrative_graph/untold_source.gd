@tool
extends RefCounted
## Manipulation TEXTUELLE d'un fichier .untold, par blocs de nœuds : chaque
## bloc (de « :: id » jusqu'au nœud suivant) est conservé mot pour mot, jamais
## régénéré depuis le modèle parsé. C'est ce qui permet à l'outil graphe de
## réordonner ou d'enrichir la SOURCE DE VÉRITÉ sans aucun risque de perte
## (gardes, glue, commentaires, mise en forme... intacts).

var path := ""
## Lignes avant le premier nœud (@var, commentaires d'en-tête).
var prelude: Array = []
## Ids des nœuds, dans l'ordre du fichier.
var order: Array = []
## id -> Array de lignes du bloc (ligne « :: id » incluse), verbatim.
var blocks: Dictionary = {}


func load_file(p_path: String) -> bool:
	path = p_path
	prelude = []
	order = []
	blocks = {}
	if not FileAccess.file_exists(path):
		return false
	var current := ""
	for raw_line in FileAccess.get_file_as_string(path).split("\n"):
		var line: String = raw_line.trim_suffix("\r")
		if line.strip_edges().begins_with("::"):
			current = line.strip_edges().substr(2).strip_edges()
			order.append(current)
			blocks[current] = [line]
		elif current.is_empty():
			prelude.append(line)
		else:
			blocks[current].append(line)
	return true


## Reconstruit le fichier : prélude puis blocs dans l'ordre, séparés par une
## ligne vide (seuls les blancs de fin de bloc sont normalisés).
func text() -> String:
	var chunks: Array = []
	var head := _without_trailing_blanks(prelude)
	if not head.is_empty():
		chunks.append("\n".join(PackedStringArray(head)))
	for id in order:
		chunks.append("\n".join(PackedStringArray(_without_trailing_blanks(blocks[id]))))
	return "\n\n".join(PackedStringArray(chunks)) + "\n"


func save() -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("UntoldSource: impossible d'écrire " + path)
		return false
	file.store_string(text())
	return true


## Nouvel ordre des nœuds. Les ids inconnus sont ignorés, les ids absents de
## la liste sont conservés à la fin (aucun bloc ne peut être perdu).
func reorder(new_order: Array) -> void:
	var seen: Dictionary = {}
	var result: Array = []
	for id in new_order:
		if blocks.has(id) and not seen.has(id):
			result.append(id)
			seen[id] = true
	for id in order:
		if not seen.has(id):
			result.append(id)
			seen[id] = true
	order = result


## Remplace la cible du index-ième lien sortant du nœud (même ordre que
## StoryGraph.outgoing) : seule la cible après la flèche « -> » est réécrite,
## tout le reste de la ligne (texte du choix, garde, espaces) est intact.
func set_link_target(id: String, link_index: int, new_target: String) -> bool:
	if not blocks.has(id):
		return false
	var line_i := _link_line(id, link_index)
	if line_i < 0:
		return false
	var raw: String = blocks[id][line_i]
	var arrow := raw.rfind("->")
	if arrow < 0:
		return false
	var tail := raw.substr(arrow + 2)
	var token := RegEx.create_from_string("\\S+").search(tail)
	if token == null:
		return false
	# Premier token après la flèche = la cible ; un « } » collé (saut
	# conditionnel écrit sans espace) n'en fait pas partie.
	var end := token.get_end()
	var brace := token.get_string().find("}")
	if brace >= 0:
		end = token.get_start() + brace
	blocks[id][line_i] = raw.substr(0, arrow + 2) \
			+ tail.substr(0, token.get_start()) + new_target + tail.substr(end)
	return true


## Indice de la ligne du index-ième lien sortant du bloc. Reproduit le
## classement de StoryParser : choix, saut conditionnel et saut direct,
## gardes « { ... } instruction » comprises.
func _link_line(id: String, link_index: int) -> int:
	var re_guard := RegEx.create_from_string("^\\{\\s*[^{}]+?\\s*\\}\\s*(\\S.*)$")
	var re_choice := RegEx.create_from_string("^\\*\\s*\\[.*?\\]\\s*->\\s*\\S+$")
	var re_cond := RegEx.create_from_string(
			"^\\{\\s*[A-Za-z_]\\w*\\s*==\\s*\"[^\"]*\"\\s*->\\s*\\S+\\s*\\}$")
	var count := 0
	for i in blocks[id].size():
		var line: String = str(blocks[id][i]).strip_edges()
		if line.is_empty() or line.begins_with("//") or line.begins_with("::") \
				or line.begins_with("#"):
			continue
		var mg := re_guard.search(line)
		if mg:
			line = mg.get_string(1).strip_edges()
		if re_choice.search(line) or re_cond.search(line) or line.begins_with("->"):
			if count == link_index:
				return i
			count += 1
	return -1


## Remplace la première commande « @nom(...) » du bloc par de nouveaux
## arguments (préfixe de la ligne — garde, indentation — conservé), ou
## l'ajoute en fin de bloc si le nœud n'en a pas.
func set_command(id: String, command: String, args: Array) -> bool:
	if not blocks.has(id):
		return false
	var quoted := PackedStringArray()
	for arg in args:
		quoted.append('"%s"' % arg)
	var call := "@%s(%s)" % [command, ", ".join(quoted)]
	var re := RegEx.create_from_string("@" + command + "\\(.*\\)")
	for i in blocks[id].size():
		var raw: String = blocks[id][i]
		if str(raw).strip_edges().begins_with("//"):
			continue
		var found := re.search(raw)
		if found:
			blocks[id][i] = raw.substr(0, found.get_start()) + call + raw.substr(found.get_end())
			return true
	append_instruction(id, call)
	return true


## Supprime la occurrence-ième commande « @nom(...) » du bloc — la ligne
## entière, garde éventuelle comprise. Retourne false si absente.
func remove_command(id: String, command: String, occurrence := 0) -> bool:
	if not blocks.has(id):
		return false
	var re := RegEx.create_from_string("@" + command + "\\(.*\\)")
	var count := 0
	for i in blocks[id].size():
		var raw: String = blocks[id][i]
		if str(raw).strip_edges().begins_with("//"):
			continue
		if re.search(raw):
			if count == occurrence:
				blocks[id].remove_at(i)
				return true
			count += 1
	return false


## Ajoute une ligne d'instruction à la fin du bloc d'un nœud (ex: un event
## « @illustration("...") » depuis l'inspecteur).
func append_instruction(id: String, line: String) -> void:
	if not blocks.has(id):
		push_error("UntoldSource: nœud inconnu « %s »." % id)
		return
	blocks[id] = _without_trailing_blanks(blocks[id])
	blocks[id].append(line)


static func _without_trailing_blanks(lines: Array) -> Array:
	var out := lines.duplicate()
	while not out.is_empty() and str(out.back()).strip_edges().is_empty():
		out.pop_back()
	return out
