@tool
class_name ItemLibrary
extends RefCounted
## Construit un ItemData à partir de son id (celui utilisé dans le .untold via
## @add_into_inventory("id") et dans les zones d'interaction). Mirroring exact
## d'IllustrationLibrary : chaque histoire porte son propre items_defs.json
## (data/stories/<id>/), chargé par load_story() au démarrage. Un cache évite de
## reconstruire les ItemData.
##
## Format items_defs.json : { id: { "display_name", "description", "icon" } }.
## "icon" est un chemin d'icône, relatif au dossier de l'histoire, ou absolu s'il
## commence par "res://" (pratique pour un placeholder partagé tant que l'art
## définitif n'est pas là).

## Définitions de l'histoire courante, peuplées par load_story().
## { id: { "display_name": String, "description": String, "icon": String(res://) } }
static var _defs: Dictionary = {}
static var _cache: Dictionary = {}
## Dossier d'histoire actuellement chargé (évite un rechargement inutile).
static var _loaded_dir: String = ""


## Charge les définitions d'objets d'une histoire depuis <story_dir>/items_defs.json
## et vide le cache (un objet de même id dans une autre histoire ne doit pas
## ressortir l'ancienne définition). À appeler au démarrage de l'histoire.
## items_defs.json est OPTIONNEL : une histoire sans objets charge simplement vide.
static func load_story(story_dir: String) -> void:
	if not story_dir.ends_with("/"):
		story_dir += "/"
	if _loaded_dir == story_dir and not _defs.is_empty():
		return
	_defs = {}
	_cache = {}
	_loaded_dir = story_dir

	var defs_path := story_dir + "items_defs.json"
	if not FileAccess.file_exists(defs_path):
		return  # histoire sans objets : inventaire simplement vide
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(defs_path))
	if not (parsed is Dictionary):
		push_error("ItemLibrary: JSON illisible " + defs_path)
		return
	for id in parsed:
		var raw: Dictionary = parsed[id]
		_defs[id] = {
			"display_name": str(raw.get("display_name", id)),
			"description": str(raw.get("description", "")),
			"icon": _resolve_icon(story_dir, str(raw.get("icon", ""))),
		}


## Chemin d'icône absolu : tel quel s'il est déjà en res://, sinon relatif au
## dossier de l'histoire. Vide si aucune icône déclarée.
static func _resolve_icon(story_dir: String, icon: String) -> String:
	if icon.is_empty():
		return ""
	return icon if icon.begins_with("res://") else story_dir + icon


## Définitions courantes (lecture seule) — pour l'UI ou la validation.
static func defs() -> Dictionary:
	return _defs


static func get_item(id: String) -> ItemData:
	if _cache.has(id):
		return _cache[id]
	if not _defs.has(id):
		return null
	var data := _build(id, _defs[id])
	_cache[id] = data
	return data


static func _build(id: String, def: Dictionary) -> ItemData:
	var item := ItemData.new()
	item.id = id
	item.display_name = def["display_name"]
	item.description = def["description"]
	var icon_path: String = def["icon"]
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		item.icon = load(icon_path)
	return item
