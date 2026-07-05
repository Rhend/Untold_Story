class_name StoryMap
extends Control
## Carte de progression narrative (L7, volet jeu) : les embranchements de
## l'acte se révèlent au fil de l'exploration. Sans disposition d'auteur, le
## récit s'enchaîne de HAUT en BAS (défilement vertical, variantes en largeur)
## et la carte s'ouvre centrée sur le nœud courant.
##
## Les enchaînements linéaires sont CONTRACTÉS : un nœud visité qui n'a qu'une
## seule sortie (pistes cachées incluses) fusionne avec son successeur visité
## si celui-ci n'a pas d'autre entrée. La carte montre un seul nœud par
## chaîne ; la relecture concatène les textes de ses membres.
##
##  - nœud visité → panneau nommé + pastilles des personnages passés ;
##  - nœud courant → liseré à la couleur du personnage incarné (repère) ;
##  - nœud aperçu (cible d'un choix visible jamais pris) → bulle noire « ? »,
##    dont AUCUNE suite n'est montrée ;
##  - lien découvert → trait continu ;
##  - piste cachée (choix/saut sous condition jamais exploré) → amorce en
##    pointillé qui s'évanouit (fade out), sans révéler la destination.
##    Exception : les liens conditionnés par l'IDENTITÉ du joueur (variantes
##    de personnage, ex. Prologue1 → Prologue1N/S/P) ne sont pas des secrets
##    de l'histoire et ne laissent aucune amorce ;
##  - nœud totalement inconnu → absent de la carte ;
##  - clic sur un nœud visité → liseré sépia + volet de relecture : texte du
##    passage, illustration figée, personnages l'ayant découvert ou non.
##    Ce volet est purement consultatif : aucune interaction narrative.

signal close_requested()

const CHARACTER_PATHS := [
	"res://data/characters/naditum.tres",
	"res://data/characters/soldat.tres",
	"res://data/characters/pretresse.tres",
]

## Taille MINIMALE d'un panneau — la largeur réelle suit le libellé.
const NODE_SIZE := Vector2(170, 46)
const BUBBLE_SIZE := Vector2(40, 40)
const EDGE_COLOR := Color(0.78, 0.7, 0.52, 0.8)
const HIDDEN_COLOR := Color(0.6, 0.55, 0.7)
const MARGIN := Vector2(60, 90)
## Disposition auto verticale : écart entre deux profondeurs (vers le bas) et
## écart horizontal entre deux variantes d'une même profondeur.
const DEPTH_GAP := 120.0
const H_GAP := 60.0
## Police des libellés de nœud (sert aussi à mesurer la largeur des panneaux).
const LABEL_FONT_SIZE := 13
## Liseré du nœud sélectionné (relecture) — sépia, distinct du nœud courant.
const SEPIA := Color(0.85, 0.64, 0.38)
const RECAP_WIDTH := 480.0
## Marqueur "glue" du format .untold (cf. StoryRunner.GLUE).
const GLUE := "<>"

var _story: Story
var _graph: StoryGraph
var _positions: Dictionary = {}   # rep -> Vector2 (coin haut-gauche du widget)
var _sizes: Dictionary = {}       # rep -> Vector2 (taille réelle du widget)
var _revealed: Dictionary = {}    # id -> "visited" | "known" (nœuds d'origine)
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


func setup(story: Story, untold_path: String, current_node := "") -> void:
	_story = story
	_graph = StoryGraph.build(story)
	_current_id = current_node
	for path in CHARACTER_PATHS:
		var data: CharacterData = load(path)
		if data != null:
			_characters.append(data)
	_player_color = _color_of(GameState.character_type)

	_compute_revealed()
	_build_chains()
	_compute_sizes()
	_compute_positions(untold_path)
	_build_ui()


# ------------------------------------------------------------------ Modèle

## Règles de révélation. « known » = le joueur a vu le libellé du choix en jeu
## (choix non gardé d'un nœud visité) sans jamais le prendre.
func _compute_revealed() -> void:
	for id in _story.nodes:
		if Progress.is_visited(id):
			_revealed[id] = "visited"
	for id in _story.nodes:
		if _revealed.get(id) != "visited":
			continue
		for link in _graph.outgoing(id):
			var target: String = link["target"]
			if not _story.has_node(target) or _revealed.has(target):
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


## Liens sortants vers des nœuds existants (END exclu).
func _real_outgoing(id: String) -> Array:
	return _graph.outgoing(id).filter(
			func(link: Dictionary) -> bool: return _story.has_node(link["target"]))


## Libellé affiché : id du premier membre, suffixé du nombre de nœuds absorbés.
func _label_of(rep: String) -> String:
	var count: int = _chains.get(rep, [rep]).size()
	return rep if count == 1 else "%s  (+%d)" % [rep, count - 1]


## Taille réelle de chaque widget : la largeur suit le libellé (les ids longs
## ne débordent plus sur leurs voisins ni ne faussent l'ancrage des liens).
func _compute_sizes() -> void:
	var font := ThemeDB.fallback_font
	for rep in _chains:
		var text_width := font.get_string_size(
				_label_of(rep), HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE).x
		_sizes[rep] = Vector2(maxf(NODE_SIZE.x, text_width + 28.0), NODE_SIZE.y)
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


## Positions des représentants : celles de l'outil narratif (sidecar
## .meta.json) si présentes, sinon disposition automatique VERTICALE — le
## récit descend (profondeur = rangée, défilement de haut en bas), les
## variantes d'une même profondeur se partagent la largeur selon leur taille
## réelle. Recalées pour partir de MARGIN.
func _compute_positions(untold_path: String) -> void:
	var meta := StoryMeta.load_for(untold_path)
	var authored: Dictionary = meta.positions()
	if authored.is_empty():
		_auto_layout_vertical()
	else:
		# Disposition d'auteur : on reste dans son espace de coordonnées,
		# complété par la disposition auto horizontale d'origine.
		var auto: Dictionary = {}
		for id in _story.nodes:
			var rep: String = _rep_of.get(id, id)
			if rep != id or _positions.has(rep):
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


func _auto_layout_vertical() -> void:
	var start_rep: String = _rep_of.get(_story.start_node, _story.start_node)
	var depth: Dictionary = {start_rep: 0}
	var queue: Array = [start_rep]
	var max_depth := 0
	while not queue.is_empty():
		var rep: String = queue.pop_front()
		for target in _contracted_targets(rep):
			if not depth.has(target):
				depth[target] = depth[rep] + 1
				max_depth = maxi(max_depth, depth[target])
				queue.append(target)

	var next_x: Dictionary = {}  # rangée -> prochaine abscisse libre
	for id in _story.nodes:  # l'ordre du fichier rend la disposition stable
		var rep: String = _rep_of.get(id, id)
		if rep != id or _positions.has(rep):
			continue
		var row: int = depth.get(rep, max_depth + 1)
		var x: float = next_x.get(row, 0.0)
		_positions[rep] = Vector2(x, row * DEPTH_GAP)
		next_x[row] = x + _size_of(rep).x + H_GAP


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
	_scroll.offset_top = 64
	add_child(_scroll)

	_canvas = Control.new()
	_canvas.custom_minimum_size = _canvas_bounds()
	_canvas.draw.connect(_draw_edges)
	_canvas.gui_input.connect(_on_canvas_input)
	_scroll.add_child(_canvas)

	for rep in _drawn_reps():
		_canvas.add_child(_make_widget(rep))

	# Ouvre la carte centrée sur « vous êtes ici » (différé : les plages de
	# défilement ne sont valides qu'après la première mise en page).
	if _panels.has(_current_rep):
		_center_on.call_deferred(_current_rep)

	var title := Label.new()
	var seen: int = Progress.visited_count()
	title.text = "Carte de l'histoire   —   %d / %d nœuds découverts" % [seen, _story.nodes.size()]
	title.position = Vector2(24, 18)
	title.add_theme_font_size_override("font_size", 22)
	title.modulate = Color(0.85, 0.8, 0.65)
	add_child(title)

	var close := Button.new()
	close.text = "✕  Fermer (M)"
	close.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	close.position = Vector2(-180, 14)
	close.pressed.connect(func() -> void: close_requested.emit())
	add_child(close)


func _center_on(rep: String) -> void:
	var center := _center_of(rep)
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


## Chaîne visitée : panneau nommé + pastilles des personnages qui y sont
## passés (union des membres). Cliquable (sélection → volet de relecture).
func _make_node_panel(rep: String) -> Control:
	var panel := PanelContainer.new()
	panel.position = _positions[rep]
	panel.custom_minimum_size = _size_of(rep)
	panel.add_theme_stylebox_override("panel", _panel_style(rep))
	panel.gui_input.connect(_on_panel_input.bind(rep))
	var members: Array = _chains.get(rep, [rep])
	panel.tooltip_text = " → ".join(PackedStringArray(members)) if members.size() > 1 else String(rep)
	if rep == _current_rep:
		panel.tooltip_text += "\nVous êtes ici"
	_panels[rep] = panel

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	panel.add_child(col)

	var name_label := Label.new()
	name_label.text = _label_of(rep)
	name_label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	name_label.add_theme_color_override("font_color", Color(0.9, 0.86, 0.74))
	col.add_child(name_label)

	var visitors := HBoxContainer.new()
	visitors.add_theme_constant_override("separation", 4)
	col.add_child(visitors)
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


## Style du panneau selon l'état de la chaîne :
##  - sélectionnée → liseré sépia (volet de relecture ouvert) ;
##  - courante     → liseré à la couleur du personnage incarné ;
##  - sinon        → cadre discret.
func _panel_style(rep: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.11, 0.16)
	style.set_border_width_all(2)
	style.border_color = Color(0.5, 0.45, 0.35)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(6)
	var outline := Color.TRANSPARENT
	if rep == _selected_id:
		outline = SEPIA
	elif rep == _current_rep:
		outline = _player_color
	if outline != Color.TRANSPARENT:
		style.set_border_width_all(3)
		style.border_color = outline
		style.shadow_color = Color(outline.r, outline.g, outline.b, 0.45)
		style.shadow_size = 7
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
			chip.custom_minimum_size = Vector2(18, 18)
			chip.tooltip_text = character_type
			chip.mouse_filter = Control.MOUSE_FILTER_PASS
			return chip
	# Personnage sans ressource (ou sans image) : point coloré + initiale.
	var dot := Label.new()
	dot.text = "●"
	dot.tooltip_text = character_type
	dot.mouse_filter = Control.MOUSE_FILTER_PASS
	dot.add_theme_color_override("font_color", _color_of(character_type))
	dot.add_theme_font_size_override("font_size", 12)
	return dot


## Nœud aperçu mais jamais visité : bulle noire avec un « ? » blanc.
func _make_bubble(id: String) -> Control:
	var bubble := PanelContainer.new()
	bubble.position = _positions[id]
	bubble.custom_minimum_size = BUBBLE_SIZE
	bubble.tooltip_text = "Nœud non exploré"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.02, 0.03)
	style.set_border_width_all(2)
	style.border_color = Color(0.35, 0.35, 0.4)
	style.set_corner_radius_all(int(BUBBLE_SIZE.x / 2.0))
	bubble.add_theme_stylebox_override("panel", style)

	var mark := Label.new()
	mark.text = "?"
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.add_theme_font_size_override("font_size", 20)
	mark.add_theme_color_override("font_color", Color.WHITE)
	bubble.add_child(mark)
	return bubble


# --------------------------------------------------------------- Sélection

func _on_panel_input(event: InputEvent, rep: String) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_select(rep)


## Clic dans le vide : referme le volet de relecture.
func _on_canvas_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT and _selected_id != "":
		_select(_selected_id)


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

## Volet latéral droit, purement consultatif : titre, illustration figée,
## personnages l'ayant découvert ou non, textes de la chaîne concaténés.
func _show_recap(rep: String) -> void:
	var members: Array = _chains.get(rep, [rep])

	_recap = PanelContainer.new()
	_recap.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_recap.offset_left = -RECAP_WIDTH
	_recap.offset_top = 64
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.11, 0.98)
	style.border_width_left = 2
	style.border_color = Color(SEPIA.r, SEPIA.g, SEPIA.b, 0.6)
	style.set_content_margin_all(18)
	_recap.add_theme_stylebox_override("panel", style)
	add_child(_recap)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_recap.add_child(col)

	# En-tête : étendue de la chaîne + fermeture du volet.
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := Label.new()
	title.text = String(rep) if members.size() == 1 \
			else "%s  →  %s" % [members.front(), members.back()]
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", SEPIA)
	head.add_child(title)
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.pressed.connect(func() -> void: _select(_selected_id))
	head.add_child(close)

	# Version du texte rejouée : celle du personnage incarné s'il est passé
	# par là, sinon celle du premier découvreur.
	var reader := _recap_reader(rep)
	var reader_vars := {"character": reader, "type": _attribute_of(reader)}

	# Première illustration de la chaîne, figée (source de regard neutre :
	# pas de parallaxe, aucune interaction).
	var illustration_name := _chain_illustration(members, reader_vars)
	if illustration_name != "":
		var data := IllustrationLibrary.get_illustration(illustration_name)
		if data != null:
			var illustration := Illustration.new()
			illustration.look_source = LookSource.new()
			illustration.custom_minimum_size = Vector2(0, 240)
			col.add_child(illustration)
			illustration.setup(data)

	col.add_child(_make_discovery_summary(rep))

	# Textes des membres concaténés, relisibles mais sans aucune interaction.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override("normal_font_size", 16)
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
	caption.custom_minimum_size = Vector2(120, 0)
	caption.add_theme_font_size_override("font_size", 14)
	caption.modulate = Color(0.75, 0.7, 0.6)
	row.add_child(caption)
	for character in characters:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 3)
		cell.add_child(_make_visitor_chip(str(character)))
		var name_label := Label.new()
		name_label.text = str(character)
		name_label.add_theme_font_size_override("font_size", 14)
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
			if not ok:
				break
		if ok:
			return true
	return false


# ------------------------------------------------------------------ Arêtes

## Dessinées sous les widgets (les enfants du canvas passent au-dessus).
## Les liens partent du DERNIER membre de chaque chaîne visitée ; les liens
## internes aux chaînes n'existent plus.
func _draw_edges() -> void:
	for rep in _chains:
		var members: Array = _chains[rep]
		var from_center := _center_of(rep)
		for link in _real_outgoing(members.back()):
			var target: String = link["target"]
			var target_rep: String = _rep_of.get(target, target)
			var to_center := _center_of(target_rep)
			var target_visited: bool = _revealed.get(target) == "visited"
			var seen_choice: bool = link["kind"] == "choice" and not link["guarded"]
			if target_visited or (seen_choice and _revealed.has(target)):
				_canvas.draw_line(from_center, to_center, EDGE_COLOR, 2.0, true)
			elif not link.get("identity", false):
				# Une variante de personnage non explorée (ex. Prologue1 selon
				# le héros incarné) n'est PAS une piste cachée : rien à montrer.
				_draw_hidden_stub(from_center, to_center, _size_of(rep).x)


## Amorce de piste cachée : pointillés qui s'évanouissent en direction de la
## cible, tronqués pour ne rien révéler de sa position exacte.
func _draw_hidden_stub(from_center: Vector2, toward: Vector2, source_width: float) -> void:
	var dir := (toward - from_center).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var cursor := from_center + dir * (source_width * 0.45)
	const DASH := 9.0
	const GAP := 7.0
	const COUNT := 7
	for i in COUNT:
		var alpha := 0.75 * (1.0 - float(i) / COUNT)
		_canvas.draw_line(cursor, cursor + dir * DASH,
				Color(HIDDEN_COLOR.r, HIDDEN_COLOR.g, HIDDEN_COLOR.b, alpha), 2.0, true)
		cursor += dir * (DASH + GAP)
