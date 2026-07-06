@tool
extends "res://addons/narrative_graph/inspector_section.gd"
## Volet « illustration » : montre l'illustration associée au nœud (nom +
## petite preview) et accepte le glisser-déposer d'une image ou d'un dossier
## depuis le dock Système de fichiers — le fichier déposé est rattaché à
## l'illustration de la bibliothèque dont le dossier le contient, et
## « @illustration("Nom") » est écrite (ou remplacée) dans le bloc du nœud.

const PREVIEW_HEIGHT := 130.0

var _ctx: Dictionary


func setup(ctx: Dictionary) -> void:
	_ctx = ctx
	heading("Illustration")

	var names := _node_illustrations(ctx["node"])
	if names.is_empty():
		var none := Label.new()
		none.text = "(aucune)"
		none.modulate = Color(0.55, 0.55, 0.65)
		add_child(none)
	for i in names.size():
		_add_preview(names[i], i)

	var hint := Label.new()
	hint.text = "Glisser ici une image (ou un dossier)\ndepuis le Système de fichiers pour associer l'illustration."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(0.5, 0.5, 0.62)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var drop_zone := PanelContainer.new()
	drop_zone.custom_minimum_size = Vector2(0, 56)
	drop_zone.add_child(hint)
	add_child(drop_zone)


## Noms passés aux commandes @illustration(...) du nœud, dans l'ordre.
func _node_illustrations(node: StoryNode) -> Array:
	var names: Array = []
	for ins in node.instructions:
		if ins["type"] == "command" and ins["name"] == "illustration" \
				and not ins["args"].is_empty():
			names.append(str(ins["args"][0]))
	return names


func _add_preview(illustration_name: String, occurrence: int) -> void:
	var row := HBoxContainer.new()
	add_child(row)

	var title := Label.new()
	title.text = illustration_name
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)

	var remove := Button.new()
	remove.text = "Retirer"
	remove.tooltip_text = "Supprime la ligne @illustration de ce nœud dans le .untold."
	remove.pressed.connect(_remove_illustration.bind(occurrence, illustration_name))
	row.add_child(remove)

	if not IllustrationLibrary.defs().has(illustration_name):
		title.text += "  (inconnue de la bibliothèque !)"
		title.modulate = Color(0.9, 0.5, 0.4)
		title.tooltip_text = "Aucune entrée dans illustrations_defs.json de l'histoire."
		return

	var texture := _preview_texture(illustration_name)
	if texture == null:
		return
	var preview := TextureRect.new()
	preview.texture = texture
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.custom_minimum_size = Vector2(0, PREVIEW_HEIGHT)
	preview.tooltip_text = illustration_name
	add_child(preview)


## Texture de preview : le fichier « ...Preview... » du dossier de
## l'illustration s'il existe, sinon son premier calque.
func _preview_texture(illustration_name: String) -> Texture2D:
	var def: Dictionary = IllustrationLibrary.defs()[illustration_name]
	var dir_path: String = def["dir"]
	var dir := DirAccess.open(dir_path)
	if dir != null:
		for file in dir.get_files():
			if file.contains("Preview") and not file.ends_with(".import"):
				return load(dir_path + file)
	if def["layers"].is_empty():
		return null
	return load(dir_path + def["layers"][0][0])


func _remove_illustration(occurrence: int, illustration_name: String) -> void:
	if _ctx["source"].remove_command(_ctx["node_id"], "illustration", occurrence) \
			and _ctx["source"].save():
		_ctx["editor"].set_status(
				"Illustration « %s » retirée de %s." % [illustration_name, _ctx["node_id"]])
		_ctx["editor"].reload_and_select(_ctx["node_id"])
	else:
		_ctx["editor"].set_status("Impossible de retirer cette illustration.")


# ------------------------------------------------------------- Drag & drop

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return data is Dictionary \
			and str(data.get("type", "")) in ["files", "files_and_dirs"] \
			and not data.get("files", []).is_empty()


func _drop_data(_position: Vector2, data: Variant) -> void:
	var path := str(data["files"][0])
	var illustration_name := _name_for_path(path)
	if illustration_name.is_empty():
		_ctx["editor"].set_status(
				"« %s » n'appartient à aucune illustration de la bibliothèque (core/illustration/illustration_library.gd)."
				% path.get_file())
		return
	if _ctx["source"].set_command(_ctx["node_id"], "illustration", [illustration_name]) \
			and _ctx["source"].save():
		_ctx["editor"].set_status("Illustration de %s : %s." % [_ctx["node_id"], illustration_name])
		_ctx["editor"].reload_and_select(_ctx["node_id"])
	else:
		_ctx["editor"].set_status("Échec d'écriture du fichier source.")


## Illustration de la bibliothèque dont le dossier contient ce chemin
## (fichier d'un calque, preview, ou dossier de l'illustration lui-même).
func _name_for_path(path: String) -> String:
	var defs := IllustrationLibrary.defs()
	for name in defs:
		var dir: String = defs[name]["dir"]
		if path.begins_with(dir) or dir.trim_suffix("/") == path.trim_suffix("/"):
			return name
	return ""
