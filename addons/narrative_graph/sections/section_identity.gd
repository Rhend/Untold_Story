@tool
extends "res://addons/narrative_graph/inspector_section.gd"
## Volet « identité » : nom du nœud (renommable — les liens et visited() du
## fichier suivent), tags, extrait du texte, bascule du tag #hors_carte
## (exclusion de la carte de progression en jeu), et suppression du nœud.

var _ctx: Dictionary


func setup(ctx: Dictionary) -> void:
	_ctx = ctx
	heading("Nœud")

	_add_rename_row(ctx["node_id"])
	_add_title_row(ctx["node_id"])

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
	_add_delete_button(ctx["node_id"])


## Nom du nœud dans un champ éditable : valider renomme le nœud dans le
## .untold (sa ligne « :: id », toutes les cibles « -> id » et les gardes
## « visited(id) ») et fait suivre les métadonnées (position, commentaire...).
func _add_rename_row(id: String) -> void:
	var row := HBoxContainer.new()
	add_child(row)

	var edit := LineEdit.new()
	edit.text = id
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.add_theme_font_size_override("font_size", 19)
	edit.tooltip_text = "Nom du nœud. Entrée (ou « Renommer ») pour renommer partout dans le fichier."
	row.add_child(edit)

	var btn := Button.new()
	btn.text = "Renommer"
	row.add_child(btn)

	var apply := func() -> void:
		var new_id := edit.text.strip_edges()
		if new_id == id or new_id.is_empty():
			return
		if not _ctx["source"].is_valid_id(new_id):
			_ctx["editor"].set_status("Id invalide « %s » — lettres, chiffres et _ seulement (et pas END)." % new_id)
			return
		if _ctx["story"].has_node(new_id):
			_ctx["editor"].set_status("Un nœud « %s » existe déjà." % new_id)
			return
		if _ctx["source"].rename_node(id, new_id) and _ctx["source"].save():
			_ctx["meta"].rename_node(id, new_id)
			_ctx["meta"].save()
			_ctx["editor"].set_status("« %s » renommé en « %s » (liens et visited() mis à jour)." % [id, new_id])
			_ctx["editor"].reload_and_select(new_id)
		else:
			_ctx["editor"].set_status("Impossible de renommer ce nœud.")
	btn.pressed.connect(apply)
	edit.text_submitted.connect(func(_t: String) -> void: apply.call())


## Titre lisible affiché au joueur (carte de progression, en-tête de page) à la
## place de l'id technique. Vit dans le sidecar .meta.json — optionnel.
func _add_title_row(id: String) -> void:
	var edit := LineEdit.new()
	edit.text = _ctx["meta"].get_title(id)
	edit.placeholder_text = "Titre affiché au joueur (optionnel)"
	edit.tooltip_text = "Montré en jeu (carte, en-tête) à la place de l'id technique. Vide = l'id est affiché."
	add_child(edit)

	var apply := func() -> void:
		if edit.text.strip_edges() == _ctx["meta"].get_title(id):
			return
		_ctx["meta"].set_title(id, edit.text)
		_ctx["meta"].save()
		_ctx["editor"].set_status("Titre de %s : %s" % [id,
				"« %s »" % edit.text.strip_edges() if not edit.text.strip_edges().is_empty() else "(effacé)"])
	edit.text_submitted.connect(func(_t: String) -> void: apply.call())
	edit.focus_exited.connect(apply)


## Suppression du nœud, avec confirmation qui liste les liens entrants (ils
## resteraient en l'état, cibles inconnues à corriger ensuite).
func _add_delete_button(id: String) -> void:
	add_child(HSeparator.new())
	var btn := Button.new()
	btn.text = "Supprimer ce nœud"
	btn.modulate = Color(1.0, 0.75, 0.7)
	btn.tooltip_text = "Retire le bloc du .untold (confirmation demandée)."
	add_child(btn)

	var incoming: Array = []
	for other_id in _ctx["story"].nodes:
		if other_id == id:
			continue
		for link in _ctx["graph"].outgoing(other_id):
			if link["target"] == id and not incoming.has(other_id):
				incoming.append(other_id)

	var confirm := ConfirmationDialog.new()
	confirm.title = "Supprimer « %s » ?" % id
	confirm.ok_button_text = "Supprimer"
	confirm.dialog_text = "Le bloc sera retiré du fichier .untold." if incoming.is_empty() \
			else "%d nœud(s) pointent vers lui (%s) :\nleurs liens resteront en l'état, avec une cible inconnue à corriger." \
			% [incoming.size(), ", ".join(PackedStringArray(incoming))]
	add_child(confirm)
	btn.pressed.connect(confirm.popup_centered)
	confirm.confirmed.connect(func() -> void:
		if _ctx["source"].remove_node(id) and _ctx["source"].save():
			_ctx["meta"].forget_node(id)
			_ctx["meta"].save()
			_ctx["editor"].set_status("Nœud « %s » supprimé%s." % [id,
					"" if incoming.is_empty() else " — corrige les liens de : " + ", ".join(PackedStringArray(incoming))])
			_ctx["editor"].reload()
		else:
			_ctx["editor"].set_status("Impossible de supprimer ce nœud."))


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
