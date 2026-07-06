@tool
extends "res://addons/narrative_graph/inspector_section.gd"
## Volet « zones interactives » : dessine à la souris les polygones cliquables
## d'une illustration et les sauvegarde dans illustrations_defs.json (via
## IllustrationLibrary.save_layer_interactions). Les zones ne vivent PAS dans le
## .untold — elles appartiennent à l'illustration (cf. point 6).
##
## Pour chaque illustration du nœud (mêmes @illustration(...) que
## section_illustration) : choix du calque, aperçu, surface de dessin, champs de
## la zone (id, dialogue, objet), liste des zones existantes, bouton Enregistrer.

const PREVIEW_HEIGHT := 320.0

var _ctx: Dictionary


func setup(ctx: Dictionary) -> void:
	_ctx = ctx
	heading("Zones interactives")

	var names := _node_illustrations(ctx["node"])
	if names.is_empty():
		var none := Label.new()
		none.text = "Aucune illustration sur ce nœud (rien à zoner)."
		none.modulate = Color(0.55, 0.55, 0.65)
		add_child(none)
		return

	for name in names:
		_build_block(name)


## Noms passés aux commandes @illustration(...) du nœud, dans l'ordre (même
## logique que section_illustration).
func _node_illustrations(node: StoryNode) -> Array:
	var names: Array = []
	for ins in node.instructions:
		if ins["type"] == "command" and ins["name"] == "illustration" \
				and not ins["args"].is_empty():
			names.append(str(ins["args"][0]))
	return names


## Un bloc éditable par illustration. L'état mutable (calque courant, zones de
## travail, sous-conteneurs) vit dans un Dictionary capturé par les callbacks —
## permet plusieurs illustrations sur un même nœud sans collision d'état.
func _build_block(name: String) -> void:
	add_child(HSeparator.new())
	var defs := IllustrationLibrary.defs()
	if not defs.has(name):
		var missing := Label.new()
		missing.text = "« %s » inconnue de illustrations_defs.json." % name
		missing.modulate = Color(0.9, 0.5, 0.4)
		add_child(missing)
		return

	var idef: Dictionary = defs[name]
	var layers: Array = idef["layers"]

	var title := Label.new()
	title.text = name
	title.add_theme_font_size_override("font_size", 15)
	add_child(title)

	var state := {
		"name": name,
		"dir": str(idef["dir"]),
		"layers": layers,
		"entry": null,       # calque sélectionné (Dictionary)
		"zones": [],         # zones de travail du calque (Array de Dictionaries)
		"canvas": null,      # ZoneCanvas
		"list_box": null,    # VBox listant les zones existantes
		"fields": {},        # champs de saisie de la zone en cours
	}

	# --- Choix du calque ---
	var picker := OptionButton.new()
	for i in layers.size():
		picker.add_item("%s  (index %d)" % [
			IllustrationLibrary.layer_file(layers[i]), IllustrationLibrary.layer_index(layers[i])])
	add_child(picker)

	# --- Surface de dessin / aperçu ---
	var canvas := ZoneCanvas.new()
	canvas.custom_minimum_size = Vector2(0, PREVIEW_HEIGHT)
	state["canvas"] = canvas
	add_child(canvas)

	var hint := Label.new()
	hint.text = "Clic gauche : ajoute un point. Puis « Terminer la zone » (≥ 3 points)."
	hint.modulate = Color(0.55, 0.55, 0.62)
	add_child(hint)

	# --- Boutons de dessin ---
	var draw_row := HBoxContainer.new()
	add_child(draw_row)
	var finish := Button.new()
	finish.text = "Terminer la zone"
	finish.pressed.connect(_on_finish_polygon.bind(state))
	draw_row.add_child(finish)
	var cancel := Button.new()
	cancel.text = "Annuler les points"
	cancel.pressed.connect(func() -> void:
		state["canvas"].clear_current()
		_set_fields_visible(state, false))
	draw_row.add_child(cancel)

	# --- Champs de la zone (masqués tant qu'un polygone n'est pas clos) ---
	add_child(_build_fields(state))

	# --- Zones déjà définies sur ce calque ---
	var list_label := Label.new()
	list_label.text = "Zones du calque :"
	list_label.modulate = Color(0.7, 0.7, 0.8)
	add_child(list_label)
	var list_box := VBoxContainer.new()
	state["list_box"] = list_box
	add_child(list_box)

	# --- Enregistrer ---
	var save := Button.new()
	save.text = "Enregistrer les zones de ce calque"
	save.tooltip_text = "Écrit les zones dans illustrations_defs.json (les autres illustrations/calques sont préservés)."
	save.pressed.connect(_on_save.bind(state))
	add_child(save)

	picker.item_selected.connect(func(idx: int) -> void: _select_layer(state, layers[idx]))
	if not layers.is_empty():
		picker.select(0)
		_select_layer(state, layers[0])


## Sélectionne un calque : recharge la texture, les zones de travail (copie des
## zones existantes) et la liste.
func _select_layer(state: Dictionary, entry: Dictionary) -> void:
	state["entry"] = entry
	state["zones"] = []
	for z in IllustrationLibrary.layer_interactions(entry):
		if z is Dictionary:
			state["zones"].append(z.duplicate(true))
	var tex: Texture2D = load(state["dir"] + IllustrationLibrary.layer_file(entry))
	state["canvas"].set_texture(tex)
	state["canvas"].set_zones(state["zones"])
	state["canvas"].clear_current()
	_set_fields_visible(state, false)
	_refresh_zone_list(state)


func _build_fields(state: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.visible = false
	box.add_theme_constant_override("separation", 4)
	state["fields"]["box"] = box

	var id_edit := LineEdit.new()
	id_edit.placeholder_text = "id de la zone (pour zone_clicked(\"id\"))"
	state["fields"]["id"] = id_edit
	box.add_child(id_edit)

	var dlg_label := Label.new()
	dlg_label.text = "Lignes de dialogue (une par ligne) :"
	dlg_label.modulate = Color(0.65, 0.65, 0.75)
	box.add_child(dlg_label)
	var dialogue := TextEdit.new()
	dialogue.custom_minimum_size = Vector2(0, 70)
	state["fields"]["dialogue"] = dialogue
	box.add_child(dialogue)

	var obj_row := HBoxContainer.new()
	box.add_child(obj_row)
	var item_edit := LineEdit.new()
	item_edit.placeholder_text = "item_id (objet donné, optionnel)"
	item_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	state["fields"]["item_id"] = item_edit
	obj_row.add_child(item_edit)
	var qty := SpinBox.new()
	qty.min_value = 1
	qty.max_value = 99
	qty.value = 1
	state["fields"]["item_qty"] = qty
	obj_row.add_child(qty)

	var add := Button.new()
	add.text = "Ajouter la zone"
	add.pressed.connect(_on_add_zone.bind(state))
	box.add_child(add)
	return box


func _set_fields_visible(state: Dictionary, visible: bool) -> void:
	state["fields"]["box"].visible = visible


## « Terminer la zone » : valide le polygone en cours (≥ 3 points) et ouvre les
## champs pour le décrire.
func _on_finish_polygon(state: Dictionary) -> void:
	if state["canvas"].current_point_count() < 3:
		_ctx["editor"].set_status("Une zone demande au moins 3 points.")
		return
	_set_fields_visible(state, true)
	state["fields"]["id"].grab_focus()


## « Ajouter la zone » : construit la zone (polygone en cours + champs) et
## l'ajoute aux zones de travail, prête à être enregistrée.
func _on_add_zone(state: Dictionary) -> void:
	var polygon: Array = state["canvas"].current_normalized()
	if polygon.size() < 3:
		_ctx["editor"].set_status("Une zone demande au moins 3 points.")
		return
	var id: String = state["fields"]["id"].text.strip_edges()
	if id.is_empty():
		_ctx["editor"].set_status("Donne un id à la zone.")
		return
	var lines: Array = []
	for line in state["fields"]["dialogue"].text.split("\n"):
		if not line.strip_edges().is_empty():
			lines.append(line)
	state["zones"].append({
		"id": id,
		"polygon": polygon,
		"dialogue_lines": lines,
		"item_id": state["fields"]["item_id"].text.strip_edges(),
		"item_qty": int(state["fields"]["item_qty"].value),
	})
	# Réinitialise la saisie pour la zone suivante.
	state["fields"]["id"].text = ""
	state["fields"]["dialogue"].text = ""
	state["fields"]["item_id"].text = ""
	state["fields"]["item_qty"].value = 1
	state["canvas"].clear_current()
	state["canvas"].set_zones(state["zones"])
	_set_fields_visible(state, false)
	_refresh_zone_list(state)
	_ctx["editor"].set_status("Zone « %s » ajoutée (pense à Enregistrer)." % id)


## Reconstruit la liste des zones du calque (id + résumé des effets + suppression).
func _refresh_zone_list(state: Dictionary) -> void:
	var box: VBoxContainer = state["list_box"]
	for child in box.get_children():
		child.queue_free()
	if state["zones"].is_empty():
		var empty := Label.new()
		empty.text = "(aucune zone)"
		empty.modulate = Color(0.5, 0.5, 0.6)
		box.add_child(empty)
		return
	for i in state["zones"].size():
		var zone: Dictionary = state["zones"][i]
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "• %s  %s" % [str(zone.get("id", "?")), _zone_summary(zone)]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		row.add_child(label)
		var del := Button.new()
		del.text = "Suppr."
		del.pressed.connect(_on_delete_zone.bind(state, i))
		row.add_child(del)
		box.add_child(row)


func _zone_summary(zone: Dictionary) -> String:
	var parts: Array = ["%d pts" % (zone.get("polygon", []) as Array).size()]
	var lines: Array = zone.get("dialogue_lines", [])
	if not lines.is_empty():
		parts.append("%d ligne(s)" % lines.size())
	var item: String = str(zone.get("item_id", ""))
	if not item.is_empty():
		parts.append("objet %s×%d" % [item, int(zone.get("item_qty", 1))])
	return "(" + ", ".join(PackedStringArray(parts)) + ")"


func _on_delete_zone(state: Dictionary, index: int) -> void:
	if index < 0 or index >= state["zones"].size():
		return
	state["zones"].remove_at(index)
	state["canvas"].set_zones(state["zones"])
	_refresh_zone_list(state)


func _on_save(state: Dictionary) -> void:
	if state["entry"] == null:
		return
	var idx: int = IllustrationLibrary.layer_index(state["entry"])
	if IllustrationLibrary.save_layer_interactions(state["name"], idx, state["zones"]):
		_ctx["editor"].set_status("Zones de « %s » (calque %d) enregistrées." % [state["name"], idx])
	else:
		_ctx["editor"].set_status("Échec de l'enregistrement des zones.")


# ------------------------------------------------------- Surface de dessin

## Aperçu du calque + dessin des polygones. La texture est ajustée (aspect-fit)
## dans le Control, potentiellement plus grand : les clics sont normalisés [0,1]
## par rapport au RECTANGLE RÉEL de la texture affichée, pas au Control.
class ZoneCanvas extends Control:
	var _tex: Texture2D
	var _zones: Array = []       # zones (Dictionaries, polygones normalisés)
	var _current: Array = []      # points en cours (Vector2 normalisés)

	func set_texture(t: Texture2D) -> void:
		_tex = t
		queue_redraw()

	func set_zones(z: Array) -> void:
		_zones = z
		queue_redraw()

	func clear_current() -> void:
		_current = []
		queue_redraw()

	func current_point_count() -> int:
		return _current.size()

	## Points en cours au format JSON zone : [[x, y], ...] normalisés.
	func current_normalized() -> Array:
		var out: Array = []
		for p in _current:
			out.append([p.x, p.y])
		return out

	## Rectangle réellement occupé par la texture (aspect-fit centré) dans le Control.
	func _fitted_rect() -> Rect2:
		if _tex == null:
			return Rect2(Vector2.ZERO, size)
		var ts := Vector2(_tex.get_size())
		if ts.x <= 0.0 or ts.y <= 0.0:
			return Rect2(Vector2.ZERO, size)
		var scale := minf(size.x / ts.x, size.y / ts.y)
		var draw_size := ts * scale
		return Rect2((size - draw_size) * 0.5, draw_size)

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var r := _fitted_rect()
			if r.size.x <= 0.0 or r.size.y <= 0.0:
				return
			var n: Vector2 = (mb.position - r.position) / r.size
			_current.append(Vector2(clampf(n.x, 0.0, 1.0), clampf(n.y, 0.0, 1.0)))
			queue_redraw()
			accept_event()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.08, 0.1))
		var r := _fitted_rect()
		if _tex != null:
			draw_texture_rect(_tex, r, false)
		for zone in _zones:
			_draw_polygon(zone.get("polygon", []), r, Color(0.4, 0.8, 1.0, 0.85), true)
		_draw_polygon(current_normalized(), r, Color(1.0, 0.8, 0.3, 0.95), false)
		for p in _current:
			draw_circle(r.position + p * r.size, 3.0, Color(1.0, 0.8, 0.3))

	func _draw_polygon(norm_points: Array, r: Rect2, col: Color, closed: bool) -> void:
		if norm_points.size() < 2:
			return
		var pts := PackedVector2Array()
		for p in norm_points:
			pts.append(r.position + Vector2(float(p[0]), float(p[1])) * r.size)
		for i in pts.size() - 1:
			draw_line(pts[i], pts[i + 1], col, 2.0)
		if closed and pts.size() >= 3:
			draw_line(pts[pts.size() - 1], pts[0], col, 2.0)
