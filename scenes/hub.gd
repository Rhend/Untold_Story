extends Control
## Hub des histoires (point d'entrée du jeu).
## Scanne data/stories/ (chaque sous-dossier portant un manifest.json est une
## histoire) et affiche une carte par histoire. Clic sur une histoire
## disponible : pose GameState.story_id puis va à la sélection de personnage.
## Une histoire verrouillée (manifest "locked": true) est grisée + cadenas, et
## reste injouable — le verrouillage est SIMULÉ (donnée statique du manifest),
## une vraie vérification Steamworks viendra le remplacer plus tard.
## UI construite en code pour cette tranche (DA à venir quand l'artiste sera là).

const SELECTION_SCENE := "res://scenes/character_selection.tscn"
const STORIES_ROOT := "res://data/stories/"

var _status: Label


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.06, 0.09)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 80
	root.offset_right = -80
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 32)
	add_child(root)

	var title := Label.new()
	title.text = "Choisis une histoire"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	root.add_child(title)

	# HFlowContainer : les cartes s'enroulent sur plusieurs lignes → tient avec
	# 1 comme avec N histoires, sans liste de largeur fixe.
	var flow := HFlowContainer.new()
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 28)
	flow.add_theme_constant_override("v_separation", 28)
	root.add_child(flow)

	var stories := _scan_stories()
	if stories.is_empty():
		var empty := Label.new()
		empty.text = "Aucune histoire trouvée dans " + STORIES_ROOT
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.modulate = Color(0.7, 0.5, 0.4)
		flow.add_child(empty)
	for story in stories:
		flow.add_child(_make_card(story))

	# Ligne de retour visuel (clic sur une histoire verrouillée).
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.custom_minimum_size = Vector2(0, 28)
	_status.modulate = Color(0.85, 0.6, 0.5)
	root.add_child(_status)


## Histoires disponibles : chaque sous-dossier de data/stories/ contenant un
## manifest.json lisible. { "id": dossier, "display_name": String, "locked": bool }.
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
			"locked": bool(parsed.get("locked", false)),
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["display_name"] < b["display_name"])
	return result


func _make_card(story: Dictionary) -> Control:
	var locked: bool = story["locked"]

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 190)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.09, 0.12)
	style.set_border_width_all(3)
	style.border_color = Color(0.45, 0.42, 0.5) if locked else Color(0.75, 0.62, 0.4)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	panel.gui_input.connect(_on_card_input.bind(story))
	if not locked:
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	else:
		# État visuel « indisponible » : carte grisée (pas de DA, juste distinct).
		panel.modulate = Color(1, 1, 1, 0.5)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)

	var name_label := Label.new()
	name_label.text = ("🔒  " if locked else "") + story["display_name"]
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 26)
	col.add_child(name_label)

	var button := Button.new()
	button.text = "Verrouillée" if locked else "Jouer"
	button.disabled = locked
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(_on_choose.bind(story))
	col.add_child(button)

	return panel


func _on_card_input(event: InputEvent, story: Dictionary) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_on_choose(story)


func _on_choose(story: Dictionary) -> void:
	if story["locked"]:
		# Pas de flux d'achat (pas d'App ID Steam) : simple retour visuel.
		_status.text = "« %s » : non encore disponible." % story["display_name"]
		return
	GameState.story_id = story["id"]
	get_tree().change_scene_to_file(SELECTION_SCENE)
