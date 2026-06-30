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

const END_NODE := "END"

var variables: Dictionary = {}

var _story: Story
var _pending_choices: Array = []

## Démarre une histoire. `initial_vars` écrase les variables par défaut
## (ex: {"character": "Nadîtum", "type": "Mystique"}).
func start(story: Story, initial_vars: Dictionary = {}) -> void:
	_story = story
	variables = story.variables.duplicate(true)
	for key in initial_vars:
		variables[key] = initial_vars[key]
	_run_from(story.start_node)

## Le joueur sélectionne le choix d'index `index`.
func choose(index: int) -> void:
	if index < 0 or index >= _pending_choices.size():
		return
	var target: String = _pending_choices[index]["target"]
	_pending_choices = []
	_run_from(target)

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
		var jumped := false

		for ins in node.instructions:
			match ins["type"]:
				"text":
					buffer = _append_line(buffer, ins["value"])
				"set":
					variables[ins["name"]] = ins["value"]
				"command":
					command.emit(ins["name"], ins["args"])
				"choice":
					choices.append({"text": ins["text"], "target": ins["target"]})
				"cond":
					if str(variables.get(ins["var"], "")) == ins["value"]:
						id = ins["target"]
						jumped = true
						break
				"divert":
					id = ins["target"]
					jumped = true
					break

		if jumped:
			continue  # On enchaîne sur le nœud cible en accumulant le texte.
		break          # Fin naturelle du nœud : on s'arrête pour présenter la suite.

	# Restitution de l'état accumulé.
	if not buffer.is_empty():
		display_text.emit(buffer, last_node, last_tags)

	if id == END_NODE:
		story_ended.emit()
	elif choices.size() > 0:
		_pending_choices = choices
		present_choices.emit(choices)
	else:
		story_ended.emit()


func _append_line(buffer: String, line: String) -> String:
	if buffer.is_empty():
		return line
	return buffer + "\n" + line
