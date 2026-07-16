extends Node
## Harnais de vérification de la REPRISE : joue jusqu'à une illustration, avance
## le checkpoint sur un nœud SANS @illustration, « quitte », relance — et vérifie
## que l'illustration laissée sur la page de gauche est bien restaurée.
## Sauvegarde/restaure user://progress.json — ne pollue pas la vraie partie.
##   C:\Godot\godot.exe --path . res://tools/dev_resume_capture.tscn
## Env : $RESUME_SHOT (PNG de la page après reprise, optionnel).
## Sortie : « RESUME OK » et code 0, ou « RESUME FAIL … » et code 1.

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

	# Première session : traverse le nœud à illustration (« Le village »), puis
	# valide un choix — le checkpoint avance sur A01S01N004, qui n'en a pas.
	var scene: Control = load("res://scenes/story.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	scene._runner.go_to("A01S01N003")
	await get_tree().process_frame
	scene._runner.choose(0)
	await get_tree().process_frame
	scene.free()  # « quitte » la partie (le checkpoint est déjà sur disque)
	await get_tree().process_frame

	# Seconde session : reprise auto au checkpoint — l'illustration doit revenir.
	var resumed: Control = load("res://scenes/story.tscn").instantiate()
	add_child(resumed)
	await get_tree().process_frame
	await get_tree().create_timer(0.8).timeout

	var failures: Array[String] = []
	if resumed._current_node != "A01S01N004":
		failures.append("nœud de reprise « %s » ≠ A01S01N004" % resumed._current_node)
	if resumed._illustration == null or resumed._illustration_data == null:
		failures.append("aucune illustration restaurée sur la page de gauche")
	elif resumed._illustration_data.illustration_name != "Le village":
		failures.append("illustration « %s » ≠ « Le village »"
				% resumed._illustration_data.illustration_name)

	var shot := OS.get_environment("RESUME_SHOT")
	if not shot.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot)
		print("capture -> " + shot)

	_restore()
	if failures.is_empty():
		print("RESUME OK — illustration restaurée à la reprise.")
		get_tree().quit(0)
	else:
		for failure in failures:
			print("RESUME FAIL — " + failure)
		get_tree().quit(1)


func _restore() -> void:
	if _had:
		FileAccess.open(SAVE, FileAccess.WRITE).store_string(_backup)
	elif FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
