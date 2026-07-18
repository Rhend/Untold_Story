extends Node
## Harnais TEMPORAIRE d'itération visuelle sur l'animation du jet de dé
## (DiceRollOverlay) : joue une réussite et un échec sur fond de table, et
## capture chaque phase.
##   C:\Godot\godot.exe --path . res://tools/dev_dice_capture.tscn
## Sorties : $DICE_SHOT_ROLLING (dé en train de rouler), $DICE_SHOT_SUCCESS
## (verdict réussite), $DICE_SHOT_FAILURE (verdict échec).

const Overlay := preload("res://scenes/dice_roll_overlay.gd")


func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	add_child(BookTheme.make_desk())
	await get_tree().process_frame

	if DisplayServer.get_name() != "headless":
		# 1. En plein roulement.
		var overlay: Control = Overlay.new()
		add_child(overlay)
		overlay.play("courage", 4, 2, 6, 5, true)
		overlay._elapsed = overlay.APPEAR + 0.4   # au milieu du roulement
		await get_tree().process_frame
		await get_tree().process_frame
		await _snap(OS.get_environment("DICE_SHOT_ROLLING"))

		# 2. Verdict réussite (dé posé, détail visible).
		overlay._elapsed = overlay.APPEAR + overlay.ROLLING + 1.0
		await get_tree().process_frame
		await _snap(OS.get_environment("DICE_SHOT_SUCCESS"))
		overlay.queue_free()

		# 3. Verdict échec.
		var fail: Control = Overlay.new()
		add_child(fail)
		fail.play("eloquence", 1, 1, 2, 5, false)
		fail._elapsed = fail.APPEAR + fail.ROLLING + 1.0
		await get_tree().process_frame
		await _snap(OS.get_environment("DICE_SHOT_FAILURE"))

	print("DICE OK")
	get_tree().quit(0)


func _snap(out: String) -> void:
	if out.is_empty():
		return
	await RenderingServer.frame_post_draw
	var shot := get_viewport().get_texture().get_image()
	shot.save_png(out)
