@tool
class_name IllustrationLibrary
extends RefCounted
## Construit une IllustrationData à partir de son nom (celui utilisé dans le
## .untold via @illustration("Nom")). Les configs (calques, parallaxe) sont
## reprises des assets Unity d'origine.
##
## Construction en code (load des textures) plutôt qu'en .tres : robuste et
## sûr à l'export. Un cache évite de reconstruire, et preload_all() précharge
## les textures en tâche de fond pour éviter le à-coup à l'affichage.
##
## Les définitions ne sont plus en dur : chaque histoire porte son propre
## illustrations_defs.json (data/stories/<id>/), chargé par load_story() au
## démarrage. Le format JSON reprend les mêmes clés que l'ancien dictionnaire
## DEFS (template, dir, layers, parallax_enabled), le champ "dir" étant relatif
## au dossier de l'histoire.

const HORIZONTAL := Vector2(1, 0)

## Gabarits nommés en JSON → valeurs de l'énum IllustrationData.Template.
const TEMPLATE_NAMES := {
	"PORTRAIT": IllustrationData.Template.PORTRAIT,
	"LANDSCAPE": IllustrationData.Template.LANDSCAPE,
	"CHARACTER": IllustrationData.Template.CHARACTER,
}

## Définitions de l'histoire courante, peuplées par load_story() (remplace
## l'ancienne constante DEFS). Même forme que DEFS, "dir" rendu absolu (res://).
## { nom: { "template": int, "dir": String, "layers": Array, "parallax_enabled": bool } }
static var _defs: Dictionary = {}
static var _cache: Dictionary = {}
## Dossier d'histoire actuellement chargé (évite un rechargement inutile).
static var _loaded_dir: String = ""


## Charge les définitions d'illustrations d'une histoire depuis
## <story_dir>/illustrations_defs.json et vide le cache (une illustration de même
## nom dans une autre histoire ne doit pas ressortir l'ancienne image). À appeler
## avant preload_all()/get_illustration() au démarrage de l'histoire.
static func load_story(story_dir: String) -> void:
	if not story_dir.ends_with("/"):
		story_dir += "/"
	if _loaded_dir == story_dir and not _defs.is_empty():
		return
	_defs = {}
	_cache = {}
	_loaded_dir = story_dir

	var defs_path := story_dir + "illustrations_defs.json"
	if not FileAccess.file_exists(defs_path):
		push_error("IllustrationLibrary: fichier introuvable " + defs_path)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(defs_path))
	if not (parsed is Dictionary):
		push_error("IllustrationLibrary: JSON illisible " + defs_path)
		return
	for name in parsed:
		var raw: Dictionary = parsed[name]
		_defs[name] = {
			"template": TEMPLATE_NAMES.get(
					str(raw.get("template", "LANDSCAPE")), IllustrationData.Template.LANDSCAPE),
			"dir": story_dir + str(raw["dir"]),  # relatif → absolu res://
			"layers": raw["layers"],
			"parallax_enabled": bool(raw.get("parallax_enabled", true)),
		}


## Définitions courantes (lecture seule) — pour l'outil narratif et la validation
## qui inspectent les illustrations sans passer par get_illustration().
static func defs() -> Dictionary:
	return _defs


static func get_illustration(name: String) -> IllustrationData:
	if _cache.has(name):
		return _cache[name]
	if not _defs.has(name):
		return null
	var data := _build(name, _defs[name])
	_cache[name] = data
	return data


## Lance le chargement de toutes les textures en tâche de fond. À appeler tôt
## (ex. au démarrage de l'histoire) : à l'affichage d'une illustration, les
## textures sont déjà en cache → plus d'à-coup.
static func preload_all() -> void:
	for name in _defs:
		var def: Dictionary = _defs[name]
		for entry in def["layers"]:
			ResourceLoader.load_threaded_request(def["dir"] + entry[0])


static func _build(name: String, def: Dictionary) -> IllustrationData:
	var data := IllustrationData.new()
	data.illustration_name = name
	data.template = def["template"]
	data.parallax_enabled = def.get("parallax_enabled", true)
	var layers: Array[IllustrationLayer] = []
	for entry in def["layers"]:
		var layer := IllustrationLayer.new()
		layer.sprite = load(def["dir"] + entry[0])
		layer.layer_index = entry[1]
		layer.parallax_multiplier = HORIZONTAL
		layers.append(layer)
	data.layers = layers
	return data
