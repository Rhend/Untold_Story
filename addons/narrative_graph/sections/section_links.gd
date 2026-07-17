@tool
extends "res://addons/narrative_graph/inspector_section.gd"
## Volet « sorties » : chaque lien sortant du nœud avec sa cible dans un champ
## éditable. Valider (Entrée, ou quitter le champ) réécrit la cible dans le
## fichier .untold — seule la cible change, le reste de la ligne est intact.


func setup(ctx: Dictionary) -> void:
	heading("Sorties")

	var links: Array = ctx["graph"].outgoing(ctx["node_id"])
	if links.is_empty():
		var none := Label.new()
		none.text = "(aucune — nœud terminal)"
		none.modulate = Color(0.55, 0.55, 0.65)
		add_child(none)
	for i in links.size():
		add_child(_make_row(ctx, i, links[i]))

	_add_new_link_form(ctx)


func _make_row(ctx: Dictionary, index: int, link: Dictionary) -> Control:
	var row := VBoxContainer.new()

	var caption := Label.new()
	caption.text = _caption(link)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.modulate = Color(0.7, 0.7, 0.8)
	row.add_child(caption)

	var edit := LineEdit.new()
	edit.text = link["target"]
	edit.tooltip_text = "Id du nœud cible (ou END). Entrée pour réécrire le lien dans le .untold."
	edit.text_submitted.connect(func(_text: String) -> void:
		_apply(ctx, index, edit, link["target"]))
	edit.focus_exited.connect(func() -> void:
		_apply(ctx, index, edit, link["target"]))
	row.add_child(edit)
	return row


func _caption(link: Dictionary) -> String:
	var guard_prefix := "{…} " if link["guarded"] else ""
	match link["kind"]:
		"choice":
			return guard_prefix + "▸ " + link["text"]
		"cond":
			return guard_prefix + "→ saut conditionnel"
		_:
			return guard_prefix + "→ saut direct"


## Formulaire d'ajout guidé : un texte (vide = saut direct « -> cible »)
## et une cible choisie dans la liste des nœuds (+ END) — la ligne est
## écrite en fin de bloc, sans toucher au reste.
func _add_new_link_form(ctx: Dictionary) -> void:
	add_child(HSeparator.new())
	var caption := Label.new()
	caption.text = "Ajouter une sortie :"
	caption.modulate = Color(0.7, 0.7, 0.8)
	add_child(caption)

	var text_edit := LineEdit.new()
	text_edit.placeholder_text = "Texte du choix (vide = saut direct)"
	add_child(text_edit)

	var row := HBoxContainer.new()
	add_child(row)
	var target := OptionButton.new()
	target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target.fit_to_longest_item = false
	target.add_item("END")
	for id in ctx["source"].order:
		if id != ctx["node_id"] and ctx["story"].has_node(id):
			target.add_item(id)
	row.add_child(target)

	var add := Button.new()
	add.text = "Ajouter"
	add.tooltip_text = "Écrit « * [Texte] -> cible » (ou « -> cible » sans texte) en fin de bloc."
	add.pressed.connect(func() -> void:
		var target_id := target.get_item_text(target.selected)
		# Des crochets dans le texte casseraient « * [texte] -> cible ».
		var choice_text := text_edit.text.strip_edges().replace("[", "(").replace("]", ")")
		var line := "-> " + target_id if choice_text.is_empty() \
				else "* [%s] -> %s" % [choice_text, target_id]
		ctx["source"].append_instruction(ctx["node_id"], line)
		if ctx["source"].save():
			ctx["editor"].set_status("Sortie ajoutée à %s : %s" % [ctx["node_id"], line])
			ctx["editor"].reload_and_select(ctx["node_id"])
		else:
			ctx["editor"].set_status("Échec d'écriture du fichier source."))
	row.add_child(add)


func _apply(ctx: Dictionary, index: int, edit: LineEdit, old_target: String) -> void:
	var target := edit.text.strip_edges()
	if target.is_empty() or target == old_target or edit.get_meta("applied", false):
		return
	# Marqué AVANT l'écriture : focus_exited re-déclenche _apply juste après
	# text_submitted (le reload vole le focus), il ne doit pas réécrire.
	edit.set_meta("applied", true)
	var known: bool = target == "END" or ctx["story"].has_node(target)
	if not ctx["source"].set_link_target(ctx["node_id"], index, target) \
			or not ctx["source"].save():
		# Échec : on dé-marque pour qu'une correction du champ reste possible.
		edit.set_meta("applied", false)
		ctx["editor"].set_status("Impossible de réécrire ce lien dans le fichier.")
		return
	if known:
		ctx["editor"].set_status("Lien de %s réécrit → %s." % [ctx["node_id"], target])
	else:
		ctx["editor"].set_status(
				"Lien réécrit → %s — attention, ce nœud n'existe pas (encore)." % target)
	ctx["editor"].reload_and_select(ctx["node_id"])
