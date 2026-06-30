extends Control
## Scène de démonstration : charge l'histoire d'exemple, la fait tourner via le
## StoryRunner et affiche texte + choix. L'UI est construite en code pour cette
## première tranche (on la passera en scènes .tscn éditables ensuite).

const SAMPLE_PATH := "res://data/stories/sample.untold"

var _runner: StoryRunner
var _header: Label
var _text_label: RichTextLabel
var _choices_box: VBoxContainer
var _typewriter: Tween


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

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 72)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 28)
	margin.add_child(vbox)

	_header = Label.new()
	_header.modulate = Color(0.55, 0.55, 0.7)
	vbox.add_child(_header)

	_text_label = RichTextLabel.new()
	_text_label.bbcode_enabled = true
	_text_label.fit_content = true
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_label.add_theme_font_size_override("normal_font_size", 20)
	vbox.add_child(_text_label)

	_choices_box = VBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", 12)
	vbox.add_child(_choices_box)


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

	# Effet "machine à écrire" — premier exemple du contrôle d'affichage du texte.
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
	# Branchements à venir (illustrations, mini-jeux). Pour l'instant : trace.
	print("[command] %s(%s)" % [name, ", ".join(PackedStringArray(args))])


func _on_story_ended() -> void:
	_clear_choices()
	var button := Button.new()
	button.text = "↻ Recommencer"
	button.pressed.connect(_start_story)
	_choices_box.add_child(button)
