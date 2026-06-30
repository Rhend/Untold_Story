extends Node
## État global du jeu (autoload "GameState").
## Remplace le GameManager statique de la version Unity, sans ses défauts
## (pas de singleton bricolé, pas de SaveManager recréé à chaque accès).

## Personnage et attribut sélectionnés (pilotent le filtrage narratif par tags).
var character_type: String = "Nadîtum"
var character_attribute: String = "Mystique"

## Contrôle de l'affichage du texte (sera enrichi : vitesse, sauts, effets).
## Secondes par caractère pour l'effet "machine à écrire".
var text_speed: float = 0.02
