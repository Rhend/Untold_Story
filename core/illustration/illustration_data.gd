@tool
class_name IllustrationData
extends Resource
## Une illustration complète (équivalent de l'IllustrationData Unity) :
## un nom (référencé par @illustration("Nom") dans le .untold) et ses calques.

enum Template { PORTRAIT, LANDSCAPE }

@export var illustration_name: String = ""
@export var template: Template = Template.LANDSCAPE
@export var layers: Array[IllustrationLayer] = []
