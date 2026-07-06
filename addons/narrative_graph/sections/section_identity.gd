@tool
extends "res://addons/narrative_graph/inspector_section.gd"
## Volet « identité » : nom du nœud, tags, extrait du texte, et bascule du tag
## #hors_carte (exclusion de la carte de progression en jeu).

var _ctx: Dictionary


func setup(ctx: Dictionary) -> void:
	_ctx = ctx
	heading("Nœud")

	var id_label := Label.new()
	id_label.text = ctx["node_id"]
	id_label.add_theme_font_size_override("font_size", 19)
	add_child(id_label)

	var node: StoryNode = ctx["node"]
	if not node.tags.is_empty():
		var tags := Label.new()
		tags.text = "#" + "  #".join(PackedStringArray(node.tags))
		tags.modulate = Color(0.6, 0.6, 0.75)
		tags.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(tags)

	for ins in node.instructions:
		if ins["type"] == "text":
			var excerpt := Label.new()
			excerpt.text = "« %s »" % ins["value"]
			excerpt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			excerpt.modulate = Color(0.75, 0.72, 0.62)
			add_child(excerpt)
			break

	_add_hors_carte_toggle(node)


## Bascule le tag #hors_carte via la source .untold. Le libellé et l'état
## affiché reflètent l'état courant du tag sur le nœud.
func _add_hors_carte_toggle(node: StoryNode) -> void:
	add_child(HSeparator.new())
	var present := "hors_carte" in node.tags

	var state := Label.new()
	state.text = "Carte de progression : exclu (#hors_carte)" if present \
			else "Carte de progression : visible"
	state.modulate = Color(0.9, 0.62, 0.5) if present else Color(0.6, 0.72, 0.6)
	add_child(state)

	var btn := Button.new()
	btn.text = "Réintégrer à la carte" if present else "Retirer de la carte (#hors_carte)"
	btn.tooltip_text = "Ajoute ou retire le tag #hors_carte dans le .untold. Un nœud hors carte n'apparaît jamais sur la carte de progression en jeu — sans effet sur le récit."
	btn.pressed.connect(_toggle_hors_carte)
	add_child(btn)


func _toggle_hors_carte() -> void:
	var source = _ctx["source"]
	var id: String = _ctx["node_id"]
	var present: bool = source.has_tag(id, "hors_carte")
	var ok: bool = source.remove_tag(id, "hors_carte") if present \
			else source.add_tag(id, "hors_carte")
	if ok and source.save():
		_ctx["editor"].set_status(
				"%s %s la carte de progression." % [id, "réintégré à" if present else "retiré de"])
		_ctx["editor"].reload_and_select(id)
	else:
		_ctx["editor"].set_status("Impossible de modifier le tag #hors_carte.")
