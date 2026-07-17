@tool
extends "res://addons/narrative_graph/inspector_section.gd"
## Volet « contenu » : le corps du bloc du nœud (source .untold, verbatim, sans
## la ligne « :: id ») dans un éditeur de texte — Enregistrer réécrit le bloc
## dans le fichier. C'est le volet d'écriture au quotidien : texte narratif,
## choix, sauts, commandes, tout s'édite ici sans quitter Godot.


func setup(ctx: Dictionary) -> void:
	heading("Contenu (source .untold)")

	var edit := TextEdit.new()
	edit.text = "\n".join(PackedStringArray(ctx["source"].body_lines(ctx["node_id"])))
	edit.custom_minimum_size = Vector2(0, 190)
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.tooltip_text = "Le bloc du nœud, tel qu'écrit dans le fichier (sans la ligne « :: id »)."
	add_child(edit)

	var hint := Label.new()
	hint.text = "Une ligne = une instruction : texte, « * [Choix] -> cible », « -> cible », « @commande(\"...\") », « { garde } instruction »."
	hint.modulate = Color(0.55, 0.55, 0.62)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)

	var save := Button.new()
	save.text = "Enregistrer le contenu"
	save.tooltip_text = "Réécrit le bloc de ce nœud dans le .untold (le reste du fichier est intact)."
	save.pressed.connect(func() -> void:
		if ctx["source"].set_body(ctx["node_id"], edit.text.split("\n")) \
				and ctx["source"].save():
			ctx["editor"].set_status("Contenu de %s enregistré." % ctx["node_id"])
			ctx["editor"].reload_and_select(ctx["node_id"])
		else:
			ctx["editor"].set_status("Impossible d'enregistrer le contenu."))
	add_child(save)
