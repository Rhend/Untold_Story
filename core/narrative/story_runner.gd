class_name StoryRunner
extends Node
## Moteur d'exécution narratif.
##
## Parcourt une Story depuis son nœud d'entrée, accumule le texte en suivant les
## sauts (diverts) et les sauts conditionnels — façon "glue" Ink — jusqu'à
## rencontrer un point de choix ou la fin. Communique uniquement par signaux :
## l'UI ne connaît rien du moteur, et inversement (découplage strict).

## Texte à afficher (accumulé), id du nœud courant, et ses tags.
signal display_text(text: String, node_id: String, tags: Array)
## Choix à présenter : Array de {"text": String, "target": String}.
signal present_choices(choices: Array)
## Commande moteur (ex: "illustration", "minigame") avec ses arguments.
signal command(name: String, args: Array)
## L'histoire a atteint une fin (-> END ou nœud sans suite).
signal story_ended()
## Un nœud vient d'être traversé — émis aussi pour les nœuds intermédiaires
## enchaînés par des sauts (sert au suivi de progression, autoload Progress).
signal node_visited(node_id: String)
## Le joueur a validé une réponse : nœud d'où venait le choix, et le choix
## lui-même {"text", "target", "node"}.
signal choice_selected(node_id: String, choice: Dictionary)

const END_NODE := "END"

## Marqueur "glue" : une ligne terminée (ou débutée) par <> se colle à la
## suivante sans saut de ligne — permet de composer une phrase à partir de
## fragments conditionnels.
const GLUE := "<>"

var variables: Dictionary = {}

var _story: Story
var _pending_choices: Array = []
## Nœuds déjà traversés (pour les conditions visited()).
var _visited: Dictionary = {}
## Nœud dont les choix sont actuellement présentés (pour refresh_choices()).
var _current_node_id := ""
## true tant qu'un point de choix est ouvert (garde refresh_choices()).
var _awaiting_choice := false

## Démarre une histoire. `initial_vars` écrase les variables par défaut
## (ex: {"character": "Nadîtum", "type": "Mystique"}). `from_node` permet de
## reprendre à un nœud précis (checkpoint) plutôt qu'au nœud d'entrée — les
## variables sont posées de la même façon, seul le point de départ change.
## `visited_ids` réamorce l'ensemble des nœuds déjà visités : indispensable à la
## reprise pour que les gardes visited()/!visited() se comportent comme dans une
## lecture continue. Restauré APRÈS la remise à zéro de _visited et AVANT le saut
## vers `from_node`, sinon les gardes du nœud de reprise verraient un état vierge.
func start(story: Story, initial_vars: Dictionary = {}, from_node := "", visited_ids: Array = []) -> void:
	_story = story
	variables = story.variables.duplicate(true)
	for key in initial_vars:
		variables[key] = initial_vars[key]
	_visited = {}
	_current_node_id = ""
	_awaiting_choice = false
	restore_visited(visited_ids)
	_run_from(from_node if not from_node.is_empty() else story.start_node)


## Réamorce _visited depuis une liste d'ids (reprise). N'affecte que l'état
## interne des gardes visited() ; ne rejoue rien, n'émet aucun signal.
func restore_visited(ids: Array) -> void:
	for id in ids:
		_visited[id] = true

## Le joueur sélectionne le choix d'index `index`.
func choose(index: int) -> void:
	if index < 0 or index >= _pending_choices.size():
		return
	var choice: Dictionary = _pending_choices[index]
	_pending_choices = []
	_awaiting_choice = false
	choice_selected.emit(choice["node"], choice)
	_run_from(choice["target"])


## Ré-évalue UNIQUEMENT les choix du nœud courant avec l'état à jour (variables,
## zone_clicked) et ré-émet present_choices — sans retoucher au texte ni aux
## commandes. À appeler quand un clic de zone a pu débloquer une nouvelle sortie.
## Sans effet si aucun point de choix n'est ouvert.
func refresh_choices() -> void:
	if not _awaiting_choice or _story == null:
		return
	var node: StoryNode = _story.get_node_by_id(_current_node_id)
	if node == null:
		return
	var choices: Array = []
	for ins in node.instructions:
		if ins["type"] != "choice":
			continue
		if ins.has("if") and not _check_conds(ins["if"]):
			continue
		choices.append({"text": ins["text"], "target": ins["target"], "node": _current_node_id})
	_pending_choices = choices
	present_choices.emit(choices)

## Reprend l'histoire à un nœud précis (utile au retour d'un mini-jeu).
func go_to(node_id: String) -> void:
	_pending_choices = []
	_run_from(node_id)

func set_variable(name: String, value) -> void:
	variables[name] = value


func _run_from(start_id: String) -> void:
	var id := start_id
	var buffer := ""
	var choices: Array = []
	var last_node := start_id
	var last_tags: Array = []

	while true:
		if id == END_NODE:
			break

		var node: StoryNode = _story.get_node_by_id(id)
		if node == null:
			push_error("StoryRunner: nœud introuvable « %s »." % id)
			break

		last_node = id
		last_tags = node.tags
		_visited[id] = true
		node_visited.emit(id)
		var jumped := false

		for ins in node.instructions:
			# Garde éventuelle : l'instruction est sautée si sa condition est fausse.
			if ins.has("if") and not _check_conds(ins["if"]):
				continue
			match ins["type"]:
				"text":
					buffer = _append_line(buffer, ins["value"])
				"set":
					variables[ins["name"]] = ins["value"]
				"command":
					command.emit(ins["name"], ins["args"])
				"choice":
					choices.append({"text": ins["text"], "target": ins["target"], "node": id})
				"cond":
					# Un point de choix ouvert arrête le flux (sémantique Ink) :
					# les sauts qui suivent des choix sont ignorés.
					if choices.is_empty() and str(variables.get(ins["var"], "")) == ins["value"]:
						id = ins["target"]
						jumped = true
						break
				"divert":
					if choices.is_empty():
						id = ins["target"]
						jumped = true
						break

		if jumped:
			continue  # On enchaîne sur le nœud cible en accumulant le texte.
		break          # Fin naturelle du nœud : on s'arrête pour présenter la suite.

	# Restitution de l'état accumulé (une glue restée en suspens est purgée).
	buffer = buffer.trim_suffix(GLUE).strip_edges()
	if not buffer.is_empty():
		display_text.emit(buffer, last_node, last_tags)

	if id == END_NODE:
		_awaiting_choice = false
		story_ended.emit()
	elif choices.size() > 0:
		_pending_choices = choices
		_current_node_id = last_node
		_awaiting_choice = true
		present_choices.emit(choices)
	else:
		_awaiting_choice = false
		story_ended.emit()


func _append_line(buffer: String, line: String) -> String:
	var glue := line.begins_with(GLUE)
	if glue:
		line = line.trim_prefix(GLUE)
	if buffer.is_empty():
		return line
	if buffer.ends_with(GLUE):
		return buffer.trim_suffix(GLUE) + line
	if glue:
		return buffer + line
	return buffer + "\n" + line


## Évalue une garde en forme disjonctive : vraie si AU MOINS UN groupe a
## TOUTES ses conditions vraies (les groupes viennent de "or", les conditions
## d'un groupe de "and").
func _check_conds(groups: Array) -> bool:
	for conds in groups:
		if _check_group(conds):
			return true
	return false


func _check_group(conds: Array) -> bool:
	for cond in conds:
		match cond["kind"]:
			"var":
				var equal: bool = str(variables.get(cond["name"], "")) == cond["value"]
				if (cond["op"] == "==") != equal:
					return false
			"visited":
				if _visited.has(cond["id"]) == cond["neg"]:
					return false
			"zone":
				# Zone d'illustration cliquée : état persistant (autoload Progress).
				if Progress.is_zone_clicked(cond["id"]) == cond["neg"]:
					return false
	return true
