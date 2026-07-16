extends Control
## Hub des histoires (point d'entrée du jeu).
## Scanne data/stories/ (chaque sous-dossier portant un manifest.json est une
## histoire) et affiche chaque histoire comme une COUVERTURE DE GRIMOIRE
## (thème BookTheme) : cuir, filet doré, ruban marque-page pour les histoires
## disponibles. Clic sur une couverture disponible : pose GameState.story_id
## puis va à la sélection de personnage.
## Une histoire verrouillée (manifest "locked": true) est assombrie et reste
## injouable — le verrouillage est SIMULÉ (donnée statique du manifest), une
## vraie vérification Steamworks viendra le remplacer plus tard.
## UI construite en code pour cette tranche (DA à venir quand l'artiste sera là).

const SELECTION_SCENE := "res://scenes/character_selection.tscn"
const STORIES_ROOT := "res://data/stories/"

## Taille d'une couverture sur le rayon (proportions d'un in-octavo).
const COVER_SIZE := Vector2(340, 480)

var _status: Label
## Popup « pas encore d'histoire » du tome fantôme (null tant que fermé).
var _placeholder_popup: Control
## true pendant le plongeon vers la sélection (bloque tout autre clic).
var _transitioning := false


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	add_child(BookTheme.make_desk())

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 80
	root.offset_right = -80
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 44)
	add_child(root)

	var title := BookTheme.make_label("Choisis une histoire", 38,
			BookTheme.PARCHMENT, false, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	# HFlowContainer : les couvertures s'enroulent sur plusieurs lignes → tient
	# avec 1 comme avec N histoires, sans liste de largeur fixe.
	var flow := HFlowContainer.new()
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 44)
	flow.add_theme_constant_override("v_separation", 44)
	root.add_child(flow)

	var stories := _scan_stories()
	if stories.is_empty():
		var empty := BookTheme.make_label(
				"Aucune histoire trouvée dans " + STORIES_ROOT, 16,
				Color(0.85, 0.6, 0.5), true)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		flow.add_child(empty)
	for story in stories:
		flow.add_child(_make_card(story))
	# Tome fantôme en fin de rayon : promesse d'histoires à venir.
	flow.add_child(_make_placeholder_card())

	# Ligne de retour visuel (clic sur une histoire verrouillée).
	_status = BookTheme.make_label("", 15, Color(0.85, 0.6, 0.5), true)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.custom_minimum_size = Vector2(0, 28)
	root.add_child(_status)


## Histoires disponibles : chaque sous-dossier de data/stories/ contenant un
## manifest.json lisible. { "id": dossier, "display_name": String,
## "author": String (vide si non renseigné), "locked": bool }.
## L'id est le NOM DU DOSSIER (source de vérité pour le chargement, cf.
## GameState.story_dir) ; il coïncide avec le champ "id" du manifest.
func _scan_stories() -> Array:
	var result: Array = []
	var root := DirAccess.open(STORIES_ROOT)
	if root == null:
		push_error("Hub : dossier introuvable : " + STORIES_ROOT)
		return result
	for sub in root.get_directories():
		var manifest_path := STORIES_ROOT + sub + "/manifest.json"
		if not FileAccess.file_exists(manifest_path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		if not (parsed is Dictionary):
			push_warning("Hub : manifest illisible ignoré : " + manifest_path)
			continue
		result.append({
			"id": sub,
			"display_name": str(parsed.get("display_name", sub)),
			"author": str(parsed.get("author", "")).strip_edges(),
			"locked": bool(parsed.get("locked", false)),
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["display_name"] < b["display_name"])
	return result


## Couverture d'un tome : cuir, filet doré intérieur, titre, fleuron et nom
## d'auteur (rien si non renseigné). Toute la couverture est cliquable, avec
## une surbrillance au survol. Disponible → ruban marque-page ; verrouillée →
## assombrie et mention « Verrouillée ».
func _make_card(story: Dictionary) -> Control:
	var locked: bool = story["locked"]

	var cover := PanelContainer.new()
	cover.custom_minimum_size = COVER_SIZE
	cover.add_theme_stylebox_override("panel", BookTheme.leather_style(8, 16))
	cover.gui_input.connect(_on_card_input.bind(story, cover))
	if not locked:
		cover.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_add_hover_highlight(cover)
	else:
		# État visuel « indisponible » : couverture assombrie (pas de DA, juste distinct).
		cover.modulate = Color(0.72, 0.72, 0.72, 0.85)

	# Filet doré intérieur, comme un fer à dorer sur le cuir. Transparent à la
	# souris (comme toute la descendance) : le clic et le survol appartiennent
	# à la couverture entière.
	var filet := PanelContainer.new()
	filet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var filet_style := StyleBoxFlat.new()
	filet_style.bg_color = Color(0, 0, 0, 0)
	filet_style.set_border_width_all(1)
	filet_style.border_color = Color(BookTheme.PAGE_EDGE, 0.8)
	filet_style.set_corner_radius_all(5)
	filet_style.set_content_margin_all(18)
	filet.add_theme_stylebox_override("panel", filet_style)
	cover.add_child(filet)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 18)
	filet.add_child(col)

	var name_label := BookTheme.make_label(str(story["display_name"]), 31,
			BookTheme.PARCHMENT, false, true)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(name_label)

	col.add_child(BookTheme.make_fleuron())

	# Nom d'auteur sous le fleuron, comme sur une vraie couverture — rien
	# si le manifest ne le renseigne pas.
	if not str(story["author"]).is_empty():
		var author := BookTheme.make_label(str(story["author"]), 19,
				Color(BookTheme.PARCHMENT, 0.85), true)
		author.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		author.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(author)

	if locked:
		var lock_hint := BookTheme.make_label("Verrouillée", 16,
				Color(BookTheme.PAGE_EDGE, 0.8), true)
		lock_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(lock_hint)

	# Marque d'éditeur au bas de la couverture. Le PanelContainer étire ses
	# enfants directs : on passe par un canevas intermédiaire pour ancrer.
	var mark_holder := Control.new()
	mark_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.add_child(mark_holder)
	var mark := BookTheme.make_label("·  UNTOLD  ·", 12, Color(BookTheme.PAGE_EDGE, 0.75))
	mark.anchor_top = 1.0
	mark.anchor_bottom = 1.0
	mark.anchor_right = 1.0
	mark.offset_top = -26
	mark.offset_bottom = -8
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark_holder.add_child(mark)

	# Ruban marque-page élimé (cf. icon.svg), sur les tomes disponibles.
	if not locked:
		var ribbon := Control.new()
		ribbon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ribbon.draw.connect(func() -> void:
			var left := ribbon.size.x - 26.0
			var top := -12.0  # dépasse le bord du cuir (dessin non clippé)
			var points := PackedVector2Array([
				Vector2(left, top), Vector2(left + 20, top),
				Vector2(left + 20, top + 58), Vector2(left + 10, top + 44),
				Vector2(left, top + 58)])
			ribbon.draw_colored_polygon(points, BookTheme.RIBBON)
			var outline := points.duplicate()
			outline.append(points[0])
			ribbon.draw_polyline(outline, Color("54211a"), 1.5, true))
		cover.add_child(ribbon)

	return cover


## Tome fantôme « Nouvelle Histoire ? » : couverture au cuir éteint, sans
## ruban ni marque d'éditeur — un livre pas encore écrit. Clic → popup.
func _make_placeholder_card() -> Control:
	var cover := PanelContainer.new()
	cover.custom_minimum_size = COVER_SIZE
	cover.add_theme_stylebox_override("panel", BookTheme.leather_style(8, 16))
	cover.modulate = Color(0.62, 0.62, 0.62, 0.9)
	cover.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_add_hover_highlight(cover)
	cover.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			_show_placeholder_popup())

	# Filet doré en pointillé discret : la dorure n'est pas encore posée.
	var filet := Control.new()
	filet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	filet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	filet.draw.connect(func() -> void:
		var rect := Rect2(Vector2.ZERO, filet.size).grow(-16.0)
		var color := Color(BookTheme.PAGE_EDGE, 0.5)
		for side in [[rect.position, Vector2(rect.end.x, rect.position.y)],
				[Vector2(rect.end.x, rect.position.y), rect.end],
				[rect.end, Vector2(rect.position.x, rect.end.y)],
				[Vector2(rect.position.x, rect.end.y), rect.position]]:
			filet.draw_dashed_line(side[0], side[1], color, 1.0, 7.0))
	cover.add_child(filet)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 18)
	cover.add_child(col)

	var name_label := BookTheme.make_label("Nouvelle Histoire ?", 31,
			Color(BookTheme.PARCHMENT, 0.8), true)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(name_label)

	col.add_child(BookTheme.make_fleuron())

	var hint := BookTheme.make_label("À paraître", 18,
			Color(BookTheme.PAGE_EDGE, 0.8), true)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)
	return cover


## Popup du tome fantôme : feuille de parchemin sur fond assombri, message et
## fermeture (bouton, clic hors de la feuille ou Échap... via le bouton).
func _show_placeholder_popup() -> void:
	if _placeholder_popup != null:
		return
	_placeholder_popup = Control.new()
	_placeholder_popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_placeholder_popup)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Clic n'importe où sur le fond : ferme le popup.
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_close_placeholder_popup())
	_placeholder_popup.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_placeholder_popup.add_child(center)

	var sheet := PanelContainer.new()
	sheet.custom_minimum_size = Vector2(460, 0)
	var sheet_style := StyleBoxFlat.new()
	sheet_style.bg_color = BookTheme.PARCHMENT
	sheet_style.set_border_width_all(2)
	sheet_style.border_color = BookTheme.PAGE_EDGE
	sheet_style.set_corner_radius_all(6)
	sheet_style.set_content_margin_all(34)
	sheet_style.shadow_color = Color(0, 0, 0, 0.5)
	sheet_style.shadow_size = 18
	sheet.add_theme_stylebox_override("panel", sheet_style)
	center.add_child(sheet)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 20)
	sheet.add_child(col)

	var message := BookTheme.make_label(
			"Désolé mais il n'y a pas encore d'histoire derrière ce livre...\nRevenez plus tard.",
			19, BookTheme.INK, true)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(message)

	col.add_child(BookTheme.make_fleuron())

	var close := Button.new()
	close.text = "Fermer"
	BookTheme.style_choice(close, false, 17)
	close.alignment = HORIZONTAL_ALIGNMENT_CENTER
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(_close_placeholder_popup)
	col.add_child(close)


func _close_placeholder_popup() -> void:
	if _placeholder_popup != null:
		_placeholder_popup.queue_free()
		_placeholder_popup = null


## Surbrillance de survol d'une couverture cliquable : léger grossissement
## depuis le centre et cuir éclairci, en fondu doux (aller-retour).
func _add_hover_highlight(cover: Control) -> void:
	var base: Color = cover.modulate
	# Inerte pendant le plongeon : le mouse_exited provoqué par le bouclier de
	# transition écraserait l'animation d'ouverture de la couverture.
	cover.mouse_entered.connect(func() -> void:
		if not _transitioning:
			_tween_highlight(cover, base * Color(1.14, 1.13, 1.10), 1.03))
	cover.mouse_exited.connect(func() -> void:
		if not _transitioning:
			_tween_highlight(cover, base, 1.0))


func _tween_highlight(cover: Control, color: Color, target_scale: float) -> void:
	var previous: Variant = cover.get_meta("hover_tween") \
			if cover.has_meta("hover_tween") else null
	if previous is Tween and (previous as Tween).is_valid():
		(previous as Tween).kill()
	cover.pivot_offset = cover.size / 2.0
	var tween := cover.create_tween().set_parallel()
	tween.tween_property(cover, "scale", Vector2.ONE * target_scale, 0.16) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(cover, "modulate", color, 0.16)
	cover.set_meta("hover_tween", tween)


func _on_card_input(event: InputEvent, story: Dictionary, cover: Control) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_on_choose(story, cover)


func _on_choose(story: Dictionary, cover: Control) -> void:
	if story["locked"]:
		# Pas de flux d'achat (pas d'App ID Steam) : simple retour visuel.
		_status.text = "« %s » : non encore disponible." % story["display_name"]
		return
	if _transitioning:
		return
	_transitioning = true
	GameState.story_id = story["id"]
	_play_dive_transition(cover)


# ------------------------------------------------- Plongeon dans l'histoire

## Transition « on plonge dans le livre » — tout se joue EN MÊME TEMPS :
## pendant que la caméra pique vers la page (zoom continu + arc en cloche),
## la couverture s'ouvre comme une vraie : le plat avant pivote sur la
## charnière de la reliure (sa face se dérobe jusqu'à la tranche), puis son
## DOS se déploie vers la gauche, découvrant la première page. Le zoom
## continue jusqu'à la pleine page ; le fondu au noir n'est là que pour
## couvrir la génération de la page de garde (qui rouvre en FadeOut).
func _play_dive_transition(cover: Control) -> void:
	# Bouclier plein écran : plus aucune interaction pendant la transition.
	var shield := Control.new()
	shield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shield.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shield)

	# La première page du livre, révélée sous le plat avant qui s'ouvre.
	var rect := cover.get_global_rect()
	var paper := PanelContainer.new()
	var paper_style := StyleBoxFlat.new()
	paper_style.bg_color = Color("e9dbb9")
	paper_style.set_border_width_all(1)
	paper_style.border_color = Color(BookTheme.PAGE_EDGE, 0.9)
	paper_style.set_corner_radius_all(4)
	paper.add_theme_stylebox_override("panel", paper_style)
	paper.position = rect.position
	paper.size = rect.size
	shield.add_child(paper)
	paper.add_child(BookTheme.page_wear(7))

	# Le plat avant = la couverture d'origine, passée AU-DESSUS de la page
	# (z_index), charnière sur sa tranche gauche (la reliure).
	var hover: Variant = cover.get_meta("hover_tween") if cover.has_meta("hover_tween") else null
	if hover is Tween and (hover as Tween).is_valid():
		(hover as Tween).kill()
	cover.scale = Vector2.ONE
	cover.z_index = 10
	cover.pivot_offset = Vector2(0.0, cover.size.y / 2.0)

	# Le DOS du plat avant : cuir nu qui se déploie À GAUCHE de la charnière
	# quand la couverture passe la tranche (2e moitié de la rotation).
	var inside := PanelContainer.new()
	var inside_style := BookTheme.leather_style(8, 16)
	inside_style.shadow_size = 0  # le dos ne porte pas l'ombre du livre
	inside.add_theme_stylebox_override("panel", inside_style)
	inside.modulate = Color(0.62, 0.58, 0.52)  # face interne, moins éclairée
	inside.position = rect.position - Vector2(rect.size.x, 0)
	inside.size = rect.size
	inside.pivot_offset = Vector2(rect.size.x, rect.size.y / 2.0)
	inside.scale = Vector2(0.0, 1.0)
	inside.z_index = 10
	shield.add_child(inside)

	# Voile noir final, au-dessus de tout.
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 0)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.z_index = 20
	shield.add_child(black)

	# Le zoom du plongeon converge vers le centre de la page.
	pivot_offset = rect.get_center()

	# TOUT EN PARALLÈLE : plongeon 1.3 s, ouverture 0.4 + 0.35 s, fondu au
	# noir sur la fin — puis bascule de scène une fois le noir posé.
	var tween := create_tween().set_parallel()
	tween.tween_method(_dive_step, 0.0, 1.0, 1.3)
	# 1re moitié : la face de la couverture se dérobe jusqu'à la tranche
	# (accélération de bascule), en perdant sa lumière.
	tween.tween_property(cover, "scale:x", 0.0, 0.4) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(cover, "modulate", Color(0.66, 0.60, 0.53), 0.4)
	# 2e moitié : le dos du plat se déploie vers la gauche (décélération).
	tween.tween_property(inside, "scale:x", 1.0, 0.35).set_delay(0.4) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(black, "color:a", 1.0, 0.4).set_delay(0.85)
	tween.chain().tween_callback(func() -> void:
		get_tree().change_scene_to_file(SELECTION_SCENE))


## Une étape du plongeon : zoom continu vers la page (quadratique — la
## caméra accélère en approchant) et arc « en cloche », léger soulèvement
## avant le piqué. À t = 1, la page emplit l'écran.
func _dive_step(t: float) -> void:
	scale = Vector2.ONE * (1.0 + 2.8 * t * t)
	position.y = 90.0 * sin(PI * t)
