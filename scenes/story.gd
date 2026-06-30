extends Control
## Vue d'histoire : charge l'histoire, la fait tourner via le StoryRunner et
## affiche le buste du personnage + texte (effet machine à écrire) + choix.
## UI construite en code pour cette tranche (passage en .tscn éditable plus tard).

const SAMPLE_PATH := "res://data/stories/sample.untold"
const SELECTION_SCENE := "res://scenes/character_selection.tscn"

var _runner: StoryRunner
var _header: Label
var _text_label: RichTextLabel
var _choices_box: VBoxContainer
var _typewriter: Tween
var _illustration: Illustration


func _ready() -> void:
	_build_ui()

	_runner = StoryRunner.new()
	add_child(_runner)
	_runner.display_text.connect(_on_display_text)
	_runner.present_choices.connect(_on_present_choices)
	_runner.command.connect(_on_command)
	_runner.story_ended.connect(_on_story_ended)

	_start_story()


func _start_story() -> void:
	var source := FileAccess.get_file_as_string(SAMPLE_PATH)
	var story := StoryParser.parse(source)
	_runner.start(story, {
		"character": GameState.character_type,
		"type": GameState.character_attribute,
	})


# ------------------------------------------------------------------ UI

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.06, 0.09)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Voile sombre posé AU-DESSUS de l'illustration (insérée dynamiquement en
	# index 1) et SOUS l'UI, pour garder le texte lisible par-dessus l'image.
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.3)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 56)
	add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 40)
	margin.add_child(hbox)

	# Panneau personnage (buste + nom), si un personnage est sélectionné.
	var character: CharacterData = GameState.selected_character
	if character != null:
		hbox.add_child(_build_character_panel(character))

	# Colonne d'histoire (en-tête, texte, choix).
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 24)
	hbox.add_child(col)

	_header = Label.new()
	_header.modulate = Color(0.55, 0.55, 0.7)
	col.add_child(_header)

	_text_label = RichTextLabel.new()
	_text_label.bbcode_enabled = true
	_text_label.fit_content = true
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_label.add_theme_font_size_override("normal_font_size", 20)
	col.add_child(_text_label)

	_choices_box = VBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", 12)
	col.add_child(_choices_box)


func _build_character_panel(character: CharacterData) -> Control:
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(240, 0)
	panel.add_theme_constant_override("separation", 10)
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	var bust := TextureRect.new()
	bust.texture = character.bust
	bust.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	bust.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bust.custom_minimum_size = Vector2(240, 320)
	panel.add_child(bust)

	var name_label := Label.new()
	name_label.text = character.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", character.color)
	panel.add_child(name_label)

	var type_label := Label.new()
	type_label.text = character.character_type
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_label.modulate = Color(0.65, 0.65, 0.78)
	panel.add_child(type_label)

	return panel


func _clear_choices() -> void:
	for child in _choices_box.get_children():
		child.queue_free()


# ------------------------------------------------------------- Signaux runner

func _on_display_text(text: String, node_id: String, tags: Array) -> void:
	_clear_choices()

	var header := node_id
	if tags.size() > 0:
		header += "   [ " + " · ".join(PackedStringArray(tags)) + " ]"
	_header.text = header

	_text_label.text = text

	# Effet "machine à écrire" — contrôle d'affichage du texte.
	_text_label.visible_ratio = 0.0
	if _typewriter and _typewriter.is_running():
		_typewriter.kill()
	_typewriter = create_tween()
	var duration: float = clampf(text.length() * GameState.text_speed, 0.3, 6.0)
	_typewriter.tween_property(_text_label, "visible_ratio", 1.0, duration)


func _on_present_choices(choices: Array) -> void:
	_clear_choices()
	for i in choices.size():
		var button := Button.new()
		button.text = choices[i]["text"]
		button.pressed.connect(_runner.choose.bind(i))
		_choices_box.add_child(button)


func _on_command(name: String, args: Array) -> void:
	match name:
		"illustration":
			if args.size() > 0:
				_show_illustration(args[0])
		_:
			# Autres commandes à venir (mini-jeux, etc.).
			print("[command] %s(%s)" % [name, ", ".join(PackedStringArray(args))])


func _show_illustration(illustration_name: String) -> void:
	if _illustration != null:
		_illustration.queue_free()
		_illustration = null

	var data := IllustrationLibrary.get_illustration(illustration_name)
	if data == null:
		push_warning("Illustration inconnue : " + illustration_name)
		return

	_illustration = Illustration.new()
	_illustration.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_illustration)
	# Au-dessus du fond (index 0), sous le voile et l'UI.
	move_child(_illustration, 1)
	_illustration.setup(data)


func _on_story_ended() -> void:
	_clear_choices()

	var restart := Button.new()
	restart.text = "↻ Recommencer"
	restart.pressed.connect(_start_story)
	_choices_box.add_child(restart)

	var back := Button.new()
	back.text = "↩ Choisir un autre personnage"
	back.pressed.connect(_go_to_selection)
	_choices_box.add_child(back)


func _go_to_selection() -> void:
	get_tree().change_scene_to_file(SELECTION_SCENE)
