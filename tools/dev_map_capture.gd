extends Node
## Harnais TEMPORAIRE d'itération visuelle sur la carte (story_map.gd) :
## simule plusieurs parties réelles (StoryRunner) puis capture des PNG.
## Sauvegarde/restaure user://progress.json — ne pollue pas la vraie partie.
##   C:\Godot\godot.exe --path . res://tools/dev_map_capture.tscn
## Sorties : $MAP_SHOT (vue carte) et $MAP_SHOT_RECAP (volet de relecture).

const SAVE := "user://progress.json"
const STORY_PATH := "res://data/stories/mesopotamia/act1_sc1.untold"

var _backup := ""
var _had := false


func _ready() -> void:
	_had = FileAccess.file_exists(SAVE)
	if _had:
		_backup = FileAccess.get_file_as_string(SAVE)
	Progress.reset()

	var story := StoryParser.parse(FileAccess.get_file_as_string(STORY_PATH))

	# Trois personnages jouent chacun une partie, avec des choix divergents.
	# $MAP_STEPS module la longueur de la première (défaut 60) — mettre 2 pour
	# tester une carte de tout début de partie.
	var steps := maxi(int(OS.get_environment("MAP_STEPS").to_int()), 2) \
			if not OS.get_environment("MAP_STEPS").is_empty() else 60
	_play(story, "Nadîtum", "Mystique", 0, steps)
	if steps > 10:
		_play(story, "Soldat", "Physique", 1, 25)
		_play(story, "Prêtresse", "Social", 2, 10)

	# État « en jeu » : Nadîtum incarnée, arrêtée à son point de reprise.
	GameState.story_id = "mesopotamia"
	GameState.character_type = "Nadîtum"
	GameState.character_attribute = "Mystique"
	for path in GameState.character_paths():
		var data: CharacterData = load(path)
		if data != null and data.character_type == "Nadîtum":
			GameState.selected_character = data
	Progress.begin_story("act1_sc1", "Nadîtum")
	var current := Progress.resume_node("act1_sc1", "Nadîtum")

	IllustrationLibrary.load_story(GameState.story_dir())

	var map := StoryMap.new()
	add_child(map)
	map.setup(story, STORY_PATH, current)

	await get_tree().process_frame
	await get_tree().process_frame
	print("MAP OK — widgets: %d, courant: %s" % [map._canvas.get_child_count(), current])

	if DisplayServer.get_name() != "headless":
		await _snap(OS.get_environment("MAP_SHOT"))
		# Deuxième vue : un nœud visité sélectionné → volet de relecture.
		var recap_target: String = map._current_rep
		if map._panels.has(recap_target):
			map._select(recap_target)
			await get_tree().process_frame
			await _snap(OS.get_environment("MAP_SHOT_RECAP"))

	_restore()
	get_tree().quit(0)


func _snap(out: String) -> void:
	if out.is_empty():
		return
	await RenderingServer.frame_post_draw
	var shot := get_viewport().get_texture().get_image()
	shot.save_png(out)
	print("capture -> " + out)


## Joue une partie entière : au ke point de choix, prend (k + variant) modulo
## le nombre de réponses — chaque personnage suit ainsi un chemin différent.
func _play(story: Story, character: String, attribute: String, variant: int, max_steps: int) -> void:
	Progress.begin_story("act1_sc1", character)
	var runner := StoryRunner.new()
	add_child(runner)
	runner.node_visited.connect(func(id: String) -> void: Progress.record_visit(id))
	runner.choice_selected.connect(func(id: String, c: Dictionary) -> void:
		Progress.record_choice(id, c["text"]))
	runner.present_choices.connect(func(choices: Array) -> void:
		if not choices.is_empty():
			Progress.record_checkpoint(choices[0]["node"]))
	runner.start(story, {"character": character, "type": attribute})
	var steps := 0
	while runner._awaiting_choice and steps < max_steps:
		runner.choose((steps + variant) % runner._pending_choices.size())
		steps += 1
	runner.queue_free()


func _restore() -> void:
	if _had:
		FileAccess.open(SAVE, FileAccess.WRITE).store_string(_backup)
	elif FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
