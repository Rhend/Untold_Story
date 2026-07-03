@tool
extends "res://addons/narrative_graph/inspector_section.gd"
## Volet « events » : liste les commandes moteur du nœud (@illustration,
## @minigame, ...) et permet d'en ajouter — la ligne est écrite dans le bloc
## du nœud, directement dans le fichier .untold.


func setup(ctx: Dictionary) -> void:
	heading("Events (commandes moteur)")

	var node: StoryNode = ctx["node"]
	var found := false
	for ins in node.instructions:
		if ins["type"] != "command":
			continue
		found = true
		var line := Label.new()
		var args := PackedStringArray()
		for arg in ins["args"]:
			args.append('"%s"' % arg)
		line.text = "@%s(%s)" % [ins["name"], ", ".join(args)]
		if ins.has("if"):
			line.text = "{…} " + line.text
			line.tooltip_text = "Event sous condition (garde)."
		line.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		add_child(line)
	if not found:
		var none := Label.new()
		none.text = "(aucun)"
		none.modulate = Color(0.55, 0.55, 0.65)
		add_child(none)

	# ---- Ajout d'un event ----
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "nom (ex: illustration)"
	add_child(name_edit)

	var args_edit := LineEdit.new()
	args_edit.placeholder_text = "arguments, séparés par des virgules"
	add_child(args_edit)

	var add := Button.new()
	add.text = "Ajouter l'event au .untold"
	add.pressed.connect(func() -> void:
		var command := name_edit.text.strip_edges()
		if command.is_empty():
			ctx["editor"].set_status("Nom d'event manquant.")
			return
		var quoted := PackedStringArray()
		for part in args_edit.text.split(",", false):
			quoted.append('"%s"' % part.strip_edges())
		var line := "@%s(%s)" % [command, ", ".join(quoted)]
		ctx["source"].append_instruction(ctx["node_id"], line)
		if ctx["source"].save():
			ctx["editor"].set_status("Event ajouté à %s : %s" % [ctx["node_id"], line])
			ctx["editor"].reload_and_select(ctx["node_id"])
		else:
			ctx["editor"].set_status("Échec d'écriture du fichier source."))
	add_child(add)
