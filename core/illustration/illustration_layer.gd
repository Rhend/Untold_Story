class_name IllustrationLayer
extends Resource
## Un calque d'illustration (équivalent du LayerInfo Unity).
## layer_index = ordre de dessin ET plan de parallaxe : 4 = pivot immobile,
## 1→3 devant, 5→8 derrière ; l'amplitude croît avec |index − 4| (cf. Illustration).
## parallax_multiplier module l'effet par axe (X=1, Y=0 → parallaxe horizontal).

@export var sprite: Texture2D
@export_range(1, 8) var layer_index: int = 4
@export var parallax_multiplier: Vector2 = Vector2(1, 0)
## Zones interactives — réservé pour le L4b (événements sur une zone de l'image).
@export var interactions: Array = []
