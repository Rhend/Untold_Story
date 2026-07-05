@tool
class_name Env
extends RefCounted
## Distinction environnement DEV / PROD.
##
##   DEV  = éditeur, ou export "avec debug" → affichages de debug autorisés.
##   PROD = export release → aucune fuite de détail technique au joueur.
##
## Détection native Godot 4 : OS.is_debug_build() (vrai en éditeur et en export
## debug, faux en export release) — gratuit, sans configuration. Des retours
## communautaires signalent toutefois des incohérences de cette API sur
## certaines cibles (rapporté sur Android). Cible du projet = PC/Steam, risque
## faible mais À CONFIRMER sur un vrai export release Windows.
##
## Fallback prêt (non activé) : override_production() force le mode, quelle que
## soit la valeur de is_debug_build(). Peut être appelé au démarrage depuis un
## fichier de config, en dur, ou par les tests. `null` = détection automatique.

## null = auto (OS.is_debug_build) ; true/false = mode forcé.
static var _force_production: Variant = null


## Vrai en export release (ou si forcé PROD). En PROD, ne rien montrer au
## joueur qui relève du debug (ids techniques, etc.).
static func is_production() -> bool:
	if _force_production != null:
		return bool(_force_production)
	return not OS.is_debug_build()


## Vrai en éditeur / export debug (ou si forcé DEV).
static func is_development() -> bool:
	return not is_production()


## Force le mode : true = PROD, false = DEV, null = revenir à la détection
## automatique. Sert de filet si is_debug_build() se révèle non fiable sur la
## cible d'export, et permet aux tests de simuler la production.
static func override_production(value: Variant) -> void:
	_force_production = value
