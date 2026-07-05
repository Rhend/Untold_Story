extends Node
## Autoload « Settings » : charge les réglages partagés (GameSettings, depuis
## data/game_settings.tres) au démarrage et les expose au reste du projet
## directement sous Settings.<champ> (ex. Settings.parallax_pivot_index).
##
## La ressource elle-même reste accessible via Settings.config (pour recharger
## ou éditer). Si le .tres est absent, on retombe sur les défauts de GameSettings.

const SETTINGS_PATH := "res://data/game_settings.tres"

## Ressource de réglages chargée (jamais null après _ready).
var config: GameSettings

## Noms des champs @export de la ressource, pour le forwarding Settings.<champ>.
var _keys: Dictionary = {}


func _ready() -> void:
	config = ResourceLoader.load(SETTINGS_PATH) as GameSettings
	if config == null:
		push_warning("Settings: %s introuvable — valeurs par défaut utilisées." % SETTINGS_PATH)
		config = GameSettings.new()
	for prop in config.get_property_list():
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			_keys[prop["name"]] = true


## Expose chaque champ de la ressource : Settings.parallax_pivot_index renvoie
## config.parallax_pivot_index. Retourne null pour toute autre propriété (le
## moteur poursuit alors sa résolution normale).
func _get(property: StringName) -> Variant:
	if _keys.has(property):
		return config.get(property)
	return null
