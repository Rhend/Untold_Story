extends Control
## Sélection de personnage (L3), présentée comme la PAGE DE GARDE du livre
## ouvert. Page de gauche : titre et pitch de l'histoire (manifest "pitch"),
## texte centré dans un liseré rouge, lettrine rubriquée comme les passages
## du récit. Page de droite : les portraits du casting — un clic sur un
## portrait remplit la moitié basse de la page avec la fiche du personnage
## (nom, rôle, archétype, description, % de complétion) et les actions :
## lancer l'histoire, ou la recommencer depuis le début.
## On arrive du plongeon du hub : l'écran s'ouvre sur un fondu depuis le noir.
## UI construite en code pour cette tranche (passage en .tscn éditable plus tard).

const STORY_SCENE := "res://scenes/story.tscn"
const HUB_SCENE := "res://scenes/hub.tscn"

## Proportions du livre ouvert : format A4 (ISO 216), comme la scène d'histoire.
const BOOK_RATIO := 420.0 / 297.0
## Débord du bloc des pages (tranches empilées) autour des pages ouvertes.
const PAGE_BLOCK := 9.0

## Manifest de l'histoire courante (titre, pitch), chargé une fois.
var _manifest: Dictionary = {}
## Nombre total de nœuds de l'histoire (pour le % de complétion), 0 si inconnu.
var _total_nodes := 0
## Fiche du personnage sélectionné (moitié basse de la page de droite).
var _details: VBoxContainer
## Par personnage : { "frame": PanelContainer, "data": CharacterData } —
## pour marquer le portrait sélectionné et redessiner les autres.
var _portraits: Dictionary = {}
var _selected: CharacterData


func _ready() -> void:
	# Repli pour un lancement direct de character_selection.tscn (sans hub) :
	# résout génériquement l'histoire pour que le scan des personnages aboutisse.
	if GameState.story_id.is_empty():
		GameState.story_id = GameState.first_story_id()
	_manifest = _load_manifest()
	_total_nodes = _count_story_nodes()
	_build_ui()


## Manifest de l'histoire courante, ou {} s'il est illisible.
func _load_manifest() -> Dictionary:
	var manifest_path := GameState.story_dir() + "manifest.json"
	if not FileAccess.file_exists(manifest_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	return parsed if parsed is Dictionary else {}


## Nombre de nœuds du .untold de l'histoire (dénominateur du % de complétion).
func _count_story_nodes() -> int:
	var entry := str(_manifest.get("entry_file", ""))
	if entry.is_empty():
		return 0
	var path := GameState.story_dir() + entry
	if not FileAccess.file_exists(path):
		return 0
	return StoryParser.parse(FileAccess.get_file_as_string(path)).nodes.size()


func _build_ui() -> void:
	add_child(BookTheme.make_desk())

	# Le livre ouvert, même construction que la scène d'histoire.
	var frame := MarginContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		frame.add_theme_constant_override(side, 24)
	add_child(frame)

	var ratio_box := AspectRatioContainer.new()
	ratio_box.ratio = BOOK_RATIO
	frame.add_child(ratio_box)

	var book := PanelContainer.new()
	book.add_theme_stylebox_override("panel", BookTheme.leather_style(12, 18.0))
	ratio_box.add_child(book)

	book.add_child(BookTheme.make_page_block(PAGE_BLOCK))
	var pages_margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pages_margin.add_theme_constant_override(side, int(PAGE_BLOCK))
	book.add_child(pages_margin)

	var pages := HBoxContainer.new()
	pages.add_theme_constant_override("separation", 0)
	pages_margin.add_child(pages)
	pages.add_child(_build_pitch_page())
	pages.add_child(_build_cast_page())

	# Reliure centrale (creux ombré + renflement des pages), cf. story.gd.
	var spine := TextureRect.new()
	spine.texture = BookTheme.gradient_tex(
			[Color(BookTheme.SPINE, 0.0), Color(BookTheme.PARCHMENT_BRIGHT, 0.16),
			Color(BookTheme.SPINE, 0.60), Color(BookTheme.SPINE, 0.60),
			Color(BookTheme.PARCHMENT_BRIGHT, 0.16), Color(BookTheme.SPINE, 0.0)],
			[0.44, 0.474, 0.494, 0.506, 0.526, 0.56])
	spine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	book.add_child(spine)

	# Retour au hub : le joueur n'est pas enfermé dans une histoire une fois
	# entré (il peut en changer avant de choisir un personnage). Sur la table,
	# hors du livre.
	var back := Button.new()
	back.text = "↩  Changer d'histoire"
	BookTheme.style_choice(back, false, 16, true)
	back.set_anchors_preset(Control.PRESET_TOP_LEFT)
	back.position = Vector2(24, 16)
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file(HUB_SCENE))
	add_child(back)

	# Arrivée depuis le plongeon du hub : fondu depuis le noir.
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)
	var fade := create_tween()
	fade.tween_property(black, "color:a", 0.0, 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fade.tween_callback(black.queue_free)


# ------------------------------------------------------------ Page de gauche

## Page de gauche : titre de l'histoire et pitch centré dans un liseré rouge,
## avec la lettrine rubriquée des passages du récit. Sobre si pas de pitch.
func _build_pitch_page() -> Control:
	var page := _make_page(true, 11)

	var inner := MarginContainer.new()
	inner.add_theme_constant_override("margin_left", 52)
	inner.add_theme_constant_override("margin_right", 44)  # côté reliure
	inner.add_theme_constant_override("margin_top", 52)
	inner.add_theme_constant_override("margin_bottom", 44)
	page.add_child(inner)

	# Titre haut placé (page de garde), pitch au-dessous.
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 24)
	inner.add_child(col)

	var title := BookTheme.make_label(str(_manifest.get("display_name", "")),
			38, BookTheme.INK, false, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	col.add_child(BookTheme.make_fleuron())

	var pitch_text := str(_manifest.get("pitch", ""))
	if pitch_text.is_empty():
		return page

	# Respiration entre le fleuron et le bloc du pitch.
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gap)

	# Le liseré rouge : cadre fin au rouge du ruban, filet dédoublé et petits
	# losanges de coin, autour du pitch.
	var box := PanelContainer.new()
	var box_style := StyleBoxEmpty.new()
	box_style.set_content_margin_all(34)
	box.add_theme_stylebox_override("panel", box_style)
	box.add_child(_make_red_liseret())
	col.add_child(box)

	# Le pitch : centré, aéré, lettrine rubriquée sur la première lettre — la
	# même écriture que les passages du récit.
	var pitch := RichTextLabel.new()
	pitch.bbcode_enabled = true
	pitch.fit_content = true
	pitch.add_theme_font_override("normal_font", BookTheme.serif())
	pitch.add_theme_font_override("italics_font", BookTheme.serif(true))
	pitch.add_theme_font_override("bold_font", BookTheme.serif(false, true))
	pitch.add_theme_font_size_override("normal_font_size", 19)
	pitch.add_theme_color_override("default_color", BookTheme.INK)
	pitch.add_theme_constant_override("line_separation", 12)
	pitch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pitch.text = "[center]" + _with_drop_cap(pitch_text) + "[/center]"
	box.add_child(pitch)
	return page


## Liseré rouge : filet fin au rouge du ruban, dédoublé d'un trait encore plus
## léger, petits losanges de coin — discret, à peine plus qu'un fil.
func _make_red_liseret() -> Control:
	var liseret := Control.new()
	liseret.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	liseret.mouse_filter = Control.MOUSE_FILTER_IGNORE
	liseret.draw.connect(func() -> void:
		var outer := Rect2(Vector2.ZERO, liseret.size).grow(-2.0)
		liseret.draw_rect(outer, Color(BookTheme.RIBBON, 0.7), false, 1.0, true)
		liseret.draw_rect(outer.grow(-4.0), Color(BookTheme.RIBBON, 0.28), false, 1.0, true)
		for corner in [outer.position, Vector2(outer.end.x, outer.position.y),
				Vector2(outer.position.x, outer.end.y), outer.end]:
			liseret.draw_colored_polygon(PackedVector2Array([
				corner + Vector2(0, -3.0), corner + Vector2(3.0, 0),
				corner + Vector2(0, 3.0), corner + Vector2(-3.0, 0)]),
				Color(BookTheme.RIBBON, 0.8)))
	return liseret


## Lettrine : première lettre grossie à l'encre du ruban, comme en tête des
## passages du récit (copie de story.gd — même rendu, même règle).
func _with_drop_cap(text: String) -> String:
	var i := 0
	while i < text.length() and text[i] in [" ", "\t", "\n"]:
		i += 1
	if i >= text.length():
		return text
	var first := text[i]
	if first == "[" or first.to_upper() == first.to_lower():
		return text
	return text.substr(0, i) \
			+ "[font_size=44][color=#7a3126]%s[/color][/font_size]" % first \
			+ text.substr(i + 1)


# ------------------------------------------------------------- Page de droite

## Page de droite : consigne, rangée de portraits, et fiche du personnage
## sélectionné dans la moitié basse.
func _build_cast_page() -> Control:
	var page := _make_page(false, 27)

	var inner := MarginContainer.new()
	inner.add_theme_constant_override("margin_left", 44)  # côté reliure
	inner.add_theme_constant_override("margin_right", 52)
	inner.add_theme_constant_override("margin_top", 44)
	inner.add_theme_constant_override("margin_bottom", 40)
	page.add_child(inner)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	inner.add_child(col)

	var title := BookTheme.make_label(
			"Choisissez avec quel personnage vous voulez partir à l'aventure.",
			22, BookTheme.INK, false, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)

	col.add_child(BookTheme.make_fleuron())

	# Les portraits seuls — le reste de la fiche apparaît à la sélection.
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	col.add_child(row)
	for path in GameState.character_paths():
		var data: CharacterData = load(path)
		if data == null:
			push_error("Sélection : personnage introuvable : " + path)
			continue
		row.add_child(_make_portrait(data))

	# Moitié basse : la fiche du personnage sélectionné.
	_details = VBoxContainer.new()
	_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_details.alignment = BoxContainer.ALIGNMENT_CENTER
	_details.add_theme_constant_override("separation", 10)
	col.add_child(_details)
	_show_placeholder()
	return page


## Portrait cliquable d'un personnage : cadre sombre à sa couleur, épaissi
## quand il est sélectionné.
func _make_portrait(data: CharacterData) -> Control:
	var bust_frame := PanelContainer.new()
	bust_frame.custom_minimum_size = Vector2(150, 178)
	bust_frame.clip_contents = true
	bust_frame.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	bust_frame.tooltip_text = data.display_name
	bust_frame.add_theme_stylebox_override("panel", _portrait_style(data, false))
	bust_frame.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			_select(data))
	_add_hover_highlight(bust_frame)
	_portraits[data.character_type] = {"frame": bust_frame, "data": data}

	var bust := TextureRect.new()
	bust.texture = data.bust
	bust.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bust.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bust.mouse_filter = Control.MOUSE_FILTER_IGNORE  # le clic reste au cadre
	bust_frame.add_child(bust)
	return bust_frame


## Cadre d'un portrait : bordure fine à la couleur du héros, nettement
## épaissie pour le portrait sélectionné.
func _portrait_style(data: CharacterData, selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("241c12")
	style.set_border_width_all(5 if selected else 2)
	style.border_color = data.color
	style.set_corner_radius_all(3)
	style.set_content_margin_all(3)
	return style


## Sélectionne un personnage : marque son portrait (bordure épaissie, les
## autres reprennent leur trait fin) et remplit sa fiche.
func _select(data: CharacterData) -> void:
	_selected = data
	for character_type in _portraits:
		var entry: Dictionary = _portraits[character_type]
		(entry["frame"] as PanelContainer).add_theme_stylebox_override("panel",
				_portrait_style(entry["data"], character_type == data.character_type))
	_show_details(data)


## Invite affichée tant qu'aucun portrait n'est sélectionné.
func _show_placeholder() -> void:
	_clear_details()
	var hint := BookTheme.make_label(
			"— Cliquez sur un portrait pour découvrir le personnage —",
			15, BookTheme.INK_FADED, true)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_details.add_child(hint)


func _clear_details() -> void:
	for child in _details.get_children():
		child.queue_free()


## Fiche du personnage sélectionné, en CARTE D'IDENTITÉ : le portrait en
## grand à gauche, et à droite les textes empilés — nom, rôle, archétype,
## description, % de complétion — puis les actions (lancer / recommencer).
func _show_details(data: CharacterData) -> void:
	_clear_details()

	# CENTRÉE dans la page, avec de l'air : la carte ne prend que sa largeur
	# minimale (portrait + colonne de textes bornée) et flotte au centre.
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0, 0, 0, 0.04)
	card_style.set_border_width_all(1)
	card_style.border_color = Color(BookTheme.PAGE_EDGE, 0.7)
	card_style.set_corner_radius_all(3)
	card_style.set_content_margin_all(22)
	card.add_theme_stylebox_override("panel", card_style)
	_details.add_child(card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	card.add_child(row)

	# Le portrait, repris en plus grand.
	var bust_frame := PanelContainer.new()
	bust_frame.custom_minimum_size = Vector2(170, 204)
	bust_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bust_frame.clip_contents = true
	bust_frame.add_theme_stylebox_override("panel", _portrait_style(data, false))
	var bust := TextureRect.new()
	bust.texture = data.bust
	bust.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bust.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bust_frame.add_child(bust)
	row.add_child(bust_frame)

	# Les textes, les uns sous les autres — tout à 19, comme le récit.
	var info := VBoxContainer.new()
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 10)
	row.add_child(info)

	info.add_child(BookTheme.make_label(data.display_name, 24,
			data.color.lerp(BookTheme.INK, 0.35), false, true))
	info.add_child(BookTheme.make_label("Rôle : " + data.character_type,
			19, BookTheme.INK_MUTED, true))
	info.add_child(BookTheme.make_label("Archétype : " + data.attribute,
			19, BookTheme.INK_MUTED, true))

	if not data.description.is_empty():
		var desc := BookTheme.make_label(data.description, 19, BookTheme.INK)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(290, 0)
		info.add_child(desc)

	# Complétion : nœuds découverts par CE personnage (cumulatif inter-parties)
	# sur le total de l'histoire.
	var progress_id := _story_progress_id()
	if _total_nodes > 0 and not progress_id.is_empty():
		var seen := Progress.visited_count_by(data.character_type, progress_id)
		info.add_child(BookTheme.make_label("Histoire complétée à %d %%"
				% roundi(100.0 * seen / _total_nodes), 19, BookTheme.INK_FADED, true))

	# Actions empilées : lancer l'histoire (reprise ou début), et recommencer
	# à zéro quand une partie est en cours.
	var has_run := not progress_id.is_empty() \
			and not Progress.resume_node(progress_id, data.character_type).is_empty()
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 2)
	info.add_child(actions)

	var launch := Button.new()
	launch.text = "•  Continuer l'histoire" if has_run else "•  Commencer l'histoire"
	if has_run:
		launch.tooltip_text = "Reprend au dernier point de choix"
	BookTheme.style_choice(launch, false, 19)
	launch.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	launch.pressed.connect(_on_choose.bind(data))
	actions.add_child(launch)

	if has_run:
		var restart := Button.new()
		restart.text = "↻  Recommencer depuis le début"
		restart.tooltip_text = "Efface la partie en cours de ce personnage"
		BookTheme.style_choice(restart, true, 19)
		restart.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		restart.pressed.connect(func() -> void:
			Progress.restart_playthrough(progress_id, data.character_type)
			_on_choose(data))
		actions.add_child(restart)


# ------------------------------------------------------------------ Communs

## Une page du livre : papier, usure et enluminure (mêmes briques que story.gd).
func _make_page(left_side: bool, wear_seed: int) -> PanelContainer:
	var page := PanelContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	page.add_child(BookTheme.paper(left_side))
	page.add_child(BookTheme.page_wear(wear_seed))
	page.add_child(BookTheme.make_page_frame())
	return page


## Id de progression de l'histoire courante : le nom de base de son .untold
## (celui sous lequel Progress range reprise et découverte, cf. story.gd).
func _story_progress_id() -> String:
	var entry := str(_manifest.get("entry_file", ""))
	return entry.get_file().get_basename() if not entry.is_empty() else ""


## Surbrillance de survol d'un portrait : léger grossissement depuis le
## centre, même langage que les couvertures du hub.
func _add_hover_highlight(card: Control) -> void:
	card.mouse_entered.connect(func() -> void: _tween_highlight(card, 1.04))
	card.mouse_exited.connect(func() -> void: _tween_highlight(card, 1.0))


func _tween_highlight(card: Control, target_scale: float) -> void:
	var previous: Variant = card.get_meta("hover_tween") \
			if card.has_meta("hover_tween") else null
	if previous is Tween and (previous as Tween).is_valid():
		(previous as Tween).kill()
	card.pivot_offset = card.size / 2.0
	var tween := card.create_tween()
	tween.tween_property(card, "scale", Vector2.ONE * target_scale, 0.14) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	card.set_meta("hover_tween", tween)


func _on_choose(data: CharacterData) -> void:
	GameState.selected_character = data
	GameState.character_type = data.character_type
	GameState.character_attribute = data.attribute
	get_tree().change_scene_to_file(STORY_SCENE)
