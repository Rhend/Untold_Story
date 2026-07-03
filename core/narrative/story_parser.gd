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
	# Garde : "{ cond [and cond...] } instruction" — la condition s'applique à
	# l'instruction qui suit sur la même ligne (texte, choix, saut, commande...).
	var re_guard := RegEx.new()
	re_guard.compile("^\\{\\s*([^{}]+?)\\s*\\}\\s*(\\S.*)$")

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

		# Garde éventuelle : "{ cond } instruction" — extraite, le reste de la
		# ligne est parsé normalement et la condition attachée à l'instruction.
		# (Le saut conditionnel historique '{ ... -> noeud }' n'est pas concerné :
		# rien ne suit son accolade fermante.)
		var guard: Array = []
		var mg := re_guard.search(line)
		if mg:
			guard = _parse_conds(mg.get_string(1))
			if guard.is_empty():
				push_warning("StoryParser: condition illisible ignorée : " + line)
			line = mg.get_string(2).strip_edges()

		# Choix : "* [Texte affiché] -> noeud_cible"
		var mc := re_choice.search(line)
		if mc:
			_append(current, {
				"type": "choice",
				"text": mc.get_string(1).strip_edges(),
				"target": mc.get_string(2),
			}, guard)
			continue

		# Saut conditionnel : '{ var == "valeur" -> noeud }'
		var mco := re_cond.search(line)
		if mco:
			_append(current, {
				"type": "cond",
				"var": mco.get_string(1),
				"value": mco.get_string(2),
				"target": mco.get_string(3),
			}, guard)
			continue

		# Saut direct : "-> noeud" (ou "-> END")
		if line.begins_with("->"):
			_append(current, {
				"type": "divert",
				"target": line.substr(2).strip_edges(),
			}, guard)
			continue

		# Affectation : "@set nom = valeur"
		if line.begins_with("@set"):
			var ms := re_assign.search(line)
			if ms:
				_append(current, {
					"type": "set",
					"name": ms.get_string(1),
					"value": _unquote(ms.get_string(2)),
				}, guard)
			continue

		# Commande moteur : '@nom("arg1", "arg2")' (ex: illustration, minigame)
		if line.begins_with("@"):
			var mcmd := re_cmd.search(line)
			if mcmd:
				_append(current, {
					"type": "command",
					"name": mcmd.get_string(1),
					"args": _parse_args(mcmd.get_string(2)),
				}, guard)
			continue

		# Sinon : ligne de texte narratif.
		_append(current, {"type": "text", "value": line}, guard)

	return story


static func _append(node: StoryNode, ins: Dictionary, guard: Array) -> void:
	if not guard.is_empty():
		ins["if"] = guard
	node.instructions.append(ins)


## Parse une expression booléenne en forme disjonctive : "or" sépare des
## groupes de conditions liées par "and" (précédence usuelle, pas de
## parenthèses). Retourne une liste de groupes, chaque groupe étant une liste
## de conditions :
##   var == "valeur"   → {"kind": "var", "name", "op": "==", "value"}
##   var != "valeur"   → {"kind": "var", "name", "op": "!=", "value"}
##   visited(noeud)    → {"kind": "visited", "id", "neg": false}
##   !visited(noeud)   → {"kind": "visited", "id", "neg": true}
## Retourne [] si une des conditions est illisible.
static func _parse_conds(s: String) -> Array:
	var re_var := RegEx.new()
	re_var.compile("^([A-Za-z_]\\w*)\\s*(==|!=)\\s*\"([^\"]*)\"$")
	var re_visited := RegEx.new()
	re_visited.compile("^(!)?\\s*visited\\(\\s*(\\S+?)\\s*\\)$")

	var groups: Array = []
	for group_src in s.split(" or "):
		var conds: Array = []
		for part in group_src.split(" and "):
			part = part.strip_edges()
			var mv := re_var.search(part)
			if mv:
				conds.append({
					"kind": "var",
					"name": mv.get_string(1),
					"op": mv.get_string(2),
					"value": mv.get_string(3),
				})
				continue
			var mt := re_visited.search(part)
			if mt:
				conds.append({
					"kind": "visited",
					"id": mt.get_string(2),
					"neg": mt.get_string(1) == "!",
				})
				continue
			return []
		groups.append(conds)
	return groups


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
