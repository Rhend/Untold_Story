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
