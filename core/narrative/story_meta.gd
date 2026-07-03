class_name StoryMeta
extends RefCounted
## Métadonnées d'édition d'une histoire, dans un fichier « sidecar »
## (<histoire>.meta.json à côté du .untold) : la source narrative n'est
## jamais polluée par des données d'outillage.
##
## Structure libre (extensible sans migration), clés utilisées aujourd'hui :
##   "positions": { node_id: [x, y] }  — disposition du graphe (outil + carte)
##   "comments":  { node_id: String }  — notes privées à l'outil narratif

var path := ""
var data: Dictionary = {}


static func load_for(untold_path: String) -> StoryMeta:
	var meta := StoryMeta.new()
	meta.path = untold_path.get_basename() + ".meta.json"
	if FileAccess.file_exists(meta.path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta.path))
		if parsed is Dictionary:
			meta.data = parsed
	return meta


func save() -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("StoryMeta: impossible d'écrire " + path)
		return
	file.store_string(JSON.stringify(data, "\t"))


## Sous-dictionnaire nommé, créé au besoin (point d'extension générique).
func section(key: String) -> Dictionary:
	if not data.has(key):
		data[key] = {}
	return data[key]


# ------------------------------------------------------------------ Positions

## Toutes les positions connues : { node_id: Vector2 }.
func positions() -> Dictionary:
	var result: Dictionary = {}
	for id in section("positions"):
		var raw: Variant = section("positions")[id]
		if raw is Array and raw.size() == 2:
			result[id] = Vector2(float(raw[0]), float(raw[1]))
	return result


func set_node_position(node_id: String, pos: Vector2) -> void:
	section("positions")[node_id] = [pos.x, pos.y]


# ---------------------------------------------------------------- Commentaires

func get_comment(node_id: String) -> String:
	return str(section("comments").get(node_id, ""))


func set_comment(node_id: String, text: String) -> void:
	if text.strip_edges().is_empty():
		section("comments").erase(node_id)
	else:
		section("comments")[node_id] = text
