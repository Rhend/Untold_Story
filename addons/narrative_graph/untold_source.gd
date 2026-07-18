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
## Ids déclarés plusieurs fois dans le fichier (« :: id » en double). Les blocs
## surnuméraires sont conservés sous une clé interne unique — leur ligne
## « :: id » d'origine reste verbatim dans le bloc, donc la réécriture ne perd
## RIEN — et l'outil peut avertir l'auteur (le jeu, lui, ne garde que le dernier).
var duplicate_ids: Array = []

## Puits d'historique optionnel, appelé avec (path, texte_disque_précédent)
## juste avant chaque réécriture qui CHANGE le fichier — c'est ce qui alimente
## l'annuler/rétablir de l'outil graphe sans que cette classe le connaisse.
var history_sink: Callable = Callable()

## Motifs compilés UNE fois (repérage des liens, validation d'id) — les mêmes
## motifs de ligne que StoryParser, partagés pour ne jamais diverger du parse.
static var _re_guard := RegEx.create_from_string(StoryParser.GUARD_PATTERN)
static var _re_choice := RegEx.create_from_string(StoryParser.CHOICE_PATTERN)
static var _re_cond := RegEx.create_from_string(StoryParser.COND_PATTERN)
## Même règle que StoryGraph.build : un @roll ne vaut des liens que complet
## (4 arguments — compétence, difficulté, réussite, échec).
static var _re_roll := RegEx.create_from_string("^@roll\\((?:[^,]*,){3,}[^,]*\\)$")
static var _re_valid_id := RegEx.create_from_string("^[A-Za-z_]\\w*$")


func load_file(p_path: String) -> bool:
	path = p_path
	prelude = []
	order = []
	blocks = {}
	duplicate_ids = []
	if not FileAccess.file_exists(path):
		return false
	var current := ""
	for raw_line in FileAccess.get_file_as_string(path).split("\n"):
		var line: String = raw_line.trim_suffix("\r")
		if line.strip_edges().begins_with("::"):
			var id := line.strip_edges().substr(2).strip_edges()
			current = id
			if blocks.has(current):
				duplicate_ids.append(id)
				var n := 2
				while blocks.has("%s__%d" % [id, n]):
					n += 1
				current = "%s__%d" % [id, n]
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
	var new_text := text()
	var old_text := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("UntoldSource: impossible d'écrire " + path)
		return false
	file.store_string(new_text)
	if history_sink.is_valid() and old_text != new_text:
		history_sink.call(path, old_text)
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
## StoryGraph.outgoing) : seule la cible est réécrite — après la flèche
## « -> » pour un choix/saut, ou l'argument réussite/échec pour un @roll —
## tout le reste de la ligne (texte du choix, garde, espaces) est intact.
func set_link_target(id: String, link_index: int, new_target: String) -> bool:
	if not blocks.has(id):
		return false
	var ref := _link_ref(id, link_index)
	if ref.is_empty():
		return false
	var line_i: int = ref["line"]
	if ref["roll_slot"] >= 0:
		return _set_roll_target(id, line_i, ref["roll_slot"], new_target)
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


## Réécrit l'argument réussite (slot 0) ou échec (slot 1) d'une ligne @roll.
## Les autres arguments sont conservés tels quels.
func _set_roll_target(id: String, line_i: int, slot: int, new_target: String) -> bool:
	var raw: String = blocks[id][line_i]
	var found := RegEx.create_from_string("@roll\\((.*)\\)").search(raw)
	if found == null:
		return false
	var parts := found.get_string(1).split(",")
	if parts.size() < 4:
		return false
	parts[2 + slot] = " " + new_target
	blocks[id][line_i] = raw.substr(0, found.get_start()) \
			+ "@roll(%s)" % ", ".join(_strip_parts(parts)) \
			+ raw.substr(found.get_end())
	return true


static func _strip_parts(parts: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for p in parts:
		out.append(p.strip_edges())
	return out


## Référence du index-ième lien sortant du bloc : sa ligne, et pour un @roll,
## quel argument (0 = réussite, 1 = échec ; -1 = lien fléché ordinaire).
## Reproduit le classement de StoryGraph.build : choix, saut conditionnel,
## saut direct, gardes « { ... } instruction » comprises — et chaque ligne
## @roll(...) vaut DEUX indices consécutifs (réussite puis échec).
func _link_ref(id: String, link_index: int) -> Dictionary:
	var count := 0
	for i in blocks[id].size():
		var line: String = str(blocks[id][i]).strip_edges()
		if line.is_empty() or line.begins_with("//") or line.begins_with("::") \
				or line.begins_with("#"):
			continue
		var guard_match := _re_guard.search(line)
		if guard_match:
			# Groupe 2 du motif partagé = l'instruction après la garde.
			line = guard_match.get_string(2).strip_edges()
		if _re_choice.search(line) or _re_cond.search(line) or line.begins_with("->"):
			if count == link_index:
				return {"line": i, "roll_slot": -1}
			count += 1
		elif _re_roll.search(line):
			if link_index == count or link_index == count + 1:
				return {"line": i, "roll_slot": link_index - count}
			count += 2
	return {}


# ------------------------------------------------------- Opérations de nœud

## Id de nœud acceptable pour une création/un renommage depuis l'outil :
## lettres/chiffres/underscore, commence par une lettre ou « _ », et pas le
## nœud réservé END. (Le format tolère plus large, mais l'outil recommande
## des ids simples — lisibles dans les liens et valides comme noms Godot.)
static func is_valid_id(id: String) -> bool:
	if id == "END":
		return false
	return _re_valid_id.search(id) != null


## Corps du bloc (lignes après « :: id »), verbatim — blancs de fin normalisés
## (comme text() à la réécriture).
func body_lines(id: String) -> Array:
	if not blocks.has(id):
		return []
	return _without_trailing_blanks(blocks[id]).slice(1)


## Remplace le corps du bloc — la ligne « :: id » d'origine est conservée.
func set_body(id: String, lines: Array) -> bool:
	if not blocks.has(id):
		return false
	var head: String = blocks[id][0]
	blocks[id] = [head]
	blocks[id].append_array(lines)
	return true


## Ajoute un nœud à la fin du fichier. false si l'id existe déjà ou est invalide.
func add_node(id: String, body: Array = []) -> bool:
	if blocks.has(id) or not is_valid_id(id):
		return false
	order.append(id)
	blocks[id] = [":: " + id]
	blocks[id].append_array(body)
	return true


## Supprime le bloc du nœud (les liens qui pointaient vers lui deviennent des
## cibles inconnues — à l'appelant de prévenir l'auteur). false si absent.
func remove_node(id: String) -> bool:
	if not blocks.has(id):
		return false
	blocks.erase(id)
	order.erase(id)
	return true


## Renomme un nœud : sa ligne « :: id », puis toutes les références dans le
## fichier — cibles « -> id » (choix, sauts, sauts conditionnels) et gardes
## « visited(id) ». false si l'ancien id est absent, le nouveau déjà pris ou
## invalide.
func rename_node(old_id: String, new_id: String) -> bool:
	if not blocks.has(old_id) or blocks.has(new_id) or not is_valid_id(new_id):
		return false
	var escaped := _regex_escape(old_id)
	var re_target := RegEx.create_from_string("(->\\s*)" + escaped + "(?=[\\s}]|$)")
	var re_visited := RegEx.create_from_string("(visited\\(\\s*)" + escaped + "(?=\\s*\\))")

	blocks[new_id] = blocks[old_id]
	blocks.erase(old_id)
	blocks[new_id][0] = ":: " + new_id  # en-tête normalisé (espaces d'origine non significatifs)
	order[order.find(old_id)] = new_id

	for id in blocks:
		for i in blocks[id].size():
			var line: String = blocks[id][i]
			if line.strip_edges().begins_with("//"):
				continue
			line = re_target.sub(line, "${1}" + new_id, true)
			line = re_visited.sub(line, "${1}" + new_id, true)
			blocks[id][i] = line
	return true


static func _regex_escape(s: String) -> String:
	var out := ""
	for c in s:
		out += ("\\" + c) if "\\^$.|?*+()[]{}".contains(c) else c
	return out


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
	var re := RegEx.create_from_string("@" + _regex_escape(command) + "\\(.*\\)")
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
	var re := RegEx.create_from_string("@" + _regex_escape(command) + "\\(.*\\)")
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


## Vrai si le bloc du nœud porte le tag donné (sans le « # »), sur une des
## lignes de tags « #A #B ... » du bloc.
func has_tag(id: String, tag: String) -> bool:
	if not blocks.has(id):
		return false
	for line in blocks[id]:
		var stripped: String = str(line).strip_edges()
		if stripped.begins_with("#"):
			for token in stripped.split(" ", false):
				if token.lstrip("#") == tag:
					return true
	return false


## Ajoute un tag au bloc du nœud : accolé à une ligne de tags existante, ou
## inséré juste après la ligne « :: id » si le nœud n'en a pas encore. No-op
## (retourne true) si le tag est déjà présent.
func add_tag(id: String, tag: String) -> bool:
	if not blocks.has(id):
		return false
	if has_tag(id, tag):
		return true
	for i in blocks[id].size():
		if str(blocks[id][i]).strip_edges().begins_with("#"):
			blocks[id][i] = str(blocks[id][i]).rstrip(" \t") + " #" + tag
			return true
	blocks[id].insert(1, "#" + tag)  # index 0 = la ligne « :: id »
	return true


## Retire un tag du bloc du nœud : ôte le jeton « #tag » de sa ligne de tags (la
## ligne entière disparaît si elle devient vide). Retourne false si absent.
func remove_tag(id: String, tag: String) -> bool:
	if not blocks.has(id):
		return false
	for i in blocks[id].size():
		var stripped: String = str(blocks[id][i]).strip_edges()
		if not stripped.begins_with("#"):
			continue
		var kept: Array = []
		var removed := false
		for token in stripped.split(" ", false):
			if token.lstrip("#") == tag:
				removed = true
			else:
				kept.append(token)
		if removed:
			if kept.is_empty():
				blocks[id].remove_at(i)
			else:
				blocks[id][i] = " ".join(PackedStringArray(kept))
			return true
	return false


static func _without_trailing_blanks(lines: Array) -> Array:
	var out := lines.duplicate()
	while not out.is_empty() and str(out.back()).strip_edges().is_empty():
		out.pop_back()
	return out
