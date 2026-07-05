@tool
class_name IllustrationLayer
extends Resource
## Un calque d'illustration (équivalent du LayerInfo Unity).
## layer_index = ordre de dessin ET plan de parallaxe (modèle à 9 calques) : le
## pivot (Settings.parallax_pivot_index, défaut 5) est immobile, les indices
## plus petits passent devant, les plus grands derrière ; l'amplitude croît avec
## |index − pivot| (cf. Illustration).
## parallax_multiplier module l'effet par axe (X=1, Y=0 → parallaxe horizontal).

@export var sprite: Texture2D
@export_range(1, 9) var layer_index: int = 5
@export var parallax_multiplier: Vector2 = Vector2(1, 0)
## Zones interactives — réservé pour le L4b (événements sur une zone de l'image).
@export var interactions: Array = []
