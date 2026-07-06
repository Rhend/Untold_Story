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

## Racine des histoires : un sous-dossier par histoire (data/stories/<id>/).
const STORIES_ROOT := "res://data/stories/"

## Histoire choisie. Défaut "mesopotamia" tant que le hub (point 9) n'existe pas
## — le joueur arrive donc directement dans la seule histoire disponible, sans
## changement de comportement.
var story_id: String = "mesopotamia"


## Dossier de l'histoire courante (terminé par « / »).
func story_dir() -> String:
	return STORIES_ROOT + story_id + "/"


## Chemins des CharacterData (.tres) de l'histoire courante, scannés dans son
## dossier characters/ (ordre alphabétique stable). Vide si le dossier manque.
func character_paths() -> Array:
	var dir_path := story_dir() + "characters/"
	var paths: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("GameState: dossier personnages introuvable : " + dir_path)
		return paths
	for file in dir.get_files():
		if file.ends_with(".tres"):
			paths.append(dir_path + file)
	paths.sort()
	return paths
