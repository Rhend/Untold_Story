extends Node
## Harnais TEMPORAIRE d'itération visuelle sur l'OUTIL NARRATIF (le panneau
## graphe de l'addon, instanciable hors éditeur) :
##   C:\Godot\godot.exe --path . res://tools/dev_tool_capture.tscn
## Sorties : $TOOL_SHOT (vue d'ensemble) et $TOOL_SHOT_NODE (nœud sélectionné,
## inspecteur ouvert). $TOOL_STORY (défaut demo_format.untold) choisit le
## fichier, $TOOL_NODE le nœud à sélectionner pour la seconde vue.

const GraphEditorPanel := preload("res://addons/narrative_graph/graph_editor.gd")


func _ready() -> void:
	get_window().size = Vector2i(1720, 960)

	var panel: Control = GraphEditorPanel.new()
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	await get_tree().process_frame
	await get_tree().process_frame

	# Sélectionne l'histoire demandée dans le menu déroulant de l'outil.
	var wanted := OS.get_environment("TOOL_STORY")
	if wanted.is_empty():
		wanted = "demo_format.untold"
	var stories: OptionButton = panel._stories
	for i in stories.item_count:
		if str(stories.get_item_metadata(i)).ends_with(wanted):
			stories.select(i)
			panel._load_selected()
			break
	await get_tree().process_frame
	print("TOOL OK — nœuds affichés : %d" % panel._node_names.size())

	# Vérification fonctionnelle de l'annuler/rétablir : une modification du
	# .untold doit s'annuler à l'octet près, et se rétablir. Seulement sur une
	# histoire qui a le nœud-cobaye « fin » (la démo) — pas de faux FAIL quand
	# le harnais est pointé sur une vraie histoire via $TOOL_STORY.
	var path: String = panel._current_path()
	var before := FileAccess.get_file_as_string(path)
	if not panel._source.blocks.has("fin"):
		print("UNDO/REDO non testés (pas de nœud « fin » dans cette histoire).")
		await _shots(panel)
		get_tree().quit(0)
		return
	panel._source.set_body("fin", ["Texte modifié pour le test de l'undo.", "-> END"])
	panel._source.save()
	panel._undo()
	print("UNDO OK" if FileAccess.get_file_as_string(path) == before else "UNDO FAIL")
	panel._redo()
	print("REDO OK" if FileAccess.get_file_as_string(path).contains("test de l'undo")
			else "REDO FAIL")
	panel._undo()  # laisse le fichier de démo dans son état d'origine
	print("UNDO2 OK" if FileAccess.get_file_as_string(path) == before else "UNDO2 FAIL")
	await _shots(panel)
	get_tree().quit(0)


func _shots(panel: Control) -> void:
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		return
	await _snap(OS.get_environment("TOOL_SHOT"))
	var node_id := OS.get_environment("TOOL_NODE")
	if node_id.is_empty():
		node_id = "prologue2"
	panel.reload_and_select(node_id)
	await get_tree().process_frame
	await _snap(OS.get_environment("TOOL_SHOT_NODE"))


func _snap(out: String) -> void:
	if out.is_empty():
		return
	await RenderingServer.frame_post_draw
	var shot := get_viewport().get_texture().get_image()
	shot.save_png(out)
