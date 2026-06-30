class_name IllustrationLibrary
extends RefCounted
## Construit une IllustrationData à partir de son nom (celui utilisé dans le
## .untold via @illustration("Nom")). Les configs (calques, parallaxe) sont
## reprises des assets Unity d'origine.
##
## Construction en code (load des textures) plutôt qu'en .tres : robuste et
## sûr à l'export. Un cache évite de reconstruire, et preload_all() précharge
## les textures en tâche de fond pour éviter le à-coup à l'affichage.

const HORIZONTAL := Vector2(1, 0)

## Définition de chaque illustration : gabarit, dossier et calques (fichier, index).
const DEFS := {
	"Le village": {
		"template": IllustrationData.Template.LANDSCAPE,
		"dir": "res://assets/illustrations/landscape/Village/",
		"layers": [
			["Illu_Village_Plan04.png", 4],
			["Illu_Village_Plan05.png", 5],
			["Illu_Village_Plan06.png", 6],
			["Illu_Village_Plan07.png", 7],
		],
	},
	"Statue de Sîn": {
		"template": IllustrationData.Template.PORTRAIT,
		"dir": "res://assets/illustrations/portrait/Sin/",
		"layers": [
			["Illu_Prologue_Sin_Unique_Plan05.png", 5],
			["Illu_Prologue_Sin_Unique_Plan06.png", 6],
		],
	},
	"Halî-Ammi": {
		"template": IllustrationData.Template.PORTRAIT,
		"dir": "res://assets/illustrations/portrait/HaliAmmi/",
		"layers": [
			["Illu_HaliAmmi_Plan06.png", 6],
			["Illu_HaliAmmi_Plan07.png", 7],
		],
	},
}

static var _cache := {}


static func get_illustration(name: String) -> IllustrationData:
	if _cache.has(name):
		return _cache[name]
	if not DEFS.has(name):
		return null
	var data := _build(name, DEFS[name])
	_cache[name] = data
	return data


## Lance le chargement de toutes les textures en tâche de fond. À appeler tôt
## (ex. au démarrage de l'histoire) : à l'affichage d'une illustration, les
## textures sont déjà en cache → plus d'à-coup.
static func preload_all() -> void:
	for name in DEFS:
		var def: Dictionary = DEFS[name]
		for entry in def["layers"]:
			ResourceLoader.load_threaded_request(def["dir"] + entry[0])


static func _build(name: String, def: Dictionary) -> IllustrationData:
	var data := IllustrationData.new()
	data.illustration_name = name
	data.template = def["template"]
	var layers: Array[IllustrationLayer] = []
	for entry in def["layers"]:
		var layer := IllustrationLayer.new()
		layer.sprite = load(def["dir"] + entry[0])
		layer.layer_index = entry[1]
		layer.parallax_multiplier = HORIZONTAL
		layers.append(layer)
	data.layers = layers
	return data
