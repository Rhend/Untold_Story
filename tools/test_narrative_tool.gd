extends SceneTree
## Tests hors-ligne de l'outil narratif (L7) :
##  - UntoldSource : round-trip sans perte, réordonnancement, ajout d'event ;
##  - StoryGraph : liens et auto-layout ;
##  - StoryMeta : positions et commentaires.
## Lancer : godot --headless --path . --script tools/test_narrative_tool.gd

const STORY_PATH := "res://data/stories/mesopotamia/act1_sc1.untold"
const UntoldSource := preload("res://addons/narrative_graph/untold_source.gd")

var _failures := 0


func _initialize() -> void:
	_test_untold_source()
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
