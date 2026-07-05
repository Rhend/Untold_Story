extends Node
## Test des zones interactives : garde zone_clicked (parser), refresh_choices
## (runner), suivi Progress (zones + migration ancien format), hit-test polygone.
## Sauvegarde puis restaure user://progress.json pour ne pas écraser la vraie
## progression du joueur.
##   C:\Godot\godot.exe --headless --path . tools/test_zones.tscn

const SAVE := "user://progress.json"

var _failures := 0
var _had_save := false
var _backup := ""


func _ready() -> void:
	_had_save = FileAccess.file_exists(SAVE)
	if _had_save:
		_backup = FileAccess.get_file_as_string(SAVE)

	_test_parser()
	_test_runner_refresh()
	_test_progress_zones()
	_test_migration()
	_test_hit_test()

	_restore_save()
	if _failures == 0:
		print("\n[OK] Tous les tests passent.")
	else:
		printerr("\n[ÉCHEC] %d assertion(s) en échec." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   ", label)
	else:
		_failures += 1
		printerr("  FAIL ", label)


func _restore_save() -> void:
	if _had_save:
		FileAccess.open(SAVE, FileAccess.WRITE).store_string(_backup)
	elif FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))


func _sample_story() -> Story:
	var story := StoryParser.parse("\n".join([
		":: n1",
		'{ zone_clicked("statue") } * [Regarder la statue] -> n2',
		"* [Continuer] -> n3",
		":: n2",
		"Tu observes la statue.",
		":: n3",
		"Tu continues.",
	]))
	story.start_node = "n1"
	return story


func _test_parser() -> void:
	print("Parser — garde zone_clicked :")
	var story := _sample_story()
	var choice: Dictionary = story.get_node_by_id("n1").instructions[0]
	_check(choice["type"] == "choice" and choice.has("if"), "choix gardé reconnu")
	var cond: Dictionary = choice["if"][0][0]
	_check(cond["kind"] == "zone" and cond["id"] == "statue" and not cond["neg"],
			"garde parsée : kind=zone, id=statue, neg=false")


func _test_runner_refresh() -> void:
	print("Runner — refresh_choices après clic de zone :")
	Progress.begin_story("ztest_runner", "Nadîtum")
	var runner := StoryRunner.new()
	add_child(runner)
	# NB : une lambda GDScript capture par valeur → on MUTE le tableau (assign)
	# au lieu de le réassigner, sinon la valeur ne remonterait pas ici.
	var captured: Array = []
	runner.present_choices.connect(func(c: Array) -> void: captured.assign(c))
	runner.start(_sample_story(), {})
	_check(captured.size() == 1, "zone non cliquée : le choix gardé est absent (1 choix)")

	Progress.record_zone_click("statue")
	runner.refresh_choices()
	_check(captured.size() == 2, "après clic + refresh : le choix gardé apparaît (2 choix)")
	runner.queue_free()


func _test_progress_zones() -> void:
	print("Progress — suivi des zones :")
	Progress.begin_story("ztest_prog", "Soldat")
	_check(not Progress.is_zone_clicked("porte"), "zone jamais cliquée : false")
	Progress.record_zone_click("porte")
	_check(Progress.is_zone_clicked("porte"), "après record : true")
	# Isolé par histoire.
	_check(not Progress.is_zone_clicked("porte", "autre_histoire"), "isolé par story_id")


func _test_migration() -> void:
	print("Progress — migration de l'ancien format à plat :")
	var old := {"act1_sc1": {"start": {"visited_by": {"Nadîtum": 1}, "chosen": {}}}}
	FileAccess.open(SAVE, FileAccess.WRITE).store_string(JSON.stringify(old))
	var tracker: Node = preload("res://core/game/progress_tracker.gd").new()
	add_child(tracker)  # _ready -> _load migre
	_check(tracker.is_visited("start", "act1_sc1"), "ancien format chargé (is_visited)")
	_check(not tracker.is_zone_clicked("x", "act1_sc1"), "zones vides après migration")
	tracker.queue_free()


func _test_hit_test() -> void:
	print("Illustration — hit-test polygone :")
	var zone := IllustrationInteraction.new()
	zone.id = "carre"
	zone.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var illu := Illustration.new()
	add_child(illu)  # _ready (gain via Settings)
	# Rect à (100,100) de taille (200,200) → zone couvre [100,300]².
	_check(illu._point_in_zone(Vector2(150, 150), zone, Vector2(100, 100), Vector2(200, 200)),
			"point intérieur détecté")
	_check(not illu._point_in_zone(Vector2(50, 50), zone, Vector2(100, 100), Vector2(200, 200)),
			"point extérieur rejeté")

	# mouse_filter selon la présence de zones.
	var layer := IllustrationLayer.new()
	layer.layer_index = 5
	layer.sprite = PlaceholderTexture2D.new()
	var zones: Array[IllustrationInteraction] = [zone]
	layer.interactions = zones
	var data := IllustrationData.new()
	data.template = IllustrationData.Template.PORTRAIT
	data.layers = [layer]
	illu.setup(data)
	_check(illu.mouse_filter == Control.MOUSE_FILTER_STOP, "avec zones : intercepte les clics")

	var bare := IllustrationLayer.new()
	bare.sprite = PlaceholderTexture2D.new()
	var data2 := IllustrationData.new()
	data2.layers = [bare]
	illu.setup(data2)
	_check(illu.mouse_filter == Control.MOUSE_FILTER_IGNORE, "sans zone : transparent aux clics")
	illu.queue_free()
