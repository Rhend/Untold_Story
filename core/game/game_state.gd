extends Node
## État global du jeu (autoload "GameState").
## Remplace le GameManager statique de la version Unity, sans ses défauts
## (pas de singleton bricolé, pas de SaveManager recréé à chaque accès).

## Personnage complet sélectionné (renseigné par l'écran de sélection).
var selected_character: CharacterData = null

## Personnage et attribut sélectionnés (pilotent le filtrage narratif par tags).
## Vides par défaut : renseignés par la sélection de personnage. core/ reste
## agnostique au contenu — aucun nom de personnage n'y est codé en dur.
var character_type: String = ""
var character_attribute: String = ""

## Racine des histoires : un sous-dossier par histoire (data/stories/<id>/).
const STORIES_ROOT := "res://data/stories/"

## Histoire choisie, posée par le hub. Vide par défaut : core/ ne nomme aucune
## histoire. Un lancement direct d'une scène de test la résout génériquement
## (cf. first_story_id, appelé par story.gd/character_selection.gd).
var story_id: String = ""


## Dossier de l'histoire courante (terminé par « / »).
func story_dir() -> String:
	return STORIES_ROOT + story_id + "/"


## Id de la première histoire (ordre alphabétique) disposant d'un manifest.json,
## ou "" si aucune. Repli GÉNÉRIQUE pour lancer une scène de test sans passer par
## le hub — ne nomme aucune histoire en dur, garde core/ agnostique au contenu.
func first_story_id() -> String:
	var dir := DirAccess.open(STORIES_ROOT)
	if dir == null:
		return ""
	var ids: Array = []
	for sub in dir.get_directories():
		if FileAccess.file_exists(STORIES_ROOT + sub + "/manifest.json"):
			ids.append(sub)
	ids.sort()
	return ids[0] if not ids.is_empty() else ""


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
