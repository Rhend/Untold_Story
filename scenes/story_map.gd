class_name StoryMap
extends Control
## Carte de progression narrative (L7, volet jeu) : les embranchements de
## l'acte se révèlent au fil de l'exploration. Sans disposition d'auteur, le
## récit s'enchaîne de HAUT en BAS par défaut (variantes en largeur) ou de
## GAUCHE à DROITE (bouton de bascule dans l'en-tête, choix retenu pour la
## session). La carte s'ouvre centrée sur le nœud courant ; le volet de
## relecture s'ancre à droite en vertical, en bas en horizontal.
##
## La disposition automatique ne place QUE les nœuds dessinés (chaînes visitées
## et bulles « ? ») : les nœuds encore inconnus n'occupent aucune place — la
## carte reste compacte quel que soit le total de nœuds de l'histoire. Chaque
## rangée est centrée sur l'axe du récit puis « redressée » : un nœud se range
## sous le barycentre de ses parents (et au-dessus de celui de ses enfants),
## pour des liens majoritairement verticaux.
##
## Les enchaînements linéaires sont CONTRACTÉS : un nœud visité qui n'a qu'une
## seule sortie (pistes cachées incluses) fusionne avec son successeur visité
## si celui-ci n'a pas d'autre entrée. La carte montre un seul nœud par
## chaîne ; la relecture concatène les textes de ses membres.
##
##  - nœud visité → pilule nommée (titre lisible du sidecar s'il existe, sinon
##    id technique) + pastilles des personnages passés ;
##  - nœud courant → liseré à la couleur du personnage incarné (repère) ;
##  - nœud aperçu (cible d'un choix visible jamais pris) → bulle noire « ? »,
##    dont AUCUNE suite n'est montrée ;
##  - lien découvert → trait continu fléché dans le sens de lecture ;
##  - piste cachée (choix/saut sous condition jamais exploré) → amorce en
##    pointillé qui s'évanouit (fade out), sans révéler la destination.
##    Exception : les liens conditionnés par l'IDENTITÉ du joueur (variantes
##    de personnage, ex. Prologue1 → Prologue1N/S/P) ne sont pas des secrets
##    de l'histoire et ne laissent aucune amorce ;
##  - nœud totalement inconnu → absent de la carte (et sans place réservée) ;
##  - clic sur un nœud visité → liseré sépia + volet de relecture : texte du
##    passage, illustration figée, personnages l'ayant découvert ou non.
##    Ce volet est purement consultatif : aucune interaction narrative.
##
## Filtrage par personnage (boutons on/off de l'en-tête) : un nœud visité
## reste affiché tant qu'AU MOINS un de ses découvreurs est actif ; les nœuds
## découverts uniquement par des personnages masqués disparaissent (avec leurs
## bulles « ? ») et la disposition se recompacte. Filtre remis à zéro à chaque
## ouverture de la carte (contrairement à l'orientation, retenue en session).
##
## Navigation : glisser (clic gauche maintenu) pour se déplacer, Ctrl+molette
## pour zoomer, molette seule pour défiler.

signal close_requested()


## Taille MINIMALE d'une pilule — la largeur réelle suit libellé + pastilles.
const NODE_SIZE := Vector2(96, 32)
const BUBBLE_SIZE := Vector2(28, 28)
const EDGE_COLOR := Color(0.78, 0.7, 0.52, 0.55)
const HIDDEN_COLOR := Color(0.6, 0.55, 0.7)
const MARGIN := Vector2(80, 70)
## Disposition auto verticale : écart entre deux profondeurs (vers le bas) et
## écart horizontal entre deux variantes d'une même profondeur.
const DEPTH_GAP := 92.0
const H_GAP := 30.0
## Disposition auto horizontale : écart entre deux colonnes (après la plus
## large) et écart vertical entre deux variantes d'une même colonne.
const FLOW_GAP_H := 80.0
const CROSS_GAP_H := 22.0
## Courbure des connecteurs : fraction de la distance (projetée sur l'axe du
## flux) dont on décale les points de contrôle de la Bézier (0 = trait droit).
const EDGE_CURVATURE := 0.4
## Balayages de l'heuristique du barycentre (aller/retour) pour ranger les
## rangées et réduire les croisements de liens.
const BARYCENTER_PASSES := 4
## Balayages de redressement (aller/retour) : chaque rangée s'aligne sous le
## barycentre de ses voisines pour rendre les liens verticaux.
const ALIGN_PASSES := 3
## Police des libellés de nœud (sert aussi à mesurer la largeur des pilules).
const LABEL_FONT_SIZE := 13
## Pastille de personnage dans une pilule (côté, px).
const CHIP := 16.0
## Liseré du nœud sélectionné (relecture) — sépia, distinct du nœud courant.
const SEPIA := Color(0.85, 0.64, 0.38)
const PARCHMENT := Color(0.9, 0.86, 0.74)
const RECAP_WIDTH := 460.0
const RECAP_HEIGHT := 340.0
const HEADER_H := 52.0
const MIN_ZOOM := 0.5
const MAX_ZOOM := 2.0
## Marqueur "glue" du format .untold (cf. StoryRunner.GLUE).
const GLUE := "<>"

## Orientation choisie via le bouton de bascule, retenue pour la session
## (la carte est reconstruite à chaque ouverture).
static var preferred_horizontal := false

var _story: Story
var _horizontal := false          # flux gauche → droite plutôt que haut → bas
var _filtered_out: Dictionary = {}  # character_type -> true : nœuds masqués
var _graph: StoryGraph
var _meta: StoryMeta              # titres lisibles + positions d'auteur
var _positions: Dictionary = {}   # rep -> Vector2 (coin haut-gauche du widget)
var _sizes: Dictionary = {}       # rep -> Vector2 (taille réelle du widget)
var _revealed: Dictionary = {}    # id -> "visited" | "known" (nœuds d'origine)
var _map_hidden: Dictionary = {}  # id -> true : nœuds #hors_carte, exclus de la carte
var _chains: Dictionary = {}      # rep -> membres de la chaîne (ordre du récit)
var _rep_of: Dictionary = {}      # id -> rep de sa chaîne (identité hors chaîne)
var _canvas: Control
var _scroll: ScrollContainer
var _characters: Array = []       # CharacterData chargés (pastilles visiteurs)
var _current_id := ""             # nœud où se trouve le joueur
var _current_rep := ""            # sa chaîne sur la carte
var _player_color := Color.WHITE  # couleur du personnage incarné
var _selected_id := ""            # chaîne sélectionnée (volet de relecture)
var _panels: Dictionary = {}      # rep -> PanelContainer des chaînes visitées
var _recap: Control
var _zoom := 1.0
var _panning := false             # glisser-déplacer en cours sur le canevas
var _pan_moved := false           # le glisser a bougé (≠ simple clic à vide)
var _pan_last := Vector2.ZERO     # dernière position globale du curseur


func setup(story: Story, untold_path: String, current_node := "") -> void:
	_story = story
	_graph = StoryGraph.build(story)
	_meta = StoryMeta.load_for(untold_path)
	_current_id = current_node
	_horizontal = preferred_horizontal
	for path in GameState.character_paths():
		var data: CharacterData = load(path)
		if data != null:
			_characters.append(data)
	_player_color = _color_of(GameState.character_type)
	_rebuild()


## (Re)calcule tout le modèle (révélation, chaînes, tailles, positions) puis
## reconstruit l'UI. Appelé au setup, à la bascule d'orientation et à chaque
## changement de filtre personnage.
func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_selected_id = ""
	_recap = null
	_panels.clear()
	_positions.clear()
	_sizes.clear()
	_revealed.clear()
	_map_hidden.clear()
	_chains.clear()
	_rep_of.clear()
	_current_rep = ""
	_zoom = 1.0
	_panning = false

	_compute_map_hidden()
	_compute_revealed()
	_build_chains()
	_compute_sizes()
	_compute_positions()
	_build_ui()


# ------------------------------------------------------------------ Modèle

## Nœuds tagués #hors_carte : jamais dessinés (ni visité, ni aperçu, ni inconnu)
## et jamais suivis comme cible d'un lien. N'affecte pas le jeu (filtrage carte).
func _compute_map_hidden() -> void:
	for id in _story.nodes:
		if "hors_carte" in _story.nodes[id].tags:
			_map_hidden[id] = true


## Règles de révélation. « known » = le joueur a vu le libellé du choix en jeu
## (choix non gardé d'un nœud visité) sans jamais le prendre.
## Le filtre par personnage s'applique ICI : un nœud dont TOUS les découvreurs
## sont masqués n'est pas révélé — chaînes, bulles, liens et disposition
## suivent sans autre traitement.
func _compute_revealed() -> void:
	for id in _story.nodes:
		if _map_hidden.has(id):
			continue
		if Progress.is_visited(id) and _has_active_visitor(id):
			_revealed[id] = "visited"
	for id in _story.nodes:
		if _revealed.get(id) != "visited":
			continue
		for link in _graph.outgoing(id):
			var target: String = link["target"]
			if not _story.has_node(target) or _revealed.has(target) or _map_hidden.has(target):
				continue
			if link["kind"] == "choice" and not link["guarded"]:
				_revealed[target] = "known"


## Contraction des enchaînements linéaires visités : A fusionne avec B si A n'a
## qu'une seule sortie réelle (cachées incluses) menant à B, B est visité et
## aucune autre entrée n'arrive sur B. Le représentant est le premier membre.
func _build_chains() -> void:
	var in_degree: Dictionary = {}
	for id in _story.nodes:
		for link in _real_outgoing(id):
			if link["target"] != id:
				in_degree[link["target"]] = int(in_degree.get(link["target"], 0)) + 1

	var succ: Dictionary = {}
	var has_pred: Dictionary = {}
	for id in _story.nodes:
		if _revealed.get(id) != "visited":
			continue
		var out := _real_outgoing(id)
		if out.size() != 1:
			continue
		var target: String = out[0]["target"]
		if target == id or _revealed.get(target) != "visited" \
				or int(in_degree.get(target, 0)) != 1:
			continue
		succ[id] = target
		has_pred[target] = true

	for id in _story.nodes:  # ordre du fichier → représentants stables
		if _revealed.get(id) != "visited" or has_pred.has(id):
			continue
		var members: Array = [id]
		var cursor: String = id
		while succ.has(cursor):
			cursor = succ[cursor]
			members.append(cursor)
		_chains[id] = members
		for member in members:
			_rep_of[member] = id
	_current_rep = _rep_of.get(_current_id, _current_id)


## Au moins un des personnages passés par ce nœud est-il encore affiché ?
func _has_active_visitor(id: String) -> bool:
	for character in Progress.visitors(id):
		if not _filtered_out.has(str(character)):
			return true
	return false


## Liens sortants vers des nœuds existants et non exclus de la carte (END exclu).
func _real_outgoing(id: String) -> Array:
	return _graph.outgoing(id).filter(
			func(link: Dictionary) -> bool:
				return _story.has_node(link["target"]) and not _map_hidden.has(link["target"]))


## Nom montré au joueur : titre lisible du sidecar s'il existe, sinon id brut.
func _display_name(id: String) -> String:
	var title := _meta.get_title(id) if _meta != null else ""
	return title if not title.is_empty() else id


## Libellé affiché : nom du premier membre, suffixé du nombre de nœuds absorbés.
func _label_of(rep: String) -> String:
	var count: int = _chains.get(rep, [rep]).size()
	var name := _display_name(rep)
	return name if count == 1 else "%s  +%d" % [name, count - 1]


## Taille réelle de chaque widget : la largeur suit le libellé et les pastilles
## (les ids longs ne débordent plus sur leurs voisins ni ne faussent les liens).
func _compute_sizes() -> void:
	var font := ThemeDB.fallback_font
	for rep in _chains:
		var text_width := font.get_string_size(
				_label_of(rep), HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE).x
		var chips: int = _chain_visitors(rep).size()
		var chips_width := 6.0 + chips * CHIP + maxf(chips - 1, 0) * 3.0 if chips > 0 else 0.0
		_sizes[rep] = Vector2(maxf(NODE_SIZE.x, text_width + 24.0 + chips_width), NODE_SIZE.y)
	for id in _revealed:
		if _revealed[id] == "known":
			_sizes[id] = BUBBLE_SIZE


func _size_of(rep: String) -> Vector2:
	return _sizes.get(rep, NODE_SIZE)


func _center_of(rep: String) -> Vector2:
	return _positions.get(rep, Vector2.ZERO) + _size_of(rep) / 2.0


## Cibles sortantes d'une chaîne, ramenées à leur représentant (les liens
## internes à la chaîne ont disparu par construction).
func _contracted_targets(rep: String) -> Array:
	var members: Array = _chains.get(rep, [rep])
	var result: Array = []
	for link in _real_outgoing(members.back()):
		result.append(_rep_of.get(link["target"], link["target"]))
	return result


## Cibles DESSINÉES d'une chaîne : celles reliées par un trait plein sur la
## carte (chaîne visitée ou bulle « ? » d'un choix aperçu). Une bulle n'a
## jamais de suite. Base de la disposition auto ET du dessin des liens.
func _drawn_children(rep: String) -> Array:
	if _revealed.get(rep) == "known":
		return []
	var members: Array = _chains.get(rep, [rep])
	var result: Array = []
	for link in _real_outgoing(members.back()):
		var target: String = link["target"]
		var target_rep: String = _rep_of.get(target, target)
		if target_rep == rep or result.has(target_rep):
			continue
		var target_visited: bool = _revealed.get(target) == "visited"
		var seen_choice: bool = link["kind"] == "choice" and not link["guarded"]
		if target_visited or (seen_choice and _revealed.has(target)):
			result.append(target_rep)
	return result


## Positions des représentants : celles de l'outil narratif (sidecar
## .meta.json) si présentes, sinon disposition automatique VERTICALE — le
## récit descend (profondeur = rangée, défilement de haut en bas), les
## variantes d'une même profondeur se partagent la largeur selon leur taille
## réelle. Recalées pour partir de MARGIN.
func _compute_positions() -> void:
	var authored: Dictionary = _meta.positions()
	if authored.is_empty():
		_auto_layout()
	else:
		# Disposition d'auteur : on reste dans son espace de coordonnées,
		# complété par la disposition auto horizontale d'origine.
		var auto: Dictionary = {}
		for rep in _drawn_reps():
			if _positions.has(rep):
				continue
			if authored.has(rep):
				_positions[rep] = authored[rep]
			else:
				if auto.is_empty():
					auto = _graph.auto_layout()
				_positions[rep] = auto.get(rep, Vector2.ZERO)

	var top_left := Vector2(INF, INF)
	for rep in _drawn_reps():
		top_left = top_left.min(_positions.get(rep, Vector2.ZERO))
	if top_left.x == INF:
		top_left = Vector2.ZERO
	for rep in _positions:
		_positions[rep] = _positions[rep] - top_left + MARGIN


## Disposition auto : ne place QUE les nœuds dessinés. Profondeur (BFS sur le
## graphe dessiné) = rangée (flux vertical) ou colonne (flux horizontal) ;
## chaque rangée est ordonnée (barycentre), paquetée centrée sur l'axe du
## récit, puis redressée sous ses voisines (_straighten).
func _auto_layout() -> void:
	var drawn := _drawn_reps()
	if drawn.is_empty():
		return
	var drawn_set: Dictionary = {}
	for rep in drawn:
		drawn_set[rep] = true

	var start_rep: String = _rep_of.get(_story.start_node, _story.start_node)
	var depth: Dictionary = {}
	var max_depth := 0
	if drawn_set.has(start_rep):
		depth[start_rep] = 0
		var queue: Array = [start_rep]
		while not queue.is_empty():
			var rep: String = queue.pop_front()
			for child in _drawn_children(rep):
				if not depth.has(child):
					depth[child] = depth[rep] + 1
					max_depth = maxi(max_depth, depth[child])
					queue.append(child)

	# Rangée (= profondeur) → représentants, dans l'ordre du fichier au départ.
	# Les dessinés inatteignables (cas limite) forment une rangée finale.
	var rows: Dictionary = {}  # row:int -> Array[rep]
	var max_row := 0
	for id in _story.nodes:  # l'ordre du fichier rend la disposition stable
		var rep: String = _rep_of.get(id, id)
		if rep != id or not drawn_set.has(rep):
			continue
		var row: int = depth.get(rep, max_depth + 1)
		max_row = maxi(max_row, row)
		rows.get_or_add(row, []).append(rep)

	# Heuristique du barycentre (Sugiyama) : réordonne chaque rangée pour réduire
	# les croisements, puis pose les positions selon l'ordre obtenu.
	var adj := _row_adjacency(depth)
	_order_by_barycenter(rows, max_row, adj["parents"], adj["children"])

	# Position le long du flux : rangées régulières en vertical (hauteur de
	# pilule uniforme) ; en horizontal, chaque colonne avance de la largeur de
	# son nœud le plus large.
	var flow: Dictionary = {}  # row -> coordonnée le long du flux
	if _horizontal:
		var x := 0.0
		for row in range(0, max_row + 1):
			if not rows.has(row):
				continue
			flow[row] = x
			var widest := 0.0
			for rep in rows[row]:
				widest = maxf(widest, _size_of(rep).x)
			x += widest + FLOW_GAP_H
	else:
		for row in rows:
			flow[row] = row * DEPTH_GAP

	# Paquetage initial : chaque rangée centrée sur l'axe transverse = 0.
	var axis := _cross_axis()
	var gap := _cross_gap()
	for row in rows:
		var total := -gap
		for rep in rows[row]:
			total += _size_of(rep)[axis] + gap
		var c := -total / 2.0
		for rep in rows[row]:
			_positions[rep] = Vector2(flow[row], c) if _horizontal else Vector2(c, flow[row])
			c += _size_of(rep)[axis] + gap

	_straighten(rows, max_row, adj)


## Axe TRANSVERSE au flux : x quand le récit descend, y quand il va à droite.
func _cross_axis() -> int:
	return Vector2.AXIS_Y if _horizontal else Vector2.AXIS_X


func _cross_gap() -> float:
	return CROSS_GAP_H if _horizontal else H_GAP


func _set_cross(rep: String, value: float) -> void:
	var pos: Vector2 = _positions[rep]
	pos[_cross_axis()] = value
	_positions[rep] = pos


## Liens entre rangées ADJACENTES (profondeur r → r+1) dans le graphe dessiné :
##   { "parents": rep -> [reps de la rangée du dessus],
##     "children": rep -> [reps de la rangée du dessous] }.
## Les liens qui sautent des rangées sont ignorés (ils croiseront de toute façon).
func _row_adjacency(depth: Dictionary) -> Dictionary:
	var parents: Dictionary = {}
	var children: Dictionary = {}
	for rep in _chains:
		if not depth.has(rep):
			continue
		for target in _drawn_children(rep):
			if depth.get(target, -1) != depth[rep] + 1:
				continue
			children.get_or_add(rep, []).append(target)
			parents.get_or_add(target, []).append(rep)
	return {"parents": parents, "children": children}


## Quelques balayages haut→bas (par les parents) et bas→haut (par les enfants) :
## chaque rangée est triée selon la position moyenne de ses voisins de la rangée
## adjacente. Réduit les croisements sans prétendre les annuler.
func _order_by_barycenter(rows: Dictionary, max_depth: int,
		parents: Dictionary, children: Dictionary) -> void:
	var rank := _row_ranks(rows)
	for pass_i in BARYCENTER_PASSES:
		if pass_i % 2 == 0:
			for r in range(1, max_depth + 1):
				_sort_row(rows, r, rank, parents)
		else:
			for r in range(max_depth - 1, -1, -1):
				_sort_row(rows, r, rank, children)


## Rang (position horizontale) courant de chaque rep dans sa rangée.
func _row_ranks(rows: Dictionary) -> Dictionary:
	var rank: Dictionary = {}
	for row in rows:
		for i in rows[row].size():
			rank[rows[row][i]] = i
	return rank


## Trie une rangée par le barycentre des rangs de ses voisins (neighbors), et met
## à jour les rangs de cette rangée. Un rep sans voisin garde sa place courante.
func _sort_row(rows: Dictionary, row: int, rank: Dictionary, neighbors: Dictionary) -> void:
	if not rows.has(row):
		return
	var bary: Dictionary = {}
	for rep in rows[row]:
		var neigh: Array = neighbors.get(rep, [])
		if neigh.is_empty():
			bary[rep] = float(rank.get(rep, 0))
		else:
			var sum := 0.0
			for n in neigh:
				sum += float(rank.get(n, 0))
			bary[rep] = sum / neigh.size()
	# Tri par barycentre, départage par le rang courant (stabilité).
	rows[row].sort_custom(func(a: String, b: String) -> bool:
		if bary[a] == bary[b]:
			return rank.get(a, 0) < rank.get(b, 0)
		return bary[a] < bary[b])
	for i in rows[row].size():
		rank[rows[row][i]] = i


## Redressement des abscisses : balayages alternés haut→bas (chaque nœud vise le
## barycentre de ses parents) et bas→haut (celui de ses enfants). L'ordre de la
## rangée est préservé ; les chevauchements se résolvent en poussant depuis la
## gauche ou la droite selon le balayage — les liens deviennent verticaux.
## Le nombre de balayages est IMPAIR : le dernier descend, l'alignement sous
## les parents a le dernier mot (les feuilles restent près de leur source).
func _straighten(rows: Dictionary, max_row: int, adj: Dictionary) -> void:
	for sweep in ALIGN_PASSES * 2 + 1:
		var down := sweep % 2 == 0
		var neighbors: Dictionary = adj["parents"] if down else adj["children"]
		var from_left := (sweep % 4) < 2
		var seq: Array = range(1, max_row + 1) if down else range(max_row - 1, -1, -1)
		for row in seq:
			if rows.has(row):
				_align_row(rows[row], neighbors, from_left)


## Aligne une rangée sur les centres visés (barycentre des voisins), en résolvant
## les collisions par un passage glouton depuis un bord ou depuis l'autre.
## Tout se joue sur l'axe TRANSVERSE au flux (x en vertical, y en horizontal).
func _align_row(reps: Array, neighbors: Dictionary, from_start: bool) -> void:
	var axis := _cross_axis()
	var gap := _cross_gap()
	var want: Array = []
	for rep in reps:
		var neigh: Array = neighbors.get(rep, [])
		if neigh.is_empty():
			want.append(_center_of(rep)[axis])
		else:
			var sum := 0.0
			for n in neigh:
				sum += _center_of(n)[axis]
			want.append(sum / neigh.size())
	_spread_sibling_targets(reps, want)
	if from_start:
		var cursor := -INF
		for i in reps.size():
			var w := _size_of(reps[i])[axis]
			var c := maxf(want[i] - w / 2.0, cursor)
			_set_cross(reps[i], c)
			cursor = c + w + gap
	else:
		var cursor := INF
		for i in range(reps.size() - 1, -1, -1):
			var w := _size_of(reps[i])[axis]
			var c := minf(want[i] - w / 2.0, cursor - w)
			_set_cross(reps[i], c)
			cursor = c - gap


## Des voisins de rangée qui visent le MÊME centre (frères d'un même parent) se
## pousseraient en chaîne d'un seul côté : on les répartit plutôt autour du
## centre commun, chacun à sa place dans l'ordre de la rangée.
func _spread_sibling_targets(reps: Array, want: Array) -> void:
	var axis := _cross_axis()
	var gap := _cross_gap()
	var i := 0
	while i < reps.size():
		var j := i
		while j + 1 < reps.size() and absf(want[j + 1] - want[i]) < 0.5:
			j += 1
		if j > i:
			var total := -gap
			for k in range(i, j + 1):
				total += _size_of(reps[k])[axis] + gap
			var c: float = want[i] - total / 2.0
			for k in range(i, j + 1):
				var w := _size_of(reps[k])[axis]
				want[k] = c + w / 2.0
				c += w + gap
		i = j + 1


## Représentants effectivement dessinés : chaînes visitées + bulles « ? ».
func _drawn_reps() -> Array:
	var reps: Array = _chains.keys()
	for id in _revealed:
		if _revealed[id] == "known":
			reps.append(id)
	return reps


# --------------------------------------------------------------------- UI

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.045, 0.075, 0.98)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_top = HEADER_H
	add_child(_scroll)

	# Le conteneur centreur occupe toute la zone visible : une carte encore
	# petite (début de partie) s'affiche au centre plutôt que collée en haut à
	# gauche. Il relaie aussi la navigation depuis le vide autour du canevas.
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.gui_input.connect(_on_canvas_input)
	_scroll.add_child(center)

	_canvas = Control.new()
	_canvas.custom_minimum_size = _canvas_bounds()
	_canvas.draw.connect(_draw_edges)
	_canvas.gui_input.connect(_on_canvas_input)
	center.add_child(_canvas)

	for rep in _drawn_reps():
		_canvas.add_child(_make_widget(rep))

	# Ouvre la carte centrée sur « vous êtes ici » (différé : les plages de
	# défilement ne sont valides qu'après la première mise en page).
	if _panels.has(_current_rep):
		_center_on.call_deferred(_current_rep)

	add_child(_build_header())
	add_child(_build_footer_hint())


## Barre d'en-tête : titre, progression (compteur + jauge), légende, fermeture.
func _build_header() -> Control:
	var header := PanelContainer.new()
	header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header.custom_minimum_size = Vector2(0, HEADER_H)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.11)
	style.border_width_bottom = 1
	style.border_color = Color(0.5, 0.45, 0.35, 0.35)
	style.content_margin_left = 20
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	header.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	header.add_child(row)

	var title := Label.new()
	title.text = "Carte de l'histoire"
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", PARCHMENT)
	row.add_child(title)

	row.add_child(_build_progress_box())

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	# Filtres par personnage (uniquement ceux ayant découvert quelque chose :
	# un bouton sans effet n'aurait rien à masquer).
	var any_filter := false
	for data in _characters:
		if _character_has_discoveries(data.character_type):
			row.add_child(_make_filter_toggle(data))
			any_filter = true
	if any_filter:
		var sep := VSeparator.new()
		sep.modulate = Color(1, 1, 1, 0.25)
		row.add_child(sep)

	var flip := Button.new()
	flip.text = "⇅  Vue verticale" if _horizontal else "⇄  Vue horizontale"
	flip.tooltip_text = "Bascule le sens de lecture de la carte"
	flip.flat = true
	flip.focus_mode = Control.FOCUS_NONE
	flip.add_theme_font_size_override("font_size", 13)
	flip.pressed.connect(func() -> void: _set_orientation(not _horizontal))
	row.add_child(flip)

	row.add_child(_legend_item("current", "Vous êtes ici"))
	row.add_child(_legend_item("bubble", "Entrevu"))
	row.add_child(_legend_item("hidden", "Piste cachée"))

	var close := Button.new()
	close.text = "✕  Fermer"
	close.tooltip_text = "Touche M"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 13)
	close.pressed.connect(func() -> void: close_requested.emit())
	row.add_child(close)
	return header


## Compteur de découverte : « n / total » au-dessus d'une fine jauge sépia.
func _build_progress_box() -> Control:
	var seen: int = Progress.visited_count()
	var total: int = _story.nodes.size()

	var box := VBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_theme_constant_override("separation", 4)

	var label := Label.new()
	label.text = "%d / %d nœuds découverts" % [seen, total]
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.7, 0.66, 0.58))
	box.add_child(label)

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(150, 5)
	bar.max_value = maxi(total, 1)
	bar.value = seen
	bar.show_percentage = false
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(1, 1, 1, 0.08)
	bar_bg.set_corner_radius_all(2)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = SEPIA
	bar_fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", bar_bg)
	bar.add_theme_stylebox_override("fill", bar_fill)
	box.add_child(bar)
	return box


## Ce personnage a-t-il découvert au moins un nœud de la carte ?
func _character_has_discoveries(character_type: String) -> bool:
	for id in _story.nodes:
		if not _map_hidden.has(id) and Progress.visitors(id).has(character_type):
			return true
	return false


## Filtre par personnage : bouton on/off à sa couleur — enfoncé, ses nœuds
## sont visibles ; relâché, les nœuds qu'il est seul à avoir découverts
## disparaissent de la carte (elle se recompacte).
func _make_filter_toggle(data: CharacterData) -> Button:
	var active := not _filtered_out.has(data.character_type)
	var toggle := Button.new()
	toggle.toggle_mode = true
	toggle.button_pressed = active
	toggle.flat = true
	toggle.focus_mode = Control.FOCUS_NONE
	# ● = ses nœuds sont visibles, ○ = masqués (en plus de l'atténuation).
	toggle.text = ("●  %s" if active else "○  %s") % data.character_type
	toggle.tooltip_text = ("Masquer les nœuds découverts par %s" if active
			else "Réafficher les nœuds découverts par %s") % data.character_type
	toggle.add_theme_font_size_override("font_size", 13)
	for state in ["font_color", "font_pressed_color", "font_hover_color",
			"font_hover_pressed_color"]:
		toggle.add_theme_color_override(state, data.color)
	if not active:
		toggle.modulate = Color(1, 1, 1, 0.45)
	toggle.toggled.connect(func(pressed: bool) -> void:
		if pressed:
			_filtered_out.erase(data.character_type)
		else:
			_filtered_out[data.character_type] = true
		_rebuild())
	return toggle


## Entrée de légende : petit glyphe dessiné + libellé discret.
func _legend_item(kind: String, text: String) -> Control:
	var item := HBoxContainer.new()
	item.add_theme_constant_override("separation", 6)

	var glyph := Control.new()
	glyph.custom_minimum_size = Vector2(24, 16)
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	glyph.draw.connect(func() -> void: _draw_legend_glyph(glyph, kind))
	item.add_child(glyph)

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.7, 0.66, 0.58))
	item.add_child(label)
	return item


func _draw_legend_glyph(glyph: Control, kind: String) -> void:
	match kind:
		"current":
			var pill := StyleBoxFlat.new()
			pill.bg_color = Color(0.12, 0.11, 0.16)
			pill.set_border_width_all(2)
			pill.border_color = _player_color
			pill.set_corner_radius_all(8)
			pill.draw(glyph.get_canvas_item(), Rect2(0, 0, 24, 16))
		"bubble":
			glyph.draw_circle(Vector2(12, 8), 7.0, Color(0.02, 0.02, 0.03))
			glyph.draw_arc(Vector2(12, 8), 7.0, 0.0, TAU, 24, Color(0.35, 0.35, 0.4), 1.5, true)
			glyph.draw_string(ThemeDB.fallback_font, Vector2(9.5, 12), "?",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
		"hidden":
			var x := 1.0
			for i in 3:
				var alpha := 0.8 * (1.0 - float(i) / 3.0)
				glyph.draw_line(Vector2(x, 8), Vector2(x + 5, 8),
						Color(HIDDEN_COLOR.r, HIDDEN_COLOR.g, HIDDEN_COLOR.b, alpha), 1.6, true)
				x += 9.0


## Rappel discret des commandes de navigation, hors du chemin du regard.
func _build_footer_hint() -> Control:
	var hint := Label.new()
	hint.text = "Glisser : déplacer   ·   Ctrl + molette : zoom   ·   M : fermer"
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(20, -34)
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(1, 1, 1, 0.4)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return hint


## Bascule le flux vertical ↔ horizontal et reconstruit toute la carte (même
## modèle, disposition et volet réorientés). Le choix vaut pour la session.
func _set_orientation(horizontal: bool) -> void:
	if horizontal == _horizontal:
		return
	_horizontal = horizontal
	StoryMap.preferred_horizontal = horizontal
	_rebuild()


func _center_on(rep: String) -> void:
	var center := _center_of(rep) * _zoom
	_scroll.scroll_horizontal = int(center.x - _scroll.size.x / 2.0)
	_scroll.scroll_vertical = int(center.y - _scroll.size.y / 2.0)


func _canvas_bounds() -> Vector2:
	var bounds := Vector2.ZERO
	for rep in _drawn_reps():
		bounds = bounds.max(_positions[rep] + _size_of(rep))
	return bounds + MARGIN


func _make_widget(rep: String) -> Control:
	if _revealed.get(rep) == "known":
		return _make_bubble(rep)
	return _make_node_panel(rep)


## Chaîne visitée : pilule sur UNE ligne — libellé + pastilles des personnages
## qui y sont passés (union des membres). Cliquable (sélection → relecture).
func _make_node_panel(rep: String) -> Control:
	var panel := PanelContainer.new()
	panel.position = _positions[rep]
	panel.custom_minimum_size = _size_of(rep)
	panel.add_theme_stylebox_override("panel", _panel_style(rep))
	panel.gui_input.connect(_on_panel_input.bind(rep))
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var members: Array = _chains.get(rep, [rep])
	panel.tooltip_text = " → ".join(PackedStringArray(members)) if members.size() > 1 else String(rep)
	if rep == _current_rep:
		panel.tooltip_text += "\nVous êtes ici"
	_panels[rep] = panel

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)

	var name_label := Label.new()
	name_label.text = _label_of(rep)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	name_label.add_theme_color_override("font_color", PARCHMENT)
	row.add_child(name_label)

	var visitors := HBoxContainer.new()
	visitors.add_theme_constant_override("separation", 3)
	visitors.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(visitors)
	for character in _chain_visitors(rep):
		visitors.add_child(_make_visitor_chip(str(character)))

	return panel


## Personnages passés par AU MOINS un membre de la chaîne.
func _chain_visitors(rep: String) -> Array:
	var seen: Dictionary = {}
	for member in _chains.get(rep, [rep]):
		for character in Progress.visitors(member):
			seen[str(character)] = true
	return seen.keys()


## Style de la pilule :
##  - fond/bordure teintés par le personnage quand UN SEUL l'a traversée ;
##    accent neutre si plusieurs (les pastilles distinguent déjà qui) ;
##  - sélectionnée → liseré sépia (volet de relecture ouvert) ;
##  - courante     → liseré à la couleur du personnage incarné.
func _panel_style(rep: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	# Rayon = moitié de la hauteur du nœud → vrai effet pilule.
	style.set_corner_radius_all(int(_size_of(rep).y / 2.0))
	style.content_margin_left = 12
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4

	# Accent par personnage : couleur du seul visiteur, sinon neutre.
	var visitors: Array = _chain_visitors(rep)
	if visitors.size() == 1:
		var accent := _color_of(str(visitors[0]))
		style.bg_color = Color(0.12, 0.11, 0.16).lerp(accent, 0.18)
		style.border_color = accent.lerp(Color(0.5, 0.45, 0.35), 0.35)
	else:
		style.bg_color = Color(0.12, 0.11, 0.16)
		style.border_color = Color(0.5, 0.45, 0.35)
	style.set_border_width_all(1)

	var outline := Color.TRANSPARENT
	if rep == _selected_id:
		outline = SEPIA
	elif rep == _current_rep:
		outline = _player_color
	if outline != Color.TRANSPARENT:
		style.set_border_width_all(2)
		style.border_color = outline
		style.shadow_color = Color(outline.r, outline.g, outline.b, 0.45)
		style.shadow_size = 8
	return style


## Couleur d'un personnage : sa ressource si connue, sinon une teinte stable
## dérivée de son nom.
func _color_of(character_type: String) -> Color:
	for data in _characters:
		if data.character_type == character_type:
			return data.color
	return Color.from_hsv(fmod(abs(float(character_type.hash())) / 1000.0, 1.0), 0.55, 0.9)


## Pastille d'un personnage : son icône si connue, sinon un point à sa couleur.
func _make_visitor_chip(character_type: String) -> Control:
	for data in _characters:
		if data.character_type != character_type:
			continue
		var texture: Texture2D = data.icon if data.icon != null else data.bust
		if texture != null:
			var chip := TextureRect.new()
			chip.texture = texture
			chip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			chip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			chip.custom_minimum_size = Vector2(CHIP, CHIP)
			chip.tooltip_text = character_type
			chip.mouse_filter = Control.MOUSE_FILTER_PASS
			return chip
	# Personnage sans ressource (ou sans image) : point coloré + initiale.
	var dot := Label.new()
	dot.text = "●"
	dot.tooltip_text = character_type
	dot.mouse_filter = Control.MOUSE_FILTER_PASS
	dot.add_theme_color_override("font_color", _color_of(character_type))
	dot.add_theme_font_size_override("font_size", 11)
	return dot


## Nœud aperçu mais jamais visité : bulle noire avec un « ? » blanc.
func _make_bubble(id: String) -> Control:
	var bubble := PanelContainer.new()
	bubble.position = _positions[id]
	bubble.custom_minimum_size = BUBBLE_SIZE
	bubble.tooltip_text = "Nœud non exploré"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.02, 0.03)
	style.set_border_width_all(1)
	style.border_color = Color(0.35, 0.35, 0.4)
	style.set_corner_radius_all(int(BUBBLE_SIZE.x / 2.0))
	bubble.add_theme_stylebox_override("panel", style)

	var mark := Label.new()
	mark.text = "?"
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.add_theme_font_size_override("font_size", 14)
	mark.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	bubble.add_child(mark)
	return bubble


# ------------------------------------------------- Sélection et navigation

func _on_panel_input(event: InputEvent, rep: String) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_select(rep)


## Canevas : glisser pour déplacer la vue, Ctrl+molette pour zoomer, simple
## clic dans le vide (sans glisser) pour refermer le volet de relecture.
func _on_canvas_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_panning = true
				_pan_moved = false
				_pan_last = get_global_mouse_position()
			else:
				_panning = false
				if not _pan_moved and _selected_id != "":
					_select(_selected_id)
		elif event.pressed and event.ctrl_pressed \
				and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var factor := 1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15
			_set_zoom(_zoom * factor)
			accept_event()
	elif event is InputEventMouseMotion and _panning:
		var pos := get_global_mouse_position()
		var delta := pos - _pan_last
		_pan_last = pos
		if delta != Vector2.ZERO:
			_pan_moved = true
			_scroll.scroll_horizontal -= int(delta.x)
			_scroll.scroll_vertical -= int(delta.y)


## Zoome le canevas en gardant (au mieux) le point sous le curseur immobile.
func _set_zoom(value: float) -> void:
	var zoom := clampf(value, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(zoom, _zoom):
		return
	var mouse := _scroll.get_local_mouse_position()
	var anchor := (Vector2(_scroll.scroll_horizontal, _scroll.scroll_vertical) + mouse) / _zoom
	_zoom = zoom
	_canvas.scale = Vector2(_zoom, _zoom)
	_canvas.custom_minimum_size = _canvas_bounds() * _zoom
	# Les plages de défilement ne suivent la nouvelle taille qu'à la mise en
	# page suivante : on recale le défilement en différé.
	var target := anchor * _zoom - mouse
	_apply_scroll.call_deferred(target)


func _apply_scroll(target: Vector2) -> void:
	_scroll.scroll_horizontal = int(target.x)
	_scroll.scroll_vertical = int(target.y)


## Sélectionne une chaîne (ou la désélectionne si elle l'était déjà) et met à
## jour liserés + volet de relecture.
func _select(rep: String) -> void:
	var previous := _selected_id
	_selected_id = "" if rep == _selected_id else rep
	for node_id in [previous, _selected_id]:
		if _panels.has(node_id):
			_panels[node_id].add_theme_stylebox_override("panel", _panel_style(node_id))
	if _recap != null:
		_recap.queue_free()
		_recap = null
	if _selected_id != "":
		_show_recap(_selected_id)


# ---------------------------------------------------- Volet de relecture

## Volet de relecture, purement consultatif : titre, illustration figée,
## personnages l'ayant découvert ou non, textes de la chaîne concaténés.
## Ancré au bord DROIT quand le récit descend (contenu empilé), au bord BAS
## quand il va à droite (illustration à gauche, textes à droite).
func _show_recap(rep: String) -> void:
	var members: Array = _chains.get(rep, [rep])

	_recap = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.075, 0.065, 0.105, 0.99)
	style.border_color = Color(SEPIA.r, SEPIA.g, SEPIA.b, 0.5)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 18
	style.set_content_margin_all(20)
	if _horizontal:
		_recap.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		_recap.offset_top = -RECAP_HEIGHT
		style.border_width_top = 1
		style.shadow_offset = Vector2(0, -6)
	else:
		_recap.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		_recap.offset_left = -RECAP_WIDTH
		_recap.offset_top = HEADER_H
		style.border_width_left = 1
		style.shadow_offset = Vector2(-6, 0)
	_recap.add_theme_stylebox_override("panel", style)
	add_child(_recap)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_recap.add_child(col)

	# En-tête : étendue de la chaîne + fermeture du volet.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	var title := Label.new()
	title.text = _display_name(rep) if members.size() == 1 \
			else "%s  →  %s" % [_display_name(members.front()), _display_name(members.back())]
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", SEPIA)
	head.add_child(title)
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: _select(_selected_id))
	head.add_child(close)

	# Version du texte rejouée : celle du personnage incarné s'il est passé
	# par là, sinon celle du premier découvreur.
	var reader := _recap_reader(rep)
	var reader_vars := {"character": reader, "type": _attribute_of(reader)}

	# Première illustration de la chaîne, figée (source de regard neutre :
	# pas de parallaxe, aucune interaction).
	var illustration: Illustration = null
	var illustration_data: IllustrationData = null
	var illustration_name := _chain_illustration(members, reader_vars)
	if illustration_name != "":
		illustration_data = IllustrationLibrary.get_illustration(illustration_name)
		if illustration_data != null:
			illustration = Illustration.new()
			illustration.look_source = LookSource.new()

	var summary := _make_discovery_summary(rep)
	var rule := ColorRect.new()
	rule.color = Color(1, 1, 1, 0.08)
	rule.custom_minimum_size = Vector2(0, 1)
	var body := _make_recap_body(members, reader, reader_vars)

	if _horizontal:
		var content := HBoxContainer.new()
		content.add_theme_constant_override("separation", 18)
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(content)
		if illustration != null:
			illustration.custom_minimum_size = Vector2(400, 0)
			content.add_child(illustration)
		var right := VBoxContainer.new()
		right.add_theme_constant_override("separation", 10)
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.add_child(right)
		right.add_child(summary)
		right.add_child(rule)
		right.add_child(body)
	else:
		if illustration != null:
			illustration.custom_minimum_size = Vector2(0, 240)
			col.add_child(illustration)
		col.add_child(summary)
		col.add_child(rule)
		col.add_child(body)

	if illustration != null:
		illustration.setup(illustration_data)


## Textes des membres concaténés, relisibles mais sans aucune interaction.
func _make_recap_body(members: Array, reader: String, reader_vars: Dictionary) -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override("normal_font_size", 15)
	body.add_theme_constant_override("line_separation", 3)
	var parts: Array = []
	for member in members:
		var part := _replay_text(member, reader_vars)
		if not part.is_empty():
			parts.append(part)
	var text := "\n\n".join(PackedStringArray(parts))
	if text.is_empty():
		body.text = "[i]Passage sans texte (transition).[/i]"
	elif reader != GameState.character_type:
		body.text = "[i]Version lue par %s :[/i]\n\n%s" % [reader, text]
	else:
		body.text = text
	scroll.add_child(body)
	return scroll


## Deux lignes : personnages ayant découvert la chaîne, et ceux qui ne l'ont
## pas encore fait (parmi les personnages jouables connus).
func _make_discovery_summary(rep: String) -> Control:
	var visitors: Array = _chain_visitors(rep)
	var found: Array = []
	var missing: Array = []
	for data in _characters:
		if visitors.has(data.character_type):
			found.append(data.character_type)
		else:
			missing.append(data.character_type)
	for character in visitors:  # découvreurs hors ressources connues
		if not found.has(character):
			found.append(character)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(_make_discovery_row("Découvert par :", found, false))
	if not missing.is_empty():
		box.add_child(_make_discovery_row("Pas encore par :", missing, true))
	return box


func _make_discovery_row(caption_text: String, characters: Array, dimmed: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var caption := Label.new()
	caption.text = caption_text
	caption.custom_minimum_size = Vector2(110, 0)
	caption.add_theme_font_size_override("font_size", 13)
	caption.modulate = Color(0.75, 0.7, 0.6)
	row.add_child(caption)
	for character in characters:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 3)
		cell.add_child(_make_visitor_chip(str(character)))
		var name_label := Label.new()
		name_label.text = str(character)
		name_label.add_theme_font_size_override("font_size", 13)
		cell.add_child(name_label)
		if dimmed:
			cell.modulate = Color(1, 1, 1, 0.4)
		row.add_child(cell)
	return row


# ----------------------------------------------- Relecture du contenu du nœud

## Personnage dont on rejoue la version du texte.
func _recap_reader(rep: String) -> String:
	var visitors: Array = _chain_visitors(rep)
	if visitors.is_empty() or visitors.has(GameState.character_type):
		return GameState.character_type
	return str(visitors[0])


func _attribute_of(character: String) -> String:
	if character == GameState.character_type:
		return GameState.character_attribute
	for data in _characters:
		if data.character_type == character:
			return data.attribute
	return ""


## Texte d'un nœud tel que le personnage `vars` l'a lu : lignes dont la garde
## passe, recollées avec la même logique de glue que le StoryRunner.
func _replay_text(id: String, vars: Dictionary) -> String:
	var buffer := ""
	for ins in _story.nodes[id].instructions:
		if ins["type"] != "text":
			continue
		if ins.has("if") and not _guard_true(ins["if"], vars):
			continue
		var line: String = ins["value"]
		var glue := line.begins_with(GLUE)
		if glue:
			line = line.trim_prefix(GLUE)
		if buffer.is_empty():
			buffer = line
		elif buffer.ends_with(GLUE):
			buffer = buffer.trim_suffix(GLUE) + line
		elif glue:
			buffer += line
		else:
			buffer += "\n" + line
	return buffer.trim_suffix(GLUE).strip_edges()


## Nom de la première illustration affichée le long de la chaîne (commande
## @illustration dont la garde passe), ou "" s'il n'y en a pas.
func _chain_illustration(members: Array, vars: Dictionary) -> String:
	for member in members:
		for ins in _story.nodes[member].instructions:
			if ins["type"] != "command" or ins["name"] != "illustration":
				continue
			if ins.has("if") and not _guard_true(ins["if"], vars):
				continue
			if ins["args"].size() > 0:
				return str(ins["args"][0])
	return ""


## Évalue une garde (forme disjonctive, cf. StoryParser) hors exécution :
## les variables viennent de `vars`, visited() de la progression persistée.
func _guard_true(groups: Array, vars: Dictionary) -> bool:
	for conds in groups:
		var ok := true
		for cond in conds:
			match cond["kind"]:
				"var":
					var equal: bool = str(vars.get(cond["name"], "")) == cond["value"]
					if (cond["op"] == "==") != equal:
						ok = false
				"visited":
					if Progress.is_visited(cond["id"]) == cond["neg"]:
						ok = false
				"zone":
					if Progress.is_zone_clicked(cond["id"]) == cond["neg"]:
						ok = false
				"item":
					if Progress.has_item(cond["id"], cond["qty"]) == cond["neg"]:
						ok = false
			if not ok:
				break
		if ok:
			return true
	return false


# ------------------------------------------------------------------ Arêtes

## Dessinées sous les widgets (les enfants du canvas passent au-dessus), après
## une trame de points discrète qui donne l'échelle. Les liens partent du
## DERNIER membre de chaque chaîne visitée ; les liens internes n'existent plus.
func _draw_edges() -> void:
	_draw_grid()
	for rep in _chains:
		var members: Array = _chains[rep]
		var from_center := _center_of(rep)
		for link in _real_outgoing(members.back()):
			var target: String = link["target"]
			var target_rep: String = _rep_of.get(target, target)
			if target_rep == rep:
				continue
			var target_visited: bool = _revealed.get(target) == "visited"
			var seen_choice: bool = link["kind"] == "choice" and not link["guarded"]
			if target_visited or (seen_choice and _revealed.has(target)):
				_draw_arrow_edge(from_center, target_rep)
			elif not link.get("identity", false):
				# Une variante de personnage non explorée (ex. Prologue1 selon
				# le héros incarné) n'est PAS une piste cachée : rien à montrer.
				_draw_hidden_stub(rep, target)


## Trame de fond : un point discret tous les GRID_STEP px — repère d'échelle
## pendant le glisser/zoom, sans jamais concurrencer le graphe.
func _draw_grid() -> void:
	const GRID_STEP := 64.0
	var bounds := _canvas_bounds()
	var dots := PackedVector2Array()
	var y := GRID_STEP
	while y < bounds.y:
		var x := GRID_STEP
		while x < bounds.x:
			dots.append(Vector2(x, y))
			dots.append(Vector2(x + 1.5, y))
			x += GRID_STEP
		y += GRID_STEP
	if dots.size() >= 2:
		_canvas.draw_multiline(dots, Color(1, 1, 1, 0.05), 1.5)


## Lien découvert : courbe pleine, tronquée au bord du nœud cible et terminée
## par une pointe de flèche (sens de lecture).
func _draw_arrow_edge(from_center: Vector2, target_rep: String) -> void:
	var to_center := _center_of(target_rep)
	var points := _edge_curve(from_center, to_center).tessellate()
	var rect := Rect2(_positions.get(target_rep, Vector2.ZERO), _size_of(target_rep)).grow(3.0)
	var trimmed := _trim_to_rect(points, rect)
	if trimmed.size() < 2:
		return
	_canvas.draw_polyline(trimmed, EDGE_COLOR, 1.6, true)
	var tip: Vector2 = trimmed[trimmed.size() - 1]
	var dir := (tip - trimmed[trimmed.size() - 2]).normalized()
	if dir == Vector2.ZERO:
		return
	var side := dir.orthogonal() * 3.5
	var base := tip - dir * 7.0
	var head := Color(EDGE_COLOR.r, EDGE_COLOR.g, EDGE_COLOR.b, 0.9)
	_canvas.draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), head)


## Tronque une polyligne juste avant son entrée (finale) dans `rect` : la pointe
## de flèche se pose sur le bord du nœud, pas en son centre.
func _trim_to_rect(points: PackedVector2Array, rect: Rect2) -> PackedVector2Array:
	var last := points.size() - 1
	var outside := last
	while outside >= 0 and rect.has_point(points[outside]):
		outside -= 1
	if outside < 0:
		return PackedVector2Array()  # entièrement dans le rect : rien à dessiner
	if outside == last:
		return points  # la courbe ne finit pas dans le rect : inchangée
	# Affine le point de bord entre points[outside] (dehors) et le suivant (dedans).
	var a := points[outside]
	var b := points[outside + 1]
	for i in 8:
		var mid := (a + b) * 0.5
		if rect.has_point(mid):
			b = mid
		else:
			a = mid
	var trimmed := points.slice(0, outside + 1)
	trimmed.append(a)
	return trimmed


## Courbe d'un lien : Bézier cubique dont les points de contrôle sont décalés le
## long de l'AXE DU FLUX (l'axe dominant de la distance — vertical en disposition
## auto, horizontal en disposition d'auteur), même principe que la courbure de
## GraphEdit mais dessinée à la main.
func _edge_curve(from_center: Vector2, to_center: Vector2) -> Curve2D:
	var delta := to_center - from_center
	var bend: Vector2
	if absf(delta.y) >= absf(delta.x):
		bend = Vector2(0.0, delta.y * EDGE_CURVATURE)
	else:
		bend = Vector2(delta.x * EDGE_CURVATURE, 0.0)
	var curve := Curve2D.new()
	curve.add_point(from_center, Vector2.ZERO, bend)   # sort dans le sens du flux
	curve.add_point(to_center, -bend, Vector2.ZERO)    # arrive dans le sens du flux
	return curve


## Amorce de piste cachée : pointillés qui s'évanouissent EN SUIVANT LA COURBE
## vers la cible, tronqués pour ne rien révéler de sa position exacte. Une cible
## absente de la carte (non placée) reçoit une amorce vers le bas — le sens du
## récit — légèrement déportée pour distinguer plusieurs pistes voisines.
func _draw_hidden_stub(rep: String, target: String) -> void:
	var from_center := _center_of(rep)
	var target_rep: String = _rep_of.get(target, target)
	var toward: Vector2
	if _positions.has(target_rep):
		toward = _center_of(target_rep)
	else:
		var fan := float(int(target.hash() % 3)) - 1.0  # -1 | 0 | 1, stable par cible
		if _horizontal:
			toward = from_center + Vector2(_size_of(rep).x / 2.0 + 100.0, fan * 46.0)
		else:
			toward = from_center + Vector2(fan * 70.0, DEPTH_GAP)
	var curve := _edge_curve(from_center, toward)
	var length := curve.get_baked_length()
	const DASH := 7.0
	const GAP := 6.0
	const COUNT := 6
	# Démarre au bord du nœud source, selon l'axe du flux.
	var cursor := (_size_of(rep).x if _horizontal else _size_of(rep).y) * 0.5 + 4.0
	for i in COUNT:
		if cursor >= length:
			break
		var alpha := 0.7 * (1.0 - float(i) / COUNT)
		_canvas.draw_line(curve.sample_baked(cursor), curve.sample_baked(minf(cursor + DASH, length)),
				Color(HIDDEN_COLOR.r, HIDDEN_COLOR.g, HIDDEN_COLOR.b, alpha), 1.6, true)
		cursor += DASH + GAP
