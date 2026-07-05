@tool
class_name GameSettings
extends Resource
## Réglages partagés de tout le projet, éditables dans l'inspecteur Godot via
## data/game_settings.tres et chargés au démarrage par l'autoload « Settings ».
##
## Ce fichier a vocation à accueillir d'autres réglages au fil du temps
## (vitesse de texte, volumes, accessibilité…) : ajouter un @export ici suffit,
## l'autoload l'expose automatiquement sous Settings.<nom_du_champ>.

## Index du calque immobile (plan de référence) du parallaxe. Modèle à 9
## calques : les indices < pivot passent devant, > pivot passent derrière.
@export var parallax_pivot_index: int = 5

## Multiplicateur appliqué au « regard » souris avant le clamp [-1, 1].
## > 1 = plus sensible (atteint les bords plus vite), < 1 = plus doux.
@export var mouse_sensitivity: float = 1.0

## Amplitude par défaut du parallaxe (px de décalage par unité de distance au
## pivot et de regard). Une illustration peut la surcharger par instance.
@export var parallax_gain_default: float = 9.0

## Vitesse de l'effet « machine à écrire » : secondes par caractère visible.
## Plus petit = plus rapide.
@export var text_speed: float = 0.02
