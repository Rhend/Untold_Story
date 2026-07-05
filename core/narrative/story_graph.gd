@tool
class_name StoryGraph
extends RefCounted
## Vue « graphe » d'une Story : pour chaque nœud, ses liens sortants typés.
## Base commune du volet L7 : carte de progression en jeu (story_map.gd) et
## outil d'édition du graphe (addons/narrative_graph).
##
## Un lien est un Dictionary :
##   "from"     : id du nœud source
##   "target"   : id du nœud cible (peut être "END")
##   "kind"     : "choice" | "divert" | "cond"
##   "text"     : libellé du choix ("" pour un saut)
##   "guarded"  : true si l'instruction est sous condition (garde { ... } ou
##                saut conditionnel) — le joueur peut ne jamais l'avoir vue.
##   "identity" : true si la condition porte UNIQUEMENT sur l'identité du
##                joueur (variables character/type, fixées à la sélection du
##                personnage) — c'est une variante de personnage, pas un
##                embranchement secret de l'histoire.

## Variables fixées une fois pour toutes au choix du personnage.
const IDENTITY_VARS := ["character", "type"]

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
							"text": ins["text"], "guarded": ins.has("if"),
							"identity": ins.has("if") and _guard_identity_only(ins)})
				"divert":
					out.append({"from": id, "target": ins["target"], "kind": "divert",
							"text": "", "guarded": ins.has("if"),
							"identity": ins.has("if") and _guard_identity_only(ins)})
				"cond":
					out.append({"from": id, "target": ins["target"], "kind": "cond",
							"text": "", "guarded": true,
							"identity": IDENTITY_VARS.has(ins["var"]) and _guard_identity_only(ins)})
		graph.links[id] = out
	return graph


## Vrai si la garde "if" éventuelle ne porte que sur des variables d'identité
## (aucun visited(), aucune variable d'état de l'histoire).
static func _guard_identity_only(ins: Dictionary) -> bool:
	for group in ins.get("if", []):
		for cond in group:
			if cond["kind"] != "var" or not IDENTITY_VARS.has(cond["name"]):
				return false
	return true


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
