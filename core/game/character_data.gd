class_name CharacterData
extends Resource
## Données d'un personnage jouable (équivalent propre du ScriptableObject Unity).
## Le `character_type` et l'`attribute` pilotent le filtrage narratif (tags) et
## les sauts conditionnels du format .untold.

@export var display_name: String = ""
## Type de personnage (héros unique depuis juillet 2026 : "Nadîtum").
@export var character_type: String = ""
## Attribut : "Physique" / "Social" / "Mystique".
@export var attribute: String = ""
@export var bust: Texture2D
@export var icon: Texture2D
@export var color: Color = Color.WHITE
@export_multiline var description: String = ""


## Couleur d'affichage d'un type de personnage : sa ressource si elle figure
## dans `known` (Array de CharacterData), sinon une teinte STABLE dérivée du
## nom — la même partout (carte en jeu, outil narratif), pour qu'un personnage
## historique d'une vieille sauvegarde garde une couleur constante.
static func color_for(character_type: String, known: Array) -> Color:
	for data in known:
		if data is CharacterData and data.character_type == character_type:
			return data.color
	return Color.from_hsv(fmod(abs(float(character_type.hash())) / 1000.0, 1.0), 0.55, 0.9)
