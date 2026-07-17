extends SceneTree
## Tests hors-ligne de l'outil narratif (L7) :
##  - UntoldSource : round-trip sans perte, réordonnancement, ajout d'event ;
##  - StoryGraph : liens et auto-layout ;
##  - StoryMeta : positions et commentaires.
## Lancer : godot --headless --path . --script tools/test_narrative_tool.gd

const STORY_PATH := "res://data/stories/mesopotamia/act1_sc1.untold"
const UntoldSource := preload("res://addons/narrative_graph/untold_source.gd")
# En mode --script, les class_name globaux non-@tool ne sont pas chargés.
const Runner := preload("res://core/narrative/story_runner.gd")

var _failures := 0


func _initialize() -> void:
	_test_untold_source()
	_test_duplicate_ids()
	_test_node_operations()
	_test_runner_cycle_guard()
	_test_story_graph()
	_test_story_meta()
	if _failures == 0:
		print("TESTS OK")
	else:
		print("%d ÉCHEC(S)" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok  — " + label)
	else:
		_failures += 1
		printerr("  FAIL — " + label)


func _test_untold_source() -> void:
	print("[UntoldSource]")
	var source := UntoldSource.new()
	_check(source.load_file(STORY_PATH), "chargement de l'acte 1")
	var original_order: Array = source.order.duplicate()
	_check(original_order.size() >= 100, "blocs trouvés (%d)" % original_order.size())

	# Round-trip : le texte reconstruit re-parse en une histoire identique.
	var story_before := StoryParser.parse(FileAccess.get_file_as_string(STORY_PATH))
	var story_after := StoryParser.parse(source.text())
	_check(story_after.nodes.size() == story_before.nodes.size(),
			"round-trip : même nombre de nœuds (%d)" % story_after.nodes.size())
	var same_content := true
	for id in story_before.nodes:
		var a: StoryNode = story_before.nodes[id]
		var b: StoryNode = story_after.nodes.get(id)
		if b == null or str(a.instructions) != str(b.instructions) or str(a.tags) != str(b.tags):
			same_content = false
			printerr("    divergence sur " + id)
	_check(same_content, "round-trip : instructions et tags identiques partout")

	# Réordonnancement sur une COPIE de travail, puis re-parse.
	var work_path := "user://_test_reorder.untold"
	source.path = work_path
	var shuffled: Array = original_order.duplicate()
	shuffled.reverse()
	source.reorder(shuffled)
	_check(source.order == shuffled, "reorder : ordre inversé appliqué")
	source.append_instruction(shuffled[0], "@illustration(\"TestEvent\")")
	_check(source.save(), "écriture de la copie de travail")

	var reparsed := StoryParser.parse(FileAccess.get_file_as_string(work_path))
	_check(reparsed.nodes.size() == story_before.nodes.size(),
			"après reorder : aucun nœud perdu")
	var target: StoryNode = reparsed.get_node_by_id(shuffled[0])
	var has_event := false
	for ins in target.instructions:
		if ins["type"] == "command" and ins["name"] == "illustration" \
				and ins["args"] == ["TestEvent"]:
			has_event = true
	_check(has_event, "event ajouté retrouvé au parse")

	# reorder avec liste partielle : rien ne doit disparaître.
	source.reorder([original_order[3], original_order[1]])
	_check(source.order.size() == original_order.size(), "reorder partiel : blocs conservés")
	_check(source.order[0] == original_order[3] and source.order[1] == original_order[1],
			"reorder partiel : têtes de liste respectées")
	DirAccess.remove_absolute(work_path)


## Un fichier avec un id déclaré deux fois ne doit RIEN perdre à la réécriture
## (les deux blocs restent verbatim), et signaler le doublon à l'outil.
func _test_duplicate_ids() -> void:
	print("[UntoldSource — ids dupliqués]")
	var work_path := "user://_test_dup.untold"
	var text := ":: start\nPremier bloc.\n\n:: start\nSecond bloc.\n"
	var file := FileAccess.open(work_path, FileAccess.WRITE)
	file.store_string(text)
	file = null

	var source := UntoldSource.new()
	_check(source.load_file(work_path), "chargement du fichier à doublon")
	_check(source.duplicate_ids == ["start"], "doublon signalé (%s)" % str(source.duplicate_ids))
	_check(source.order.size() == 2, "deux blocs conservés")
	_check(source.text() == text, "réécriture sans perte (les deux blocs verbatim)")
	DirAccess.remove_absolute(work_path)


## Opérations de nœud de l'outil : édition du corps, création, renommage
## (références « -> id » et « visited(id) » suivies), suppression.
func _test_node_operations() -> void:
	print("[UntoldSource — opérations de nœud]")
	var work_path := "user://_test_ops.untold"
	var text := ":: start\nDébut.\n{ visited(milieu) } Tu reviens.\n* [Aller] -> milieu\n\n:: milieu\nMilieu.\n{ etat == \"ok\" -> start }\n-> fin\n\n:: fin\nFin.\n-> END\n"
	var file := FileAccess.open(work_path, FileAccess.WRITE)
	file.store_string(text)
	file = null

	var source := UntoldSource.new()
	source.load_file(work_path)

	# --- corps ---
	_check(source.body_lines("fin") == ["Fin.", "-> END"], "body_lines lit le corps verbatim")
	_check(source.set_body("fin", ["La toute fin.", "-> END"]), "set_body remplace le corps")
	var story := StoryParser.parse(source.text())
	_check(story.get_node_by_id("fin").instructions[0]["value"] == "La toute fin.",
			"corps réécrit retrouvé au parse")

	# --- création ---
	_check(not source.add_node("milieu"), "add_node refuse un id existant")
	_check(not source.add_node("END"), "add_node refuse END")
	_check(not source.add_node("id impossible"), "add_node refuse les espaces")
	_check(source.add_node("epilogue", ["Nouveau nœud.", "-> END"]), "add_node accepte un id neuf")
	story = StoryParser.parse(source.text())
	_check(story.has_node("epilogue"), "nœud créé retrouvé au parse")

	# --- renommage : cibles et visited() suivent ---
	_check(not source.rename_node("milieu", "fin"), "rename refuse un id déjà pris")
	_check(source.rename_node("milieu", "scene_centrale"), "rename accepte")
	var t := source.text()
	_check(not t.contains("-> milieu") and t.contains("-> scene_centrale"),
			"cible de choix renommée")
	_check(t.contains("visited(scene_centrale)"), "visited() renommé")
	_check(t.contains("{ etat == \"ok\" -> start }"), "le saut conditionnel intact (autre cible)")
	story = StoryParser.parse(t)
	_check(story.has_node("scene_centrale") and not story.has_node("milieu"),
			"re-parse cohérent après rename")

	# --- recâblage (utilisé par le drag de connexion du graphe) ---
	_check(source.set_link_target("start", 0, "fin"), "set_link_target accepte")
	_check(source.text().contains("* [Aller] -> fin"),
			"cible du choix redirigée, texte du choix intact")

	# --- suppression ---
	_check(source.remove_node("epilogue"), "remove_node supprime")
	_check(not source.text().contains("epilogue"), "bloc absent du fichier réécrit")

	# --- métadonnées qui suivent ---
	var meta := StoryMeta.load_for(work_path)
	meta.set_node_position("scene_centrale", Vector2(5, 6))
	meta.set_comment("scene_centrale", "note")
	meta.rename_node("scene_centrale", "coeur")
	_check(meta.positions().get("coeur") == Vector2(5, 6) \
			and meta.get_comment("coeur") == "note", "meta.rename_node fait tout suivre")
	meta.forget_node("coeur")
	_check(meta.positions().is_empty() and meta.get_comment("coeur") == "",
			"meta.forget_node efface tout")

	DirAccess.remove_absolute(work_path)


## Un cycle de sauts (a -> b -> a) doit terminer l'histoire proprement au lieu
## de geler le jeu dans la boucle d'accumulation.
func _test_runner_cycle_guard() -> void:
	print("[StoryRunner — cycle de sauts]")
	var story := StoryParser.parse(":: start\nTexte.\n-> a\n\n:: a\n-> start\n")
	var runner: Node = Runner.new()
	var ended := [false]
	runner.story_ended.connect(func() -> void: ended[0] = true)
	runner.start(story)
	_check(ended[0], "l'histoire se termine au lieu de boucler")
	runner.free()


func _test_story_graph() -> void:
	print("[StoryGraph]")
	var story := StoryParser.parse(FileAccess.get_file_as_string(STORY_PATH))
	var graph := StoryGraph.build(story)
	_check(graph.links.size() == story.nodes.size(), "un jeu de liens par nœud")

	var kinds := {}
	var links_valid := true
	for id in graph.links:
		for link in graph.outgoing(id):
			kinds[link["kind"]] = true
			if link["target"] != "END" and not story.has_node(link["target"]):
				links_valid = false
	_check(links_valid, "toutes les cibles existent (ou END)")
	_check(kinds.has("choice") and kinds.has("divert"), "choix et sauts détectés")

	var layout := graph.auto_layout()
	_check(layout.size() == story.nodes.size(), "auto-layout : une position par nœud")
	var start_pos: Vector2 = layout[story.start_node]
	_check(start_pos == Vector2.ZERO, "auto-layout : nœud d'entrée en tête")


func _test_story_meta() -> void:
	print("[StoryMeta]")
	var work_path := "user://_test_meta.untold"
	var file := FileAccess.open(work_path, FileAccess.WRITE)
	file.store_string(":: start\nBonjour.\n")
	file = null

	var meta := StoryMeta.load_for(work_path)
	meta.set_node_position("start", Vector2(120, 40))
	meta.set_comment("start", "Note interne.")
	meta.save()

	var reloaded := StoryMeta.load_for(work_path)
	_check(reloaded.positions().get("start") == Vector2(120, 40), "position persistée")
	_check(reloaded.get_comment("start") == "Note interne.", "commentaire persisté")
	reloaded.set_comment("start", "  ")
	_check(reloaded.get_comment("start") == "", "commentaire vide effacé")
	DirAccess.remove_absolute(work_path)
	DirAccess.remove_absolute(work_path.get_basename() + ".meta.json")
