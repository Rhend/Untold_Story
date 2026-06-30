class_name IllustrationLayer
extends Resource
## Un calque d'illustration (équivalent du LayerInfo Unity).
## layer_index = ordre de dessin ET intensité de parallaxe (via la table
## ParallaxScrollValue, voir Illustration). parallax_multiplier module l'effet
## par axe (X=1, Y=0 → parallaxe horizontal uniquement).

@export var sprite: Texture2D
@export_range(1, 9) var layer_index: int = 1
@export var parallax_multiplier: Vector2 = Vector2(1, 0)
## Zones interactives — réservé pour le L4b (événements sur une zone de l'image).
@export var interactions: Array = []
