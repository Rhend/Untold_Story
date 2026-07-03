class_name StoryGraph
extends RefCounted
## Vue « graphe » d'une Story : pour chaque nœud, ses liens sortants typés.
## Base commune du volet L7 : carte de progression en jeu (story_map.gd) et
## outil d'édition du graphe (addons/narrative_graph).
##
## Un lien est un Dictionary :
##   "from"    : id du nœud source
##   "target"  : id du nœud cible (peut être "END")
##   "kind"    : "choice" | "divert" | "cond"
##   "text"    : libellé du choix ("" pour un saut)
##   "guarded" : true si l'instruction est sous condition (garde { ... } ou
##               saut conditionnel) — le joueur peut ne jamais l'avoir vue.

var story: Story
## id -> Array de liens sortants, dans l'ordre du fichier.
var links: Dictionary = {}


static func build(p_story: Story) -> StoryGraph:
	var graph := StoryGraph.new()
	graph.story = p_story
	for id in p_story.nodes:
		var out: Array = []
		for ins in p_story.nodes[id].instructions:
			match ins["type"]:
				"choice":
					out.append({"from": id, "target": ins["target"], "kind": "choice",
							"text": ins["text"], "guarded": ins.has("if")})
				"divert":
					out.append({"from": id, "target": ins["target"], "kind": "divert",
							"text": "", "guarded": ins.has("if")})
				"cond":
					out.append({"from": id, "target": ins["target"], "kind": "cond",
							"text": "", "guarded": true})
		graph.links[id] = out
	return graph


func outgoing(id: String) -> Array:
	return links.get(id, [])


## Disposition automatique en couches : colonne = profondeur (BFS) depuis le
## nœud d'entrée, rang = ordre d'apparition dans la couche. Les nœuds
## inatteignables sont posés dans une colonne supplémentaire à la fin.
## Retourne { id: Vector2 } — même espace de coordonnées que les positions
## sauvegardées par l'outil d'édition (StoryMeta), interchangeables.
func auto_layout(h_gap := 280.0, v_gap := 120.0) -> Dictionary:
	var depth: Dictionary = {story.start_node: 0}
	var queue: Array = [story.start_node]
	var max_depth := 0
	while not queue.is_empty():
		var id: String = queue.pop_front()
		for link in outgoing(id):
			var target: String = link["target"]
			if story.has_node(target) and not depth.has(target):
				depth[target] = depth[id] + 1
				max_depth = maxi(max_depth, depth[target])
				queue.append(target)

	var next_row: Dictionary = {}  # colonne -> prochain rang libre
	var positions: Dictionary = {}
	for id in story.nodes:  # l'ordre du fichier rend la disposition stable
		var col: int = depth.get(id, max_depth + 1)
		var row: int = next_row.get(col, 0)
		next_row[col] = row + 1
		positions[id] = Vector2(col * h_gap, row * v_gap)
	return positions
