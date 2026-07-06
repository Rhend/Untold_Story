extends Control
## Écran de sélection de personnage (L3).
## Affiche une carte par personnage (buste + nom + attribut + description),
## renseigne GameState au clic puis lance la scène d'histoire.
## UI construite en code pour cette tranche (passage en .tscn éditable plus tard).

const STORY_SCENE := "res://scenes/story.tscn"


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.06, 0.09)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 32)
	add_child(root)

	var title := Label.new()
	title.text = "Choisis ton personnage"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	root.add_child(title)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 36)
	root.add_child(row)

	# Casting scanné dans le dossier characters/ de l'histoire choisie (plus de
	# liste en dur) : chaque histoire apporte ses propres personnages.
	for path in GameState.character_paths():
		var data: CharacterData = load(path)
		if data == null:
			push_error("Sélection : personnage introuvable : " + path)
			continue
		row.add_child(_make_card(data))


func _make_card(data: CharacterData) -> Control:
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 12)
	card.custom_minimum_size = Vector2(300, 0)

	# Cadre avec outline à la couleur du héros ; cliquable pour sélectionner.
	var bust_frame := PanelContainer.new()
	bust_frame.custom_minimum_size = Vector2(300, 380)
	bust_frame.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	bust_frame.gui_input.connect(_on_card_input.bind(data))
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0.1, 0.09, 0.12)
	frame_style.set_border_width_all(3)
	frame_style.border_color = data.color
	frame_style.set_corner_radius_all(8)
	frame_style.set_content_margin_all(6)
	bust_frame.add_theme_stylebox_override("panel", frame_style)

	var bust := TextureRect.new()
	bust.texture = data.bust
	bust.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bust.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bust.mouse_filter = Control.MOUSE_FILTER_IGNORE  # le clic passe au cadre
	bust_frame.add_child(bust)
	card.add_child(bust_frame)

	var name_label := Label.new()
	name_label.text = data.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 24)
	name_label.add_theme_color_override("font_color", data.color)
	card.add_child(name_label)

	var subtitle := Label.new()
	subtitle.text = "%s  ·  %s" % [data.character_type, data.attribute]
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(0.7, 0.7, 0.82)
	card.add_child(subtitle)

	if not data.description.is_empty():
		var desc := Label.new()
		desc.text = data.description
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.custom_minimum_size = Vector2(300, 0)
		desc.modulate = Color(0.6, 0.6, 0.72)
		card.add_child(desc)

	var button := Button.new()
	button.text = "Choisir"
	button.pressed.connect(_on_choose.bind(data))
	card.add_child(button)

	return card


func _on_card_input(event: InputEvent, data: CharacterData) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_on_choose(data)


func _on_choose(data: CharacterData) -> void:
	GameState.selected_character = data
	GameState.character_type = data.character_type
	GameState.character_attribute = data.attribute
	get_tree().change_scene_to_file(STORY_SCENE)
