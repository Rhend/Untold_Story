extends Node
## Test des réglages partagés (Settings/GameSettings), de la résolution du gain
## de parallaxe, du flag parallax_enabled par illustration, du template Character
## et de la sensibilité souris. Lancé comme une VRAIE scène (autoloads chargés) :
##   C:\Godot\godot.exe --headless --path . tools/test_settings_parallax.tscn

var _failures := 0


func _ready() -> void:
	_test_settings()
	_test_template_enum()
	_test_library_parallax_flag()
	_test_gain_resolution()
	_test_mouse_sensitivity()
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


func _test_settings() -> void:
	print("Settings — chargement et forwarding :")
	_check(Settings.config != null, "config chargée (non null)")
	# Forwarding Settings.<champ> -> config.<champ>.
	_check(Settings.parallax_pivot_index == 5, "parallax_pivot_index == 5")
	_check(is_equal_approx(Settings.mouse_sensitivity, 1.0), "mouse_sensitivity == 1.0")
	_check(is_equal_approx(Settings.parallax_gain_default, 9.0), "parallax_gain_default == 9.0")


func _test_template_enum() -> void:
	print("IllustrationData — template Character :")
	# Ajouté en fin d'énum : les valeurs existantes ne bougent pas.
	_check(IllustrationData.Template.PORTRAIT == 0, "PORTRAIT reste 0")
	_check(IllustrationData.Template.LANDSCAPE == 1, "LANDSCAPE reste 1")
	_check(IllustrationData.Template.CHARACTER == 2, "CHARACTER == 2")


func _test_library_parallax_flag() -> void:
	print("IllustrationLibrary — parallax_enabled par illustration :")
	for name in ["Démon", "Orante", "Statue de Sîn", "Halî-Ammi"]:
		var data := IllustrationLibrary.get_illustration(name)
		_check(data != null and not data.parallax_enabled,
				"%s : parallax désactivé (bug de bord vide corrigé)" % name)
	var landscape := IllustrationLibrary.get_illustration("Le village")
	_check(landscape != null and landscape.parallax_enabled,
			"Le village : parallax actif par défaut")


func _test_gain_resolution() -> void:
	print("Illustration — résolution du gain depuis Settings :")
	var a := Illustration.new()
	add_child(a)  # _ready résout le gain
	_check(not is_nan(a.parallax_gain), "gain résolu (non NAN)")
	_check(is_equal_approx(a.parallax_gain, Settings.parallax_gain_default),
			"gain hérite de Settings.parallax_gain_default")

	var b := Illustration.new()
	b.parallax_gain = 3.0  # surcharge d'instance avant l'entrée dans l'arbre
	add_child(b)
	_check(is_equal_approx(b.parallax_gain, 3.0), "surcharge d'instance conservée")

	a.queue_free()
	b.queue_free()


func _test_mouse_sensitivity() -> void:
	print("MouseLookSource — sensibilité appliquée avant le clamp :")
	var source := MouseLookSource.new()
	# Avec une forte sensibilité, le résultat DOIT rester borné [-1,1] : c'est la
	# preuve que le clamp intervient APRÈS le multiplicateur (cf. consigne).
	Settings.config.mouse_sensitivity = 5.0
	var look := source.sample(get_viewport())
	_check(absf(look.x) <= 1.0 and absf(look.y) <= 1.0,
			"sensibilité 5 : regard borné [-1,1] (clamp après multiplicateur)")
	Settings.config.mouse_sensitivity = 1.0  # restauration
