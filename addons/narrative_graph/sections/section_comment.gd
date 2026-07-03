@tool
extends "res://addons/narrative_graph/inspector_section.gd"
## Volet « commentaire » : note libre sur le nœud, stockée dans le sidecar
## .meta.json — elle n'apparaît NULLE PART ailleurs que dans cet outil
## (ni dans le .untold, ni en jeu).


func setup(ctx: Dictionary) -> void:
	heading("Commentaire (privé à l'outil)")

	var edit := TextEdit.new()
	edit.text = ctx["meta"].get_comment(ctx["node_id"])
	edit.custom_minimum_size = Vector2(0, 110)
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	add_child(edit)

	var save := Button.new()
	save.text = "Enregistrer le commentaire"
	save.pressed.connect(func() -> void:
		ctx["meta"].set_comment(ctx["node_id"], edit.text)
		ctx["meta"].save()
		ctx["editor"].set_status("Commentaire enregistré pour %s." % ctx["node_id"]))
	add_child(save)
