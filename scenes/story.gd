extends Control
## Vue d'histoire : charge l'histoire, la fait tourner via le StoryRunner et
## affiche le buste du personnage + texte (effet machine à écrire) + choix.
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
var _text_label: RichTextLabel
var _choices_box: VBoxContainer
var _typewriter: Tween
## Effet « shock » gardé en référence pour relancer son à-coup à chaque passage.
var _fx_shock: RichTextEffect
## Texte brut (avec balises de pause) actuellement affiché, accumulé par les
## lignes de dialogue ajoutées au clic d'une zone — base des ajouts suivants.
var _display_raw := ""
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

## Gabarit Character : petit portrait carré ancré en haut à gauche. Valeurs
## PROVISOIRES non validées par le design — à ajuster visuellement.
const CHARACTER_SIDE := 288.0    # ~15 % de 1920 (largeur de référence)
const CHARACTER_MARGIN := 24.0


func _ready() -> void:
	_build_ui()

	# La carte du récit s'ouvre par la touche M ou depuis le menu Échap : on
	# active l'entrée « Carte du récit » du menu tant que cette scène est active.
	SettingsMenu.set_map_available(true)
	SettingsMenu.map_requested.connect(_toggle_map)

	# Entrée « Recommencer cette histoire » du menu, active pendant l'histoire.
	SettingsMenu.set_restart_available(true)
	SettingsMenu.restart_requested.connect(_restart_story)

	# Résout l'histoire choisie (dossier data/stories/<id>/ + entry_file du
	# manifest), puis charge ses définitions d'illustrations AVANT le préchargement.
	_story_path = _resolve_story_path()
	IllustrationLibrary.load_story(GameState.story_dir())

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


## Résout le chemin du .untold de l'histoire courante via son manifest.json.
func _resolve_story_path() -> String:
	var dir := GameState.story_dir()
	var manifest_path := dir + "manifest.json"
	if not FileAccess.file_exists(manifest_path):
		push_error("story: manifest introuvable : " + manifest_path)
		return ""
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	var entry := str(parsed.get("entry_file", "")) if parsed is Dictionary else ""
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
	# En paysage, _content couvre tout l'écran : PASS laisse les clics NON
	# consommés par un enfant réel (texte, boutons) remonter jusqu'aux zones
	# interactives de l'illustration en dessous. _content n'a pas de gui_input
	# propre, donc rien de son comportement n'est perdu.
	_content.mouse_filter = Control.MOUSE_FILTER_PASS
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

	# Extrait les pauses dramatiques [Soupir:X] : le texte affiché n'en contient
	# plus, et chaque pause connaît son rang en caractères VISIBLES.
	_display_raw = text
	var prepared := _prepare_dramatic_text(_display_raw)
	_text_label.text = prepared["text"]
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
		# TODO point 10 : Inventory n'existe pas encore.
		# Inventory.add_item(interaction.item_id, interaction.item_qty)
		pass

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
	_text_label.text = prepared["text"]
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
	_map.setup(_story, _story_path, _current_node)
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
	_illustration.interaction_clicked.connect(_on_illustration_interaction)
	add_child(_illustration)
	# Au-dessus du fond (index 0), sous le voile et l'UI.
	move_child(_illustration, 1)
	_illustration.setup(data)
	_apply_illustration_layout(data.template)


## Place l'illustration et la zone de texte selon le gabarit :
##  - PORTRAIT : mise en page « livre » — illustration sur la moitié gauche,
##    texte sur la moitié droite.
##  - CHARACTER : petit portrait carré en haut à gauche, texte plein écran à
##    côté (dimensions PROVISOIRES, cf. CHARACTER_SIDE).
##  - LANDSCAPE (défaut) : illustration plein écran, texte par-dessus (voile).
func _apply_illustration_layout(template: int) -> void:
	match template:
		IllustrationData.Template.PORTRAIT:
			# Livre : texte sur la demi-page droite, loin de la pastille → marge normale.
			_set_rect_anchors(_illustration, 0.0, 0.0, 0.5, 1.0, BORDER)
			_set_rect_anchors(_content, 0.5, 0.0, 1.0, 1.0)
			_content.add_theme_constant_override("margin_left", 56)
			_scrim.visible = false
		IllustrationData.Template.CHARACTER:
			# Carré ancré en haut à gauche ; le texte occupe l'écran mais dégage
			# le coin. Réutilise le dégagement de la pastille (même emprise).
			_set_corner_square(_illustration, CHARACTER_MARGIN, CHARACTER_SIDE)
			_set_rect_anchors(_content, 0.0, 0.0, 1.0, 1.0)
			_content.add_theme_constant_override("margin_left", BADGE_CLEARANCE)
			_scrim.visible = false
		_:
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


## Ancre un contrôle en carré (side × side) dans le coin haut-gauche, à `margin`
## px des bords — gabarit Character.
func _set_corner_square(node: Control, margin: float, side: float) -> void:
	node.anchor_left = 0.0
	node.anchor_top = 0.0
	node.anchor_right = 0.0
	node.anchor_bottom = 0.0
	node.offset_left = margin
	node.offset_top = margin
	node.offset_right = margin + side
	node.offset_bottom = margin + side


func _on_story_ended() -> void:
	_clear_choices()

	# Fin atteinte : plus de reprise pour ce personnage — la prochaine sélection
	# repartira du début (reprendre une fin n'a pas de sens).
	Progress.clear_checkpoint()

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


## Recommence l'histoire pour le personnage courant, depuis le menu Réglages :
## efface sa partie en cours (zones + reprise, PAS la découverte cumulative)
## puis recharge la scène. Le rechargement remet à zéro TOUT l'état d'affichage
## (illustration, texte, carte) et, la reprise effacée, _start_story repart de
## start_node — plus propre qu'un go_to() qui laisserait variables et décor en
## place.
func _restart_story() -> void:
	Progress.restart_playthrough(_story_path.get_file().get_basename(), GameState.character_type)
	get_tree().reload_current_scene()
