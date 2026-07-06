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

## Balayages de l'heuristique du barycentre (aller/retour) pour ranger les
## colonnes de la disposition auto et réduire les croisements de liens.
const BARYCENTER_PASSES := 4

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
## nœud d'entrée (gauche → droite), rang VERTICAL dans la colonne = ordre qui
## réduit les croisements (heuristique du barycentre, cf. _order_by_barycenter).
## Les nœuds inatteignables sont posés dans une colonne supplémentaire à la fin.
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

	# Colonne (= profondeur) → nœuds, dans l'ordre du fichier au départ ; les
	# inatteignables forment une colonne supplémentaire à la fin.
	var columns: Dictionary = {}  # col:int -> Array[id]
	var max_col := max_depth
	for id in story.nodes:  # l'ordre du fichier rend la disposition stable
		var col: int = depth.get(id, max_depth + 1)
		max_col = maxi(max_col, col)
		columns.get_or_add(col, []).append(id)

	# Heuristique du barycentre (Sugiyama) transposée à l'axe horizontal :
	# réordonne VERTICALEMENT chaque colonne selon la position moyenne de ses
	# voisins de la colonne adjacente. Réduit les croisements sans les annuler.
	var adj := _column_adjacency(depth)
	_order_by_barycenter(columns, max_col, adj["parents"], adj["children"])

	var positions: Dictionary = {}
	for col in columns:
		var y := 0.0
		for id in columns[col]:
			positions[id] = Vector2(col * h_gap, y)
			y += v_gap
	return positions


## Liens entre colonnes ADJACENTES (profondeur c → c+1) : ignore les liens qui
## sautent des colonnes (ils croiseront de toute façon) et les cibles absentes.
##   { "parents": id -> [ids de la colonne de gauche],
##     "children": id -> [ids de la colonne de droite] }.
func _column_adjacency(depth: Dictionary) -> Dictionary:
	var parents: Dictionary = {}
	var children: Dictionary = {}
	for id in story.nodes:
		if not depth.has(id):
			continue
		for link in outgoing(id):
			var target: String = link["target"]
			if not story.has_node(target) or depth.get(target, -1) != depth[id] + 1:
				continue
			children.get_or_add(id, []).append(target)
			parents.get_or_add(target, []).append(id)
	return {"parents": parents, "children": children}


## Quelques balayages gauche→droite (par les parents) et droite→gauche (par les
## enfants) : chaque colonne est triée selon le rang moyen de ses voisins de la
## colonne adjacente. Réduit les croisements sans prétendre les annuler.
func _order_by_barycenter(columns: Dictionary, max_col: int,
		parents: Dictionary, children: Dictionary) -> void:
	var rank := _column_ranks(columns)
	for pass_i in BARYCENTER_PASSES:
		if pass_i % 2 == 0:
			for c in range(1, max_col + 1):
				_sort_column(columns, c, rank, parents)
		else:
			for c in range(max_col - 1, -1, -1):
				_sort_column(columns, c, rank, children)


## Rang (position verticale) courant de chaque nœud dans sa colonne.
func _column_ranks(columns: Dictionary) -> Dictionary:
	var rank: Dictionary = {}
	for col in columns:
		for i in columns[col].size():
			rank[columns[col][i]] = i
	return rank


## Trie une colonne par le barycentre des rangs de ses voisins, et met à jour
## les rangs de cette colonne. Un nœud sans voisin garde sa place courante.
func _sort_column(columns: Dictionary, col: int, rank: Dictionary, neighbors: Dictionary) -> void:
	if not columns.has(col):
		return
	var bary: Dictionary = {}
	for id in columns[col]:
		var neigh: Array = neighbors.get(id, [])
		if neigh.is_empty():
			bary[id] = float(rank.get(id, 0))
		else:
			var sum := 0.0
			for n in neigh:
				sum += float(rank.get(n, 0))
			bary[id] = sum / neigh.size()
	# Tri par barycentre, départage par le rang courant (stabilité).
	columns[col].sort_custom(func(a: String, b: String) -> bool:
		if bary[a] == bary[b]:
			return rank.get(a, 0) < rank.get(b, 0)
		return bary[a] < bary[b])
	for i in columns[col].size():
		rank[columns[col][i]] = i


# ------------------------------------------------- Accessibilité par identité

## Pour chaque nœud atteignable depuis le début, l'ensemble des valeurs de
## `character` sous lesquelles on peut l'atteindre, en ne resserrant QU'AUX
## liens d'identité (identity == true). Downstream : un seul personnage => sa
## couleur ; plusieurs, aucun, ou nœud absent de la carte => accent neutre.
## Retourne { id: Array[String] }.
##
## Limite ASSUMÉE : une garde d'identité sur `type` (attribut Physique/Social/
## Mystique) ne désigne pas un personnage précis — elle laisse l'ensemble
## inchangé (sur-approximation vers « plusieurs », jamais vers une fausse
## couleur unique).
func identity_reach() -> Dictionary:
	var universe := _character_universe()
	if universe.is_empty() or not story.has_node(story.start_node):
		return {}
	var reach: Dictionary = {story.start_node: universe.duplicate()}
	var queue: Array = [story.start_node]
	while not queue.is_empty():
		var id: String = queue.pop_front()
		var src: Array = reach[id]
		for edge in _identity_edges(id, universe):
			if not story.has_node(edge["target"]):
				continue
			var passed := _char_intersect(src, edge["filter"])
			if passed.is_empty():
				continue
			var before: Array = reach.get(edge["target"], [])
			var merged := _char_union(before, passed)
			if merged.size() != before.size():
				reach[edge["target"]] = merged
				if not queue.has(edge["target"]):
					queue.append(edge["target"])
	return reach


## Tous les personnages nommés dans une garde d'identité `character` (== ou !=)
## à travers l'histoire — l'« univers », qui sert de valeur « tous ».
func _character_universe() -> Array:
	var seen: Dictionary = {}
	for id in story.nodes:
		for ins in story.nodes[id].instructions:
			match ins["type"]:
				"choice", "divert":
					for group in ins.get("if", []):
						for cond in group:
							if cond["kind"] == "var" and cond["name"] == "character":
								seen[cond["value"]] = true
				"cond":
					if ins["var"] == "character":
						seen[ins["value"]] = true
	return seen.keys()


## Liens sortants d'un nœud, chacun avec le filtre de personnages qu'il laisse
## passer : sous-ensemble de l'univers pour un lien d'identité `character`,
## univers entier sinon (aucun resserrement).
func _identity_edges(id: String, universe: Array) -> Array:
	var edges: Array = []
	for ins in story.nodes[id].instructions:
		match ins["type"]:
			"choice", "divert":
				var filter: Array = universe
				if ins.has("if") and _guard_identity_only(ins):
					filter = _char_filter_from_guard(ins["if"], universe)
				edges.append({"target": ins["target"], "filter": filter})
			"cond":
				var f: Array = universe
				if IDENTITY_VARS.has(ins["var"]) and _guard_identity_only(ins):
					f = [ins["value"]] if ins["var"] == "character" else universe
				edges.append({"target": ins["target"], "filter": f})
	return edges


## Personnages admis par une garde d'identité (forme disjonctive) : union sur les
## groupes ; dans un groupe, « character == X » restreint à {X}, « character != X »
## retire X, les conditions sur `type` ne touchent pas l'ensemble.
func _char_filter_from_guard(groups: Array, universe: Array) -> Array:
	var result: Dictionary = {}
	for group in groups:
		var cand: Dictionary = {}
		for c in universe:
			cand[c] = true
		for cond in group:
			if cond["kind"] != "var" or cond["name"] != "character":
				continue
			if cond["op"] == "==":
				var only: Dictionary = {}
				if cand.has(cond["value"]):
					only[cond["value"]] = true
				cand = only
			else:
				cand.erase(cond["value"])
		for c in cand:
			result[c] = true
	return result.keys()


func _char_intersect(a: Array, b: Array) -> Array:
	var out: Array = []
	for x in a:
		if b.has(x):
			out.append(x)
	return out


func _char_union(a: Array, b: Array) -> Array:
	var out: Array = a.duplicate()
	for x in b:
		if not out.has(x):
			out.append(x)
	return out
