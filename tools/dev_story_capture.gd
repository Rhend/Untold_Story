extends Node
## Harnais d'itération visuelle sur la scène d'histoire (UI grimoire) :
## lance story.tscn avec un personnage, saute à un nœud, capture des PNG.
## Sauvegarde/restaure user://progress.json — ne pollue pas la vraie partie.
##   C:\Godot\godot.exe --path . res://tools/dev_story_capture.tscn
## Env : $STORY_NODE (nœud à atteindre), $STORY_SHOT (PNG de la page),
##       $STORY_SHOT_FULL (PNG de l'illustration plein écran, si présente).

const SAVE := "user://progress.json"

var _backup := ""
var _had := false


func _ready() -> void:
	_had = FileAccess.file_exists(SAVE)
	if _had:
		_backup = FileAccess.get_file_as_string(SAVE)
	Progress.reset()

	GameState.story_id = "mesopotamia"
	for path in GameState.character_paths():
		var data: CharacterData = load(path)
		if data != null and data.character_type == "Nadîtum":
			GameState.selected_character = data
			GameState.character_type = data.character_type
			GameState.character_attribute = data.attribute

	var scene: Control = load("res://scenes/story.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	var node := OS.get_environment("STORY_NODE")
	if not node.is_empty():
		scene._runner.go_to(node)
		await get_tree().process_frame

	# Texte affiché d'un coup (pas d'attente de la machine à écrire).
	if scene._typewriter != null and scene._typewriter.is_running():
		scene._typewriter.kill()
	scene._text_label.visible_ratio = 1.0
	await get_tree().process_frame

	if DisplayServer.get_name() != "headless":
		await _snap(OS.get_environment("STORY_SHOT"))
		var full := OS.get_environment("STORY_SHOT_FULL")
		if not full.is_empty():
			scene._open_fullscreen()
			await get_tree().process_frame
			await _snap(full)

	print("STORY_UI OK — nœud : %s" % scene._current_node)
	_restore()
	get_tree().quit(0)


func _snap(out: String) -> void:
	if out.is_empty():
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("capture -> " + out)


func _restore() -> void:
	if _had:
		FileAccess.open(SAVE, FileAccess.WRITE).store_string(_backup)
	elif FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
