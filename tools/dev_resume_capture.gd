extends Node
## Harnais de vérification de la REPRISE : rejoue des débuts de partie, « quitte »,
## relance — et vérifie que la page est restaurée telle que laissée :
##  1. l'illustration de la page de gauche (posée par un nœud antérieur au
##     checkpoint : « Le village » vu à N003, reprise à N004) ;
##  2. le texte complet du passage (accumulé sur des nœuds enchaînés :
##     N001 + N002, alors que le checkpoint ne rejoue que N002).
## Sauvegarde/restaure user://progress.json — ne pollue pas la vraie partie.
##   C:\Godot\godot.exe --path . res://tools/dev_resume_capture.tscn
## Env : $RESUME_SHOT (PNG de la page après la reprise du scénario 1, optionnel).
## Sortie : « RESUME OK » et code 0, ou « RESUME FAIL … » et code 1.

const SAVE := "user://progress.json"

var _backup := ""
var _had := false
var _failures: Array[String] = []


func _ready() -> void:
	_had = FileAccess.file_exists(SAVE)
	if _had:
		_backup = FileAccess.get_file_as_string(SAVE)

	GameState.story_id = "mesopotamia"
	for path in GameState.character_paths():
		var data: CharacterData = load(path)
		if data != null and data.character_type == "Nadîtum":
			GameState.selected_character = data
			GameState.character_type = data.character_type
			GameState.character_attribute = data.attribute

	# --- Scénario 1 : illustration persistante -----------------------------
	# Traverse le nœud à illustration (« Le village »), puis valide un choix —
	# le checkpoint avance sur A01S01N004, qui n'a pas de @illustration.
	Progress.reset()
	var scene: Control = await _play("A01S01N003")
	scene._runner.choose(0)
	# La bascule « tourner la page » applique le contenu en différé : attendre
	# sa fin avant de relever le texte affiché (sinon on lit l'ancien passage).
	await get_tree().create_timer(0.8).timeout
	var expected_text: String = scene._display_raw
	scene.free()
	await get_tree().process_frame

	var resumed: Control = await _resume()
	_check("S1 nœud", resumed._current_node, "A01S01N004")
	if resumed._illustration == null or resumed._illustration_data == null:
		_failures.append("S1 — aucune illustration restaurée sur la page de gauche")
	else:
		_check("S1 illustration",
				resumed._illustration_data.illustration_name, "Le village")
	_check("S1 texte", resumed._display_raw, expected_text)

	var shot := OS.get_environment("RESUME_SHOT")
	if not shot.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot)
		print("capture -> " + shot)
	resumed.free()
	await get_tree().process_frame

	# --- Scénario 2 : texte accumulé sur des nœuds enchaînés ----------------
	# A01S01N001 (texte) enchaîne par un saut sur A01S01N002 (texte + choix) :
	# le passage affiché est la somme des deux, le checkpoint ne pointe que N002.
	Progress.reset()
	scene = await _play("A01S01N001")
	expected_text = scene._display_raw
	scene.free()
	await get_tree().process_frame

	resumed = await _resume()
	_check("S2 nœud", resumed._current_node, "A01S01N002")
	_check("S2 texte", resumed._display_raw, expected_text)
	if resumed._illustration != null:
		_failures.append("S2 — illustration inattendue (aucune vue dans ce run)")
	resumed.free()
	await get_tree().process_frame

	_restore()
	if _failures.is_empty():
		print("RESUME OK — illustration et texte restaurés à la reprise.")
		get_tree().quit(0)
	else:
		for failure in _failures:
			print("RESUME FAIL — " + failure)
		get_tree().quit(1)


## Lance story.tscn et saute au nœud demandé (première session d'un scénario).
## Attend la fin de la bascule de page : le contenu du passage est appliqué
## page fermée, en différé.
func _play(node: String) -> Control:
	var scene: Control = load("res://scenes/story.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	scene._runner.go_to(node)
	await get_tree().create_timer(0.8).timeout
	return scene


## Relance story.tscn : reprise auto au checkpoint du personnage courant.
func _resume() -> Control:
	var scene: Control = load("res://scenes/story.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().create_timer(0.8).timeout
	return scene


func _check(label: String, got: String, expected: String) -> void:
	if got != expected:
		_failures.append("%s : « %s » ≠ « %s »"
				% [label, got.left(60), expected.left(60)])


func _restore() -> void:
	if _had:
		FileAccess.open(SAVE, FileAccess.WRITE).store_string(_backup)
	elif FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
