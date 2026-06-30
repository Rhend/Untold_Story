class_name Story
extends Resource
## Une histoire complète : l'ensemble des nœuds + les variables par défaut.
## C'est la SOURCE UNIQUE lue à la fois par le jeu (runtime) et, plus tard,
## par le plugin de visualisation (Phase 2).

## id (String) -> StoryNode
@export var nodes: Dictionary = {}
## Variables par défaut (ex: {"character": "", "type": ""}).
@export var variables: Dictionary = {}
## Nœud d'entrée.
@export var start_node: String = "start"

func add_node(node: StoryNode) -> void:
	nodes[node.id] = node

func get_node_by_id(id: String) -> StoryNode:
	return nodes.get(id)

func has_node(id: String) -> bool:
	return nodes.has(id)
