extends Node
## Fumée : instancie la carte de progression (StoryMap) avec les autoloads
## réels, pour attraper toute erreur d'exécution sans lancer l'UI complète.
## Lancer : godot --headless --path . tools/test_story_map.tscn

const STORY_PATH := "res://data/stories/mesopotamia/act1_sc1.untold"


func _ready() -> void:
	Progress.begin_story("act1_sc1", "Nadîtum")
	# Un peu de progression factice pour exercer tous les états de la carte.
	Progress.record_visit("start")
	Progress.record_visit("Prologue1")

	var story := StoryParser.parse(FileAccess.get_file_as_string(STORY_PATH))
	var map := StoryMap.new()
	add_child(map)
	map.setup(story, STORY_PATH)

	await get_tree().process_frame
	await get_tree().process_frame
	print("STORY_MAP OK — widgets: %d" % map.get_child_count())

	# Avec un vrai renderer, sauve une capture pour contrôle visuel.
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var shot := get_viewport().get_texture().get_image()
		var out := OS.get_environment("STORY_MAP_SHOT")
		if not out.is_empty():
			shot.save_png(out)
			print("Capture : " + out)
	get_tree().quit(0)
