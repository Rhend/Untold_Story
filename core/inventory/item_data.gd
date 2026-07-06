@tool
class_name ItemData
extends Resource
## Définition d'un objet d'inventaire, référencé par son id dans les commandes
## .untold (@add_into_inventory("id")) et par les zones d'interaction (item_id).
## Construit à partir de items_defs.json par ItemLibrary (mirroring IllustrationData).
##
## PAS de champ "stackable" : unique vs empilable ne dépend pas de la définition,
## seulement de la façon dont les commandes sont invoquées (avec ou sans quantité).

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var icon: Texture2D = null
