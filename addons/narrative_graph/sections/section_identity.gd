@tool
extends "res://addons/narrative_graph/inspector_section.gd"
## Volet « identité » : nom du nœud, tags, extrait du texte.


func setup(ctx: Dictionary) -> void:
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
