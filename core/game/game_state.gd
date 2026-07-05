extends Node
## État global du jeu (autoload "GameState").
## Remplace le GameManager statique de la version Unity, sans ses défauts
## (pas de singleton bricolé, pas de SaveManager recréé à chaque accès).

## Personnage complet sélectionné (renseigné par l'écran de sélection).
var selected_character: CharacterData = null

## Personnage et attribut sélectionnés (pilotent le filtrage narratif par tags).
## Valeurs par défaut utilisées si l'histoire est lancée sans passer par la sélection.
var character_type: String = "Nadîtum"
var character_attribute: String = "Social"
