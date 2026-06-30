class_name CharacterData
extends Resource
## Données d'un personnage jouable (équivalent propre du ScriptableObject Unity).
## Le `character_type` et l'`attribute` pilotent le filtrage narratif (tags) et
## les sauts conditionnels du format .untold.

@export var display_name: String = ""
## Type de personnage : "Nadîtum" / "Soldat" / "Prêtresse".
@export var character_type: String = ""
## Attribut : "Physique" / "Social" / "Mystique".
@export var attribute: String = ""
@export var bust: Texture2D
@export var icon: Texture2D
@export var color: Color = Color.WHITE
@export_multiline var description: String = ""
