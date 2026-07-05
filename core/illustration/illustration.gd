class_name Illustration
extends Control
## Affiche une IllustrationData en calques superposés et applique un parallaxe
## piloté par une LookSource (souris par défaut).
##
## L'illustration s'adapte à SA PROPRE zone (Control), pas au viewport entier :
## elle peut donc occuper tout l'écran (paysage) ou une demi-page (portrait,
## mise en page « livre »).
##
## Modèle de parallaxe (façon diorama, repris du projet d'origine), à 9 calques :
##   - Le calque PIVOT (Settings.parallax_pivot_index, défaut 5) ne bouge
##     JAMAIS : il cadre la scène.
##   - Les calques DEVANT le pivot (1..4) et DERRIÈRE (6..9) se décalent d'autant
##     plus qu'ils sont LOIN du pivot (amplitude = |index − pivot|).
##   - Devant et derrière se décalent en sens OPPOSÉS (offset ∝ (index − pivot)).
##   - parallax_gain module l'amplitude globale ; une illustration dont
##     IllustrationData.parallax_enabled == false reste totalement figée.

## Petite marge de sécurité au-delà du décalage max, en px.
const EDGE_MARGIN := 8.0

## Amplitude du parallaxe : px de décalage par unité de distance au pivot et par
## unité de « regard » (-1..1). NAN = hériter de Settings.parallax_gain_default ;
## fixer une valeur dans l'inspecteur surcharge ce réglage global pour l'instance.
@export var parallax_gain := NAN

var look_source: LookSource = MouseLookSource.new()

## true = on montre l'illustration ENTIÈRE, cadrée dans la zone (portrait,
## page de livre) ; false = on REMPLIT la zone quitte à rogner (paysage plein écran).
var _contain := false
## false = illustration figée (aucun décalage de parallaxe), cf. IllustrationData.
var _parallax_enabled := true
var _max_distance := 0  # plus grande |index − pivot| parmi les calques (pour l'overscan)
var _layers: Array = []  # [{ "rect": TextureRect, "scroll": float, "mult": Vector2 }]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Empêche un calque décalé par le parallaxe de déborder hors de la zone.
	clip_contents = true
	# Amplitude non fixée par l'instance → réglage global partagé.
	if is_nan(parallax_gain):
		parallax_gain = Settings.parallax_gain_default


func setup(data: IllustrationData) -> void:
	for child in get_children():
		child.queue_free()
	_layers.clear()
	_max_distance = 0

	# Portrait et Character : on garde toute l'image visible (fit, cadre carré/
	# vertical). Paysage : on remplit la zone quitte à rogner (cover).
	_contain = data.template != IllustrationData.Template.LANDSCAPE
	_parallax_enabled = data.parallax_enabled
	var pivot: int = Settings.parallax_pivot_index
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
		var scroll := float(layer.layer_index - pivot)
		_max_distance = maxi(_max_distance, absi(layer.layer_index - pivot))
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
	# plus mobile. Dépend du parallax (pas du gabarit) : une illustration en
	# mode contain avec parallax rogne donc un peu son cadrage — compromis
	# assumé (parallax + contain), pas un bug. Sans parallax, aucun overscan.
	var overscan := (_max_distance * parallax_gain + EDGE_MARGIN) if _parallax_enabled else 0.0
	var layer_size := size + Vector2(overscan * 2.0, overscan * 2.0)
	var base := Vector2(-overscan, -overscan)

	for entry in _layers:
		var rect: TextureRect = entry["rect"]
		rect.size = layer_size
		var offset := Vector2.ZERO
		# Illustration figée (parallax_enabled == false) : aucun décalage.
		if _parallax_enabled:
			var mult: Vector2 = entry["mult"]
			offset = Vector2(
				entry["scroll"] * mult.x * look.x,
				entry["scroll"] * mult.y * look.y
			) * parallax_gain
		rect.position = base + offset
