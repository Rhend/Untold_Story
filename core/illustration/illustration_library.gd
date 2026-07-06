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
## l'ancienne constante DEFS). "dir" rendu absolu (res://) ; chaque calque est un
## objet { "file", "index", "interactions": [ {id, polygon, dialogue_lines,
## item_id, item_qty}, ... ] }.
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
			ResourceLoader.load_threaded_request(def["dir"] + layer_file(entry))


static func _build(name: String, def: Dictionary) -> IllustrationData:
	var data := IllustrationData.new()
	data.illustration_name = name
	data.template = def["template"]
	data.parallax_enabled = def.get("parallax_enabled", true)
	var layers: Array[IllustrationLayer] = []
	for entry in def["layers"]:
		var layer := IllustrationLayer.new()
		layer.sprite = load(def["dir"] + layer_file(entry))
		layer.layer_index = layer_index(entry)
		layer.parallax_multiplier = HORIZONTAL
		layer.interactions = _build_interactions(layer_interactions(entry))
		layers.append(layer)
	data.layers = layers
	return data


## Construit les zones interactives (Resources) d'un calque à partir du tableau
## JSON "interactions" — c'est ce qui ferme la boucle jusqu'au runtime : sans ça,
## IllustrationLayer.interactions restait toujours vide (cf. illustration.gd).
static func _build_interactions(raw_zones: Array) -> Array[IllustrationInteraction]:
	var result: Array[IllustrationInteraction] = []
	for raw in raw_zones:
		if not (raw is Dictionary):
			continue
		var zone := IllustrationInteraction.new()
		zone.id = str(raw.get("id", ""))
		var poly := PackedVector2Array()
		for p in raw.get("polygon", []):
			if p is Array and p.size() == 2:
				poly.append(Vector2(float(p[0]), float(p[1])))
		zone.polygon = poly
		var lines: Array[String] = []
		for line in raw.get("dialogue_lines", []):
			lines.append(str(line))
		zone.dialogue_lines = lines
		zone.item_id = str(raw.get("item_id", ""))
		zone.item_qty = int(raw.get("item_qty", 1))
		result.append(zone)
	return result


# ---------------------------------------------------------- Lecture d'un calque
# Une entrée "layers" est un objet { "file", "index", "interactions" }. Ces
# accesseurs tolèrent aussi l'ancien format positionnel [fichier, index] au cas
# où un fichier n'aurait pas encore été converti (pas de crash dur).

static func layer_file(entry: Variant) -> String:
	return str(entry["file"]) if entry is Dictionary else str(entry[0])


static func layer_index(entry: Variant) -> int:
	return int(entry["index"]) if entry is Dictionary else int(entry[1])


static func layer_interactions(entry: Variant) -> Array:
	return entry.get("interactions", []) if entry is Dictionary else []


# --------------------------------------------------------------------- Écriture

## Réécrit les zones interactives d'un calque dans illustrations_defs.json de
## l'histoire chargée, EN PRÉSERVANT tout le reste du fichier (autres
## illustrations, autres calques, autres champs). Met à jour _defs en mémoire et
## invalide le cache de cette illustration pour que la prochaine
## get_illustration() reflète le changement. `interactions` : Array de
## Dictionaries au format zone { id, polygon, dialogue_lines, item_id, item_qty }.
static func save_layer_interactions(illustration_name: String, index: int, interactions: Array) -> bool:
	if _loaded_dir.is_empty():
		push_error("IllustrationLibrary: aucune histoire chargée, save impossible.")
		return false
	var path := _loaded_dir + "illustrations_defs.json"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary) or not parsed.has(illustration_name):
		push_error("IllustrationLibrary: illustration « %s » absente de %s." % [illustration_name, path])
		return false
	var layers: Array = parsed[illustration_name].get("layers", [])
	var found := false
	for entry in layers:
		if entry is Dictionary and int(entry.get("index", -9999)) == index:
			entry["interactions"] = _normalize_zones(interactions)
			found = true
			break
	if not found:
		push_error("IllustrationLibrary: calque index %d introuvable dans « %s »." % [index, illustration_name])
		return false

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("IllustrationLibrary: impossible d'écrire " + path)
		return false
	file.store_string(JSON.stringify(parsed, "\t"))

	# Aligne l'état mémoire sur le disque (mêmes calques, interactions à jour) et
	# invalide le cache de cette illustration : prochaine lecture = version fraîche.
	if _defs.has(illustration_name):
		_defs[illustration_name]["layers"] = layers
	_cache.erase(illustration_name)
	return true


## Nettoie chaque zone en un Dictionary JSON propre (types garantis).
static func _normalize_zones(zones: Array) -> Array:
	var out: Array = []
	for z in zones:
		if not (z is Dictionary):
			continue
		out.append({
			"id": str(z.get("id", "")),
			"polygon": z.get("polygon", []),
			"dialogue_lines": z.get("dialogue_lines", []),
			"item_id": str(z.get("item_id", "")),
			"item_qty": int(z.get("item_qty", 1)),
		})
	return out
