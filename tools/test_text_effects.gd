extends Node
## Test : extraction des pauses dramatiques [Soupir:X] (comptage en caractères
## visibles hors BBCode) et instanciation des 4 effets RichTextEffect custom.
##   C:\Godot\godot.exe --headless --path . tools/test_text_effects.tscn

const Story := preload("res://scenes/story.gd")

var _failures := 0


func _ready() -> void:
	_test_pause_extraction()
	_test_effects()
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


func _test_pause_extraction() -> void:
	print("Pauses [Soupir:X] — extraction et comptage visible :")

	var r0 := Story._prepare_dramatic_text("rien à signaler")
	_check(r0["text"] == "rien à signaler" and r0["pauses"].is_empty(), "zéro pause : texte intact")

	var r1 := Story._prepare_dramatic_text("Bonjour[Soupir:1.5]tout le monde")
	_check(r1["text"] == "Bonjourtout le monde", "une pause : balise retirée du texte")
	_check(r1["pauses"].size() == 1, "une pause détectée")
	_check(r1["pauses"][0]["visible"] == 7, "pause après 7 caractères visibles (Bonjour)")
	_check(is_equal_approx(r1["pauses"][0]["duration"], 1.5), "durée 1.5 s")

	var r2 := Story._prepare_dramatic_text("[color=#ff0000]Rouge[/color][Soupir:2]suite")
	_check(r2["text"] == "[color=#ff0000]Rouge[/color]suite", "BBCode conservé, seule la pause ôtée")
	_check(r2["pauses"][0]["visible"] == 5, "5 visibles avant la pause (les balises ne comptent pas)")

	var r3 := Story._prepare_dramatic_text("ab[Soupir:1]cd[Soupir:0.5]ef")
	_check(r3["text"] == "abcdef", "plusieurs pauses : texte recollé")
	_check(r3["pauses"].size() == 2, "deux pauses détectées")
	_check(r3["pauses"][0]["visible"] == 2 and r3["pauses"][1]["visible"] == 4,
			"positions visibles 2 puis 4")

	var r4 := Story._prepare_dramatic_text("x[Soupir:2secondes]y")
	_check(r4["text"] == "xy" and is_equal_approx(r4["pauses"][0]["duration"], 2.0),
			"suffixe 'secondes' toléré, durée = 2 s")


func _test_effects() -> void:
	print("Effets RichTextEffect custom :")
	for name in ["shock", "danger", "silence"]:
		var fx: RichTextEffect = load("res://core/text_effects/%s.gd" % name).new()
		_check(fx.bbcode == name, "%s : bbcode == \"%s\"" % [name, name])
		var cfx := CharFXTransform.new()
		cfx.color = Color.WHITE
		var ok: bool = fx._process_custom_fx(cfx)
		_check(ok, "%s : _process_custom_fx renvoie true sans erreur" % name)

	var shock: RichTextEffect = load("res://core/text_effects/shock.gd").new()
	shock.restart()
	_check(true, "shock.restart() sans erreur")
