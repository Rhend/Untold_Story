extends CanvasLayer
## Menu de réglages global (autoload "SettingsMenu").
## S'ouvre / se ferme avec Échap, met le jeu en pause tant qu'il est ouvert, et
## permet de quitter le jeu à tout moment (depuis n'importe quelle scène).

## Demande de recommencer l'histoire en cours (efface la partie en cours du
## personnage, garde la découverte cumulative). La scène d'histoire s'y abonne
## quand elle est active (cf. story.gd).
signal restart_requested

var _fullscreen_toggle: CheckButton
## Entrée « Recommencer » — visible seulement quand une histoire est active.
var _restart_button: Button


func _ready() -> void:
	layer = 128  # au-dessus de toute l'UI de jeu
	process_mode = Node.PROCESS_MODE_ALWAYS  # reste actif quand le jeu est en pause
	_build_ui()
	visible = false


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_toggle()
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	visible = not visible
	get_tree().paused = visible
	if visible and _fullscreen_toggle != null:
		_fullscreen_toggle.set_pressed_no_signal(
			DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)


## Ouvre le menu (équivalent d'Échap) — appelé par l'écrou du bandeau de la
## scène d'histoire.
func open() -> void:
	if not visible:
		_toggle()


func _close() -> void:
	visible = false
	get_tree().paused = false


# --------------------------------------------------------------------- UI

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.09, 0.12, 0.98)
	panel_style.set_border_width_all(1)
	panel_style.border_color = Color(0.3, 0.3, 0.4)
	panel_style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 40)
	panel.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 20)
	col.custom_minimum_size = Vector2(360, 0)
	margin.add_child(col)

	var title := Label.new()
	title.text = "Réglages"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	col.add_child(title)

	_fullscreen_toggle = CheckButton.new()
	_fullscreen_toggle.text = "Plein écran"
	_fullscreen_toggle.button_pressed = \
		DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	_fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)
	col.add_child(_fullscreen_toggle)

	_restart_button = Button.new()
	_restart_button.text = "↻  Recommencer cette histoire"
	_restart_button.visible = false  # activée par la scène d'histoire (set_restart_available)
	_restart_button.pressed.connect(_on_restart_pressed)
	col.add_child(_restart_button)

	var resume := Button.new()
	resume.text = "Reprendre"
	resume.pressed.connect(_close)
	col.add_child(resume)

	var quit := Button.new()
	quit.text = "Quitter le jeu"
	quit.pressed.connect(_on_quit_pressed)
	col.add_child(quit)


## Active/désactive l'entrée « Recommencer » (appelée par la scène d'histoire).
func set_restart_available(available: bool) -> void:
	if _restart_button != null:
		_restart_button.visible = available


## Ferme le menu puis demande à la scène d'histoire de tout recommencer.
func _on_restart_pressed() -> void:
	_close()
	restart_requested.emit()


func _on_fullscreen_toggled(on: bool) -> void:
	if on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	# Le retour fenêtré REPOSE sur window_width/height_override dans
	# project.godot : sans taille fenêtrée déclarée, Godot (Windows) restaure
	# une fenêtre couvrant tout l'écran, la re-détecte « plein écran » et
	# ignore ensuite tout set_size/set_position — le mode fenêtré devient
	# inatteignable. On impose ensuite la taille et on recentre.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var win_size := Vector2i(1280, 720)
	DisplayServer.window_set_size(win_size)
	var screen := DisplayServer.window_get_current_screen()
	var screen_pos := DisplayServer.screen_get_position(screen)
	var screen_size := DisplayServer.screen_get_size(screen)
	DisplayServer.window_set_position(screen_pos + (screen_size - win_size) / 2)


func _on_quit_pressed() -> void:
	get_tree().quit()
