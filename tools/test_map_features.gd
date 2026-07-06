extends Node
## Test des évolutions de la carte : filtrage #hors_carte, exécution du layout
## barycentre, helper de courbe. Sauvegarde/restaure user://progress.json.
##   C:\Godot\godot.exe --headless --path . tools/test_map_features.tscn

const SAVE := "user://progress.json"

var _failures := 0
var _had := false
var _backup := ""


func _ready() -> void:
	_had = FileAccess.file_exists(SAVE)
	if _had:
		_backup = FileAccess.get_file_as_string(SAVE)

	_test_hidden_tag()
	_test_layout_and_curve()

	_restore()
	if _failures == 0:
		print("\n[OK] Tous les tests passent.")
	else:
		printerr("\n[ÉCHEC] %d assertion(s) en échec." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _check(c: bool, label: String) -> void:
	if c:
		print("  ok   ", label)
	else:
		_failures += 1
		printerr("  FAIL ", label)


func _restore() -> void:
	if _had:
		FileAccess.open(SAVE, FileAccess.WRITE).store_string(_backup)
	elif FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))


func _parse(lines: Array) -> Story:
	return StoryParser.parse("\n".join(PackedStringArray(lines)))


func _visit(story_id: String, nodes: Array) -> void:
	Progress.begin_story(story_id, "Nadîtum")
	for n in nodes:
		Progress.record_visit(n)


func _test_hidden_tag() -> void:
	print("Carte — filtrage #hors_carte :")
	var story := _parse([
		":: start", "-> A",
		":: A", "Texte A.", "* [Aller] -> B", "* [Rester] -> C",
		":: B", "#hors_carte", "Passage secret.", "-> C",
		":: C", "Texte C.",
	])
	_visit("mapfeat_hidden", ["start", "A", "B", "C"])
	var map := StoryMap.new()
	add_child(map)
	map.setup(story, "user://_none_hidden.untold", "A")

	_check(map._map_hidden.has("B"), "B reconnu #hors_carte")
	_check(not map._revealed.has("B"), "B jamais révélé (ni visité ni aperçu)")
	_check(not map._rep_of.has("B"), "B n'a aucun représentant")
	_check(not map._drawn_reps().has("B"), "B absent des nœuds dessinés")
	_check(map._revealed.get("A") == "visited", "A visité et conservé")
	map.queue_free()


func _test_layout_and_curve() -> void:
	print("Carte — layout barycentre + courbe :")
	# start se ramifie en 3 branches (rangée large) qui reconvergent : de quoi
	# exercer le réordonnancement sans planter.
	var story := _parse([
		":: start", "Départ.", "* [1] -> A", "* [2] -> B", "* [3] -> C",
		":: A", "A.", "-> D",
		":: B", "B.", "-> D",
		":: C", "C.", "-> D",
		":: D", "Fin.",
	])
	_visit("mapfeat_layout", ["start", "A", "B", "C", "D"])
	var map := StoryMap.new()
	add_child(map)
	map.setup(story, "user://_none_layout.untold")  # pas de .meta → auto layout

	var drawn: Array = map._drawn_reps()
	_check(drawn.size() >= 4, "plusieurs nœuds dessinés (%d)" % drawn.size())
	var all_placed := true
	for rep in drawn:
		if not map._positions.has(rep):
			all_placed = false
	_check(all_placed, "tous les nœuds dessinés ont une position")

	var curve: Curve2D = map._edge_curve(Vector2(0, 0), Vector2(0, 120))
	_check(curve is Curve2D and curve.get_baked_length() > 0.0, "courbe verticale non vide")
	_check(curve.tessellate().size() >= 2, "courbe échantillonnable (draw_polyline)")
	map.queue_free()
