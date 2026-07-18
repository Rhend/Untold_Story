extends Node
## Suivi persistant de la progression narrative (autoload "Progress") — L6.
##
## Répond à tout moment aux questions :
##  - tel nœud a-t-il été visité, et par quels personnages ?
##  - à tel point de choix, quelles réponses ont déjà été choisies (et par qui),
##    et lesquelles ne l'ont pas encore été ? (voir choice_status())
##
## Les données sont regroupées par histoire (story_id = nom du fichier .untold)
## et persistées en JSON dans user://progress.json à chaque événement.

const SAVE_PATH := "user://progress.json"

## Contexte courant, posé par begin_story().
var _story_id := ""
var _character := ""

## { story_id: { node_id: {
##     "visited_by": { personnage: nombre de passages },
##     "chosen":     { texte de la réponse: { personnage: nombre de fois } } } } }
var _data: Dictionary = {}

## Clics sur les zones interactives d'illustration (indépendant des nœuds).
## Appartient à la PARTIE EN COURS : remis à zéro par restart_playthrough(),
## contrairement à visited_by/chosen (section "decouverte", cumulatifs).
## { story_id: { zone_id: { personnage: nombre de clics } } }
var _zones: Dictionary = {}

## LA PARTIE EN COURS, une section par donnée — toutes de même forme
## { story_id: { personnage: valeur } }, toutes effacées ensemble à la fin de
## l'histoire et par restart_playthrough (cf. _erase_current_run), toutes
## sauvées sous "partie_en_cours" sur le disque. AJOUTER une donnée de run =
## ajouter son nom ici : sauvegarde, chargement et effacement suivent seuls.
##
##   position        : point de reprise (checkpoint) — le dernier nœud où un
##                     point de choix a été présenté ; sauté directement à la
##                     prochaine sélection du personnage (reprise auto).
##                     valeur : node_id (String).
##   visited_session : nœuds traversés PENDANT la partie — restaure
##                     StoryRunner._visited à la reprise pour que les gardes
##                     visited() se comportent comme en lecture continue.
##                     DISTINCT de "decouverte" (cumulatif inter-parties).
##                     valeur : [node_id, ...].
##   inventory       : inventaire du run (un nouveau run repart les mains
##                     vides). valeur : { item_id: quantité }.
##   illustration    : dernière illustration affichée — elle persiste sur la
##                     page de gauche bien au-delà du nœud qui l'a invoquée ;
##                     sans cette trace, la reprise repartirait page vierge.
##                     valeur : nom d'illustration (String).
##   passage_text    : texte COMPLET du passage au checkpoint — un passage
##                     accumule plusieurs nœuds enchaînés + les dialogues de
##                     zones, or le checkpoint ne rejoue que son propre nœud.
##                     valeur : texte brut (String).
##   variables       : variables du récit (@set : compétences, réputation…)
##                     au checkpoint — sans elles, la reprise repartirait des
##                     valeurs par défaut. valeur : { nom: valeur }.
const RUN_SECTIONS := ["position", "visited_session", "inventory",
		"illustration", "passage_text", "variables"]

## { section (cf. RUN_SECTIONS): { story_id: { personnage: valeur } } }
var _run: Dictionary = {}


func _ready() -> void:
	_load()


# ------------------------------------------------------------ Enregistrement

## Pose le contexte : histoire jouée et personnage incarné.
func begin_story(story_id: String, character: String) -> void:
	_story_id = story_id
	_character = character


## Le personnage courant traverse un nœud (y compris les nœuds intermédiaires
## enchaînés par des sauts). Deux écritures synchronisées ICI, jamais séparées :
##  - "decouverte" (_data) : compteur cumulatif inter-parties (visited_by) ;
##  - "visited_session"     : trace de la partie en cours (pour la reprise).
func record_visit(node_id: String) -> void:
	var visitors_of_node: Dictionary = _node_entry(node_id)["visited_by"]
	visitors_of_node[_character] = int(visitors_of_node.get(_character, 0)) + 1
	var session: Array = _run_slot("visited_session", [])
	if not session.has(node_id):
		session.append(node_id)
	_save()


## Liste des nœuds traversés durant la partie en cours de ce (story_id,
## personnage), pour restaurer StoryRunner._visited à la reprise. Copie défensive
## (l'appelant ne doit pas muter l'état interne). Vide si aucune partie en cours.
func resume_visited_set(story_id := "", character := "") -> Array:
	return (_run_get("visited_session", [], story_id, character) as Array).duplicate()


## Le personnage courant valide une réponse à un point de choix.
func record_choice(node_id: String, choice_text: String) -> void:
	var chosen: Dictionary = _node_entry(node_id)["chosen"]
	var by: Dictionary = chosen.get(choice_text, {})
	by[_character] = int(by.get(_character, 0)) + 1
	chosen[choice_text] = by
	_save()


## Le personnage courant clique sur une zone interactive d'illustration.
## Enregistré quelle que soit la zone (même sans effet dialogue/objet).
func record_zone_click(zone_id: String) -> void:
	if not _zones.has(_story_id):
		_zones[_story_id] = {}
	var zones: Dictionary = _zones[_story_id]
	var by: Dictionary = zones.get(zone_id, {})
	by[_character] = int(by.get(_character, 0)) + 1
	zones[zone_id] = by
	_save()


# -------------------------------------------------------------- Inventaire
# Partie en cours, personnage courant. « unique » = qty 1 par défaut ; aucune
# distinction stockée, seule l'invocation (avec ou sans quantité) la porte.

## Ajoute qty exemplaires d'un objet à l'inventaire du personnage courant.
func add_item(id: String, qty: int = 1) -> void:
	var items: Dictionary = _run_slot("inventory", {})
	items[id] = int(items.get(id, 0)) + qty
	_save()


## Retire qty exemplaires. Si le total tombe à 0 ou moins, l'entrée DISPARAÎT
## (un objet n'est jamais affiché « à 0 »). Sans effet si l'objet est absent.
func remove_item(id: String, qty: int = 1) -> void:
	var items: Dictionary = _run_get("inventory", {})
	if not items.has(id):
		return
	var left := int(items[id]) - qty
	if left <= 0:
		items.erase(id)
		if items.is_empty():
			_erase_from(_run_store("inventory"), _story_id, _character)
	else:
		items[id] = left
	_save()


## Le personnage possède-t-il AU MOINS qty exemplaires de l'objet ?
## Interrogé par la garde has_item("id"[, qty]) du .untold. Comparaison >=.
func has_item(id: String, qty: int = 1, story_id := "", character := "") -> bool:
	return int((_run_get("inventory", {}, story_id, character) as Dictionary).get(id, 0)) >= qty


## Inventaire { item_id: quantité } d'un (story_id, personnage), pour l'UI.
## Copie défensive (l'appelant ne doit pas muter l'état interne).
func inventory_items(story_id := "", character := "") -> Dictionary:
	return (_run_get("inventory", {}, story_id, character) as Dictionary).duplicate()


## Enregistre le point de reprise du personnage courant : le nœud où un point de
## choix vient d'être présenté (PAS les nœuds intermédiaires enchaînés — le
## joueur ne s'y "arrête" pas). Appelé aussi à la fin de l'histoire, où il faut
## au contraire EFFACER la reprise (cf. clear_checkpoint).
## `variables` : l'état des variables du récit à cet instant (runner.variables),
## rejoué à la reprise — les compteurs @set (compétences, réputation) survivent.
func record_checkpoint(node_id: String, variables: Dictionary = {}) -> void:
	_run_put("position", node_id)
	_run_put("variables", variables.duplicate(true))
	_save()


## Variables du récit au dernier checkpoint de (story_id, personnage), ou {}.
## Copie défensive. NB : le JSON rend les entiers en float — sans importance,
## les comparaisons et l'arithmétique du moteur sont numériques.
func resume_variables(story_id := "", character := "") -> Dictionary:
	return (_run_get("variables", {}, story_id, character) as Dictionary).duplicate(true)


## Efface l'état du run terminé (reprise + trace de session + inventaire) pour le
## personnage courant. Fin d'histoire : reprendre une fin n'a pas de sens, la
## prochaine sélection repart de start_node, _visited vierge et les mains vides —
## sinon la trace de la partie terminée contaminerait les gardes visited()/
## has_item() d'un nouveau run.
func clear_checkpoint() -> void:
	_erase_current_run(_story_id, _character)
	_save()


## Nœud de reprise pour (story_id, personnage), ou "" si aucun (repart du début).
## story_id / character vides = contexte courant.
func resume_node(story_id := "", character := "") -> String:
	return _run_get("position", "", story_id, character)


## Enregistre l'illustration actuellement affichée pour le personnage courant —
## appelé à CHAQUE @illustration exécutée, pour que la reprise retrouve la page
## de gauche telle que laissée.
func record_illustration(illustration_name: String) -> void:
	_run_put("illustration", illustration_name)
	_save()


## Illustration à réafficher à la reprise pour (story_id, personnage), ou "" si
## aucune (page de gauche vierge, comme en début d'histoire).
func resume_illustration(story_id := "", character := "") -> String:
	return _run_get("illustration", "", story_id, character)


## Enregistre le texte du passage actuellement affiché pour le personnage
## courant — à CHAQUE affichage de passage et à chaque dialogue ajouté, pour que
## la reprise retrouve la page de droite telle que laissée.
func record_passage_text(text: String) -> void:
	_run_put("passage_text", text)
	_save()


## Texte du passage à réafficher à la reprise pour (story_id, personnage), ou ""
## si aucun (le nœud de reprise est alors rejoué tel quel).
func resume_passage_text(story_id := "", character := "") -> String:
	return _run_get("passage_text", "", story_id, character)


## Recommence la partie de ce (story_id, personnage) : efface UNIQUEMENT sa
## "partie en cours" — zones cliquées, point de reprise, trace de session
## (gardes visited() de l'ancienne partie) ET inventaire. La section "decouverte"
## (visited_by/chosen, cumulative) reste intacte.
func restart_playthrough(story_id: String, character: String) -> void:
	if _zones.has(story_id):
		for zone_id in _zones[story_id].keys():
			_zones[story_id][zone_id].erase(character)
			if _zones[story_id][zone_id].is_empty():
				_zones[story_id].erase(zone_id)
		if _zones[story_id].is_empty():
			_zones.erase(story_id)
	_erase_current_run(story_id, character)
	_save()


## Efface l'état transitoire d'un RUN (reprise + trace de session + inventaire)
## pour un (story_id, personnage). Appelé à la fin de l'histoire (clear_checkpoint)
## ET par restart_playthrough : l'inventaire est lié à la partie, pas au
## personnage — un nouveau run repart les mains vides. Ne touche NI zones NI
## "decouverte".
func _erase_current_run(story_id: String, character: String) -> void:
	for section in RUN_SECTIONS:
		_erase_from(_run_store(section), story_id, character)


func _erase_from(store: Dictionary, story_id: String, character: String) -> void:
	if not store.has(story_id):
		return
	store[story_id].erase(character)
	if store[story_id].is_empty():
		store.erase(story_id)


## Efface toute la progression (tous personnages, toutes histoires) — découverte
## comprise. Non câblé dans l'UI (aucune remise à zéro globale n'est proposée).
func reset() -> void:
	_data = {}
	_zones = {}
	_run = {}
	_save()


# ---------------------------------------------------------------- Requêtes
# story_id vide = histoire du contexte courant.

## Le nœud a-t-il déjà été visité (tous personnages confondus) ?
func is_visited(node_id: String, story_id := "") -> bool:
	return not visitors(node_id, story_id).is_empty()


## Personnages ayant visité le nœud.
func visitors(node_id: String, story_id := "") -> Array:
	return _node_of(node_id, story_id).get("visited_by", {}).keys()


## Nombre de passages d'un personnage donné sur ce nœud.
func visit_count(node_id: String, character: String, story_id := "") -> int:
	return int(_node_of(node_id, story_id).get("visited_by", {}).get(character, 0))


## Cette réponse a-t-elle déjà été choisie (tous personnages confondus) ?
func is_choice_chosen(node_id: String, choice_text: String, story_id := "") -> bool:
	return not choice_choosers(node_id, choice_text, story_id).is_empty()


## Personnages ayant déjà choisi cette réponse.
func choice_choosers(node_id: String, choice_text: String, story_id := "") -> Array:
	return _node_of(node_id, story_id).get("chosen", {}).get(choice_text, {}).keys()


## Cette zone a-t-elle déjà été cliquée (tous personnages confondus) ?
## Interrogé par la garde zone_clicked("id") du .untold.
func is_zone_clicked(zone_id: String, story_id := "") -> bool:
	return not _zones.get(_resolve(story_id), {}).get(zone_id, {}).is_empty()


## État de TOUTES les réponses déclarées par un nœud : pour chacune, si elle a
## déjà été choisie et par qui. Les réponses jamais choisies sont celles dont
## "chosen" vaut false — c'est la vue exhaustive choisi / pas encore choisi.
func choice_status(node: StoryNode, story_id := "") -> Array:
	var result: Array = []
	for ins in node.instructions:
		if ins["type"] != "choice":
			continue
		var by := choice_choosers(node.id, ins["text"], story_id)
		result.append({
			"text": ins["text"],
			"target": ins["target"],
			"chosen": not by.is_empty(),
			"by": by,
		})
	return result


## Nombre de nœuds distincts déjà visités dans l'histoire.
func visited_count(story_id := "") -> int:
	return _data.get(_resolve(story_id), {}).size()


## Nombre de nœuds distincts déjà visités par UN personnage donné (découverte
## cumulative) — alimente le % de complétion de la sélection de personnage.
func visited_count_by(character: String, story_id := "") -> int:
	var count := 0
	for node in _data.get(_resolve(story_id), {}).values():
		if (node.get("visited_by", {}) as Dictionary).has(character):
			count += 1
	return count


# -------------------------------------------------------------- Persistance

func _resolve(story_id: String) -> String:
	return _story_id if story_id.is_empty() else story_id


## Lecture seule : entrée du nœud, ou {} si jamais rencontré.
func _node_of(node_id: String, story_id := "") -> Dictionary:
	return _data.get(_resolve(story_id), {}).get(node_id, {})


## Écriture : entrée du nœud pour l'histoire courante, créée au besoin.
func _node_entry(node_id: String) -> Dictionary:
	if not _data.has(_story_id):
		_data[_story_id] = {}
	var nodes: Dictionary = _data[_story_id]
	if not nodes.has(node_id):
		nodes[node_id] = {"visited_by": {}, "chosen": {}}
	return nodes[node_id]


# ------------------------------------------- Accès aux sections de la partie
# (cf. RUN_SECTIONS pour la liste et le sens de chaque section)

## Le magasin d'une section : { story_id: { personnage: valeur } }, créé vide
## au besoin.
func _run_store(section: String) -> Dictionary:
	return _run.get_or_add(section, {})


## Lecture : valeur d'une section pour (story_id, personnage), ou `default`.
## story_id / character vides = contexte courant. La valeur renvoyée est
## l'état INTERNE quand elle existe : les accesseurs publics dupliquent.
func _run_get(section: String, default: Variant, story_id := "", character := "") -> Variant:
	var chr := _character if character.is_empty() else character
	return _run_store(section).get(_resolve(story_id), {}).get(chr, default)


## Écriture : pose la valeur pour (histoire, personnage) COURANTS. Ne sauve
## pas — l'appelant regroupe ses écritures puis appelle _save() une fois.
func _run_put(section: String, value: Variant) -> void:
	(_run_store(section).get_or_add(_story_id, {}) as Dictionary)[_character] = value


## Écriture : valeur MUTABLE pour (histoire, personnage) courants, créée à
## partir de `default` au besoin (liste de session, inventaire...).
func _run_slot(section: String, default: Variant) -> Variant:
	var per_character: Dictionary = _run_store(section).get_or_add(_story_id, {})
	if not per_character.has(_character):
		per_character[_character] = default
	return per_character[_character]


## Format disque, structuré par DURÉE DE VIE des données :
##   { "decouverte":      <cumulatif, jamais remis à zéro : visited_by/chosen>,
##     "partie_en_cours": { "zones" + une clé par section de RUN_SECTIONS } }
## Ajouter une donnée de partie = l'ajouter à RUN_SECTIONS, rien d'autre.
##
## Écriture ATOMIQUE : le JSON part dans un fichier temporaire, l'ancienne
## sauvegarde devient la copie de secours (.bak), puis le temporaire prend sa
## place. Un crash en pleine écriture ne peut donc jamais corrompre la seule
## copie existante — au pire, la .bak a un événement de retard.
func _save() -> void:
	var tmp_path := SAVE_PATH + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("Progress: impossible d'écrire " + tmp_path)
		return
	var current_run: Dictionary = {"zones": _zones}
	for section in RUN_SECTIONS:
		current_run[section] = _run_store(section)
	file.store_string(JSON.stringify({
		"decouverte": _data,
		"partie_en_cours": current_run,
	}, "\t"))
	file.close()

	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH + ".bak")
		DirAccess.rename_absolute(SAVE_PATH, SAVE_PATH + ".bak")
	if DirAccess.rename_absolute(tmp_path, SAVE_PATH) != OK:
		push_error("Progress: impossible de remplacer " + SAVE_PATH)


func _load() -> void:
	if _try_load(SAVE_PATH):
		return
	# Sauvegarde principale absente ou corrompue (crash au mauvais moment,
	# édition manuelle...) : la copie de secours prend le relais.
	if _try_load(SAVE_PATH + ".bak"):
		push_warning("Progress: sauvegarde restaurée depuis la copie de secours (.bak).")


## Charge un fichier de sauvegarde s'il existe et se parse. false sinon.
func _try_load(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_warning("Progress: sauvegarde illisible : " + path)
		return false
	_migrate(parsed)
	return true


## Charge une sauvegarde en gérant les formats successifs, du plus récent au plus
## ancien. Chaque nouvelle version du format ajoute une branche EN TÊTE ; les
## anciennes branches restent pour ne perdre aucune sauvegarde existante.
func _migrate(parsed: Dictionary) -> void:
	# v3 (points 7-8) — sections par durée de vie. Une section absente (vieille
	# sauvegarde d'avant son introduction) démarre simplement vide.
	if parsed.has("decouverte") or parsed.has("partie_en_cours"):
		_data = parsed.get("decouverte", {})
		var current: Dictionary = parsed.get("partie_en_cours", {})
		_zones = current.get("zones", {})
		_run = {}
		for section in RUN_SECTIONS:
			_run[section] = current.get(section, {})
		return
	# v2 (point 4) — { "stories", "zones" }, sans point de reprise.
	if parsed.has("stories") or parsed.has("zones"):
		_data = parsed.get("stories", {})
		_zones = parsed.get("zones", {})
		return
	# v1 (pré-point-4) — dict de story_id à plat, sans zones ni reprise.
	_data = parsed
