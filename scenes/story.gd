extends Control
## Vue d'histoire : charge l'histoire, la fait tourner via le StoryRunner et
## la présente comme un GRIMOIRE OUVERT (ambiance de icon.svg) — un bandeau
## d'informations en haut de l'écran (personnage, histoire en cours,
## progression, inventaire, carte) ; page de gauche : illustration « imprimée »
## dans une planche encadrée ; page de droite : titre de scène, texte (machine
## à écrire, police à empattements) et choix. Une icône au coin de la planche ouvre
## l'illustration en plein écran ; le parallaxe reste discret dans la page et
## ne joue pleinement qu'en plein écran.
## UI construite en code pour cette tranche (passage en .tscn éditable plus tard).

const SELECTION_SCENE := "res://scenes/character_selection.tscn"

## Chemin du .untold de l'histoire courante, résolu au démarrage depuis
## GameState.story_id + le entry_file du manifest.json de l'histoire.
var _story_path := ""

var _runner: StoryRunner
var _story: Story
## Métadonnées d'auteur (sidecar .meta.json) — sert ici aux titres de scène.
var _meta: StoryMeta
var _header: Label
var _progress_label: Label
var _map: StoryMap
var _inventory_overlay: InventoryOverlay
var _text_label: RichTextLabel
var _choices_box: VBoxContainer
var _typewriter: Tween
## Effet « shock » gardé en référence pour relancer son à-coup à chaque passage.
var _fx_shock: RichTextEffect
## Texte brut (avec balises de pause) actuellement affiché, accumulé par les
## lignes de dialogue ajoutées au clic d'une zone — base des ajouts suivants.
var _display_raw := ""
var _illustration: Illustration
## Données de l'illustration courante (pour la rejouer en plein écran).
var _illustration_data: IllustrationData
## Texte complet du passage à restaurer au premier affichage après une reprise
## ("" sinon) — consommé par _on_display_text (cf. _start_story).
var _resume_text := ""
var _plate_holder: Control  # espace de la planche (cadrage manuel, cf. _layout_plate)
var _plate: PanelContainer               # la planche (bordure + illustration)
## Ratio (largeur/hauteur) de la texture de l'illustration courante — la
## planche l'épouse exactement (cf. _layout_plate). 0 = pas d'image.
var _image_ratio := 0.0
var _fullscreen: Control                 # surimpression plein écran (ou null)
## Titre de l'histoire en cours dans le bandeau (lu dans le manifest).
var _title_label: Label
var _story_title := ""
## Bascule « tourner la page » : la page de droite se replie vers la reliure
## (dévoilant le bloc de tranches dessous, comme la page suivante), le contenu
## change page fermée, puis elle se déplie — cf. _flip_page.
var _right_page: Control
var _flip_tween: Tween
## Application différée du nouveau passage, exécutée à la page fermée.
var _flip_apply: Callable = Callable()
## UI différée jusqu'à la fin de la machine à écrire (choix, boutons de fin) :
## les réponses n'apparaissent qu'une fois le texte entièrement révélé.
var _pending_reveal: Callable = Callable()
## Nœud où le récit s'est arrêté (repère « vous êtes ici » de la carte).
var _current_node := ""

## Palette et habillages : BookTheme (thème « grimoire » partagé, cf. icon.svg).
## Proportions du livre ouvert (largeur/hauteur des deux pages réunies),
## calées sur le format normalisé A4 (ISO 216) : chaque page fait 210×297 mm,
## soit 420/297 = √2 ≈ 1,414 pour la double page.
const BOOK_RATIO := 420.0 / 297.0
## Hauteur du bandeau d'informations en haut de l'écran.
const TOP_BAR_HEIGHT := 46.0
## Épaisseur du cadre de la planche : bord (2 px) + passe-partout (7 px).
const FRAME_PAD := 9.0
## Débord du bloc des pages (tranches empilées) autour des pages ouvertes.
const PAGE_BLOCK := 9.0
## Parallaxe « imprimé » : fraction du gain plein écran tant que l'illustration
## est dans la page — le plein écran seul retrouve le parallaxe complet.
const PAGE_PARALLAX := 0.25


func _ready() -> void:
	# Repli pour un lancement direct de story.tscn dans l'éditeur (sans hub ni
	# sélection) : résout génériquement l'histoire puis le personnage, sans nommer
	# aucun contenu. En flux normal, hub + sélection les ont déjà posés.
	if GameState.story_id.is_empty():
		GameState.story_id = GameState.first_story_id()
	_ensure_character()

	_build_ui()

	# Entrée « Recommencer cette histoire » du menu, active pendant l'histoire.
	SettingsMenu.set_restart_available(true)
	SettingsMenu.restart_requested.connect(_restart_story)

	# Résout l'histoire choisie (dossier data/stories/<id>/ + entry_file du
	# manifest), puis charge ses définitions d'illustrations et d'objets AVANT le
	# préchargement / la première commande.
	_story_path = _resolve_story_path()
	IllustrationLibrary.load_story(GameState.story_dir())
	ItemLibrary.load_story(GameState.story_dir())

	# Précharge les textures d'illustration en tâche de fond pour éviter
	# l'à-coup quand une page à parallaxe apparaît.
	IllustrationLibrary.preload_all()

	_runner = StoryRunner.new()
	# État persistant (zones cliquées, inventaire) : le moteur est découplé de
	# Progress, l'hôte lui injecte les vérificateurs.
	_runner.zone_checker = Progress.is_zone_clicked
	_runner.item_checker = Progress.has_item
	add_child(_runner)
	_runner.display_text.connect(_on_display_text)
	_runner.present_choices.connect(_on_present_choices)
	_runner.command.connect(_on_command)
	_runner.story_ended.connect(_on_story_ended)
	_runner.node_visited.connect(_on_node_visited)
	_runner.choice_selected.connect(_on_choice_selected)
	_runner.dice_rolled.connect(_on_dice_rolled)

	_start_story()


## En quittant la scène : on retire l'entrée « Recommencer » du menu global
## et on se désabonne (les autres scènes n'ont pas d'histoire en cours).
func _exit_tree() -> void:
	if SettingsMenu.restart_requested.is_connected(_restart_story):
		SettingsMenu.restart_requested.disconnect(_restart_story)
	SettingsMenu.set_restart_available(false)


## Repli quand story.tscn est lancée sans personnage (hors sélection) : prend le
## PREMIER personnage scanné de l'histoire (ordre alphabétique) plutôt que de
## tourner avec un personnage vide. Placé ici — le vrai consommateur de
## character_type — et non dans character_selection.gd, qui n'écrit cette valeur
## qu'au clic et ne la lit jamais.
func _ensure_character() -> void:
	if not GameState.character_type.is_empty():
		return
	var paths := GameState.character_paths()
	if paths.is_empty():
		return
	var data: CharacterData = load(paths[0])
	if data == null:
		return
	GameState.selected_character = data
	GameState.character_type = data.character_type
	GameState.character_attribute = data.attribute


## Résout le chemin du .untold de l'histoire courante via son manifest.json.
func _resolve_story_path() -> String:
	var dir := GameState.story_dir()
	var manifest_path := dir + "manifest.json"
	if not FileAccess.file_exists(manifest_path):
		push_error("story: manifest introuvable : " + manifest_path)
		return ""
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	var entry := str(parsed.get("entry_file", "")) if parsed is Dictionary else ""
	# Nom lisible de l'histoire : affiché dans le bandeau du haut.
	_story_title = str(parsed.get("display_name", "")) if parsed is Dictionary else ""
	if _title_label != null:
		_title_label.text = _story_title
	if entry.is_empty():
		push_error("story: entry_file manquant dans " + manifest_path)
		return ""
	return dir + entry


func _start_story() -> void:
	var source := FileAccess.get_file_as_string(_story_path)
	_story = StoryParser.parse(source)
	_meta = StoryMeta.load_for(_story_path)
	Progress.begin_story(_story_path.get_file().get_basename(), GameState.character_type)

	# Reprise auto et silencieuse : si ce personnage a un point de reprise
	# valide, on démarre directement là plutôt qu'au nœud d'entrée (les
	# variables d'identité sont posées de la même manière). Un checkpoint
	# obsolète (nœud disparu après édition) est ignoré → repart du début.
	# La trace de session (nœuds déjà visités) est réamorcée AVEC la reprise pour
	# que les gardes visited() se comportent comme dans une lecture continue ;
	# sans reprise, on repart d'un _visited vierge (pas de restauration).
	var resume := Progress.resume_node()
	if not resume.is_empty() and not _story.has_node(resume):
		resume = ""
	var visited_ids: Array = Progress.resume_visited_set() if not resume.is_empty() else []

	# Réaffiche l'illustration laissée sur la page de gauche : peu de nœuds
	# portent une @illustration, le nœud de reprise n'en a presque jamais —
	# sans ça, la page resterait vide. Posée AVANT le start : si le nœud de
	# reprise invoque sa propre @illustration, elle reprend la main.
	if not resume.is_empty():
		var last_illustration := Progress.resume_illustration()
		if not last_illustration.is_empty():
			_show_illustration(last_illustration)

	# Même logique pour la page de droite : le texte complet du passage laissé
	# (nœuds enchaînés + dialogues de zones) remplacera le rejeu tronqué du seul
	# nœud de checkpoint, au premier display_text (cf. _on_display_text).
	_resume_text = Progress.resume_passage_text() if not resume.is_empty() else ""

	# Les variables du récit sauvées au checkpoint (@set : compétences,
	# réputation...) reprennent leurs valeurs — par-dessus les défauts de
	# l'histoire, l'identité étant reposée en dernier (source de vérité).
	var initial_vars: Dictionary = Progress.resume_variables() if not resume.is_empty() else {}
	initial_vars["character"] = GameState.character_type
	initial_vars["type"] = GameState.character_attribute
	_runner.start(_story, initial_vars, resume, visited_ids)


# ------------------------------------------------------------------ UI

func _build_ui() -> void:
	add_child(BookTheme.make_desk())
	add_child(_build_top_bar())

	# Le livre ouvert : centré sous le bandeau, proportions constantes quelle
	# que soit la fenêtre — marges resserrées pour qu'il occupe l'écran.
	# Construction partagée avec la sélection de personnage (BookTheme).
	var open_book := BookTheme.make_open_book(10, TOP_BAR_HEIGHT, BOOK_RATIO, PAGE_BLOCK)
	add_child(open_book["root"])
	var pages: HBoxContainer = open_book["pages"]
	pages.add_child(_build_left_page())
	_right_page = _build_right_page()
	pages.add_child(_right_page)


## Bandeau d'informations en haut de l'écran, dans la DA de la couverture
## (cuir sombre + filet doré) : médaillon du personnage incarné, histoire en
## cours, progression, et accès Inventaire / Carte du récit (la carte ne passe
## plus par le menu Réglages).
func _build_top_bar() -> Control:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.custom_minimum_size = Vector2(0, TOP_BAR_HEIGHT)
	var style := StyleBoxFlat.new()
	style.bg_color = BookTheme.LEATHER_DARK
	style.border_width_bottom = 2
	style.border_color = Color(BookTheme.PAGE_EDGE, 0.55)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	bar.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bar.add_child(row)

	# Personnage incarné : petit médaillon + nom.
	var character: CharacterData = GameState.selected_character
	if character != null:
		row.add_child(_make_medallion(character))
		row.add_child(_make_bar_divider())

	# Histoire en cours (titre du manifest, posé par _resolve_story_path).
	_title_label = BookTheme.make_label(_story_title, 16, BookTheme.PARCHMENT, true)
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_title_label)

	row.add_child(_make_bar_divider())

	# Progression (tenue à jour par _on_node_visited).
	_progress_label = BookTheme.make_label("", 14, Color(BookTheme.PARCHMENT, 0.75))
	_progress_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_progress_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	row.add_child(_make_bar_button("Inventaire  (I)", _toggle_inventory))
	row.add_child(_make_bar_divider())
	row.add_child(_make_bar_button("Carte du récit  (M)", _toggle_map))
	row.add_child(_make_bar_divider())
	row.add_child(_make_settings_button())
	return bar


## Écrou d'ouverture des Réglages, tout à droite du bandeau : engrenage dessiné
## à la main (pas de glyphe unicode — couverture de police incertaine), halo
## parchemin au survol.
func _make_settings_button() -> Button:
	var button := Button.new()
	button.tooltip_text = "Réglages (Échap)"
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(34, 34)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(BookTheme.PARCHMENT, 0.12 if state != "normal" else 0.0)
		style.set_corner_radius_all(17)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.pressed.connect(SettingsMenu.open)

	var pict := Control.new()
	pict.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pict.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pict.draw.connect(func() -> void:
		var center: Vector2 = pict.size / 2.0
		var color := Color(BookTheme.PARCHMENT, 0.9)
		pict.draw_arc(center, 7.5, 0.0, TAU, 24, color, 2.0, true)  # couronne
		pict.draw_circle(center, 2.4, color)                        # moyeu
		for i in 8:                                                 # dents
			var dir := Vector2.RIGHT.rotated(TAU * i / 8.0)
			pict.draw_line(center + dir * 7.5, center + dir * 12.0, color, 2.6, true))
	button.add_child(pict)
	return button


## Filet vertical séparant les blocs du bandeau.
func _make_bar_divider() -> Control:
	var divider := Control.new()
	divider.custom_minimum_size = Vector2(1, 0)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divider.draw.connect(func() -> void:
		divider.draw_line(Vector2(0.5, 7), Vector2(0.5, divider.size.y - 7),
				Color(BookTheme.PAGE_EDGE, 0.4), 1.0, true))
	return divider


## Bouton du bandeau : réplique parchemin sur cuir sombre (BookTheme).
func _make_bar_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	BookTheme.style_choice(button, false, 15, true)
	button.pressed.connect(action)
	return button


## Page de gauche (verso) : planche d'illustration cadrée au ratio de son
## gabarit, bouton plein écran au coin (le titre courant et le médaillon du
## personnage vivent désormais dans le bandeau du haut).
func _build_left_page() -> Control:
	var page := PanelContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	page.add_child(BookTheme.paper(true))
	page.add_child(BookTheme.page_wear(11))
	page.add_child(BookTheme.make_page_frame())

	var inner := MarginContainer.new()
	inner.add_theme_constant_override("margin_left", 38)
	inner.add_theme_constant_override("margin_right", 30)  # côté reliure
	inner.add_theme_constant_override("margin_top", 30)
	inner.add_theme_constant_override("margin_bottom", 26)
	page.add_child(inner)

	# Canevas en superposition : la planche dispose de toute la page.
	var canvas := Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(canvas)

	# La planche, cadrée au ratio du gabarit courant (cf. _show_illustration),
	# CENTRÉE verticalement dans la page.
	_plate_holder = Control.new()
	_plate_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_plate_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate_holder.visible = false
	canvas.add_child(_plate_holder)

	_plate = PanelContainer.new()
	var plate_style := StyleBoxFlat.new()
	plate_style.bg_color = Color(0, 0, 0, 0.07)
	plate_style.set_border_width_all(2)
	plate_style.border_color = BookTheme.PAGE_EDGE
	plate_style.set_corner_radius_all(3)
	plate_style.set_content_margin_all(7)  # passe-partout autour de l'image
	_plate.add_theme_stylebox_override("panel", plate_style)
	_plate_holder.add_child(_plate)
	# Cadrage MANUEL de la planche à chaque nouvelle taille de l'espace : un
	# enfant posé à la main ne renvoie aucune contrainte au layout, donc pas de
	# rétroaction possible (cf. _layout_plate — l'AspectRatioContainer utilisé
	# avant GELAIT le jeu, en oscillation avec la répartition des deux pages).
	_plate_holder.resized.connect(_layout_plate)

	# Bouton plein écran, au coin haut-droit de la planche (au-dessus de
	# l'illustration ; le reste de la surcouche laisse passer la souris —
	# les zones interactives de l'image restent cliquables).
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(overlay)
	overlay.add_child(_make_expand_button())
	return page


## Page de droite (recto) : titre de scène, fleuron, texte du récit et choix.
func _build_right_page() -> Control:
	var page := PanelContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	page.add_child(BookTheme.paper(false))
	page.add_child(BookTheme.page_wear(23))
	page.add_child(BookTheme.make_page_frame())
	# Clic n'importe où sur la feuille = affichage instantané du texte (les
	# couches décoratives ignorent la souris, les boutons de choix la stoppent).
	page.gui_input.connect(_on_text_input)

	var inner := MarginContainer.new()
	inner.add_theme_constant_override("margin_left", 32)  # côté reliure
	inner.add_theme_constant_override("margin_right", 42)
	inner.add_theme_constant_override("margin_top", 30)
	inner.add_theme_constant_override("margin_bottom", 20)
	page.add_child(inner)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	inner.add_child(col)

	_header = BookTheme.make_label("", 15, BookTheme.INK_MUTED, true)
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.clip_text = true
	col.add_child(_header)

	col.add_child(BookTheme.make_fleuron())

	# Le texte prend sa hauteur naturelle : les choix viennent JUSTE dessous
	# (le remplissage plus bas pousse le pied de page au bas de la page).
	_text_label = RichTextLabel.new()
	_text_label.bbcode_enabled = true
	_text_label.fit_content = true
	_text_label.add_theme_font_override("normal_font", BookTheme.serif())
	_text_label.add_theme_font_override("italics_font", BookTheme.serif(true))
	_text_label.add_theme_font_override("bold_font", BookTheme.serif(false, true))
	_text_label.add_theme_font_override("bold_italics_font", BookTheme.serif(true, true))
	_text_label.add_theme_font_size_override("normal_font_size", 19)
	_text_label.add_theme_color_override("default_color", BookTheme.INK)
	_text_label.add_theme_constant_override("line_separation", 6)
	# Clic sur le texte = affichage instantané (cf. _on_text_input).
	_text_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_text_label.gui_input.connect(_on_text_input)
	# Effets BBCode custom (les natifs wave/shake/fade/color restent gérés seuls).
	_fx_shock = preload("res://core/text_effects/shock.gd").new()
	_text_label.install_effect(_fx_shock)
	_text_label.install_effect(preload("res://core/text_effects/danger.gd").new())
	_text_label.install_effect(preload("res://core/text_effects/silence.gd").new())
	col.add_child(_text_label)

	_choices_box = VBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", 6)
	col.add_child(_choices_box)

	# Remplissage : absorbe l'espace restant sous le texte et les choix
	# (la progression vit désormais dans le bandeau du haut).
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(filler)
	return page


## Tourne la page de droite : elle se replie vers la reliure (ease-in) en
## s'assombrissant — le bloc de tranches dessous figure la page suivante —,
## le contenu est remplacé page fermée, puis elle se déplie (ease-out) pendant
## que la frappe du nouveau passage démarre.
func _flip_page(apply: Callable) -> void:
	# Bascule déjà en cours : on la termine (contenu en attente appliqué) et
	# la nouvelle repart du repli courant.
	if _flip_tween != null and _flip_tween.is_running():
		_flip_tween.kill()
		_finish_flip()
	_flip_apply = apply
	_right_page.pivot_offset = Vector2(0.0, _right_page.size.y / 2.0)
	_flip_tween = create_tween()
	_flip_tween.tween_property(_right_page, "scale:x", 0.02, 0.26) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_flip_tween.parallel().tween_property(_right_page, "modulate",
			Color(0.76, 0.70, 0.62), 0.26)
	_flip_tween.tween_callback(_finish_flip)
	_flip_tween.tween_property(_right_page, "scale:x", 1.0, 0.32) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_flip_tween.parallel().tween_property(_right_page, "modulate",
			Color.WHITE, 0.32)


## Applique le passage mis en attente par une bascule (à la page fermée).
func _finish_flip() -> void:
	if not _flip_apply.is_valid():
		return
	var apply := _flip_apply
	_flip_apply = Callable()
	apply.call()


## Bouton « plein écran » : pastille sombre aux coins dessinés (pas de glyphe
## unicode — couverture de police incertaine), À CHEVAL sur le coin haut-droit
## du cadre de la planche (il déborde de l'illustration au lieu de la couvrir).
func _make_expand_button() -> Button:
	var button := Button.new()
	button.tooltip_text = "Voir l'illustration en plein écran"
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(32, 32)
	# Centré sur le coin EXTÉRIEUR du cadre : la surcouche couvre la zone
	# intérieure (sous le passe-partout), le coin du cadre est à (+9, -9).
	button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	button.offset_left = FRAME_PAD - 16
	button.offset_top = -FRAME_PAD - 16
	button.offset_right = FRAME_PAD + 16
	button.offset_bottom = -FRAME_PAD + 16
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.1, 0.08, 0.05, 0.75 if state == "hover" else 0.5)
		style.set_corner_radius_all(16)
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(_open_fullscreen)

	# Quatre équerres de coin (pictogramme « agrandir ») dessinées à la main.
	var pict := Control.new()
	pict.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pict.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pict.draw.connect(func() -> void:
		var c := Color("efe3c4")
		var s: Vector2 = pict.size
		const M := 9.0   # marge au bord de la pastille
		const L := 6.0   # longueur des équerres
		for corner in [Vector2(M, M), Vector2(s.x - M, M), Vector2(M, s.y - M),
				Vector2(s.x - M, s.y - M)]:
			var dx: float = L if corner.x < s.x / 2.0 else -L
			var dy: float = L if corner.y < s.y / 2.0 else -L
			pict.draw_line(corner, corner + Vector2(dx, 0), c, 1.6, true)
			pict.draw_line(corner, corner + Vector2(0, dy), c, 1.6, true))
	button.add_child(pict)
	return button


## Médaillon du personnage incarné, dans le bandeau du haut (portrait bordé de
## la couleur du personnage + nom éclairci pour rester lisible sur le cuir).
func _make_medallion(character: CharacterData) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var medallion := PanelContainer.new()
	medallion.custom_minimum_size = Vector2(32, 32)
	medallion.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	medallion.clip_contents = true
	var style := StyleBoxFlat.new()
	style.bg_color = Color(BookTheme.SPINE, 0.25)
	style.set_border_width_all(2)
	style.border_color = character.color
	style.set_corner_radius_all(8)
	medallion.add_theme_stylebox_override("panel", style)
	var portrait := TextureRect.new()
	portrait.texture = character.icon if character.icon != null else character.bust
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	medallion.add_child(portrait)
	row.add_child(medallion)

	var name_label := BookTheme.make_label(character.display_name, 16,
			character.color.lerp(BookTheme.PARCHMENT, 0.45), false, true)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)
	return row


func _clear_choices() -> void:
	# Retrait IMMÉDIAT de l'arbre (pas seulement queue_free) : au clic d'une
	# zone, les choix sont effacés et reconstruits dans la même trame, et un
	# conteneur mêlant enfants mourants et nouveaux gèle la disposition.
	for child in _choices_box.get_children():
		_choices_box.remove_child(child)
		child.queue_free()


# ------------------------------------------------------------- Signaux runner

func _on_display_text(text: String, node_id: String, tags: Array) -> void:
	# Reprise : le runner ne rejoue que le nœud de checkpoint, or le passage
	# affiché avait pu accumuler le texte de nœuds enchaînés en amont et des
	# dialogues de zones. On restaure le passage COMPLET tel que laissé
	# (une seule fois : les affichages suivants reprennent le cours normal).
	if not _resume_text.is_empty():
		text = _resume_text
		_resume_text = ""
	# Trace de reprise du passage (cf. ci-dessus) — après la restauration,
	# pour ne pas écraser le texte complet par la version tronquée du rejeu.
	Progress.record_passage_text(text)

	_pending_reveal = Callable()  # purge une révélation d'un passage précédent
	# Nouveau passage : la page se tourne, et le contenu change page fermée.
	# Le tout premier passage et les ré-affichages du même nœud (reprise,
	# ajout de dialogue) s'installent sans animation.
	var flip := node_id != _current_node and not _current_node.is_empty()
	_current_node = node_id
	if flip:
		_flip_page(_apply_display_text.bind(text, node_id, tags))
	else:
		_apply_display_text(text, node_id, tags)


## Installe le passage dans la page de droite (en-tête, texte, machine à
## écrire) — immédiatement, ou à la page fermée pendant une bascule.
func _apply_display_text(text: String, node_id: String, tags: Array) -> void:
	_clear_choices()
	_header.text = _build_header(node_id, tags)

	# Extrait les pauses dramatiques [Soupir:X] : le texte affiché n'en contient
	# plus, et chaque pause connaît son rang en caractères VISIBLES.
	_display_raw = text
	var prepared := _prepare_dramatic_text(_display_raw)
	_text_label.text = BookTheme.with_drop_cap(prepared["text"])
	# La secousse « shock » repart depuis l'apparition de ce texte.
	if _fx_shock != null and _fx_shock.has_method("restart"):
		_fx_shock.restart()

	# Compte des caractères VISIBLES réels (hors balises BBCode), APRÈS
	# assignation du texte — sinon les balises gonfleraient la durée perçue.
	var total := _text_label.get_total_character_count()

	if _typewriter and _typewriter.is_running():
		_typewriter.kill()
	_typewriter = null
	if total <= 0:
		_text_label.visible_ratio = 1.0
		_on_typewriter_done()  # pas de frappe : révèle l'UI différée éventuelle
		return
	_typewriter = _build_typewriter(total, prepared["pauses"], 0)


## Construit la séquence « machine à écrire » : révèle le texte de start_visible
## caractères jusqu'à la fin, à vitesse Settings.text_speed, en marquant une
## pause de X s à chaque balise [Soupir:X] au-delà du point de départ. Un départ
## > 0 sert à ne dévoiler QUE des lignes ajoutées (cf. _append_dialogue).
func _build_typewriter(total: int, pauses: Array, start_visible: int) -> Tween:
	var remaining := total - start_visible
	if remaining <= 0:
		_text_label.visible_ratio = 1.0
		return null
	_text_label.visible_ratio = float(start_visible) / float(total)
	var full := clampf(remaining * Settings.text_speed, 0.3, 6.0)  # temps de frappe (hors pauses)
	var tween := create_tween()
	var cursor := start_visible
	for p in pauses:
		var v: int = p["visible"]
		if v <= start_visible:
			continue  # pause déjà dépassée avant le point de départ
		if v > cursor:
			tween.tween_property(_text_label, "visible_ratio",
				float(v) / float(total), full * float(v - cursor) / float(remaining))
			cursor = v
		if p["duration"] > 0.0:
			tween.tween_interval(p["duration"])
	if cursor < total:
		tween.tween_property(_text_label, "visible_ratio",
			1.0, full * float(total - cursor) / float(remaining))
	# Fin de frappe naturelle : révèle l'UI en attente (choix, boutons de fin).
	tween.finished.connect(_on_typewriter_done)
	return tween


## Le texte est entièrement révélé (fin de frappe ou clic pour tout afficher) :
## fait apparaître l'UI différée, en fondu.
func _on_typewriter_done() -> void:
	if not _pending_reveal.is_valid():
		return
	var reveal := _pending_reveal
	_pending_reveal = Callable()
	reveal.call()
	_choices_box.modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.tween_property(_choices_box, "modulate:a", 1.0, 0.4) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Retire les balises de pause [Soupir:X] du texte et renvoie :
##   "text"   : le texte à afficher (balises de pause ôtées, BBCode conservé) ;
##   "pauses" : Array de { "visible": int, "duration": float } — nombre de
##              caractères visibles précédant la pause, et sa durée en secondes.
## La position est convertie en caractères VISIBLES (hors BBCode) via un
## RichTextLabel de mesure, cohérent avec get_total_character_count().
static func _prepare_dramatic_text(raw: String) -> Dictionary:
	var re := RegEx.create_from_string("\\[Soupir:\\s*([0-9]*\\.?[0-9]+)[^\\]]*\\]")
	var clean := ""
	var marks: Array = []  # { "pos": index dans clean, "duration": float }
	var last := 0
	for m in re.search_all(raw):
		clean += raw.substr(last, m.get_start() - last)
		marks.append({"pos": clean.length(), "duration": float(m.get_string(1))})
		last = m.get_end()
	clean += raw.substr(last)

	var pauses: Array = []
	if not marks.is_empty():
		var scratch := RichTextLabel.new()
		scratch.bbcode_enabled = true
		for mark in marks:
			scratch.text = clean.substr(0, mark["pos"])
			pauses.append({
				"visible": scratch.get_total_character_count(),
				"duration": mark["duration"],
			})
		scratch.free()
	return {"text": clean, "pauses": pauses}


## Clic sur la page de droite (texte compris) : si la frappe est en cours, tout
## afficher d'un coup
## (on tue la séquence et on révèle le texte entier). Sinon, ne rien faire ici.
func _on_text_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if _typewriter != null and _typewriter.is_running():
			_typewriter.kill()
			_typewriter = null
			_text_label.visible_ratio = 1.0
			_on_typewriter_done()


# ------------------------------------------------- Zones interactives (clic)

## Clic sur une zone interactive d'une illustration. Rejoué à CHAQUE clic (aucune
## protection anti-répétition, décision actée).
func _on_illustration_interaction(interaction: IllustrationInteraction) -> void:
	# Toujours enregistré, même sans effet dialogue/objet (alimente zone_clicked).
	Progress.record_zone_click(interaction.id)

	if not interaction.dialogue_lines.is_empty():
		_append_dialogue(interaction.dialogue_lines)

	if not interaction.item_id.is_empty():
		# L'objet donné par la zone entre réellement dans l'inventaire (Progress,
		# section partie_en_cours). Une garde has_item pourra alors passer.
		Progress.add_item(interaction.item_id, interaction.item_qty)

	# Un clic de zone a pu débloquer une nouvelle sortie (garde zone_clicked) :
	# on ré-évalue les choix du nœud courant sans rejouer le nœud.
	_runner.refresh_choices()


## Ajoute des lignes à la SUITE du texte courant (sans rejouer le nœud), avec
## leur propre effet machine à écrire : le texte déjà affiché reste entier,
## seules les lignes ajoutées défilent.
func _append_dialogue(lines: Array) -> void:
	# Fige le texte déjà présent, en entier, avant d'ajouter la suite.
	if _typewriter and _typewriter.is_running():
		_typewriter.kill()
	_typewriter = null
	_text_label.visible_ratio = 1.0
	var shown := _text_label.get_total_character_count()

	_display_raw += "\n" + "\n".join(PackedStringArray(lines))
	# Le dialogue ajouté fait partie du passage : la reprise doit le retrouver.
	Progress.record_passage_text(_display_raw)
	var prepared := _prepare_dramatic_text(_display_raw)
	_text_label.text = BookTheme.with_drop_cap(prepared["text"])
	var total := _text_label.get_total_character_count()
	if total <= shown:
		_text_label.visible_ratio = 1.0
		return
	_typewriter = _build_typewriter(total, prepared["pauses"], shown)


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


## Jet de compétence résolu par le moteur : l'animation du dé se joue
## au-dessus du livre (autonome, se détruit toute seule) pendant que le
## passage de la branche prise s'affiche.
func _on_dice_rolled(skill: String, die: int, bonus: int, total: int,
		difficulty: int, success: bool) -> void:
	var overlay := DiceRollOverlay.new()
	add_child(overlay)
	overlay.play(skill, die, bonus, total, difficulty, success)


func _on_present_choices(choices: Array) -> void:
	_clear_choices()
	# Point de reprise : le joueur s'arrête ici (un point de choix lui est
	# présenté). Les nœuds intermédiaires enchaînés ne sont jamais un checkpoint.
	# Enregistré TOUT DE SUITE — seul l'affichage des réponses attend le texte.
	if not choices.is_empty():
		# Les variables du récit accompagnent le point de reprise : les compteurs
		# @set (compétences, réputation) survivent à la fermeture du jeu.
		Progress.record_checkpoint(choices[0]["node"], _runner.variables)
	# Les réponses n'apparaissent qu'une fois le texte entièrement révélé.
	_pending_reveal = _build_choice_buttons.bind(choices)
	# Pendant une bascule de page, la frappe du nouveau passage n'a pas encore
	# commencé : la révélation attendra sa fin (déclenchée après l'application).
	if _flip_apply.is_valid():
		return
	if _typewriter == null or not _typewriter.is_running():
		_on_typewriter_done()


## Trait de séparation entre le texte et les choix : centré, à l'encre de la
## lettrine (rouge rubriqué, cf. BookTheme.with_drop_cap). Ajouté en tête de la boîte
## des choix, il apparaît et disparaît avec eux.
func _make_choice_separator() -> Control:
	var separator := Control.new()
	separator.custom_minimum_size = Vector2(0, 14)
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	separator.draw.connect(func() -> void:
		var center: Vector2 = separator.size / 2.0
		const HALF := 70.0
		separator.draw_line(center + Vector2(-HALF, 0), center + Vector2(HALF, 0),
				Color(BookTheme.RIBBON, 0.75), 1.4, true))
	return separator


func _build_choice_buttons(choices: Array) -> void:
	_choices_box.add_child(_make_choice_separator())
	for i in choices.size():
		var choice: Dictionary = choices[i]
		var button := Button.new()
		# Réponse déjà choisie (par n'importe quel personnage) : cochée et à
		# l'encre passée, pour que les réponses encore inexplorées ressortent.
		var choosers: Array = Progress.choice_choosers(choice["node"], choice["text"])
		if choosers.is_empty():
			button.text = "•  " + choice["text"]
		else:
			button.text = "✓  " + choice["text"]
			button.tooltip_text = "Déjà choisie avec : " + ", ".join(PackedStringArray(choosers))
		_style_choice(button, not choosers.is_empty())
		button.pressed.connect(_runner.choose.bind(i))
		_choices_box.add_child(button)


## Habillage des choix : réplique à l'encre (BookTheme), CENTRÉE sous le texte.
func _style_choice(button: Button, read: bool) -> void:
	BookTheme.style_choice(button, read)
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER


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
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_M:
			_toggle_map()
		elif event.keycode == KEY_I:
			_toggle_inventory()


## Ouvre/ferme l'inventaire (overlay modal), reconstruit à chaque ouverture pour
## refléter les objets actuellement possédés.
func _toggle_inventory() -> void:
	if _inventory_overlay != null:
		_inventory_overlay.queue_free()
		_inventory_overlay = null
		return
	_inventory_overlay = InventoryOverlay.new()
	add_child(_inventory_overlay)
	_inventory_overlay.setup()
	_inventory_overlay.close_requested.connect(_toggle_inventory)


## Ouvre/ferme la carte, reconstruite à chaque ouverture pour refléter la
## progression courante.
func _toggle_map() -> void:
	if _map != null:
		_map.queue_free()
		_map = null
		return
	_map = StoryMap.new()
	add_child(_map)
	_map.setup(_story, _story_path, _current_node)
	_map.close_requested.connect(_toggle_map)


func _on_command(name: String, args: Array) -> void:
	match name:
		"illustration":
			if args.size() > 0:
				_show_illustration(args[0])
		"add_into_inventory":
			if args.size() > 0:
				Progress.add_item(str(args[0]), _arg_qty(args, 1))
		"remove_object_from_inventory", "use_object_from_inventory":
			# Identiques côté moteur : la distinction est purement pour la
			# lisibilité de l'auteur du .untold (retirer vs consommer un objet).
			if args.size() > 0:
				Progress.remove_item(str(args[0]), _arg_qty(args, 1))
		_:
			# Autres commandes à venir (mini-jeux, etc.).
			print("[command] %s(%s)" % [name, ", ".join(PackedStringArray(args))])


## Quantité d'une commande d'inventaire : args[index] (String brute) converti en
## int, défaut 1 si absent. Les objets uniques sont invoqués sans quantité.
func _arg_qty(args: Array, index: int) -> int:
	if args.size() > index and not str(args[index]).strip_edges().is_empty():
		return int(str(args[index]))
	return 1


## Installe l'illustration dans la planche de la page de gauche, cadrée au
## ratio de son gabarit, avec un parallaxe réduit (image « imprimée »).
func _show_illustration(illustration_name: String) -> void:
	if _illustration != null:
		_illustration.queue_free()
		_illustration = null
	_close_fullscreen()

	var data := IllustrationLibrary.get_illustration(illustration_name)
	if data == null:
		push_warning("Illustration inconnue : " + illustration_name)
		return

	# Trace de reprise : l'illustration persiste sur la page de gauche bien
	# au-delà de son nœud, la reprise doit donc la retrouver (cf. _start_story).
	Progress.record_illustration(illustration_name)

	_illustration_data = data
	_illustration = Illustration.new()
	_illustration.interaction_clicked.connect(_on_illustration_interaction)
	_plate.add_child(_illustration)
	# Sous la surcouche du bouton plein écran (dernier enfant de la planche).
	_plate.move_child(_illustration, 0)
	_illustration.setup(data)
	_illustration.parallax_gain = Settings.parallax_gain_default * PAGE_PARALLAX
	# Le cadre épouse l'image : ratio réel de sa texture, puis affiné pour
	# compenser l'épaisseur du cadre (cf. _layout_plate).
	_image_ratio = _illustration_ratio(data)
	_plate_holder.visible = true
	_layout_plate()


## Ratio (largeur/hauteur) RÉEL de l'illustration : celui de la texture de son
## premier calque — le cadre colle à l'image au pixel près, là où un ratio
## approché par gabarit laissait des bandes vides dans la planche.
func _illustration_ratio(data: IllustrationData) -> float:
	for layer in data.layers:
		if layer.sprite != null:
			var tex_size: Vector2 = layer.sprite.get_size()
			if tex_size.y > 0.0:
				return tex_size.x / tex_size.y
	return _template_ratio(data.template)


## Repli quand l'illustration n'a aucune texture : ratio approché par gabarit.
func _template_ratio(template: int) -> float:
	match template:
		IllustrationData.Template.PORTRAIT:
			return 0.75
		IllustrationData.Template.CHARACTER:
			return 1.0
		_:
			return 1.65


## Cadre la planche dans son espace : aspect-fit au ratio de l'image, CENTRÉ,
## en compensant l'épaisseur fixe du cadre (FRAME_PAD de chaque côté) pour que
## la zone INTÉRIEURE ait exactement le ratio de l'image. Le cadrage est
## MANUEL (position et taille posées directement) : la planche ne pèse pas
## dans le calcul de layout, donc ne peut pas rétroagir sur la taille des
## pages — l'AspectRatioContainer utilisé avant avait un minimum dépendant du
## ratio, et gelait le jeu en oscillant avec la répartition des deux pages
## (boucle infinie de tri, constatée au clic d'une zone d'illustration).
func _layout_plate() -> void:
	var pad := FRAME_PAD * 2.0
	var box := _plate_holder.size
	if _image_ratio <= 0.0 or box.x <= pad or box.y <= pad:
		return
	var plate_size := Vector2(pad + _image_ratio * (box.y - pad), box.y)
	if plate_size.x > box.x:  # trop large pour l'espace : la largeur gouverne
		plate_size = Vector2(box.x, pad + (box.x - pad) / _image_ratio)
	_plate.position = (box - plate_size) * 0.5
	_plate.size = plate_size


# ------------------------------------------------- Illustration plein écran

## Surimpression plein écran de l'illustration courante : parallaxe COMPLET
## (contrairement à la planche), zones interactives toujours actives.
func _open_fullscreen() -> void:
	if _fullscreen != null or _illustration_data == null:
		return
	_fullscreen = Control.new()
	_fullscreen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fullscreen)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.05, 0.035, 0.02, 0.985)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fullscreen.add_child(backdrop)

	var big := Illustration.new()
	big.interaction_clicked.connect(_on_illustration_interaction)
	big.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fullscreen.add_child(big)
	big.setup(_illustration_data)  # gain laissé au défaut → parallaxe complet

	# Pastille sombre : reste lisible quelle que soit la clarté de l'image.
	var close := Button.new()
	close.text = "✕  Fermer"
	close.focus_mode = Control.FOCUS_NONE
	close.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	close.position = Vector2(-150, 16)
	close.add_theme_color_override("font_color", Color("efe3c4"))
	close.add_theme_color_override("font_hover_color", Color("f3e9cd"))
	close.add_theme_color_override("font_pressed_color", Color("f3e9cd"))
	for state in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.1, 0.08, 0.05, 0.85 if state == "hover" else 0.65)
		style.set_corner_radius_all(15)
		style.content_margin_left = 14
		style.content_margin_right = 14
		style.content_margin_top = 5
		style.content_margin_bottom = 5
		close.add_theme_stylebox_override(state, style)
	close.pressed.connect(_close_fullscreen)
	_fullscreen.add_child(close)


func _close_fullscreen() -> void:
	if _fullscreen != null:
		_fullscreen.queue_free()
		_fullscreen = null


func _on_story_ended() -> void:
	_clear_choices()

	# Fin atteinte : plus de reprise pour ce personnage — la prochaine sélection
	# repartira du début (reprendre une fin n'a pas de sens).
	Progress.clear_checkpoint()

	# Comme les choix : les boutons de fin attendent la fin du texte (et la
	# fin d'une éventuelle bascule de page, cf. _on_present_choices).
	_pending_reveal = _build_end_buttons
	if _flip_apply.is_valid():
		return
	if _typewriter == null or not _typewriter.is_running():
		_on_typewriter_done()


func _build_end_buttons() -> void:
	_choices_box.add_child(_make_choice_separator())
	var restart := Button.new()
	restart.text = "↻  Recommencer"
	_style_choice(restart, false)
	restart.pressed.connect(_start_story)
	_choices_box.add_child(restart)

	var back := Button.new()
	back.text = "↩  Choisir un autre personnage"
	_style_choice(back, false)
	back.pressed.connect(_go_to_selection)
	_choices_box.add_child(back)


func _go_to_selection() -> void:
	get_tree().change_scene_to_file(SELECTION_SCENE)


## Recommence l'histoire pour le personnage courant, depuis le menu Réglages :
## efface sa partie en cours (zones + reprise, PAS la découverte cumulative)
## puis recharge la scène. Le rechargement remet à zéro TOUT l'état d'affichage
## (illustration, texte, carte) et, la reprise effacée, _start_story repart de
## start_node — plus propre qu'un go_to() qui laisserait variables et décor en
## place.
func _restart_story() -> void:
	Progress.restart_playthrough(_story_path.get_file().get_basename(), GameState.character_type)
	get_tree().reload_current_scene()
