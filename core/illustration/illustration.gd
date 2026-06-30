class_name Illustration
extends Control
## Affiche une IllustrationData en calques superposés et applique un parallaxe
## piloté par une LookSource (souris par défaut).
##
## Pour chaque calque : décalage = scroll(layer_index) × multiplier × regard × gain.
## scroll provient de la table ParallaxScrollValue reprise de la version Unity,
## indexée par layer_index (1→9).

## Table ParallaxScrollValue d'origine (indexée par layer_index, 1 à 9).
const SCROLL_VALUES := [10.0, 7.0, 5.0, 2.0, 0.0, -2.0, -5.0, -7.0, -10.0]
## Marge de débord pour que le décalage ne révèle pas les bords des calques.
const OVERSCAN := 96.0

## Amplitude globale du parallaxe (px par unité de scroll). Réglable au debug.
@export var parallax_gain := 4.0

var look_source: LookSource = MouseLookSource.new()

var _layers: Array = []  # [{ "rect": TextureRect, "scroll": float, "mult": Vector2 }]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(data: IllustrationData) -> void:
	for child in get_children():
		child.queue_free()
	_layers.clear()

	var ordered := data.layers.duplicate()
	ordered.sort_custom(func(a, b): return a.layer_index < b.layer_index)

	for layer in ordered:
		var rect := TextureRect.new()
		rect.texture = layer.sprite
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rect)

		var idx: int = clampi(layer.layer_index - 1, 0, SCROLL_VALUES.size() - 1)
		_layers.append({
			"rect": rect,
			"scroll": SCROLL_VALUES[idx],
			"mult": layer.parallax_multiplier,
		})


func _process(_delta: float) -> void:
	if _layers.is_empty():
		return

	var look := look_source.sample(get_viewport())
	var view_size := get_viewport_rect().size
	var layer_size := view_size + Vector2(OVERSCAN * 2.0, OVERSCAN * 2.0)
	var base := Vector2(-OVERSCAN, -OVERSCAN)

	for entry in _layers:
		var rect: TextureRect = entry["rect"]
		rect.size = layer_size
		var mult: Vector2 = entry["mult"]
		var offset := Vector2(
			entry["scroll"] * mult.x * look.x,
			entry["scroll"] * mult.y * look.y
		) * parallax_gain
		rect.position = base + offset
