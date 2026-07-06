extends Node
## Suivi persistant de la progression narrative (autoload "Progress") — L6.
##
## Répond à tout moment aux questions :
##  - tel nœud a-t-il été visité, et par quels personnages ?
##  - à tel point de choix, quelles réponses ont déjà été choisies (et par qui),
##    et lesquelles ne l'ont pas encore été ? (voir choice_status())
##
## Les données sont regroupées par histoire (story_id = nom du fichier .untold)
## et persistées en JSON dans user://progress.json à chaque événement.

const SAVE_PATH := "user://progress.json"

## Contexte courant, posé par begin_story().
var _story_id := ""
var _character := ""

## { story_id: { node_id: {
##     "visited_by": { personnage: nombre de passages },
##     "chosen":     { texte de la réponse: { personnage: nombre de fois } } } } }
var _data: Dictionary = {}

## Clics sur les zones interactives d'illustration (indépendant des nœuds).
## { story_id: { zone_id: { personnage: nombre de clics } } }
# TODO point 7 : appartient à la section "partie en cours", doit être remis à
# zéro à chaque nouvelle partie, contrairement à visited_by/chosen qui sont
# cumulatifs.
var _zones: Dictionary = {}


func _ready() -> void:
	_load()


# ------------------------------------------------------------ Enregistrement

## Pose le contexte : histoire jouée et personnage incarné.
func begin_story(story_id: String, character: String) -> void:
	_story_id = story_id
	_character = character


## Le personnage courant traverse un nœud (y compris les nœuds intermédiaires
## enchaînés par des sauts).
func record_visit(node_id: String) -> void:
	var visitors_of_node: Dictionary = _node_entry(node_id)["visited_by"]
	visitors_of_node[_character] = int(visitors_of_node.get(_character, 0)) + 1
	_save()


## Le personnage courant valide une réponse à un point de choix.
func record_choice(node_id: String, choice_text: String) -> void:
	var chosen: Dictionary = _node_entry(node_id)["chosen"]
	var by: Dictionary = chosen.get(choice_text, {})
	by[_character] = int(by.get(_character, 0)) + 1
	chosen[choice_text] = by
	_save()


## Le personnage courant clique sur une zone interactive d'illustration.
## Enregistré quelle que soit la zone (même sans effet dialogue/objet).
func record_zone_click(zone_id: String) -> void:
	if not _zones.has(_story_id):
		_zones[_story_id] = {}
	var zones: Dictionary = _zones[_story_id]
	var by: Dictionary = zones.get(zone_id, {})
	by[_character] = int(by.get(_character, 0)) + 1
	zones[zone_id] = by
	_save()


## Efface toute la progression (tous personnages, toutes histoires).
func reset() -> void:
	_data = {}
	_zones = {}
	_save()


# ---------------------------------------------------------------- Requêtes
# story_id vide = histoire du contexte courant.

## Le nœud a-t-il déjà été visité (tous personnages confondus) ?
func is_visited(node_id: String, story_id := "") -> bool:
	return not visitors(node_id, story_id).is_empty()


## Personnages ayant visité le nœud.
func visitors(node_id: String, story_id := "") -> Array:
	return _node_of(node_id, story_id).get("visited_by", {}).keys()


## Nombre de passages d'un personnage donné sur ce nœud.
func visit_count(node_id: String, character: String, story_id := "") -> int:
	return int(_node_of(node_id, story_id).get("visited_by", {}).get(character, 0))


## Cette réponse a-t-elle déjà été choisie (tous personnages confondus) ?
func is_choice_chosen(node_id: String, choice_text: String, story_id := "") -> bool:
	return not choice_choosers(node_id, choice_text, story_id).is_empty()


## Personnages ayant déjà choisi cette réponse.
func choice_choosers(node_id: String, choice_text: String, story_id := "") -> Array:
	return _node_of(node_id, story_id).get("chosen", {}).get(choice_text, {}).keys()


## Cette zone a-t-elle déjà été cliquée (tous personnages confondus) ?
## Interrogé par la garde zone_clicked("id") du .untold.
func is_zone_clicked(zone_id: String, story_id := "") -> bool:
	return not _zones.get(_resolve(story_id), {}).get(zone_id, {}).is_empty()


## État de TOUTES les réponses déclarées par un nœud : pour chacune, si elle a
## déjà été choisie et par qui. Les réponses jamais choisies sont celles dont
## "chosen" vaut false — c'est la vue exhaustive choisi / pas encore choisi.
func choice_status(node: StoryNode, story_id := "") -> Array:
	var result: Array = []
	for ins in node.instructions:
		if ins["type"] != "choice":
			continue
		var by := choice_choosers(node.id, ins["text"], story_id)
		result.append({
			"text": ins["text"],
			"target": ins["target"],
			"chosen": not by.is_empty(),
			"by": by,
		})
	return result


## Nombre de nœuds distincts déjà visités dans l'histoire.
func visited_count(story_id := "") -> int:
	return _data.get(_resolve(story_id), {}).size()


# -------------------------------------------------------------- Persistance

func _resolve(story_id: String) -> String:
	return _story_id if story_id.is_empty() else story_id


## Lecture seule : entrée du nœud, ou {} si jamais rencontré.
func _node_of(node_id: String, story_id := "") -> Dictionary:
	return _data.get(_resolve(story_id), {}).get(node_id, {})


## Écriture : entrée du nœud pour l'histoire courante, créée au besoin.
func _node_entry(node_id: String) -> Dictionary:
	if not _data.has(_story_id):
		_data[_story_id] = {}
	var nodes: Dictionary = _data[_story_id]
	if not nodes.has(node_id):
		nodes[node_id] = {"visited_by": {}, "chosen": {}}
	return nodes[node_id]


func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Progress: impossible d'écrire " + SAVE_PATH)
		return
	file.store_string(JSON.stringify({"stories": _data, "zones": _zones}, "\t"))


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not (parsed is Dictionary):
		push_warning("Progress: sauvegarde illisible, repartie de zéro.")
		return
	# Nouveau format { "stories", "zones" } ; ancien format = dict de story_id
	# à plat (avant l'ajout des zones) → chargé tel quel, zones vides.
	if parsed.has("stories") or parsed.has("zones"):
		_data = parsed.get("stories", {})
		_zones = parsed.get("zones", {})
	else:
		_data = parsed
