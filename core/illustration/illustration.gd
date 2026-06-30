class_name Illustration
extends Control
## Affiche une IllustrationData en calques superposés et applique un parallaxe
## piloté par une LookSource (souris par défaut).
##
## L'illustration s'adapte à SA PROPRE zone (Control), pas au viewport entier :
## elle peut donc occuper tout l'écran (paysage) ou une demi-page (portrait,
## mise en page « livre »).
##
## Modèle de parallaxe (façon diorama, repris du projet d'origine) :
##   - Le calque PIVOT (layer_index 4) ne bouge JAMAIS : il cadre la scène.
##   - Les calques DEVANT le pivot (1,2,3) et DERRIÈRE (5,6,7,8) se décalent
##     d'autant plus qu'ils sont LOIN du pivot (amplitude = |index − 4|).
##   - Devant et derrière se décalent en sens OPPOSÉS (offset = (index−4) × …).

## Index du calque pivot (immobile, plan de référence).
const PIVOT_INDEX := 4
## Petite marge de sécurité au-delà du décalage max, en px.
const EDGE_MARGIN := 8.0

## Amplitude du parallaxe : px de décalage par unité de distance au pivot et par
## unité de « regard » (-1..1). Le calque le plus loin (|index−4| max) se décale
## de _max_distance × parallax_gain au maximum.
@export var parallax_gain := 9.0

var look_source: LookSource = MouseLookSource.new()

## true = on montre l'illustration ENTIÈRE, cadrée dans la zone (portrait,
## page de livre) ; false = on REMPLIT la zone quitte à rogner (paysage plein écran).
var _contain := false
var _max_distance := 0  # plus grande |index − 4| parmi les calques (pour l'overscan)
var _layers: Array = []  # [{ "rect": TextureRect, "scroll": float, "mult": Vector2 }]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Empêche un calque décalé par le parallaxe de déborder hors de la zone.
	clip_contents = true


func setup(data: IllustrationData) -> void:
	for child in get_children():
		child.queue_free()
	_layers.clear()
	_max_distance = 0

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

		# Décalage signé par rapport au pivot : devant (<0), derrière (>0), pivot (0).
		var scroll := float(layer.layer_index - PIVOT_INDEX)
		_max_distance = maxi(_max_distance, absi(layer.layer_index - PIVOT_INDEX))
		_layers.append({
			"rect": rect,
			"scroll": scroll,
			"mult": layer.parallax_multiplier,
		})


func _process(_delta: float) -> void:
	if _layers.is_empty():
		return

	var look := look_source.sample(get_viewport())
	# Overscan commun = juste assez pour couvrir le décalage max du calque le
	# plus mobile (mode plein cadre uniquement). Garde le zoom minimal.
	var overscan := 0.0 if _contain else (_max_distance * parallax_gain + EDGE_MARGIN)
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
