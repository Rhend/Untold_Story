@tool
extends VBoxContainer
## Écran principal « Narratif » : graphe éditable des histoires .untold.
##  - drag & drop des nœuds → disposition sauvée dans <histoire>.meta.json,
##    la MÊME que celle utilisée par la carte de progression en jeu ;
##  - « Appliquer l'ordre au .untold » → réécrit la source de vérité avec les
##    blocs de nœuds réordonnés selon la disposition (gauche → droite, puis
##    haut → bas), sans toucher à leur contenu ;
##  - clic sur un nœud → inspecteur modulaire (voir node_inspector.gd pour
##    ajouter un volet : un script + une ligne dans la liste).

const UntoldSource := preload("res://addons/narrative_graph/untold_source.gd")
const NodeInspector := preload("res://addons/narrative_graph/node_inspector.gd")

const STORIES_DIR := "res://data/stories"
const EXCERPT_LENGTH := 46

## Couleur du port selon la nature du lien sortant.
const KIND_COLORS := {
	"choice": Color(0.85, 0.72, 0.4),
	"divert": Color(0.55, 0.6, 0.75),
	"cond": Color(0.7, 0.5, 0.8),
}

var _stories: OptionButton
var _status: Label
var _graph_edit: GraphEdit
var _inspector: Control

var _source: RefCounted   # UntoldSource
var _story: Story
var _graph: StoryGraph
var _meta: StoryMeta
var _node_ids: Dictionary = {}  # nom du GraphNode -> id du nœud d'histoire


func _init() -> void:
	name = "OutilNarratif"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func _ready() -> void:
	_scan_stories()


# --------------------------------------------------------------------- UI

func _build_ui() -> void:
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	add_child(toolbar)

	var caption := Label.new()
	caption.text = "Histoire :"
	toolbar.add_child(caption)

	_stories = OptionButton.new()
	_stories.item_selected.connect(func(_index: int) -> void: _load_selected())
	toolbar.add_child(_stories)

	var reload := Button.new()
	reload.text = "Recharger"
	reload.tooltip_text = "Relit le fichier depuis le disque."
	reload.pressed.connect(_load_selected)
	toolbar.add_child(reload)

	var apply := Button.new()
	apply.text = "Appliquer l'ordre au .untold"
	apply.tooltip_text = "Réécrit le fichier source avec les nœuds réordonnés selon la disposition du graphe."
	apply.pressed.connect(_apply_order)
	toolbar.add_child(apply)

	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.modulate = Color(0.7, 0.7, 0.8)
	toolbar.add_child(_status)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)

	_graph_edit = GraphEdit.new()
	_graph_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graph_edit.minimap_enabled = true
	_graph_edit.node_selected.connect(_on_node_selected)
	_graph_edit.end_node_move.connect(_save_positions)
	split.add_child(_graph_edit)

	_inspector = NodeInspector.new()
	split.add_child(_inspector)


func set_status(message: String) -> void:
	_status.text = message


# ---------------------------------------------------------------- Chargement

func _scan_stories() -> void:
	_stories.clear()
	var dir := DirAccess.open(STORIES_DIR)
	if dir == null:
		set_status("Dossier introuvable : " + STORIES_DIR)
		return
	for file in dir.get_files():
		if file.ends_with(".untold"):
			_stories.add_item(file)
	if _stories.item_count > 0:
		_stories.select(0)
		_load_selected()


func _current_path() -> String:
	if _stories.selected < 0:
		return ""
	return STORIES_DIR + "/" + _stories.get_item_text(_stories.selected)


func _load_selected() -> void:
	var path := _current_path()
	if path.is_empty():
		return
	_source = UntoldSource.new()
	if not _source.load_file(path):
		set_status("Lecture impossible : " + path)
		return
	_story = StoryParser.parse(FileAccess.get_file_as_string(path))
	_graph = StoryGraph.build(_story)
	_meta = StoryMeta.load_for(path)
	_rebuild_graph_view()
	set_status("%d nœuds — %s" % [_story.nodes.size(), path.get_file()])


func _rebuild_graph_view() -> void:
	_graph_edit.clear_connections()
	for child in _graph_edit.get_children():
		if child is GraphNode:
			child.free()  # libération immédiate : les noms doivent être réutilisables
	_node_ids.clear()

	# Disposition : positions sauvegardées, complétées par l'auto-layout.
	var positions := _meta.positions()
	var auto: Dictionary = {}
	for id in _story.nodes:
		if not positions.has(id):
			if auto.is_empty():
				auto = _graph.auto_layout()
			positions[id] = auto[id]

	for id in _source.order:
		if _story.has_node(id):
			_graph_edit.add_child(_make_graph_node(id, positions[id]))

	for id in _story.nodes:
		var links := _graph.outgoing(id)
		for i in links.size():
			var target: String = links[i]["target"]
			if _story.has_node(target):
				_graph_edit.connect_node(_gnode_name(id), i, _gnode_name(target), 0)


func _make_graph_node(id: String, pos: Vector2) -> GraphNode:
	var node: StoryNode = _story.get_node_by_id(id)
	var gnode := GraphNode.new()
	gnode.name = _gnode_name(id)
	gnode.title = id
	gnode.position_offset = pos
	_node_ids[String(gnode.name)] = id

	# Rangée 0 : extrait du texte, port d'entrée à gauche.
	var excerpt := Label.new()
	excerpt.text = _excerpt(node)
	excerpt.custom_minimum_size = Vector2(230, 0)
	excerpt.clip_text = true
	excerpt.modulate = Color(0.78, 0.78, 0.85)
	gnode.add_child(excerpt)
	gnode.set_slot(0, true, 0, Color(0.8, 0.8, 0.8), false, 0, Color.WHITE)

	# Une rangée par lien sortant, port de sortie à droite, coloré par nature.
	var row := 1
	for link in _graph.outgoing(id):
		var label := Label.new()
		label.text = _link_caption(link)
		label.clip_text = true
		label.custom_minimum_size = Vector2(230, 0)
		gnode.add_child(label)
		gnode.set_slot(row, false, 0, Color.WHITE, true, 0, KIND_COLORS[link["kind"]])
		row += 1

	return gnode


func _gnode_name(id: String) -> StringName:
	return StringName(("n_" + id).validate_node_name())


func _excerpt(node: StoryNode) -> String:
	for ins in node.instructions:
		if ins["type"] == "text":
			var value: String = ins["value"]
			if value.length() > EXCERPT_LENGTH:
				return value.left(EXCERPT_LENGTH) + "…"
			return value
	return "(sans texte)"


func _link_caption(link: Dictionary) -> String:
	var guard_prefix := "{…} " if link["guarded"] else ""
	match link["kind"]:
		"choice":
			var text: String = link["text"]
			if text.length() > 36:
				text = text.left(36) + "…"
			return guard_prefix + "▸ " + text
		"cond":
			return guard_prefix + "→ saut conditionnel → " + link["target"]
		_:
			return guard_prefix + "→ " + link["target"]


# ----------------------------------------------------------------- Actions

## Fin d'un drag : toute la disposition est sauvée dans le sidecar .meta.json
## (elle sert aussi de mise en page à la carte de progression en jeu).
func _save_positions() -> void:
	for child in _graph_edit.get_children():
		if child is GraphNode:
			_meta.set_node_position(_node_ids[String(child.name)], child.position_offset)
	_meta.save()
	set_status("Disposition enregistrée (partagée avec la carte en jeu).")


## Réordonne les blocs du fichier source selon la disposition : colonne par
## colonne (x croissant), et de haut en bas dans une même colonne.
func _apply_order() -> void:
	if _source == null:
		return
	var positions: Dictionary = {}
	for child in _graph_edit.get_children():
		if child is GraphNode:
			positions[_node_ids[String(child.name)]] = child.position_offset
	var ids: Array = positions.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		var pa: Vector2 = positions[a]
		var pb: Vector2 = positions[b]
		if absf(pa.x - pb.x) > 1.0:
			return pa.x < pb.x
		return pa.y < pb.y)
	_source.reorder(ids)
	if _source.save():
		set_status("Ordre appliqué : %s réécrit (contenu des nœuds intact)." % _current_path().get_file())
	else:
		set_status("Échec d'écriture du fichier source.")


func _on_node_selected(node: Node) -> void:
	if node is GraphNode and _node_ids.has(String(node.name)):
		_inspector.show_node(_make_context(_node_ids[String(node.name)]))


func _make_context(id: String) -> Dictionary:
	return {
		"node_id": id,
		"node": _story.get_node_by_id(id),
		"story": _story,
		"source": _source,
		"meta": _meta,
		"editor": self,
	}


## Recharge le fichier (après une modification par l'inspecteur) et rouvre le
## même nœud, disposition conservée.
func reload_and_select(id: String) -> void:
	_load_selected()
	var gnode := _graph_edit.get_node_or_null(NodePath(_gnode_name(id)))
	if gnode is GraphNode:
		gnode.selected = true
		_inspector.show_node(_make_context(id))
