extends Node
## Harnais d'itération visuelle sur les écrans hors histoire : capture le hub
## puis la sélection de personnage (une partie en cours simulée pour varier
## les boutons). Sauvegarde/restaure user://progress.json.
##   C:\Godot\godot.exe --path . res://tools/dev_screens_capture.tscn
## Env : $HUB_SHOT et $SEL_SHOT (chemins des PNG à écrire).

const SAVE := "user://progress.json"

var _backup := ""
var _had := false


func _ready() -> void:
	_had = FileAccess.file_exists(SAVE)
	if _had:
		_backup = FileAccess.get_file_as_string(SAVE)
	Progress.reset()

	# Une partie en cours pour la Nadîtum (bouton « Continuer l'histoire »).
	GameState.story_id = "mesopotamia"
	Progress.begin_story("act1_sc1", "Nadîtum")
	Progress.record_visit("start")
	Progress.record_checkpoint("A01S01N009")

	if DisplayServer.get_name() != "headless":
		await _capture_scene("res://scenes/hub.tscn", OS.get_environment("HUB_SHOT"))
		await _capture_scene("res://scenes/character_selection.tscn",
				OS.get_environment("SEL_SHOT"))
	print("SCREENS OK")
	_restore()
	get_tree().quit(0)


func _capture_scene(scene_path: String, out: String) -> void:
	if out.is_empty():
		return
	var scene: Control = load(scene_path).instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	# Laisse passer le fondu d'entrée de la sélection (arrivée depuis le hub).
	await get_tree().create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("capture -> " + out)
	scene.queue_free()
	await get_tree().process_frame


func _restore() -> void:
	if _had:
		FileAccess.open(SAVE, FileAccess.WRITE).store_string(_backup)
	elif FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
