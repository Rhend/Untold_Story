class_name StoryParser
extends RefCounted
## Parse le format texte maison ".untold" en une ressource Story.
## Voir FORMAT.md pour la spécification complète du langage.

static func parse(text: String) -> Story:
	var story := Story.new()
	var current: StoryNode = null

	var re_choice := RegEx.new()
	re_choice.compile("^\\*\\s*\\[(.*?)\\]\\s*->\\s*(\\S+)$")
	var re_cond := RegEx.new()
	re_cond.compile("^\\{\\s*([A-Za-z_]\\w*)\\s*==\\s*\"([^\"]*)\"\\s*->\\s*(\\S+)\\s*\\}$")
	var re_cmd := RegEx.new()
	re_cmd.compile("^@([A-Za-z_]\\w*)\\((.*)\\)$")
	var re_assign := RegEx.new()
	re_assign.compile("^@(?:var|set)\\s+([A-Za-z_]\\w*)\\s*=\\s*(.+)$")

	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()

		# Lignes ignorées : vides et commentaires.
		if line.is_empty() or line.begins_with("//"):
			continue

		# Déclaration d'un nœud : ":: id"
		if line.begins_with("::"):
			current = StoryNode.new(line.substr(2).strip_edges())
			story.add_node(current)
			continue

		# Variable globale : "@var nom = valeur" (avant tout nœud).
		if line.begins_with("@var"):
			var mv := re_assign.search(line)
			if mv:
				story.variables[mv.get_string(1)] = _unquote(mv.get_string(2))
			continue

		# Tout le reste appartient au nœud courant.
		if current == null:
			push_warning("StoryParser: ligne hors de tout nœud ignorée : " + line)
			continue

		# Tags : "#Nadîtum #Soldat ..."
		if line.begins_with("#"):
			for tag in line.split(" ", false):
				current.tags.append(tag.lstrip("#"))
			continue

		# Choix : "* [Texte affiché] -> noeud_cible"
		var mc := re_choice.search(line)
		if mc:
			current.instructions.append({
				"type": "choice",
				"text": mc.get_string(1).strip_edges(),
				"target": mc.get_string(2),
			})
			continue

		# Saut conditionnel : '{ var == "valeur" -> noeud }'
		var mco := re_cond.search(line)
		if mco:
			current.instructions.append({
				"type": "cond",
				"var": mco.get_string(1),
				"value": mco.get_string(2),
				"target": mco.get_string(3),
			})
			continue

		# Saut direct : "-> noeud" (ou "-> END")
		if line.begins_with("->"):
			current.instructions.append({
				"type": "divert",
				"target": line.substr(2).strip_edges(),
			})
			continue

		# Affectation : "@set nom = valeur"
		if line.begins_with("@set"):
			var ms := re_assign.search(line)
			if ms:
				current.instructions.append({
					"type": "set",
					"name": ms.get_string(1),
					"value": _unquote(ms.get_string(2)),
				})
			continue

		# Commande moteur : '@nom("arg1", "arg2")' (ex: illustration, minigame)
		if line.begins_with("@"):
			var mcmd := re_cmd.search(line)
			if mcmd:
				current.instructions.append({
					"type": "command",
					"name": mcmd.get_string(1),
					"args": _parse_args(mcmd.get_string(2)),
				})
			continue

		# Sinon : ligne de texte narratif.
		current.instructions.append({"type": "text", "value": line})

	return story


static func _unquote(s: String) -> String:
	var t := s.strip_edges()
	if t.length() >= 2 and t.begins_with("\"") and t.ends_with("\""):
		return t.substr(1, t.length() - 2)
	return t


static func _parse_args(s: String) -> Array:
	var args: Array = []
	if s.strip_edges().is_empty():
		return args
	for part in s.split(","):
		args.append(_unquote(part))
	return args
