extends SceneTree
## Test headless : Env (DEV/PROD) + titre lisible dans StoryMeta + construction
## d'en-tête PROD/DEV. Lancer :
##   C:\Godot\godot.exe --headless --path . -s res://tools/test_env_header.gd

var _failures := 0


func _init() -> void:
	_test_env()
	_test_meta_title()
	_test_header_logic()
	if _failures == 0:
		print("\n[OK] Tous les tests passent.")
	else:
		printerr("\n[ÉCHEC] %d assertion(s) en échec." % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   ", label)
	else:
		_failures += 1
		printerr("  FAIL ", label)


func _test_env() -> void:
	print("Env — détection et override :")
	# Exécution headless via l'éditeur = build debug.
	_check(OS.is_debug_build(), "OS.is_debug_build() vrai en contexte debug")
	_check(Env.is_development(), "Env.is_development() vrai par défaut ici")
	_check(not Env.is_production(), "Env.is_production() faux par défaut ici")

	Env.override_production(true)
	_check(Env.is_production(), "override_production(true) force PROD")
	_check(not Env.is_development(), "override_production(true) => is_development faux")

	Env.override_production(false)
	_check(not Env.is_production(), "override_production(false) force DEV")

	Env.override_production(null)
	_check(Env.is_development(), "override_production(null) => retour à l'auto (DEV ici)")


func _test_meta_title() -> void:
	print("StoryMeta — titre lisible (aller-retour) :")
	var tmp := "user://_test_meta_title.untold"
	var meta := StoryMeta.load_for(tmp)
	_check(meta.get_title("A01S01N019") == "", "titre absent => \"\"")

	meta.set_title("A01S01N019", "Ruelle de l'auberge")
	_check(meta.get_title("A01S01N019") == "Ruelle de l'auberge", "titre défini puis relu")

	meta.set_title("A01S01N019", "   ")  # blanc = effacement
	_check(meta.get_title("A01S01N019") == "", "titre blanc efface l'entrée")

	# Persistance : sauve puis relit depuis le disque.
	meta.set_title("Prologue2", "La statue de Sîn")
	meta.save()
	var reloaded := StoryMeta.load_for(tmp)
	_check(reloaded.get_title("Prologue2") == "La statue de Sîn", "titre persisté et rechargé")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(reloaded.path))


## Reproduit la logique de story.gd::_build_header (sans les autoloads de jeu)
## pour valider les deux branches d'affichage.
func _test_header_logic() -> void:
	print("En-tête — branches PROD / DEV :")
	var meta := StoryMeta.load_for("user://_test_header.untold")
	meta.set_title("Prologue2", "La statue de Sîn")

	Env.override_production(true)
	_check(_header_prod(meta, "Prologue2") == "La statue de Sîn",
			"PROD avec titre => le titre")
	_check(_header_prod(meta, "A01S01N019") == "",
			"PROD sans titre => vide (jamais l'id brut)")

	Env.override_production(null)


## Version isolée de la branche PROD (la branche DEV dépend de Progress/GameState,
## couverte par l'exécution réelle du jeu).
func _header_prod(meta: StoryMeta, node_id: String) -> String:
	if Env.is_production():
		return meta.get_title(node_id)
	return node_id
