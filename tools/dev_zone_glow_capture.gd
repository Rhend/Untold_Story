extends Node
## Harnais TEMPORAIRE d'itération visuelle sur les SIGNIFIANTS de zones
## interactives (lueur de survol, scintillement de révélation) : charge une
## illustration réelle, y injecte une zone de test, force chaque état et
## capture des PNG.
##   C:\Godot\godot.exe --path . res://tools/dev_zone_glow_capture.tscn
## Sorties : $GLOW_SHOT_REVEAL (scintillement) et $GLOW_SHOT_HOVER (survol).

const STORY_DIR := "res://data/stories/mesopotamia/"
const ILLUSTRATION := "Le village"


func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	IllustrationLibrary.load_story(STORY_DIR)
	var data := IllustrationLibrary.get_illustration(ILLUSTRATION)
	if data == null:
		printerr("Illustration introuvable : " + ILLUSTRATION)
		get_tree().quit(1)
		return

	# Zone de test injectée sur le calque pivot : un quadrilatère bien visible.
	var zone := IllustrationInteraction.new()
	zone.id = "test_puits"
	zone.polygon = PackedVector2Array([
		Vector2(0.42, 0.35), Vector2(0.62, 0.38), Vector2(0.60, 0.72), Vector2(0.40, 0.68)])
	data.layers[0].interactions = [zone] as Array[IllustrationInteraction]

	var illu := Illustration.new()
	illu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(illu)
	illu.setup(data)

	await get_tree().process_frame
	await get_tree().process_frame
	print("GLOW OK — zones actives : %s" % str(illu._has_zones))
	_debug_state(illu)

	if DisplayServer.get_name() != "headless":
		# 1. Le scintillement de révélation, saisi à son intensité maximale.
		illu._glow._reveal_delay = 0.0
		illu._glow._reveal_left = illu._glow._reveal_total * 0.5
		await get_tree().process_frame
		await _snap(OS.get_environment("GLOW_SHOT_REVEAL"))

		# 2. La lueur de survol (la révélation est éteinte).
		illu._glow._reveal_left = 0.0
		illu._hovered_zone = zone
		await get_tree().process_frame
		await _snap(OS.get_environment("GLOW_SHOT_HOVER"))

	get_tree().quit(0)


func _snap(out: String) -> void:
	if out.is_empty():
		return
	await RenderingServer.frame_post_draw
	var shot := get_viewport().get_texture().get_image()
	shot.save_png(out)


func _debug_state(illu: Control) -> void:
	print("DBG glow=%s all=%d hover=%d reveal_left=%.2f size=%s layers=%d" % [
		str(illu._glow != null),
		illu._glow._all.size() if illu._glow != null else -1,
		illu._glow._hover.size() if illu._glow != null else -1,
		illu._glow._reveal_left if illu._glow != null else -1.0,
		str(illu._glow.size) if illu._glow != null else "-",
		illu._layers.size()])
