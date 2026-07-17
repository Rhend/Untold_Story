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
##
## Zones interactives : un calque peut porter des IllustrationInteraction
## (polygones normalisés). Au clic, on teste les zones du premier plan vers le
## fond et on émet interaction_clicked pour la première touchée (l'UI de jeu
## décide des effets — l'illustration reste découplée, cf. story.gd).

## Émis au clic sur une zone interactive (la première touchée, premier plan
## prioritaire). L'illustration n'exécute aucun effet elle-même.
signal interaction_clicked(interaction: IllustrationInteraction)

## Petite marge de sécurité au-delà du décalage max, en px.
const EDGE_MARGIN := 8.0

## Signifiants des zones interactives : à l'apparition de la planche, un bref
## scintillement révèle les contours (découvrabilité) ; au survol, la zone luit
## doucement et le curseur devient une main ; au clic, un éclat bref confirme.
const REVEAL_DELAY := 0.8
const REVEAL_DURATION := 2.4

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
## [{ "rect": TextureRect, "scroll": float, "mult": Vector2, "zones": Array }]
## Ordre : fond → premier plan (index décroissant, cf. tri de setup).
var _layers: Array = []
## true si au moins un calque porte des zones interactives (accepte les clics).
var _has_zones := false
## Surcouche des signifiants de zones (au-dessus de tous les calques), et zone
## actuellement survolée (null hors zone).
var _glow: ZoneGlow
var _hovered_zone: IllustrationInteraction = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Empêche un calque décalé par le parallaxe de déborder hors de la zone.
	clip_contents = true
	mouse_exited.connect(_clear_hover)
	# Amplitude non fixée par l'instance → réglage global partagé.
	if is_nan(parallax_gain):
		parallax_gain = Settings.parallax_gain_default


func setup(data: IllustrationData) -> void:
	for child in get_children():
		child.queue_free()
	_layers.clear()
	_max_distance = 0
	_has_zones = false

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
		if not layer.interactions.is_empty():
			_has_zones = true
		_layers.append({
			"rect": rect,
			"scroll": scroll,
			"mult": layer.parallax_multiplier,
			"zones": layer.interactions,
		})

	# N'intercepte les clics que s'il y a des zones (sinon reste transparent
	# à la souris, pour ne pas voler les clics à l'UI au-dessus/en dessous).
	mouse_filter = Control.MOUSE_FILTER_STOP if _has_zones else Control.MOUSE_FILTER_IGNORE

	# Signifiants : la surcouche est ajoutée EN DERNIER (dessinée au-dessus de
	# tous les calques) et le scintillement de découverte est lancé.
	_glow = null
	_hovered_zone = null
	if _has_zones:
		_glow = ZoneGlow.new()
		_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_glow)
		_glow.start_reveal(REVEAL_DELAY, REVEAL_DURATION)


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

	# Les polygones suivent le parallaxe : projetés à CHAQUE trame avec les
	# rects courants, la surcouche reste collée aux calques.
	if _glow != null:
		_glow.set_polys(_all_screen_polys(), _screen_poly_of(_hovered_zone))


## Clic sur l'illustration : teste les zones du PREMIER PLAN (index de calque le
## plus petit) vers le fond, et émet la première touchée. Au survol : curseur
## main + lueur douce sur la zone (signifiants). Le polygone normalisé est
## projeté avec le rect COURANT du calque (position/size déjà mis à jour par
## _process), donc le décalage de parallaxe est pris en compte automatiquement.
func _gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null:
		var zone := _zone_at(motion.position)
		if zone != _hovered_zone:
			_hovered_zone = zone
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if zone != null \
					else Control.CURSOR_ARROW
		return

	if not (event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var clicked := _zone_at(event.position)
	if clicked != null:
		if _glow != null:
			_glow.flash(_screen_poly_of(clicked))
		interaction_clicked.emit(clicked)
		accept_event()


func _clear_hover() -> void:
	_hovered_zone = null
	mouse_default_cursor_shape = Control.CURSOR_ARROW


## Zone sous le point (local à l'illustration), ou null. _layers va du fond au
## premier plan : parcouru à l'envers pour donner la priorité au premier plan
## en cas de zones superposées.
func _zone_at(point: Vector2) -> IllustrationInteraction:
	for i in range(_layers.size() - 1, -1, -1):
		var entry: Dictionary = _layers[i]
		var rect: TextureRect = entry["rect"]
		for zone in entry["zones"]:
			if _point_in_zone(point, zone, rect.position, rect.size):
				return zone
	return null


## Polygones écran de TOUTES les zones (pour le scintillement de découverte).
func _all_screen_polys() -> Array:
	var polys: Array = []
	for entry in _layers:
		var rect: TextureRect = entry["rect"]
		for zone in entry["zones"]:
			polys.append(_project_poly(zone, rect.position, rect.size))
	return polys


## Polygone écran d'une zone (vide si null), projeté sur le rect de son calque.
func _screen_poly_of(zone: IllustrationInteraction) -> PackedVector2Array:
	if zone == null:
		return PackedVector2Array()
	for entry in _layers:
		if entry["zones"].has(zone):
			var rect: TextureRect = entry["rect"]
			return _project_poly(zone, rect.position, rect.size)
	return PackedVector2Array()


func _project_poly(zone: IllustrationInteraction,
		rect_pos: Vector2, rect_size: Vector2) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for p in zone.polygon:
		poly.append(rect_pos + Vector2(p.x * rect_size.x, p.y * rect_size.y))
	return poly


## Le point (local à l'illustration) tombe-t-il dans le polygone de la zone,
## projeté sur le rect courant du calque (coordonnées normalisées → écran) ?
func _point_in_zone(point: Vector2, zone: IllustrationInteraction,
		rect_pos: Vector2, rect_size: Vector2) -> bool:
	if zone.polygon.size() < 3:
		return false
	return Geometry2D.is_point_in_polygon(point, _project_poly(zone, rect_pos, rect_size))


## Surcouche des signifiants de zones, dessinée au-dessus de tous les calques.
## Trois effets, tous discrets et sans interaction souris :
##  - « révélation » : à l'apparition de la planche, les contours des zones
##    scintillent brièvement puis s'éteignent (le joueur SAIT qu'on peut
##    cliquer, sans spoiler en permanence) ;
##  - « survol » : la zone sous le curseur luit doucement (pulsation lente) ;
##  - « éclat » : au clic, un flash bref confirme que le geste a porté.
class ZoneGlow extends Control:
	const GLOW := Color(1.0, 0.93, 0.72)  # lueur chaude, dans les tons parchemin

	var _all: Array = []                      # PackedVector2Array par zone
	var _hover := PackedVector2Array()
	var _reveal_delay := 0.0
	var _reveal_left := 0.0
	var _reveal_total := 1.0
	var _flash_left := 0.0
	var _flash_poly := PackedVector2Array()

	func start_reveal(delay: float, duration: float) -> void:
		_reveal_delay = delay
		_reveal_left = duration
		_reveal_total = duration

	func flash(poly: PackedVector2Array) -> void:
		_flash_poly = poly
		_flash_left = 0.35

	## Polygones écran à jour (appelé chaque trame par l'illustration : les
	## zones suivent le parallaxe).
	func set_polys(all: Array, hover: PackedVector2Array) -> void:
		_all = all
		_hover = hover

	func _process(delta: float) -> void:
		if _reveal_delay > 0.0:
			_reveal_delay -= delta
		elif _reveal_left > 0.0:
			_reveal_left -= delta
		if _flash_left > 0.0:
			_flash_left -= delta
		# La pulsation de survol anime en continu : on redessine dès qu'un
		# effet est visible.
		if _reveal_left > 0.0 or _flash_left > 0.0 or not _hover.is_empty():
			queue_redraw()

	func _draw() -> void:
		# Révélation : intensité en cloche (monte, culmine, s'éteint).
		if _reveal_delay <= 0.0 and _reveal_left > 0.0:
			var a := sin(PI * clampf(_reveal_left / _reveal_total, 0.0, 1.0)) * 0.55
			for poly in _all:
				_draw_zone(poly, a * 0.16, a)
		# Survol : lueur douce qui respire.
		if not _hover.is_empty():
			var pulse := 0.55 + 0.15 * sin(Time.get_ticks_msec() / 320.0)
			_draw_zone(_hover, 0.11, pulse)
		# Éclat de clic : bref et net.
		if _flash_left > 0.0 and not _flash_poly.is_empty():
			var f := clampf(_flash_left / 0.35, 0.0, 1.0)
			_draw_zone(_flash_poly, f * 0.30, f * 0.9)

	## Le contour est un DOUBLE trait — halo d'encre sombre dessous, cœur
	## lumineux dessus — pour rester lisible sur les planches claires (sépia)
	## comme sur les sombres. L'encre reprend le trait des illustrations.
	const INK := Color(0.18, 0.10, 0.05)

	func _draw_zone(poly: PackedVector2Array, fill_alpha: float, line_alpha: float) -> void:
		if poly.size() < 3:
			return
		if fill_alpha > 0.0:
			draw_colored_polygon(poly, Color(GLOW, fill_alpha))
		var closed := poly.duplicate()
		closed.append(poly[0])
		draw_polyline(closed, Color(INK, line_alpha * 0.75), 5.0, true)
		draw_polyline(closed, Color(GLOW, line_alpha), 2.0, true)
