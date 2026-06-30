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
var _scrim: ColorRect
var _content: MarginContainer
var _has_badge := false

## Marge gauche du texte laissant la place à la pastille de profil (px de réf.).
const BADGE_CLEARANCE := 340
## Bordure autour de l'illustration (px de réf.) pour aérer et faciliter la lecture.
const BORDER := 56.0


func _ready() -> void:
	_build_ui()

	# Précharge les textures d'illustration en tâche de fond pour éviter
	# l'à-coup quand une page à parallaxe apparaît.
	IllustrationLibrary.preload_all()

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
	# index 1) et SOUS l'UI. Affiché seulement pour une illustration plein écran
	# (paysage), afin de garder le texte lisible par-dessus l'image.
	_scrim = ColorRect.new()
	_scrim.color = Color(0, 0, 0, 0.35)
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.visible = false
	add_child(_scrim)

	# Zone de récit (en-tête, texte, choix). Sa zone est repositionnée selon la
	# mise en page : plein écran, ou demi-page droite pour le mode « livre ».
	_content = MarginContainer.new()
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		_content.add_theme_constant_override(side, 56)
	add_child(_content)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 24)
	_content.add_child(col)

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

	# Pastille de profil du personnage, dans le coin haut-gauche.
	var character: CharacterData = GameState.selected_character
	_has_badge = character != null
	if _has_badge:
		add_child(_build_badge(character))
		# État initial (avant toute illustration) : texte plein écran → on
		# décale pour ne pas écrire sous la pastille.
		_content.add_theme_constant_override("margin_left", BADGE_CLEARANCE)


## Pastille de profil : petit carré (~15 % de la largeur de référence) ancré
## dans le coin haut-gauche, surimposé au reste.
func _build_badge(character: CharacterData) -> Control:
	const SIDE := 288.0  # ~15 % de 1920 (résolution de référence)

	var holder := VBoxContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	holder.position = Vector2(24, 24)
	holder.add_theme_constant_override("separation", 4)

	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(SIDE, SIDE)
	frame.clip_contents = true
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.06, 0.09)
	style.set_border_width_all(3)
	style.border_color = character.color
	style.set_corner_radius_all(6)
	frame.add_theme_stylebox_override("panel", style)

	var portrait := TextureRect.new()
	portrait.texture = character.icon if character.icon != null else character.bust
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.custom_minimum_size = Vector2(SIDE, SIDE)
	frame.add_child(portrait)
	holder.add_child(frame)

	var name_label := Label.new()
	name_label.text = character.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.custom_minimum_size = Vector2(SIDE, 0)
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", character.color)
	holder.add_child(name_label)

	return holder


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
	add_child(_illustration)
	# Au-dessus du fond (index 0), sous le voile et l'UI.
	move_child(_illustration, 1)
	_illustration.setup(data)
	_apply_illustration_layout(data.template)


## Place l'illustration et la zone de texte selon le gabarit :
##  - PAYSAGE : illustration plein écran, texte par-dessus (voile sombre).
##  - PORTRAIT : mise en page « livre » — illustration sur la moitié gauche,
##    texte sur la moitié droite.
func _apply_illustration_layout(template: int) -> void:
	if template == IllustrationData.Template.PORTRAIT:
		# Livre : texte sur la demi-page droite, loin de la pastille → marge normale.
		_set_rect_anchors(_illustration, 0.0, 0.0, 0.5, 1.0, BORDER)
		_set_rect_anchors(_content, 0.5, 0.0, 1.0, 1.0)
		_content.add_theme_constant_override("margin_left", 56)
		_scrim.visible = false
	else:
		# Plein cadre : illustration encadrée d'une bordure (meilleure lecture),
		# texte par-dessus ; on dégage la pastille à gauche.
		_set_rect_anchors(_illustration, 0.0, 0.0, 1.0, 1.0, BORDER)
		_set_rect_anchors(_content, 0.0, 0.0, 1.0, 1.0)
		_content.add_theme_constant_override("margin_left", BADGE_CLEARANCE if _has_badge else 56)
		_scrim.visible = true


func _set_rect_anchors(node: Control, l: float, t: float, r: float, b: float, inset: float = 0.0) -> void:
	node.anchor_left = l
	node.anchor_top = t
	node.anchor_right = r
	node.anchor_bottom = b
	# inset > 0 : marge intérieure sur les 4 côtés (bordure autour du décor).
	node.offset_left = inset
	node.offset_top = inset
	node.offset_right = -inset
	node.offset_bottom = -inset


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
