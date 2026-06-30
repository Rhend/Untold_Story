class_name Illustration
extends Control
## Affiche une IllustrationData en calques superposés et applique un parallaxe
## piloté par une LookSource (souris par défaut).
##
## L'illustration s'adapte à SA PROPRE zone (Control), pas au viewport entier :
## elle peut donc occuper tout l'écran (paysage) ou une demi-page (portrait,
## mise en page « livre »).
##
## Pour chaque calque : décalage = scroll(layer_index) × multiplier × regard × gain.
## scroll provient de la table ParallaxScrollValue reprise de la version Unity,
## indexée par layer_index (1→9).

## Table ParallaxScrollValue d'origine (indexée par layer_index, 1 à 9).
const SCROLL_VALUES := [10.0, 7.0, 5.0, 2.0, 0.0, -2.0, -5.0, -7.0, -10.0]
## Marge de débord pour que le décalage ne révèle pas les bords des calques
## (mode plein cadre uniquement).
const OVERSCAN := 96.0

## Amplitude globale du parallaxe (px par unité de scroll). Réglable au debug.
@export var parallax_gain := 4.0

var look_source: LookSource = MouseLookSource.new()

## true = on montre l'illustration ENTIÈRE, cadrée dans la zone (portrait,
## page de livre) ; false = on REMPLIT la zone quitte à rogner (paysage plein écran).
var _contain := false
var _layers: Array = []  # [{ "rect": TextureRect, "scroll": float, "mult": Vector2 }]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Empêche un calque décalé par le parallaxe de déborder hors de la zone.
	clip_contents = true


func setup(data: IllustrationData) -> void:
	for child in get_children():
		child.queue_free()
	_layers.clear()

	_contain = data.template == IllustrationData.Template.PORTRAIT
	# Portrait : on garde toute l'image visible (fit). Paysage : on remplit (cover).
	var stretch := TextureRect.STRETCH_KEEP_ASPECT_CENTERED if _contain \
		else TextureRect.STRETCH_KEEP_ASPECT_COVERED

	# Tri par layer_index DÉCROISSANT : le fond (index élevé) est ajouté en
	# premier (dessiné dessous), le premier plan (index faible) en dernier
	# (dessiné au-dessus). L'inverse masquerait le premier plan sous le fond.
	var ordered := data.layers.duplicate()
	ordered.sort_custom(func(a, b): return a.layer_index > b.layer_index)

	for layer in ordered:
		var rect := TextureRect.new()
		rect.texture = layer.sprite
		rect.stretch_mode = stretch
		# Sans ça, la taille native de la texture sert de taille minimale et le
		# dimensionnement à la zone (cf. _process) est ignoré → image énorme.
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
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
	# On se cale sur la taille de CE Control (zone allouée), pas sur le viewport.
	var overscan := 0.0 if _contain else OVERSCAN
	var layer_size := size + Vector2(overscan * 2.0, overscan * 2.0)
	var base := Vector2(-overscan, -overscan)

	for entry in _layers:
		var rect: TextureRect = entry["rect"]
		rect.size = layer_size
		var mult: Vector2 = entry["mult"]
		var offset := Vector2(
			entry["scroll"] * mult.x * look.x,
			entry["scroll"] * mult.y * look.y
		) * parallax_gain
		rect.position = base + offset
