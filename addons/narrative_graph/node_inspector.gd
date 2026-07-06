@tool
extends ScrollContainer
## Inspecteur du nœud sélectionné dans le graphe. MODULAIRE : chaque volet est
## un script hérité d'inspector_section.gd et listé dans SECTIONS — ajouter un
## volet = écrire une section et l'ajouter ici, rien d'autre.

const SECTIONS := [
	preload("res://addons/narrative_graph/sections/section_identity.gd"),
	preload("res://addons/narrative_graph/sections/section_links.gd"),
	preload("res://addons/narrative_graph/sections/section_illustration.gd"),
	preload("res://addons/narrative_graph/sections/section_interactions.gd"),
	preload("res://addons/narrative_graph/sections/section_events.gd"),
	preload("res://addons/narrative_graph/sections/section_comment.gd"),
]

var _box: VBoxContainer


func _init() -> void:
	custom_minimum_size = Vector2(360, 0)
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 18)
	add_child(_box)
	_show_placeholder()


func show_node(ctx: Dictionary) -> void:
	_clear()
	for section_script in SECTIONS:
		var section: Control = section_script.new()
		_box.add_child(section)
		section.setup(ctx)


func _show_placeholder() -> void:
	_clear()
	var hint := Label.new()
	hint.text = "Sélectionne un nœud du graphe."
	hint.modulate = Color(0.55, 0.55, 0.65)
	_box.add_child(hint)


func _clear() -> void:
	for child in _box.get_children():
		child.queue_free()
