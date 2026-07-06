extends SceneTree
## Validation hors-ligne d'un fichier .untold :
##   1. parse + vérification statique (cibles de saut, noms d'illustration) ;
##   2. parcours aléatoires massifs par combinaison personnage × attribut
##      (détecte nœuds introuvables, impasses, boucles infinies).
## Usage : godot --headless --path . --script tools/validate_story.gd

const STORY_DIR := "res://data/stories/mesopotamia/"
const STORY_PATH := STORY_DIR + "act1_sc1.untold"
const RUNS_PER_COMBO := 200
const MAX_STEPS := 2000

# En mode --script, les class_name globaux ne sont pas chargés : preload direct.
const Parser := preload("res://core/narrative/story_parser.gd")
const Runner := preload("res://core/narrative/story_runner.gd")
const Library := preload("res://core/illustration/illustration_library.gd")

# Paires personnage/attribut valides (mêmes appariements que l'ancien projet ;
# seuls les 3 premiers existent dans le jeu actuel).
const COMBOS := [
	["Nadîtum", "Social"],
	["Soldat", "Physique"],
	["Prêtresse", "Mystique"],
	["Marchand", "Social"],
	["Danseuse", "Physique"],
	["Exorciste", "Mystique"],
]


func _init() -> void:
	var source := FileAccess.get_file_as_string(STORY_PATH)
	if source.is_empty():
		push_error("Fichier introuvable ou vide : " + STORY_PATH)
		quit(1)
		return
	var story = Parser.parse(source)
	Library.load_story(STORY_DIR)  # peuple les définitions d'illustrations
	print("Nœuds parsés : %d" % story.nodes.size())

	var errors := 0

	# --- 1. Vérification statique -------------------------------------
	for id in story.nodes:
		var node = story.nodes[id]
		for ins in node.instructions:
			var target: String = str(ins.get("target", ""))
			if target != "" and target != "END" and not story.has_node(target):
				print("ERREUR: cible inconnue « %s » dans %s" % [target, id])
				errors += 1
			if ins["type"] == "command" and ins["name"] == "illustration":
				var illu: String = ins["args"][0]
				if not Library.defs().has(illu):
					print("ERREUR: illustration inconnue « %s » dans %s" % [illu, id])
					errors += 1

	# --- 2. Parcours aléatoires ----------------------------------------
	var endings := {}          # noeud final -> occurrences
	var all_visited := {}      # couverture globale
	var rng := RandomNumberGenerator.new()

	for combo in COMBOS:
		var character: String = combo[0]
		var type: String = combo[1]
		var combo_endings := {}
		for run in RUNS_PER_COMBO:
			rng.seed = hash("%s|%s|%d" % [character, type, run])
			var result := _play(story, character, type, rng)
			if result["error"] != "":
				print("ERREUR (%s/%s, run %d) : %s" % [character, type, run, result["error"]])
				errors += 1
			combo_endings[result["end"]] = combo_endings.get(result["end"], 0) + 1
			endings[result["end"]] = endings.get(result["end"], 0) + 1
			for id in result["visited"]:
				all_visited[id] = true
		var ends := combo_endings.keys()
		ends.sort()
		print("%s / %s → fins : %s" % [character, type, ", ".join(ends)])

	print("\nCouverture : %d / %d nœuds atteints" % [all_visited.size(), story.nodes.size()])
	var unreached := []
	for id in story.nodes:
		if not all_visited.has(id):
			unreached.append(id)
	if unreached.size() > 0:
		print("Jamais atteints : " + ", ".join(unreached))

	print("\nNœuds de fin observés :")
	var keys := endings.keys()
	keys.sort()
	for k in keys:
		print("  %s : %d parcours" % [k, endings[k]])

	print("\n%s" % ("VALIDATION OK" if errors == 0 else "%d ERREUR(S)" % errors))
	quit(0 if errors == 0 else 1)


## Joue une partie entière avec des choix aléatoires ; retourne
## {"end": id du dernier nœud, "visited": Dictionary, "error": String}.
func _play(story, character: String, type: String, rng: RandomNumberGenerator) -> Dictionary:
	var runner = Runner.new()
	var ended := [false]
	var choices := [[]]
	var last := [""]

	runner.display_text.connect(func(_t: String, node_id: String, _tags: Array) -> void:
		last[0] = node_id)
	runner.present_choices.connect(func(c: Array) -> void:
		choices[0] = c)
	runner.story_ended.connect(func() -> void:
		ended[0] = true)

	runner.start(story, {"character": character, "type": type})

	var error := ""
	var steps := 0
	while not ended[0]:
		steps += 1
		if steps > MAX_STEPS:
			error = "boucle probable (> %d étapes) vers %s" % [MAX_STEPS, last[0]]
			break
		var current: Array = choices[0]
		if current.is_empty():
			error = "bloqué sans choix après %s" % last[0]
			break
		choices[0] = []
		runner.choose(rng.randi_range(0, current.size() - 1))

	# Dernier nœud réellement ENTRÉ (et pas seulement affiché) : une impasse
	# muette (nœud sans texte ni choix pour cette combinaison) apparaît ainsi.
	var visited: Dictionary = runner._visited.duplicate()
	var end_node: String = visited.keys().back() if visited.size() > 0 else last[0]
	var result := {"end": end_node, "visited": visited, "error": error}
	runner.free()
	return result
