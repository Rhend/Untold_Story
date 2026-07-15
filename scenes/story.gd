extends Control
## Vue d'histoire : charge l'histoire, la fait tourner via le StoryRunner et
## la présente comme un GRIMOIRE OUVERT (ambiance de icon.svg) — page de
## gauche : illustration « imprimée » dans une planche encadrée (+ médaillon du
## personnage) ; page de droite : titre de scène, texte (machine à écrire,
## police à empattements) et choix. Une icône au coin de la planche ouvre
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
var _plate_holder: AspectRatioContainer  # cadre la planche au ratio du gabarit
var _plate: PanelContainer               # la planche (bordure + illustration)
var _fullscreen: Control                 # surimpression plein écran (ou null)
## Titre courant de la page verso (nom de l'histoire, lu dans le manifest).
var _verso_title: Label
var _story_title := ""
## Balayage d'ombre « tournage de page » sur la page de droite.
var _sweep: Control
var _sweep_band: Texture2D
var _sweep_pos := 2.0  # fraction de la largeur ; > 1.6 = invisible
var _sweep_tween: Tween
## Nœud où le récit s'est arrêté (repère « vous êtes ici » de la carte).
var _current_node := ""

## Palette et habillages : BookTheme (thème « grimoire » partagé, cf. icon.svg).
## Proportions du livre ouvert (largeur/hauteur des deux pages réunies).
const BOOK_RATIO := 1.58
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

	# La carte du récit s'ouvre par la touche M ou depuis le menu Échap : on
	# active l'entrée « Carte du récit » du menu tant que cette scène est active.
	SettingsMenu.set_map_available(true)
	SettingsMenu.map_requested.connect(_toggle_map)

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
	add_child(_runner)
	_runner.display_text.connect(_on_display_text)
	_runner.present_choices.connect(_on_present_choices)
	_runner.command.connect(_on_command)
	_runner.story_ended.connect(_on_story_ended)
	_runner.node_visited.connect(_on_node_visited)
	_runner.choice_selected.connect(_on_choice_selected)

	_start_story()


## En quittant la scène : on retire l'entrée « Carte du récit » du menu global
## et on se désabonne (les autres scènes n'ont pas de carte).
func _exit_tree() -> void:
	if SettingsMenu.map_requested.is_connected(_toggle_map):
		SettingsMenu.map_requested.disconnect(_toggle_map)
	SettingsMenu.set_map_available(false)
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
	# Nom lisible de l'histoire : titre courant de la page verso.
	_story_title = str(parsed.get("display_name", "")) if parsed is Dictionary else ""
	if _verso_title != null:
		_verso_title.text = _story_title
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
	_runner.start(_story, {
		"character": GameState.character_type,
		"type": GameState.character_attribute,
	}, resume, visited_ids)


# ------------------------------------------------------------------ UI

func _build_ui() -> void:
	add_child(BookTheme.make_desk())

	# Le livre ouvert : centré, proportions constantes quelle que soit la fenêtre.
	var frame := MarginContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		frame.add_theme_constant_override(side, 30)
	add_child(frame)

	var ratio_box := AspectRatioContainer.new()
	ratio_box.ratio = BOOK_RATIO
	frame.add_child(ratio_box)

	var book := PanelContainer.new()
	book.add_theme_stylebox_override("panel", BookTheme.leather_style())
	ratio_box.add_child(book)

	var pages := HBoxContainer.new()
	pages.add_theme_constant_override("separation", 0)
	book.add_child(pages)
	pages.add_child(_build_left_page())
	pages.add_child(_build_right_page())

	# Ombre de la reliure centrale, par-dessus les deux pages.
	var spine := TextureRect.new()
	spine.texture = BookTheme.gradient_tex(
			[Color(BookTheme.SPINE, 0.0), Color(BookTheme.SPINE, 0.42),
			Color(BookTheme.SPINE, 0.42), Color(BookTheme.SPINE, 0.0)],
			[0.455, 0.494, 0.506, 0.545])
	spine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	book.add_child(spine)


## Page de gauche (verso) : titre courant de l'histoire, planche d'illustration
## (cadrée au ratio de son gabarit, bouton plein écran au coin) + médaillon du
## personnage incarné en bas.
func _build_left_page() -> Control:
	var page := PanelContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	page.add_child(BookTheme.paper(true))
	page.add_child(BookTheme.page_wear(11))

	var inner := MarginContainer.new()
	inner.add_theme_constant_override("margin_left", 38)
	inner.add_theme_constant_override("margin_right", 30)  # côté reliure
	inner.add_theme_constant_override("margin_top", 30)
	inner.add_theme_constant_override("margin_bottom", 26)
	page.add_child(inner)

	# Canevas en superposition : titre courant en tête, planche au-dessous,
	# médaillon ANCRÉ en bas de page même quand la planche est absente.
	var canvas := Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(canvas)

	# Titre courant (nom de l'histoire), comme le verso d'un vrai livre.
	_verso_title = BookTheme.make_label("", 15, BookTheme.INK_MUTED, true)
	_verso_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_verso_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	canvas.add_child(_verso_title)

	# La planche, cadrée au ratio du gabarit courant (cf. _show_illustration).
	_plate_holder = AspectRatioContainer.new()
	_plate_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_plate_holder.offset_top = 36    # sous le titre courant
	_plate_holder.offset_bottom = -66  # réserve la bande du médaillon
	# Planche alignée en haut de page (au niveau du texte de la page de droite).
	_plate_holder.alignment_vertical = AspectRatioContainer.ALIGNMENT_BEGIN
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

	# Bouton plein écran, au coin haut-droit de la planche (au-dessus de
	# l'illustration ; le reste de la surcouche laisse passer la souris —
	# les zones interactives de l'image restent cliquables).
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(overlay)
	overlay.add_child(_make_expand_button())

	var character: CharacterData = GameState.selected_character
	if character != null:
		var medallion := _make_medallion(character)
		medallion.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		medallion.grow_vertical = Control.GROW_DIRECTION_BEGIN
		canvas.add_child(medallion)
	return page


## Page de droite (recto) : titre de scène, fleuron, texte du récit, choix,
## pied de page — et balayage d'ombre au tournage de page.
func _build_right_page() -> Control:
	var page := PanelContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	page.add_child(BookTheme.paper(false))
	page.add_child(BookTheme.page_wear(23))

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

	_text_label = RichTextLabel.new()
	_text_label.bbcode_enabled = true
	_text_label.fit_content = true
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	_choices_box.add_theme_constant_override("separation", 4)
	col.add_child(_choices_box)

	# Pied de page : la progression tient lieu de numéro de page.
	var footer := HBoxContainer.new()
	col.add_child(footer)
	var footer_spacer := Control.new()
	footer_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(footer_spacer)
	_progress_label = BookTheme.make_label("", 13, BookTheme.INK_FADED, true)
	footer.add_child(_progress_label)

	# Surcouche du balayage d'ombre (cf. _play_page_sweep).
	_sweep_band = BookTheme.gradient_tex(
			[Color(BookTheme.SPINE, 0.0), Color(BookTheme.SPINE, 0.30),
			Color(BookTheme.SPINE, 0.0)], [0.0, 0.5, 1.0])
	_sweep = Control.new()
	_sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sweep.draw.connect(_draw_sweep)
	page.add_child(_sweep)
	return page


## Ombre verticale qui traverse la page de droite au changement de nœud —
## l'évocation d'une page qu'on tourne, sans animation de papier.
func _draw_sweep() -> void:
	if _sweep_pos > 1.6:
		return
	var band_width := _sweep.size.x * 0.34
	var x := _sweep.size.x * _sweep_pos - band_width / 2.0
	_sweep.draw_texture_rect(_sweep_band, Rect2(x, 0, band_width, _sweep.size.y), false)


func _play_page_sweep() -> void:
	if _sweep_tween != null and _sweep_tween.is_running():
		_sweep_tween.kill()
	_sweep_tween = create_tween()
	_sweep_tween.tween_method(func(value: float) -> void:
		_sweep_pos = value
		_sweep.queue_redraw(), -0.4, 1.6, 0.55) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Bouton « plein écran » : pastille sombre aux coins dessinés (pas de glyphe
## unicode — couverture de police incertaine), coin haut-droit de la planche.
func _make_expand_button() -> Button:
	var button := Button.new()
	button.tooltip_text = "Voir l'illustration en plein écran"
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(32, 32)
	button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	button.offset_left = -40
	button.offset_top = 8
	button.offset_right = -8
	button.offset_bottom = 40
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


## Médaillon du personnage incarné, en bas de la page de gauche.
func _make_medallion(character: CharacterData) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var medallion := PanelContainer.new()
	medallion.custom_minimum_size = Vector2(52, 52)
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
			character.color.lerp(BookTheme.INK, 0.5), false, true)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)
	return row


func _clear_choices() -> void:
	for child in _choices_box.get_children():
		child.queue_free()


# ------------------------------------------------------------- Signaux runner

func _on_display_text(text: String, node_id: String, tags: Array) -> void:
	_clear_choices()
	# Nouveau passage : l'ombre du tournage de page balaie la page de droite.
	if node_id != _current_node:
		_play_page_sweep()
	_current_node = node_id

	_header.text = _build_header(node_id, tags)

	# Extrait les pauses dramatiques [Soupir:X] : le texte affiché n'en contient
	# plus, et chaque pause connaît son rang en caractères VISIBLES.
	_display_raw = text
	var prepared := _prepare_dramatic_text(_display_raw)
	_text_label.text = _with_drop_cap(prepared["text"])
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
	return tween


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


## Lettrine : la première lettre du passage est grossie à l'encre du ruban,
## comme en tête de chapitre. Pas de lettrine si le passage s'ouvre sur une
## balise BBCode ou un signe (« — », guillemet…) : on laisse tel quel.
## Les balises ajoutées ne comptent pas comme caractères visibles — la machine
## à écrire et les pauses [Soupir] restent calées.
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


## Clic sur la zone de texte : si la frappe est en cours, tout afficher d'un coup
## (on tue la séquence et on révèle le texte entier). Sinon, ne rien faire ici.
func _on_text_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if _typewriter != null and _typewriter.is_running():
			_typewriter.kill()
			_typewriter = null
			_text_label.visible_ratio = 1.0


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
	var prepared := _prepare_dramatic_text(_display_raw)
	_text_label.text = _with_drop_cap(prepared["text"])
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


func _on_present_choices(choices: Array) -> void:
	_clear_choices()
	# Point de reprise : le joueur s'arrête ici (un point de choix lui est
	# présenté). Les nœuds intermédiaires enchaînés ne sont jamais un checkpoint.
	if not choices.is_empty():
		Progress.record_checkpoint(choices[0]["node"])
	for i in choices.size():
		var choice: Dictionary = choices[i]
		var button := Button.new()
		# Réponse déjà choisie (par n'importe quel personnage) : cochée et à
		# l'encre passée, pour que les réponses encore inexplorées ressortent.
		var choosers: Array = Progress.choice_choosers(choice["node"], choice["text"])
		if choosers.is_empty():
			button.text = "—  " + choice["text"]
		else:
			button.text = "✓  " + choice["text"]
			button.tooltip_text = "Déjà choisie avec : " + ", ".join(PackedStringArray(choosers))
		_style_choice(button, not choosers.is_empty())
		button.pressed.connect(_runner.choose.bind(i))
		_choices_box.add_child(button)


## Habillage des choix : cf. BookTheme.style_choice (réplique à l'encre).
func _style_choice(button: Button, read: bool) -> void:
	BookTheme.style_choice(button, read)


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

	_illustration_data = data
	_illustration = Illustration.new()
	_illustration.interaction_clicked.connect(_on_illustration_interaction)
	_plate.add_child(_illustration)
	# Sous la surcouche du bouton plein écran (dernier enfant de la planche).
	_plate.move_child(_illustration, 0)
	_illustration.setup(data)
	_illustration.parallax_gain = Settings.parallax_gain_default * PAGE_PARALLAX
	_plate_holder.ratio = _template_ratio(data.template)
	_plate_holder.visible = true


## Ratio de la planche selon le gabarit : la page cadre l'image au lieu que
## l'image ne redessine la page.
func _template_ratio(template: int) -> float:
	match template:
		IllustrationData.Template.PORTRAIT:
			return 0.75
		IllustrationData.Template.CHARACTER:
			return 1.0
		_:
			return 1.65


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
