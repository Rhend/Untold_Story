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

var _source: RefCounted   # UntoldSource
var _story: Story
var _graph: StoryGraph
var _meta: StoryMeta
var _node_ids: Dictionary = {}  # nom du GraphNode -> id du nœud d'histoire
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
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	add_child(toolbar)

	var caption := Label.new()
	caption.text = "Histoire :"
	toolbar.add_child(caption)

	_stories = OptionButton.new()
	_stories.item_selected.connect(func(_index: int) -> void: _load_selected())
	toolbar.add_child(_stories)

	var reload := Button.new()
	reload.text = "Recharger"
	reload.tooltip_text = "Relit le fichier depuis le disque."
	reload.pressed.connect(_load_selected)
	toolbar.add_child(reload)

	var apply := Button.new()
	apply.text = "Appliquer l'ordre au .untold"
	apply.tooltip_text = "Réécrit le fichier source avec les nœuds réordonnés selon la disposition du graphe."
	apply.pressed.connect(_apply_order)
	toolbar.add_child(apply)

	var auto_layout := Button.new()
	auto_layout.text = "Disposition auto"
	auto_layout.tooltip_text = "Range les nœuds en colonnes par profondeur depuis le début (gauche → droite), et sauve cette disposition."
	auto_layout.pressed.connect(_apply_auto_layout)
	toolbar.add_child(auto_layout)

	var fold_all := Button.new()
	fold_all.text = "Replier tout"
	fold_all.tooltip_text = "Replie tous les nœuds : seul le début (et les orphelins) reste visible."
	fold_all.pressed.connect(_set_all_collapsed.bind(true))
	toolbar.add_child(fold_all)

	var unfold_all := Button.new()
	unfold_all.text = "Déplier tout"
	unfold_all.tooltip_text = "Déplie tous les nœuds de l'histoire."
	unfold_all.pressed.connect(_set_all_collapsed.bind(false))
	toolbar.add_child(unfold_all)

	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.modulate = Color(0.7, 0.7, 0.8)
	toolbar.add_child(_status)

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
	split.add_child(_graph_edit)

	_inspector = NodeInspector.new()
	split.add_child(_inspector)


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
	set_status("%d nœuds — %s" % [_story.nodes.size(), path.get_file()])


func _rebuild_graph_view() -> void:
	_graph_edit.clear_connections()
	for child in _graph_edit.get_children():
		if child is GraphNode:
			child.free()  # libération immédiate : les noms doivent être réutilisables
	_node_ids.clear()
	_collapse_buttons.clear()

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
	gnode.name = _gnode_name(id)
	gnode.title = id
	gnode.position_offset = pos
	_node_ids[String(gnode.name)] = id

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
	var illustrations := _illustration_names(node)
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


func _gnode_name(id: String) -> StringName:
	return StringName(("n_" + id).validate_node_name())


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


## Noms passés aux commandes @illustration(...) du nœud, dans l'ordre.
func _illustration_names(node: StoryNode) -> Array:
	var names: Array = []
	for ins in node.instructions:
		if ins["type"] == "command" and ins["name"] == "illustration" \
				and not ins["args"].is_empty():
			names.append(str(ins["args"][0]))
	return names


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
			child.visible = shown.has(_node_ids[String(child.name)])
			if not child.visible:
				child.selected = false
				hidden += 1

	for id in _collapse_buttons:
		_collapse_buttons[id].text = "▸" if _meta.is_collapsed(id) else "▾"

	_graph_edit.clear_connections()
	for id in _story.nodes:
		if not shown.has(id):
			continue
		var links := _graph.outgoing(id)
		for i in links.size():
			var target: String = links[i]["target"]
			if _story.has_node(target) and shown.has(target):
				_graph_edit.connect_node(_gnode_name(id), i, _gnode_name(target), 0)

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


# ----------------------------------------------------------------- Actions

## Fin d'un drag : toute la disposition est sauvée dans le sidecar .meta.json
## (elle sert aussi de mise en page à la carte de progression en jeu).
func _save_positions() -> void:
	for child in _graph_edit.get_children():
		if child is GraphNode:
			_meta.set_node_position(_node_ids[String(child.name)], child.position_offset)
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
			var id: String = _node_ids[String(child.name)]
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
			positions[_node_ids[String(child.name)]] = child.position_offset
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
	if node is GraphNode and _node_ids.has(String(node.name)):
		_inspector.show_node(_make_context(_node_ids[String(node.name)]))


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


## Recharge le fichier (après une modification par l'inspecteur) et rouvre le
## même nœud, disposition conservée.
func reload_and_select(id: String) -> void:
	_load_selected()
	var gnode := _graph_edit.get_node_or_null(NodePath(_gnode_name(id)))
	if gnode is GraphNode:
		gnode.selected = true
		_inspector.show_node(_make_context(id))
