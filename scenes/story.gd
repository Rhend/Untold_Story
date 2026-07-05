extends Control
## Vue d'histoire : charge l'histoire, la fait tourner via le StoryRunner et
## affiche le buste du personnage + texte (effet machine à écrire) + choix.
## UI construite en code pour cette tranche (passage en .tscn éditable plus tard).

const STORY_PATH := "res://data/stories/act1_sc1.untold"
const SELECTION_SCENE := "res://scenes/character_selection.tscn"

var _runner: StoryRunner
var _story: Story
## Métadonnées d'auteur (sidecar .meta.json) — sert ici aux titres de scène.
var _meta: StoryMeta
var _header: Label
var _progress_label: Label
var _map: StoryMap
var _text_label: RichTextLabel
var _choices_box: VBoxContainer
var _typewriter: Tween
var _illustration: Illustration
var _scrim: ColorRect
var _content: MarginContainer
var _has_badge := false
## Nœud où le récit s'est arrêté (repère « vous êtes ici » de la carte).
var _current_node := ""

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
	_runner.node_visited.connect(_on_node_visited)
	_runner.choice_selected.connect(_on_choice_selected)

	_start_story()


func _start_story() -> void:
	var source := FileAccess.get_file_as_string(STORY_PATH)
	_story = StoryParser.parse(source)
	_meta = StoryMeta.load_for(STORY_PATH)
	Progress.begin_story(STORY_PATH.get_file().get_basename(), GameState.character_type)
	_runner.start(_story, {
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

	# Compteur de progression narrative (nœuds découverts, tous personnages
	# confondus), en haut à droite, au-dessus du reste.
	_progress_label = Label.new()
	_progress_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_progress_label.offset_left = -480
	_progress_label.offset_top = 16
	_progress_label.offset_right = -24
	_progress_label.offset_bottom = 44
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_progress_label.modulate = Color(0.55, 0.55, 0.7)
	_progress_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_progress_label)

	# Accès à la carte de progression narrative (aussi via la touche M).
	var map_button := Button.new()
	map_button.text = "🗺  Carte (M)"
	map_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	map_button.position = Vector2(-160, 48)
	map_button.pressed.connect(_toggle_map)
	add_child(map_button)

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
	_current_node = node_id

	_header.text = _build_header(node_id, tags)

	_text_label.text = text

	# Effet "machine à écrire" — contrôle d'affichage du texte.
	_text_label.visible_ratio = 0.0
	if _typewriter and _typewriter.is_running():
		_typewriter.kill()
	_typewriter = create_tween()
	var duration: float = clampf(text.length() * GameState.text_speed, 0.3, 6.0)
	_typewriter.tween_property(_text_label, "visible_ratio", 1.0, duration)


## En-tête du passage courant, selon l'environnement :
##  - PROD : seulement le titre de scène lisible (sidecar), vide s'il n'y en a
##    pas — l'id technique n'est JAMAIS montré au joueur.
##  - DEV  : en-tête de debug complet — id brut + tags + mentions de relecture.
func _build_header(node_id: String, tags: Array) -> String:
	if Env.is_production():
		return _meta.get_title(node_id)

	var header := node_id
	if tags.size() > 0:
		header += "   [ " + " · ".join(PackedStringArray(tags)) + " ]"
	# Mentions de relecture : le passage courant est déjà compté, d'où le > 1.
	if Progress.visit_count(node_id, GameState.character_type) > 1:
		header += "   · déjà lu"
	var others: Array = Progress.visitors(node_id).filter(
		func(c: String) -> bool: return c != GameState.character_type)
	if not others.is_empty():
		header += "   · lu par " + ", ".join(PackedStringArray(others))
	return header


func _on_present_choices(choices: Array) -> void:
	_clear_choices()
	for i in choices.size():
		var choice: Dictionary = choices[i]
		var button := Button.new()
		# Réponse déjà choisie (par n'importe quel personnage) : cochée et
		# atténuée, pour que les réponses encore inexplorées ressortent.
		var choosers: Array = Progress.choice_choosers(choice["node"], choice["text"])
		if choosers.is_empty():
			button.text = choice["text"]
		else:
			button.text = "✓ " + choice["text"]
			button.modulate = Color(1, 1, 1, 0.55)
			button.tooltip_text = "Déjà choisie avec : " + ", ".join(PackedStringArray(choosers))
		button.pressed.connect(_runner.choose.bind(i))
		_choices_box.add_child(button)


func _on_node_visited(node_id: String) -> void:
	Progress.record_visit(node_id)
	var total := _story.nodes.size()
	var seen: int = Progress.visited_count()
	if total > 0:
		_progress_label.text = "Progression : %d / %d nœuds (%d %%)" % [
			seen, total, roundi(100.0 * seen / total)]


func _on_choice_selected(node_id: String, choice: Dictionary) -> void:
	Progress.record_choice(node_id, choice["text"])


# ------------------------------------------------------- Carte de progression

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_M:
		_toggle_map()


## Ouvre/ferme la carte, reconstruite à chaque ouverture pour refléter la
## progression courante.
func _toggle_map() -> void:
	if _map != null:
		_map.queue_free()
		_map = null
		return
	_map = StoryMap.new()
	add_child(_map)
	_map.setup(_story, STORY_PATH, _current_node)
	_map.close_requested.connect(_toggle_map)


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
