class_name IllustrationLibrary
extends RefCounted
## Construit une IllustrationData à partir de son nom (celui utilisé dans le
## .untold via @illustration("Nom")). Les configs (calques, parallaxe) sont
## reprises des assets Unity d'origine.
##
## Construction en code (load des textures) plutôt qu'en .tres : robuste et
## sûr à l'export. Pour ajouter une illustration, suivre le même patron.

const HORIZONTAL := Vector2(1, 0)


static func get_illustration(name: String) -> IllustrationData:
	match name:
		"Le village":
			return _village()
		"Statue de Sîn":
			return _sin()
		"Halî-Ammi":
			return _hali_ammi()
		_:
			return null


# ------------------------------------------------------- Illustrations câblées

## Paysage, calques 4→7 (vérifié sur Village.asset).
static func _village() -> IllustrationData:
	const DIR := "res://assets/illustrations/landscape/Village/"
	return _build("Le village", IllustrationData.Template.LANDSCAPE, [
		_layer(DIR + "Illu_Village_Plan04.png", 4, HORIZONTAL),
		_layer(DIR + "Illu_Village_Plan05.png", 5, HORIZONTAL),
		_layer(DIR + "Illu_Village_Plan06.png", 6, HORIZONTAL),
		_layer(DIR + "Illu_Village_Plan07.png", 7, HORIZONTAL),
	])


## Portrait, calques 5→6 (vérifié sur Sin.asset).
static func _sin() -> IllustrationData:
	const DIR := "res://assets/illustrations/portrait/Sin/"
	return _build("Statue de Sîn", IllustrationData.Template.PORTRAIT, [
		_layer(DIR + "Illu_Prologue_Sin_Unique_Plan05.png", 5, HORIZONTAL),
		_layer(DIR + "Illu_Prologue_Sin_Unique_Plan06.png", 6, HORIZONTAL),
	])


## Portrait, calques 6→7 (config par convention — à confirmer au debug).
static func _hali_ammi() -> IllustrationData:
	const DIR := "res://assets/illustrations/portrait/HaliAmmi/"
	return _build("Halî-Ammi", IllustrationData.Template.PORTRAIT, [
		_layer(DIR + "Illu_HaliAmmi_Plan06.png", 6, HORIZONTAL),
		_layer(DIR + "Illu_HaliAmmi_Plan07.png", 7, HORIZONTAL),
	])


# ------------------------------------------------------------------- Helpers

static func _build(name: String, template: IllustrationData.Template, layers: Array[IllustrationLayer]) -> IllustrationData:
	var data := IllustrationData.new()
	data.illustration_name = name
	data.template = template
	data.layers = layers
	return data


static func _layer(path: String, index: int, multiplier: Vector2) -> IllustrationLayer:
	var layer := IllustrationLayer.new()
	layer.sprite = load(path)
	layer.layer_index = index
	layer.parallax_multiplier = multiplier
	return layer
