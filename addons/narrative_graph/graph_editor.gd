@tool
extends VBoxContainer
## Écran principal « Narratif » : graphe éditable des histoires .untold.
##  - drag & drop des nœuds → disposition sauvée dans <histoire>.meta.json,
##    la MÊME que celle utilisée par la carte de progression en jeu ;
##  - « Appliquer l'ordre au .untold » → réécrit la source de vérité avec les
##    blocs de nœuds réordonnés selon la disposition (gauche → droite, puis
##    haut → bas), sans toucher à leur contenu ;
##  - clic sur un nœud → inspecteur modulaire (voir node_inspector.gd pour
##    ajouter un volet : un script + une ligne dans la liste).

const UntoldSource := preload("res://addons/narrative_graph/untold_source.gd")
const NodeInspector := preload("res://addons/narrative_graph/node_inspector.gd")

const STORIES_DIR := "res://data/stories"
const EXCERPT_LENGTH := 46

## Couleur du port selon la nature du lien sortant.
const KIND_COLORS := {
	"choice": Color(0.85, 0.72, 0.4),
	"divert": Color(0.55, 0.6, 0.75),
	"cond": Color(0.7, 0.5, 0.8),
}

## Aspect « pilule sobre » des GraphNode (arrondi plus discret qu'en jeu).
const NODE_CORNER_RADIUS := 8
const NODE_BG := Color(0.17, 0.17, 0.2)
const NODE_TITLE_BG := Color(0.21, 0.21, 0.26)
const NODE_BORDER := Color(0.33, 0.33, 0.4)
## Courbure des connecteurs natifs de GraphEdit (0 = droit, 1 = très courbe).
const LINES_CURVATURE := 0.4

var _stories: OptionButton
var _status: Label
var _graph_edit: GraphEdit
var _inspector: Control
var _new_node_dialog: ConfirmationDialog
var _new_node_edit: LineEdit
var _check_dialog: AcceptDialog
var _check_report: Label
var _search: LineEdit
var _search_matches: Array = []   # ids correspondant à la dernière recherche
var _search_index := -1
var _search_query := ""

## Annuler/rétablir des modifications du .untold, PAR fichier (l'historique
## survit aux rechargements et aux allers-retours entre histoires).
## path -> {"undo": Array[String] (textes disque), "redo": Array[String]}
const HISTORY_LIMIT := 30
var _histories: Dictionary = {}
var _undo_btn: Button
var _redo_btn: Button

var _source: RefCounted   # UntoldSource
var _story: Story
var _graph: StoryGraph
var _meta: StoryMeta
var _node_names: Dictionary = {}  # id du nœud d'histoire -> nom UNIQUE du GraphNode
var _collapse_buttons: Dictionary = {}  # id du nœud -> Button de repli (titre)
var _characters: Array = []   # CharacterData chargés (accent d'identité)
var _reach: Dictionary = {}   # id -> Array[String] personnages atteignant le nœud


func _init() -> void:
	name = "OutilNarratif"
	# L'écran principal de l'éditeur est un VBoxContainer : les ancres y sont
	# ignorées, seuls les size flags donnent la place au panneau.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_ui()


## Personnages jouables de l'histoire éditée (couleur d'accent), scannés dans le
## dossier characters/ à côté du .untold. Rechargés à chaque histoire ouverte ;
## une histoire sans dossier characters/ laisse simplement des accents neutres.
func _load_characters(story_dir: String) -> void:
	_characters.clear()
	var dir := DirAccess.open(story_dir + "characters/")
	if dir == null:
		return
	for file in dir.get_files():
		if file.ends_with(".tres"):
			var data: CharacterData = load(story_dir + "characters/" + file)
			if data != null:
				_characters.append(data)


func _ready() -> void:
	_scan_stories()


# --------------------------------------------------------------------- UI

func _build_ui() -> void:
	# Rangée 1 — l'histoire : choix du fichier, création de nœud, vérification,
	# recherche, statut.
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	add_child(toolbar)

	var caption := Label.new()
	caption.text = "Histoire :"
	toolbar.add_child(caption)

	_stories = OptionButton.new()
	_stories.item_selected.connect(func(_index: int) -> void: _load_selected())
	toolbar.add_child(_stories)

	var reload_btn := Button.new()
	reload_btn.text = "Recharger"
	reload_btn.tooltip_text = "Relit le fichier depuis le disque."
	reload_btn.pressed.connect(_load_selected)
	toolbar.add_child(reload_btn)

	var new_node := Button.new()
	new_node.text = "+ Nouveau nœud"
	new_node.tooltip_text = "Ajoute un nœud à l'histoire (bloc « :: id » en fin de fichier), placé au centre de la vue."
	new_node.pressed.connect(_prompt_new_node)
	toolbar.add_child(new_node)

	_undo_btn = Button.new()
	_undo_btn.text = "↶"
	_undo_btn.tooltip_text = "Annuler la dernière modification du .untold (contenu, liens, nœuds...). Les positions/commentaires ne sont pas concernés."
	_undo_btn.disabled = true
	_undo_btn.pressed.connect(_undo)
	toolbar.add_child(_undo_btn)

	_redo_btn = Button.new()
	_redo_btn.text = "↷"
	_redo_btn.tooltip_text = "Rétablir la modification annulée."
	_redo_btn.disabled = true
	_redo_btn.pressed.connect(_redo)
	toolbar.add_child(_redo_btn)

	var check := Button.new()
	check.text = "Vérifier"
	check.tooltip_text = "Contrôle l'histoire : liens cassés, nœuds injoignables, ids en double, illustrations inconnues."
	check.pressed.connect(_run_checks)
	toolbar.add_child(check)

	_search = LineEdit.new()
	_search.placeholder_text = "Rechercher (id ou texte)…"
	_search.custom_minimum_size = Vector2(190, 0)
	_search.tooltip_text = "Entrée : va au nœud suivant dont l'id ou le texte contient la recherche."
	_search.text_submitted.connect(_on_search_submitted)
	toolbar.add_child(_search)

	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.modulate = Color(0.7, 0.7, 0.8)
	_status.clip_text = true
	toolbar.add_child(_status)

	# Rangée 2 — la disposition : rangement, ordre du fichier, repli.
	var layout_bar := HBoxContainer.new()
	layout_bar.add_theme_constant_override("separation", 8)
	add_child(layout_bar)

	var layout_caption := Label.new()
	layout_caption.text = "Disposition :"
	layout_caption.modulate = Color(0.65, 0.65, 0.75)
	layout_bar.add_child(layout_caption)

	var auto_layout := Button.new()
	auto_layout.text = "Auto"
	auto_layout.tooltip_text = "Range les nœuds en colonnes par profondeur depuis le début (gauche → droite), et sauve cette disposition."
	auto_layout.pressed.connect(_apply_auto_layout)
	layout_bar.add_child(auto_layout)

	var apply := Button.new()
	apply.text = "Appliquer l'ordre au .untold"
	apply.tooltip_text = "Réécrit le fichier source avec les nœuds réordonnés selon la disposition du graphe."
	apply.pressed.connect(_apply_order)
	layout_bar.add_child(apply)

	var fold_all := Button.new()
	fold_all.text = "Replier tout"
	fold_all.tooltip_text = "Replie tous les nœuds : seul le début (et les orphelins) reste visible."
	fold_all.pressed.connect(_set_all_collapsed.bind(true))
	layout_bar.add_child(fold_all)

	var unfold_all := Button.new()
	unfold_all.text = "Déplier tout"
	unfold_all.tooltip_text = "Déplie tous les nœuds de l'histoire."
	unfold_all.pressed.connect(_set_all_collapsed.bind(false))
	layout_bar.add_child(unfold_all)

	var wire_hint := Label.new()
	wire_hint.text = "Tirer un port de sortie vers un nœud = rediriger le lien."
	wire_hint.modulate = Color(0.5, 0.5, 0.6)
	wire_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wire_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	layout_bar.add_child(wire_hint)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)

	_graph_edit = GraphEdit.new()
	_graph_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graph_edit.minimap_enabled = true
	# Connecteurs courbes (natif) : cohérent avec la carte en jeu (story_map),
	# aucune ligne de dessin custom à écrire.
	_graph_edit.connection_lines_curvature = LINES_CURVATURE
	# Le rangement natif de GraphEdit ignore la logique de l'histoire :
	# masqué au profit du bouton « Disposition auto » de la barre d'outils.
	_graph_edit.show_arrange_button = false
	_graph_edit.node_selected.connect(_on_node_selected)
	_graph_edit.end_node_move.connect(_save_positions)
	# Tirer un port de sortie vers l'entrée d'un autre nœud REDIRIGE le lien
	# correspondant dans le .untold (la cible seule change, la ligne est intacte).
	_graph_edit.connection_request.connect(_on_connection_request)
	split.add_child(_graph_edit)

	_inspector = NodeInspector.new()
	split.add_child(_inspector)

	_build_dialogs()


## Dialogues réutilisés : création de nœud et rapport de vérification.
func _build_dialogs() -> void:
	_new_node_dialog = ConfirmationDialog.new()
	_new_node_dialog.title = "Nouveau nœud"
	_new_node_dialog.ok_button_text = "Créer"
	var box := VBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "Id du nœud (lettres, chiffres, _) :"
	box.add_child(lbl)
	_new_node_edit = LineEdit.new()
	_new_node_edit.placeholder_text = "ex : temple_entree"
	box.add_child(_new_node_edit)
	_new_node_dialog.add_child(box)
	_new_node_dialog.register_text_enter(_new_node_edit)
	_new_node_dialog.confirmed.connect(_create_node)
	add_child(_new_node_dialog)

	_check_dialog = AcceptDialog.new()
	_check_dialog.title = "Vérification de l'histoire"
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 300)
	_check_report = Label.new()
	_check_report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_check_report.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_check_report)
	_check_dialog.add_child(scroll)
	add_child(_check_dialog)


func set_status(message: String) -> void:
	_status.text = message


# ---------------------------------------------------------------- Chargement

func _scan_stories() -> void:
	_stories.clear()
	for path in _find_untold_files():
		_stories.add_item(path.get_file())
		# Le chemin complet est porté par la métadonnée : les .untold vivent
		# désormais dans un sous-dossier par histoire (data/stories/<id>/).
		_stories.set_item_metadata(_stories.item_count - 1, path)
	if _stories.item_count > 0:
		_stories.select(0)
		_load_selected()


## .untold rangés par histoire : un niveau de sous-dossier (data/stories/<id>/),
## plus ceux restés à la racine (hors jeu, ex. demo_format — démo du format).
func _find_untold_files() -> Array:
	var found: Array = []
	var root := DirAccess.open(STORIES_DIR)
	if root == null:
		set_status("Dossier introuvable : " + STORIES_DIR)
		return found
	for file in root.get_files():
		if file.ends_with(".untold"):
			found.append(STORIES_DIR + "/" + file)
	for sub in root.get_directories():
		var subdir := DirAccess.open(STORIES_DIR + "/" + sub)
		if subdir == null:
			continue
		for file in subdir.get_files():
			if file.ends_with(".untold"):
				found.append(STORIES_DIR + "/" + sub + "/" + file)
	return found


func _current_path() -> String:
	if _stories.selected < 0:
		return ""
	return str(_stories.get_item_metadata(_stories.selected))


func _load_selected() -> void:
	var path := _current_path()
	if path.is_empty():
		return
	_source = UntoldSource.new()
	if not _source.load_file(path):
		set_status("Lecture impossible : " + path)
		return
	# Chaque réécriture du fichier alimente l'annuler/rétablir de ce fichier.
	_source.history_sink = _push_undo
	# Ressources propres à l'histoire éditée (dossier du .untold) : personnages
	# pour l'accent d'identité, définitions d'illustrations pour les aperçus.
	var story_dir := path.get_base_dir() + "/"
	_load_characters(story_dir)
	IllustrationLibrary.load_story(story_dir)
	_story = StoryParser.parse(FileAccess.get_file_as_string(path))
	_graph = StoryGraph.build(_story)
	_meta = StoryMeta.load_for(path)
	# Cache du total de nœuds dans le sidecar : le futur hub (point 9) le lit sans
	# reparser le .untold. Écrit MAINTENANT (l'ouverture donne _story gratuitement)
	# et sauvé immédiatement, indépendamment des autres call sites de _meta.save().
	_meta.data["total_nodes"] = _story.nodes.size()
	_meta.save()
	_rebuild_graph_view()
	_refresh_history_buttons()
	if not _source.duplicate_ids.is_empty():
		set_status("⚠ id(s) déclaré(s) plusieurs fois dans le fichier : %s — à corriger (le jeu ne garde que le dernier bloc)."
				% ", ".join(PackedStringArray(_source.duplicate_ids)))
	else:
		set_status("%d nœuds — %s" % [_story.nodes.size(), path.get_file()])


func _rebuild_graph_view() -> void:
	_graph_edit.clear_connections()
	for child in _graph_edit.get_children():
		if child is GraphNode:
			child.free()  # libération immédiate : les noms doivent être réutilisables
	_node_names.clear()
	_collapse_buttons.clear()
	# Le contenu a pu changer : la recherche repart de zéro.
	_search_query = ""
	_search_matches = []
	_search_index = -1

	# Accessibilité par identité (accent de couleur personnage) : calculée une
	# fois par reconstruction, structurelle (indépendante de la progression).
	_reach = _graph.identity_reach()

	# Disposition : positions sauvegardées, complétées par l'auto-layout.
	var positions := _meta.positions()
	var auto: Dictionary = {}
	for id in _story.nodes:
		if not positions.has(id):
			if auto.is_empty():
				auto = _graph.auto_layout()
			positions[id] = auto[id]

	for id in _source.order:
		if _story.has_node(id):
			_graph_edit.add_child(_make_graph_node(id, positions[id]))

	_update_visibility()


func _make_graph_node(id: String, pos: Vector2) -> GraphNode:
	var node: StoryNode = _story.get_node_by_id(id)
	var gnode := GraphNode.new()
	gnode.name = _unique_gnode_name(id)
	# L'id d'histoire vit en métadonnée : le nom du GraphNode (sanitisé, unifié)
	# n'est PAS une clé fiable pour le retrouver.
	gnode.set_meta("story_id", id)
	gnode.title = id
	gnode.position_offset = pos
	_node_names[id] = gnode.name

	# Coins arrondis + accent de couleur d'identité (fond/bordure, pas les ports).
	_apply_node_style(gnode, _node_accent(id))

	# Badge « hors carte » dans la barre de titre : le nœud est exclu de la carte
	# de progression en jeu (retour visuel de l'état du tag #hors_carte).
	if "hors_carte" in node.tags:
		var hidden_badge := Label.new()
		hidden_badge.text = "⊘"
		hidden_badge.tooltip_text = "#hors_carte : nœud exclu de la carte de progression en jeu."
		hidden_badge.modulate = Color(0.9, 0.62, 0.5)
		hidden_badge.add_theme_font_size_override("font_size", 18)
		gnode.get_titlebar_hbox().add_child(hidden_badge)

	# Badge « illustration » dans la barre de titre : repérable sans avoir à
	# cliquer sur chaque nœud (le nom est dans l'infobulle).
	var illustrations := node.command_values("illustration")
	if not illustrations.is_empty():
		var badge := TextureRect.new()
		badge.texture = get_theme_icon("ImageTexture", "EditorIcons")
		badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		badge.custom_minimum_size = Vector2(20, 20)
		badge.tooltip_text = "Illustration : " + ", ".join(PackedStringArray(illustrations))
		gnode.get_titlebar_hbox().add_child(badge)

	# Bouton de repli dans la barre de titre : masque en cascade les nœuds
	# qui dépendent de celui-ci (état conservé dans le sidecar .meta.json).
	if not _graph.outgoing(id).is_empty():
		var fold := Button.new()
		fold.flat = true
		fold.focus_mode = Control.FOCUS_NONE
		fold.add_theme_font_size_override("font_size", 26)
		fold.tooltip_text = "Replier / déplier les nœuds qui dépendent de celui-ci."
		fold.pressed.connect(_toggle_collapsed.bind(id))
		gnode.get_titlebar_hbox().add_child(fold)
		_collapse_buttons[id] = fold

	# Rangée 0 : extrait du texte, port d'entrée à gauche.
	var excerpt := Label.new()
	excerpt.text = _excerpt(node)
	excerpt.custom_minimum_size = Vector2(230, 0)
	excerpt.clip_text = true
	excerpt.modulate = Color(0.78, 0.78, 0.85)
	gnode.add_child(excerpt)
	gnode.set_slot(0, true, 0, Color(0.8, 0.8, 0.8), false, 0, Color.WHITE)

	# Une rangée par lien sortant, port de sortie à droite, coloré par nature.
	var row := 1
	for link in _graph.outgoing(id):
		var label := Label.new()
		label.text = _link_caption(link)
		label.clip_text = true
		label.custom_minimum_size = Vector2(230, 0)
		gnode.add_child(label)
		gnode.set_slot(row, false, 0, Color.WHITE, true, 0, KIND_COLORS[link["kind"]])
		row += 1

	return gnode


## Nom de GraphNode unique pour cet id : deux ids d'histoire distincts peuvent
## se « sanitiser » vers le même nom Godot (ex: « scene.1 » et « scene:1 ») —
## Godot renommerait alors le second à l'insertion et le mapping id <-> nœud
## casserait. On suffixe donc AVANT l'insertion.
func _unique_gnode_name(id: String) -> StringName:
	var base := ("n_" + id).validate_node_name()
	var candidate := base
	var n := 2
	while _node_names.values().has(StringName(candidate)):
		candidate = "%s_%d" % [base, n]
		n += 1
	return StringName(candidate)


## Id d'histoire porté par un GraphNode ("" si absent).
func _story_id_of(child: Node) -> String:
	return str(child.get_meta("story_id", ""))


## Accent d'identité d'un nœud : couleur du seul personnage qui peut l'atteindre
## (via les liens d'identité), sinon accent neutre (plusieurs personnages, aucun,
## ou nœud hors de l'accessibilité calculée). Cf. StoryGraph.identity_reach.
func _node_accent(id: String) -> Dictionary:
	var chars: Array = _reach.get(id, [])
	if chars.size() == 1:
		return {"tinted": true, "color": _character_color(str(chars[0]))}
	return {"tinted": false, "color": NODE_BORDER}


## Couleur d'un personnage : sa ressource si connue, sinon une teinte stable
## dérivée du nom (mêmes règles que la carte en jeu, story_map._color_of).
func _character_color(character_type: String) -> Color:
	for data in _characters:
		if data.character_type == character_type:
			return data.color
	return Color.from_hsv(fmod(abs(float(character_type.hash())) / 1000.0, 1.0), 0.55, 0.9)


## Style « pilule sobre » du GraphNode : coins arrondis (barre de titre + corps),
## fond/bordure teintés par l'accent d'identité. N'affecte PAS les ports (colorés
## par nature de lien — information distincte de la couleur personnage).
func _apply_node_style(gnode: GraphNode, accent: Dictionary) -> void:
	var border: Color = NODE_BORDER
	var bg := NODE_BG
	var title_bg := NODE_TITLE_BG
	if accent["tinted"]:
		var c: Color = accent["color"]
		bg = NODE_BG.lerp(c, 0.14)
		title_bg = NODE_TITLE_BG.lerp(c, 0.22)
		border = c.lerp(Color(0.5, 0.5, 0.55), 0.25)
	gnode.add_theme_stylebox_override("titlebar", _title_box(title_bg, border, false))
	gnode.add_theme_stylebox_override("titlebar_selected", _title_box(title_bg, border.lerp(Color.WHITE, 0.4), true))
	gnode.add_theme_stylebox_override("panel", _body_box(bg, border, false))
	gnode.add_theme_stylebox_override("panel_selected", _body_box(bg, border.lerp(Color.WHITE, 0.4), true))


## Barre de titre : coins arrondis EN HAUT seulement (le corps arrondit le bas).
func _title_box(bg: Color, border: Color, selected: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = NODE_CORNER_RADIUS
	s.corner_radius_top_right = NODE_CORNER_RADIUS
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	s.border_color = border
	s.border_width_left = 2 if selected else 1
	s.border_width_right = s.border_width_left
	s.border_width_top = s.border_width_left
	return s


## Corps : coins arrondis EN BAS seulement (la barre de titre arrondit le haut).
func _body_box(bg: Color, border: Color, selected: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_bottom_left = NODE_CORNER_RADIUS
	s.corner_radius_bottom_right = NODE_CORNER_RADIUS
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 4
	s.content_margin_bottom = 6
	s.border_color = border
	s.border_width_left = 2 if selected else 1
	s.border_width_right = s.border_width_left
	s.border_width_bottom = s.border_width_left
	return s


func _excerpt(node: StoryNode) -> String:
	for ins in node.instructions:
		if ins["type"] == "text":
			var value: String = ins["value"]
			if value.length() > EXCERPT_LENGTH:
				return value.left(EXCERPT_LENGTH) + "…"
			return value
	return "(sans texte)"


func _link_caption(link: Dictionary) -> String:
	var guard_prefix := "{…} " if link["guarded"] else ""
	match link["kind"]:
		"choice":
			var text: String = link["text"]
			if text.length() > 36:
				text = text.left(36) + "…"
			return guard_prefix + "▸ " + text
		"cond":
			return guard_prefix + "→ saut conditionnel → " + link["target"]
		_:
			return guard_prefix + "→ " + link["target"]


# ------------------------------------------------------------------- Repli

## Ids visibles : ceux qu'on atteint depuis le début SANS traverser un nœud
## replié (le nœud replié reste visible, ses dépendants exclusifs non).
## Un nœud encore atteignable par une autre branche ouverte reste affiché.
## Les nœuds inaccessibles depuis le début (orphelins) restent visibles.
func _visible_ids() -> Dictionary:
	var visible: Dictionary = {}
	var reachable: Dictionary = {}
	if _story.has_node(_story.start_node):
		reachable[_story.start_node] = true
		var queue: Array = [_story.start_node]
		while not queue.is_empty():
			var id: String = queue.pop_front()
			for link in _graph.outgoing(id):
				var target: String = link["target"]
				if _story.has_node(target) and not reachable.has(target):
					reachable[target] = true
					queue.append(target)

		visible[_story.start_node] = true
		queue = [_story.start_node]
		while not queue.is_empty():
			var open_id: String = queue.pop_front()
			if _meta.is_collapsed(open_id):
				continue
			for link in _graph.outgoing(open_id):
				var target: String = link["target"]
				if _story.has_node(target) and not visible.has(target):
					visible[target] = true
					queue.append(target)

	for id in _story.nodes:
		if not reachable.has(id):
			visible[id] = true
	return visible


## Applique l'état de repli : visibilité des nœuds, glyphes des boutons,
## et connexions redessinées entre nœuds visibles uniquement.
func _update_visibility() -> void:
	var shown := _visible_ids()
	var hidden := 0
	for child in _graph_edit.get_children():
		if child is GraphNode:
			child.visible = shown.has(_story_id_of(child))
			if not child.visible:
				child.selected = false
				hidden += 1

	for id in _collapse_buttons:
		_collapse_buttons[id].text = "▸" if _meta.is_collapsed(id) else "▾"

	_graph_edit.clear_connections()
	for id in _story.nodes:
		if not shown.has(id) or not _node_names.has(id):
			continue
		var links := _graph.outgoing(id)
		for i in links.size():
			var target: String = links[i]["target"]
			if shown.has(target) and _node_names.has(target):
				_graph_edit.connect_node(_node_names[id], i, _node_names[target], 0)

	if hidden > 0:
		set_status("%d nœud(s) masqué(s) par repli." % hidden)


func _toggle_collapsed(id: String) -> void:
	_meta.set_collapsed(id, not _meta.is_collapsed(id))
	_meta.save()
	_update_visibility()


func _set_all_collapsed(collapsed: bool) -> void:
	if _story == null:
		return
	for id in _story.nodes:
		if not _graph.outgoing(id).is_empty():
			_meta.set_collapsed(id, collapsed)
	_meta.save()
	_update_visibility()
	if not collapsed:
		set_status("Tous les nœuds sont dépliés.")


# ------------------------------------------------------- Annuler / rétablir

## Pile d'historique du fichier courant, créée au besoin.
func _history() -> Dictionary:
	var path := _current_path()
	if not _histories.has(path):
		_histories[path] = {"undo": [], "redo": []}
	return _histories[path]


## Alimenté par UntoldSource.save() (history_sink) : l'état disque PRÉCÉDENT
## devient annulable, et toute nouvelle écriture invalide le rétablir.
func _push_undo(_path: String, old_text: String) -> void:
	var h := _history()
	h["undo"].append(old_text)
	if h["undo"].size() > HISTORY_LIMIT:
		h["undo"].pop_front()
	h["redo"].clear()
	_refresh_history_buttons()


func _undo() -> void:
	_restore_from(_history()["undo"], _history()["redo"], "Modification annulée")


func _redo() -> void:
	_restore_from(_history()["redo"], _history()["undo"], "Modification rétablie")


## Échange l'état disque avec le sommet de `take` (l'état actuel part dans
## `give`), puis recharge le graphe. Commun à annuler et rétablir.
func _restore_from(take: Array, give: Array, label: String) -> void:
	var path := _current_path()
	if take.is_empty() or path.is_empty():
		return
	give.append(FileAccess.get_file_as_string(path))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		give.pop_back()
		set_status("Impossible d'écrire " + path)
		return
	file.store_string(take.pop_back())
	file.close()
	_load_selected()
	set_status("%s — %s." % [label, path.get_file()])


func _refresh_history_buttons() -> void:
	var h := _history()
	_undo_btn.disabled = h["undo"].is_empty()
	_redo_btn.disabled = h["redo"].is_empty()


# ------------------------------------------------------ Création / recâblage

func _prompt_new_node() -> void:
	if _source == null:
		return
	_new_node_edit.text = ""
	_new_node_dialog.popup_centered()
	_new_node_edit.grab_focus()


## Crée le nœud saisi : bloc en fin de fichier, placé au centre de la vue
## courante du graphe, puis sélectionné (prêt à écrire dans le volet Contenu).
func _create_node() -> void:
	var id := _new_node_edit.text.strip_edges()
	if not UntoldSource.is_valid_id(id):
		set_status("Id invalide « %s » — lettres, chiffres et _ seulement (et pas END)." % id)
		return
	if _story.has_node(id):
		set_status("Un nœud « %s » existe déjà." % id)
		return
	if not _source.add_node(id, ["Texte à écrire…"]) or not _source.save():
		set_status("Impossible de créer le nœud.")
		return
	var center := (_graph_edit.scroll_offset + _graph_edit.size * 0.5) / _graph_edit.zoom
	_meta.set_node_position(id, center)
	_meta.save()
	set_status("Nœud « %s » créé — écris son contenu dans le volet de droite." % id)
	reload_and_select(id)


## Tirer un port de sortie vers l'entrée d'un autre nœud : le lien n°port du
## nœud source est REDIRIGÉ vers le nœud visé (seule la cible change dans le
## fichier). L'ancienne connexion disparaît au rechargement.
func _on_connection_request(from_name: StringName, from_port: int,
		to_name: StringName, _to_port: int) -> void:
	var from_node := _graph_edit.get_node_or_null(NodePath(from_name))
	var to_node := _graph_edit.get_node_or_null(NodePath(to_name))
	if from_node == null or to_node == null:
		return
	var from_id := _story_id_of(from_node)
	var to_id := _story_id_of(to_node)
	if from_id.is_empty() or to_id.is_empty() or from_id == to_id:
		return
	if _source.set_link_target(from_id, from_port, to_id) and _source.save():
		set_status("Lien de %s redirigé vers %s." % [from_id, to_id])
		reload_and_select(from_id)
	else:
		set_status("Impossible de rediriger ce lien.")


# --------------------------------------------------------------- Recherche

## Entrée dans le champ de recherche : va au nœud suivant dont l'id ou le
## texte contient la requête (insensible à la casse, boucle sur les résultats).
func _on_search_submitted(query: String) -> void:
	query = query.strip_edges()
	if query.is_empty() or _story == null:
		return
	if query.nocasecmp_to(_search_query) != 0:
		_search_query = query
		_search_index = -1
		_search_matches = _find_matches(query)
	if _search_matches.is_empty():
		set_status("Aucun nœud ne contient « %s »." % query)
		return
	_search_index = (_search_index + 1) % _search_matches.size()
	var id: String = _search_matches[_search_index]
	set_status("%s (%d/%d pour « %s »)" % [id, _search_index + 1, _search_matches.size(), query])
	_focus_node(id)


## Ids dont l'id ou une ligne de texte contient la requête, dans l'ordre du fichier.
func _find_matches(query: String) -> Array:
	var found: Array = []
	for id in _source.order:
		if not _story.has_node(id):
			continue
		if id.containsn(query):
			found.append(id)
			continue
		for ins in _story.get_node_by_id(id).instructions:
			if ins["type"] == "text" and str(ins["value"]).containsn(query):
				found.append(id)
				break
	return found


## Sélectionne un nœud et centre la vue dessus (déplie tout si le nœud est
## masqué par un repli).
func _focus_node(id: String) -> void:
	if not _node_names.has(id):
		return
	var gnode: GraphNode = _graph_edit.get_node_or_null(NodePath(_node_names[id]))
	if gnode == null:
		return
	if not gnode.visible:
		_set_all_collapsed(false)
	_graph_edit.set_selected(gnode)
	_graph_edit.scroll_offset = gnode.position_offset * _graph_edit.zoom \
			- (_graph_edit.size - gnode.size * _graph_edit.zoom) * 0.5
	_inspector.show_node(_make_context(id))


# ------------------------------------------------------------- Vérification

## Contrôles statiques de l'histoire ouverte, présentés dans un dialogue :
## ids en double, cibles cassées, nœud d'entrée absent, nœuds injoignables,
## illustrations inconnues de la bibliothèque.
func _run_checks() -> void:
	if _story == null:
		return
	var problems: Array = []

	for id in _source.duplicate_ids:
		problems.append("• id déclaré plusieurs fois : « %s » (le jeu ne garde que le dernier bloc)." % id)

	if not _story.has_node(_story.start_node):
		problems.append("• nœud d'entrée « %s » introuvable : l'histoire ne peut pas démarrer." % _story.start_node)

	for id in _source.order:
		if not _story.has_node(id):
			continue
		for link in _graph.outgoing(id):
			var target: String = link["target"]
			if target != "END" and not _story.has_node(target):
				problems.append("• %s → cible inconnue « %s »." % [id, target])
		for illu in _story.get_node_by_id(id).command_values("illustration"):
			if not IllustrationLibrary.defs().has(illu):
				problems.append("• %s : illustration inconnue « %s » (absente de illustrations_defs.json)." % [id, illu])

	var reachable: Dictionary = {}
	if _story.has_node(_story.start_node):
		reachable[_story.start_node] = true
		var queue: Array = [_story.start_node]
		while not queue.is_empty():
			for link in _graph.outgoing(queue.pop_front()):
				var target: String = link["target"]
				if _story.has_node(target) and not reachable.has(target):
					reachable[target] = true
					queue.append(target)
	for id in _source.order:
		if _story.has_node(id) and not reachable.has(id):
			problems.append("• nœud injoignable depuis le début : « %s »." % id)

	_check_report.text = "Aucun problème détecté — l'histoire est saine. ✔" if problems.is_empty() \
			else "\n".join(PackedStringArray(problems))
	_check_dialog.popup_centered()


# ----------------------------------------------------------------- Actions

## Fin d'un drag : toute la disposition est sauvée dans le sidecar .meta.json
## (elle sert aussi de mise en page à la carte de progression en jeu).
func _save_positions() -> void:
	for child in _graph_edit.get_children():
		if child is GraphNode:
			_meta.set_node_position(_story_id_of(child), child.position_offset)
	_meta.save()
	set_status("Disposition enregistrée (partagée avec la carte en jeu).")


## Réapplique la disposition automatique en colonnes (profondeur depuis le
## début, gauche → droite) à tous les nœuds, et la sauve comme disposition
## partagée — remplace le rangement natif de GraphEdit, masqué car il
## ignore la logique de l'histoire.
func _apply_auto_layout() -> void:
	if _graph == null:
		return
	var layout := _graph.auto_layout()
	for child in _graph_edit.get_children():
		if child is GraphNode:
			var id := _story_id_of(child)
			if layout.has(id):
				child.position_offset = layout[id]
	_save_positions()
	set_status("Disposition auto appliquée : colonnes par profondeur depuis le début.")


## Réordonne les blocs du fichier source selon la disposition : colonne par
## colonne (x croissant), et de haut en bas dans une même colonne.
func _apply_order() -> void:
	if _source == null:
		return
	var positions: Dictionary = {}
	for child in _graph_edit.get_children():
		if child is GraphNode:
			positions[_story_id_of(child)] = child.position_offset
	var ids: Array = positions.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		var pa: Vector2 = positions[a]
		var pb: Vector2 = positions[b]
		if absf(pa.x - pb.x) > 1.0:
			return pa.x < pb.x
		return pa.y < pb.y)
	_source.reorder(ids)
	if _source.save():
		set_status("Ordre appliqué : %s réécrit (contenu des nœuds intact)." % _current_path().get_file())
	else:
		set_status("Échec d'écriture du fichier source.")


func _on_node_selected(node: Node) -> void:
	if node is GraphNode and not _story_id_of(node).is_empty():
		_inspector.show_node(_make_context(_story_id_of(node)))


func _make_context(id: String) -> Dictionary:
	return {
		"node_id": id,
		"node": _story.get_node_by_id(id),
		"story": _story,
		"graph": _graph,
		"source": _source,
		"meta": _meta,
		"editor": self,
	}


## Recharge le fichier depuis le disque (après une modification par
## l'inspecteur), disposition conservée.
func reload() -> void:
	_load_selected()


## Recharge le fichier et rouvre le même nœud, disposition conservée.
func reload_and_select(id: String) -> void:
	_load_selected()
	if not _node_names.has(id):
		return
	var gnode := _graph_edit.get_node_or_null(NodePath(_node_names[id]))
	if gnode is GraphNode:
		gnode.selected = true
		_inspector.show_node(_make_context(id))
