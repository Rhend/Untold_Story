@tool
class_name StoryParser
extends RefCounted
## Parse le format texte maison ".untold" en une ressource Story.
## Voir FORMAT.md pour la spécification complète du langage.

## Motifs de reconnaissance des lignes, PARTAGÉS avec l'outil d'édition
## (UntoldSource repère les mêmes lignes pour les réécrire) : une divergence
## entre le parse et l'édition ferait modifier la mauvaise ligne.
const CHOICE_PATTERN := "^\\*\\s*\\[(.*?)\\]\\s*->\\s*(\\S+)$"
const COND_PATTERN := "^\\{\\s*([A-Za-z_]\\w*)\\s*(==|!=|<=|>=|<|>)\\s*(\"[^\"]*\"|-?\\d+(?:\\.\\d+)?)\\s*->\\s*(\\S+)\\s*\\}$"
const COMMAND_PATTERN := "^@([A-Za-z_]\\w*)\\((.*)\\)$"
## « += » et « -= » avant « = » : l'alternative la plus longue doit gagner.
const ASSIGN_PATTERN := "^@(?:var|set)\\s+([A-Za-z_]\\w*)\\s*(\\+=|-=|=)\\s*(.+)$"
## Garde : "{ cond [and cond...] } instruction" — la condition s'applique à
## l'instruction qui suit sur la même ligne (texte, choix, saut, commande...).
const GUARD_PATTERN := "^\\{\\s*([^{}]+?)\\s*\\}\\s*(\\S.*)$"

## Conditions de garde, compilées UNE fois (_parse_conds tourne pour chaque
## garde du fichier). « nom op valeur » reprend le sous-langage de
## COND_PATTERN — toute évolution doit toucher les deux.
static var _re_cond_var := RegEx.create_from_string(
		"^([A-Za-z_]\\w*)\\s*(==|!=|<=|>=|<|>)\\s*(\"[^\"]*\"|-?\\d+(?:\\.\\d+)?)$")
static var _re_cond_visited := RegEx.create_from_string("^(!)?\\s*visited\\(\\s*(\\S+?)\\s*\\)$")
static var _re_cond_zone := RegEx.create_from_string("^(!)?\\s*zone_clicked\\(\\s*\"([^\"]*)\"\\s*\\)$")
static var _re_cond_item := RegEx.create_from_string(
		"^(!)?\\s*has_item\\(\\s*\"([^\"]*)\"\\s*(?:,\\s*(\\d+)\\s*)?\\)$")


static func parse(text: String) -> Story:
	var story := Story.new()
	var current: StoryNode = null

	var re_choice := RegEx.create_from_string(CHOICE_PATTERN)
	var re_cond := RegEx.create_from_string(COND_PATTERN)
	var re_cmd := RegEx.create_from_string(COMMAND_PATTERN)
	var re_assign := RegEx.create_from_string(ASSIGN_PATTERN)
	var re_guard := RegEx.create_from_string(GUARD_PATTERN)

	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()

		# Lignes ignorées : vides et commentaires.
		if line.is_empty() or line.begins_with("//"):
			continue

		# Déclaration d'un nœud : ":: id"
		if line.begins_with("::"):
			var node_id := line.substr(2).strip_edges()
			if story.has_node(node_id):
				push_warning("StoryParser: nœud « %s » déclaré plusieurs fois — seul le dernier bloc est conservé." % node_id)
			current = StoryNode.new(node_id)
			story.add_node(current)
			continue

		# Variable globale : "@var nom = valeur" (avant tout nœud).
		if line.begins_with("@var"):
			var var_match := re_assign.search(line)
			if var_match and var_match.get_string(2) == "=":
				if current != null:
					push_warning("StoryParser: « @var » après un nœud (portée globale quand même) : " + line)
				story.variables[var_match.get_string(1)] = _parse_value(var_match.get_string(3))
			else:
				push_warning("StoryParser: « @var » illisible ignoré (attendu « @var nom = valeur ») : " + line)
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
		var guard_match := re_guard.search(line)
		if guard_match:
			guard = _parse_conds(guard_match.get_string(1))
			if guard.is_empty():
				push_warning("StoryParser: condition illisible ignorée : " + line)
			line = guard_match.get_string(2).strip_edges()

		# Choix : "* [Texte affiché] -> noeud_cible"
		var choice_match := re_choice.search(line)
		if choice_match:
			_append(current, {
				"type": "choice",
				"text": choice_match.get_string(1).strip_edges(),
				"target": choice_match.get_string(2),
			}, guard)
			continue

		# Saut conditionnel : '{ var == "valeur" -> noeud }' ou numérique
		# '{ var >= 3 -> noeud }'.
		var cond_jump_match := re_cond.search(line)
		if cond_jump_match:
			_append(current, {
				"type": "cond",
				"var": cond_jump_match.get_string(1),
				"op": cond_jump_match.get_string(2),
				"value": _parse_value(cond_jump_match.get_string(3)),
				"target": cond_jump_match.get_string(4),
			}, guard)
			continue

		# Saut direct : "-> noeud" (ou "-> END")
		if line.begins_with("->"):
			_append(current, {
				"type": "divert",
				"target": line.substr(2).strip_edges(),
			}, guard)
			continue

		# Affectation : "@set nom = valeur", ou arithmétique "@set nom += 2" /
		# "@set nom -= 1" (compteurs : compétences, réputation...).
		if line.begins_with("@set"):
			var set_match := re_assign.search(line)
			if set_match:
				_append(current, {
					"type": "set",
					"name": set_match.get_string(1),
					"op": set_match.get_string(2),
					"value": _parse_value(set_match.get_string(3)),
				}, guard)
			else:
				push_warning("StoryParser: « @set » illisible ignoré : " + line)
			continue

		# Commande moteur : '@nom("arg1", "arg2")' (ex: illustration, minigame)
		if line.begins_with("@"):
			var command_match := re_cmd.search(line)
			if command_match:
				_append(current, {
					"type": "command",
					"name": command_match.get_string(1),
					"args": _parse_args(command_match.get_string(2)),
				}, guard)
			else:
				push_warning("StoryParser: commande illisible ignorée : " + line)
			continue

		# Ligne qui ressemble à un choix mal formé (« * » sans « [texte] -> cible ») :
		# traitée comme du texte, mais l'auteur est prévenu — l'oubli de la flèche
		# ou du crochet est l'erreur de saisie la plus fréquente.
		if line.begins_with("*"):
			push_warning("StoryParser: choix mal formé traité comme du texte (attendu « * [Texte] -> cible ») : " + line)

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
##   var >= 3          → {"kind": "var", "name", "op": ">=", "value": 3}
##                       (aussi <, <=, >, ==, != — valeur numérique)
##   visited(noeud)    → {"kind": "visited", "id", "neg": false}
##   !visited(noeud)   → {"kind": "visited", "id", "neg": true}
##   zone_clicked("z") → {"kind": "zone", "id", "neg": false}
##   !zone_clicked("z")→ {"kind": "zone", "id", "neg": true}
##   has_item("i")     → {"kind": "item", "id", "qty": 1, "neg": false}
##   has_item("i", 2)  → {"kind": "item", "id", "qty": 2, "neg": false}
##   !has_item("i")    → {"kind": "item", "id", "qty": 1, "neg": true}
## Retourne [] si une des conditions est illisible.
static func _parse_conds(s: String) -> Array:
	var groups: Array = []
	for group_src in s.split(" or "):
		var conds: Array = []
		for part in group_src.split(" and "):
			part = part.strip_edges()
			var var_match := _re_cond_var.search(part)
			if var_match:
				conds.append({
					"kind": "var",
					"name": var_match.get_string(1),
					"op": var_match.get_string(2),
					"value": _parse_value(var_match.get_string(3)),
				})
				continue
			var visited_match := _re_cond_visited.search(part)
			if visited_match:
				conds.append({
					"kind": "visited",
					"id": visited_match.get_string(2),
					"neg": visited_match.get_string(1) == "!",
				})
				continue
			var zone_match := _re_cond_zone.search(part)
			if zone_match:
				conds.append({
					"kind": "zone",
					"id": zone_match.get_string(2),
					"neg": zone_match.get_string(1) == "!",
				})
				continue
			var item_match := _re_cond_item.search(part)
			if item_match:
				conds.append({
					"kind": "item",
					"id": item_match.get_string(2),
					"qty": int(item_match.get_string(3)) if item_match.get_string(3) != "" else 1,
					"neg": item_match.get_string(1) == "!",
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


## Valeur typée d'une affectation ou d'une condition : entre guillemets →
## String (même « "3" » reste du texte) ; littéral numérique → int/float ;
## sinon le texte brut (String, comportement historique des valeurs non citées).
static func _parse_value(s: String) -> Variant:
	var t := s.strip_edges()
	if t.length() >= 2 and t.begins_with("\"") and t.ends_with("\""):
		return _unquote(t)
	if t.is_valid_int():
		return t.to_int()
	if t.is_valid_float():
		return t.to_float()
	return t


## Compare la valeur COURANTE d'une variable à la valeur attendue d'une
## condition. Les comparaisons d'ordre (<, <=, >, >=) sont numériques (faux si
## l'une des deux valeurs n'est pas un nombre) ; l'(in)égalité est numérique
## quand les deux valeurs sont des nombres (3 == "3"), textuelle sinon.
## SEUL point de vérité — utilisé par le runner (exécution), la carte
## (relecture) et tout futur consommateur de gardes.
static func compare_values(current: Variant, op: String, expected: Variant) -> bool:
	var a := str(current)
	var b := str(expected)
	var numeric := a.is_valid_float() and b.is_valid_float()
	match op:
		"==":
			return a.to_float() == b.to_float() if numeric else a == b
		"!=":
			return a.to_float() != b.to_float() if numeric else a != b
		"<":
			return numeric and a.to_float() < b.to_float()
		"<=":
			return numeric and a.to_float() <= b.to_float()
		">":
			return numeric and a.to_float() > b.to_float()
		">=":
			return numeric and a.to_float() >= b.to_float()
	return false


## Applique une affectation « @set » : "=" pose la valeur telle quelle,
## "+=" / "-=" font l'arithmétique (valeur manquante ou non numérique = 0).
## Le résultat entier reste un entier (compteurs propres à l'affichage).
static func apply_set(current: Variant, op: String, value: Variant) -> Variant:
	if op == "=":
		return value
	var a := str(current if current != null else 0).to_float()
	var b := str(value).to_float()
	var r := a + b if op == "+=" else a - b
	return int(r) if is_equal_approx(r, roundf(r)) else r


static func _parse_args(s: String) -> Array:
	var args: Array = []
	if s.strip_edges().is_empty():
		return args
	for part in s.split(","):
		args.append(_unquote(part))
	return args
