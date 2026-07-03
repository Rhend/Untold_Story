class_name StoryMap
extends Control
## Carte de progression narrative (L7, volet jeu) : les embranchements de
## l'acte se révèlent au fil de l'exploration.
##  - nœud visité → panneau nommé + pastilles des personnages passés ;
##  - nœud aperçu (cible d'un choix visible jamais pris) → bulle noire « ? »,
##    dont AUCUNE suite n'est montrée ;
##  - lien découvert → trait continu ;
##  - piste cachée (choix/saut sous condition jamais exploré) → amorce en
##    pointillé qui s'évanouit (fade out), sans révéler la destination ;
##  - nœud totalement inconnu → absent de la carte.

signal close_requested()

const CHARACTER_PATHS := [
	"res://data/characters/naditum.tres",
	"res://data/characters/soldat.tres",
	"res://data/characters/pretresse.tres",
]

const NODE_SIZE := Vector2(170, 46)
const BUBBLE_SIZE := Vector2(40, 40)
const EDGE_COLOR := Color(0.78, 0.7, 0.52, 0.8)
const HIDDEN_COLOR := Color(0.6, 0.55, 0.7)
const MARGIN := Vector2(60, 90)

var _story: Story
var _graph: StoryGraph
var _positions: Dictionary = {}   # id -> Vector2 (coin haut-gauche du widget)
var _revealed: Dictionary = {}    # id -> "visited" | "known"
var _canvas: Control
var _characters: Array = []       # CharacterData chargés (pastilles visiteurs)


func setup(story: Story, untold_path: String) -> void:
	_story = story
	_graph = StoryGraph.build(story)
	for path in CHARACTER_PATHS:
		var data: CharacterData = load(path)
		if data != null:
			_characters.append(data)

	_compute_revealed()
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


## Positions : celles de l'outil narratif (sidecar .meta.json) si présentes,
## sinon disposition automatique en couches. Recalées pour partir de MARGIN.
func _compute_positions(untold_path: String) -> void:
	var meta := StoryMeta.load_for(untold_path)
	_positions = meta.positions()
	var auto: Dictionary = {}
	for id in _story.nodes:
		if not _positions.has(id):
			if auto.is_empty():
				auto = _graph.auto_layout()
			_positions[id] = auto[id]

	var top_left := Vector2(INF, INF)
	for id in _revealed:
		top_left = top_left.min(_positions.get(id, Vector2.ZERO))
	if top_left.x == INF:
		top_left = Vector2.ZERO
	for id in _positions:
		_positions[id] = _positions[id] - top_left + MARGIN


# --------------------------------------------------------------------- UI

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.045, 0.075, 0.98)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 64
	add_child(scroll)

	_canvas = Control.new()
	_canvas.custom_minimum_size = _canvas_bounds()
	_canvas.draw.connect(_draw_edges)
	scroll.add_child(_canvas)

	for id in _revealed:
		_canvas.add_child(_make_widget(id))

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


func _canvas_bounds() -> Vector2:
	var bounds := Vector2.ZERO
	for id in _revealed:
		bounds = bounds.max(_positions[id] + NODE_SIZE)
	return bounds + MARGIN


func _make_widget(id: String) -> Control:
	if _revealed[id] == "known":
		return _make_bubble(id)
	return _make_node_panel(id)


## Nœud visité : panneau nommé + pastilles des personnages qui y sont passés.
func _make_node_panel(id: String) -> Control:
	var panel := PanelContainer.new()
	panel.position = _positions[id]
	panel.custom_minimum_size = NODE_SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.11, 0.16)
	style.set_border_width_all(2)
	style.border_color = Color(0.5, 0.45, 0.35)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", style)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	panel.add_child(col)

	var name_label := Label.new()
	name_label.text = id
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", Color(0.9, 0.86, 0.74))
	col.add_child(name_label)

	var visitors := HBoxContainer.new()
	visitors.add_theme_constant_override("separation", 4)
	col.add_child(visitors)
	for character in Progress.visitors(id):
		visitors.add_child(_make_visitor_chip(str(character)))

	return panel


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
	var color := Color.from_hsv(fmod(abs(float(character_type.hash())) / 1000.0, 1.0), 0.55, 0.9)
	for data in _characters:
		if data.character_type == character_type:
			color = data.color
	dot.add_theme_color_override("font_color", color)
	dot.add_theme_font_size_override("font_size", 12)
	return dot


## Nœud aperçu mais jamais visité : bulle noire avec un « ? » blanc.
func _make_bubble(id: String) -> Control:
	var bubble := PanelContainer.new()
	bubble.position = _positions[id] + (NODE_SIZE - BUBBLE_SIZE) / 2.0
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


# ------------------------------------------------------------------ Arêtes

## Dessinées sous les widgets (les enfants du canvas passent au-dessus).
func _draw_edges() -> void:
	for id in _revealed:
		if _revealed[id] != "visited":
			continue  # une bulle « ? » ne dévoile jamais sa suite
		var from_center: Vector2 = _positions[id] + NODE_SIZE / 2.0
		for link in _graph.outgoing(id):
			var target: String = link["target"]
			if not _story.has_node(target):
				continue  # -> END : la fin se lit sur le dernier nœud visité
			var to_center: Vector2 = _positions[target] + NODE_SIZE / 2.0
			var target_visited: bool = _revealed.get(target) == "visited"
			var seen_choice: bool = link["kind"] == "choice" and not link["guarded"]
			if target_visited or (seen_choice and _revealed.has(target)):
				_canvas.draw_line(from_center, to_center, EDGE_COLOR, 2.0, true)
			else:
				_draw_hidden_stub(from_center, to_center)


## Amorce de piste cachée : pointillés qui s'évanouissent en direction de la
## cible, tronqués pour ne rien révéler de sa position exacte.
func _draw_hidden_stub(from_center: Vector2, toward: Vector2) -> void:
	var dir := (toward - from_center).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var cursor := from_center + dir * (NODE_SIZE.x * 0.45)
	const DASH := 9.0
	const GAP := 7.0
	const COUNT := 7
	for i in COUNT:
		var alpha := 0.75 * (1.0 - float(i) / COUNT)
		_canvas.draw_line(cursor, cursor + dir * DASH,
				Color(HIDDEN_COLOR.r, HIDDEN_COLOR.g, HIDDEN_COLOR.b, alpha), 2.0, true)
		cursor += dir * (DASH + GAP)
