@tool
extends EditorPlugin
## Écran principal « Narratif » de l'éditeur (L7, volet outil).

const GraphEditorPanel := preload("res://addons/narrative_graph/graph_editor.gd")

var _panel: Control


func _enter_tree() -> void:
	_panel = GraphEditorPanel.new()
	get_editor_interface().get_editor_main_screen().add_child(_panel)
	_make_visible(false)


func _exit_tree() -> void:
	if _panel != null:
		_panel.queue_free()
		_panel = null


func _has_main_screen() -> bool:
	return true


func _get_plugin_name() -> String:
	return "Narratif"


func _get_plugin_icon() -> Texture2D:
	return get_editor_interface().get_base_control().get_theme_icon("GraphEdit", "EditorIcons")


func _make_visible(visible: bool) -> void:
	if _panel != null:
		_panel.visible = visible
