@tool
class_name StoryMeta
extends RefCounted
## Métadonnées d'édition d'une histoire, dans un fichier « sidecar »
## (<histoire>.meta.json à côté du .untold) : la source narrative n'est
## jamais polluée par des données d'outillage.
##
## Structure libre (extensible sans migration), clés utilisées aujourd'hui :
##   "positions":   { node_id: [x, y] }  — disposition du graphe (outil + carte)
##   "comments":    { node_id: String }  — notes privées à l'outil narratif
##   "collapsed":   { node_id: true }    — nœuds repliés dans l'outil graphe
##   "titles":      { node_id: String }  — titre lisible affiché au joueur (PROD)
##   "total_nodes": int                  — nombre de nœuds, mis en cache à
##       l'ouverture dans l'outil (évite de reparser l'histoire dans le hub)

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


## Nombre de nœuds de l'histoire, mis en cache par l'outil narratif à l'ouverture
## (cf. graph_editor._load_selected). 0 si l'histoire n'a jamais été ouverte dans
## l'outil (sidecar absent ou clé jamais écrite). Lisible sans reparser le .untold.
func total_nodes() -> int:
	return int(data.get("total_nodes", 0))


## Fait suivre TOUTES les métadonnées d'un nœud renommé (position, commentaire,
## repli, titre) vers son nouvel id.
func rename_node(old_id: String, new_id: String) -> void:
	for key in ["positions", "comments", "collapsed", "titles"]:
		var sect := section(key)
		if sect.has(old_id):
			sect[new_id] = sect[old_id]
			sect.erase(old_id)


## Oublie toutes les métadonnées d'un nœud supprimé.
func forget_node(node_id: String) -> void:
	for key in ["positions", "comments", "collapsed", "titles"]:
		section(key).erase(node_id)


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


# ---------------------------------------------------------------------- Repli

## Un nœud « replié » masque en cascade les nœuds qui dépendent de lui
## dans l'outil graphe (state d'outillage, sans effet en jeu).
func is_collapsed(node_id: String) -> bool:
	return bool(section("collapsed").get(node_id, false))


func set_collapsed(node_id: String, collapsed: bool) -> void:
	if collapsed:
		section("collapsed")[node_id] = true
	else:
		section("collapsed").erase(node_id)


# ---------------------------------------------------------------- Commentaires

func get_comment(node_id: String) -> String:
	return str(section("comments").get(node_id, ""))


func set_comment(node_id: String, text: String) -> void:
	if text.strip_edges().is_empty():
		section("comments").erase(node_id)
	else:
		section("comments")[node_id] = text


# --------------------------------------------------------------------- Titres

## Titre lisible du nœud, affiché au joueur en production à la place de l'id
## technique. "" si aucun titre n'a été défini (le champ est optionnel).
func get_title(node_id: String) -> String:
	return str(section("titles").get(node_id, ""))


func set_title(node_id: String, title: String) -> void:
	if title.strip_edges().is_empty():
		section("titles").erase(node_id)
	else:
		section("titles")[node_id] = title
