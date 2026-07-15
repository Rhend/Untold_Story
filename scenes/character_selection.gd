extends Control
## Écran de sélection de personnage (L3).
## Affiche une carte par personnage (buste + nom + attribut + description),
## renseigne GameState au clic puis lance la scène d'histoire.
## Le bouton de chaque carte annonce ce que le clic fera : « Continuer
## l'histoire » si ce personnage a une partie en cours (point de reprise
## enregistré — la scène d'histoire reprendra au dernier point de choix),
## sinon « Commencer une nouvelle histoire ».
## UI construite en code pour cette tranche (passage en .tscn éditable plus tard).

const STORY_SCENE := "res://scenes/story.tscn"
const HUB_SCENE := "res://scenes/hub.tscn"


func _ready() -> void:
	# Repli pour un lancement direct de character_selection.tscn (sans hub) :
	# résout génériquement l'histoire pour que le scan des personnages aboutisse.
	if GameState.story_id.is_empty():
		GameState.story_id = GameState.first_story_id()
	_build_ui()


func _build_ui() -> void:
	add_child(BookTheme.make_desk())

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 36)
	add_child(root)

	# Retour au hub : le joueur n'est pas enfermé dans une histoire une fois
	# entré (il peut en changer avant de choisir un personnage). Ancré en haut à
	# gauche, hors du flux centré.
	var back := Button.new()
	back.text = "↩  Changer d'histoire"
	BookTheme.style_choice(back, false, 16, true)
	back.set_anchors_preset(Control.PRESET_TOP_LEFT)
	back.position = Vector2(24, 20)
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file(HUB_SCENE))
	add_child(back)

	var title := BookTheme.make_label("Choisis ton personnage", 38,
			BookTheme.PARCHMENT, false, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 40)
	root.add_child(row)

	# Casting scanné dans le dossier characters/ de l'histoire choisie (plus de
	# liste en dur) : chaque histoire apporte ses propres personnages.
	var progress_id := _story_progress_id()
	for path in GameState.character_paths():
		var data: CharacterData = load(path)
		if data == null:
			push_error("Sélection : personnage introuvable : " + path)
			continue
		row.add_child(_make_card(data, progress_id))


## Id de progression de l'histoire courante : le nom de base de son .untold
## (celui sous lequel Progress range reprise et découverte, cf. story.gd).
## "" si le manifest est illisible — les cartes retombent alors sur le libellé
## « nouvelle histoire ».
func _story_progress_id() -> String:
	var manifest_path := GameState.story_dir() + "manifest.json"
	if not FileAccess.file_exists(manifest_path):
		return ""
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	var entry := str(parsed.get("entry_file", "")) if parsed is Dictionary else ""
	return entry.get_file().get_basename() if not entry.is_empty() else ""


## Planche de personnage : feuille de parchemin (papier, usure), portrait dans
## un cadre à la couleur du héros, textes à l'encre, action en réplique.
func _make_card(data: CharacterData, progress_id: String) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(310, 0)
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(_on_card_input.bind(data))
	var sheet_style := StyleBoxFlat.new()
	sheet_style.bg_color = Color("e9dbb9")
	sheet_style.set_border_width_all(1)
	sheet_style.border_color = Color(BookTheme.PAGE_EDGE, 0.9)
	sheet_style.set_corner_radius_all(3)
	sheet_style.shadow_color = Color(0, 0, 0, 0.5)
	sheet_style.shadow_size = 18
	sheet_style.set_content_margin_all(16)
	card.add_theme_stylebox_override("panel", sheet_style)
	card.add_child(BookTheme.page_wear(data.character_type.hash() % 1000))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)

	# Portrait gravé : cadre sombre à l'accent du héros.
	var bust_frame := PanelContainer.new()
	bust_frame.custom_minimum_size = Vector2(278, 330)
	bust_frame.clip_contents = true
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color("241c12")
	frame_style.set_border_width_all(2)
	frame_style.border_color = data.color
	frame_style.set_corner_radius_all(3)
	frame_style.set_content_margin_all(4)
	bust_frame.add_theme_stylebox_override("panel", frame_style)
	var bust := TextureRect.new()
	bust.texture = data.bust
	bust.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bust.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bust.mouse_filter = Control.MOUSE_FILTER_IGNORE  # le clic passe à la planche
	bust_frame.add_child(bust)
	col.add_child(bust_frame)

	var name_label := BookTheme.make_label(data.display_name, 24,
			data.color.lerp(BookTheme.INK, 0.35), false, true)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name_label)

	var subtitle := BookTheme.make_label("%s  ·  %s" % [data.character_type, data.attribute],
			14, BookTheme.INK_MUTED, true)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(subtitle)

	if not data.description.is_empty():
		var desc := BookTheme.make_label(data.description, 13, BookTheme.INK)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.custom_minimum_size = Vector2(278, 0)
		col.add_child(desc)

	# Le libellé annonce la suite : reprise de la partie en cours (point de
	# reprise enregistré pour ce personnage) ou départ d'une nouvelle histoire.
	var has_run := not progress_id.is_empty() \
			and not Progress.resume_node(progress_id, data.character_type).is_empty()
	var button := Button.new()
	if has_run:
		button.text = "•  Continuer l'histoire"
		button.tooltip_text = "Reprend au dernier point de choix"
	else:
		button.text = "•  Commencer une nouvelle histoire"
	BookTheme.style_choice(button, false, 15)
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.pressed.connect(_on_choose.bind(data))
	col.add_child(button)

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
