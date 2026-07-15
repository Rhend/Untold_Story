class_name BookTheme
extends RefCounted
## Thème « grimoire » partagé par tous les écrans (hub, sélection, histoire) :
## palette tirée de icon.svg, polices à empattements système, papiers
## parchemin, habillages et ornements communs. Tout est STATIQUE, aucun état
## d'instance — les scènes composent leurs vues avec ces briques.

# ------------------------------------------------------------------ Palette

const DESK := Color("17110b")          # table sous le livre
const LEATHER := Color("4c3826")       # couverture de cuir
const LEATHER_DARK := Color("2d2013")  # contour de la couverture
const PAGE_EDGE := Color("a38a5c")     # bord de page / cadre / filets
const SPINE := Color("6b5637")         # ombre de la reliure
const PARCHMENT := Color("efe3c4")     # papier clair (texte sur cuir)
const PARCHMENT_BRIGHT := Color("f3e9cd")
const INK := Color("312216")           # encre du texte courant
const INK_MUTED := Color("6b5637")     # encre atténuée (titres, légendes)
const INK_FADED := Color("8a7146")     # encre passée (pieds de page, déjà lu)
const RIBBON := Color("7a3126")        # ruban marque-page (accents, survols)

## Polices système memoïsées (une résolution par style, pas une par étiquette).
static var _fonts: Dictionary = {}


# ------------------------------------------------------------------ Polices

## Police à empattements SYSTÈME (Georgia, Times New Roman…) : lecture longue
## agréable sans embarquer de ressource — repli sur la police par défaut du
## moteur si aucune n'est installée.
static func serif(italic := false, bold := false) -> Font:
	var key := ("i" if italic else "") + ("b" if bold else "")
	if not _fonts.has(key):
		var font := SystemFont.new()
		font.font_names = PackedStringArray(
				["Georgia", "Times New Roman", "Palatino Linotype", "serif"])
		font.font_italic = italic
		font.font_weight = 700 if bold else 400
		_fonts[key] = font
	return _fonts[key]


# ------------------------------------------------------------------ Textures

## Texture de dégradé (papiers, ombres). `radial` = du centre vers les bords.
static func gradient_tex(colors: Array, offsets: Array, radial := false) -> Texture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray(colors)
	gradient.offsets = PackedFloat32Array(offsets)
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 512
	tex.height = 2
	if radial:
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.width = 512
		tex.height = 512
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
	else:
		tex.fill_from = Vector2.ZERO
		tex.fill_to = Vector2(1, 0)
	return tex


## Papier d'une page : dégradé parchemin de icon.svg, plus sombre côté reliure
## (resserré près du pli pour ne pas assombrir la zone de lecture).
static func paper(left_side: bool) -> TextureRect:
	var rect := TextureRect.new()
	if left_side:
		rect.texture = gradient_tex(
				[Color("efe3c4"), Color("e6d6b2"), Color("bda678")], [0.0, 0.86, 1.0])
	else:
		rect.texture = gradient_tex(
				[Color("bda678"), Color("e6d6b2"), Color("f3e9cd")], [0.0, 0.14, 1.0])
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## Papier « pleine feuille » (cartes de la sélection) : parchemin clair,
## légèrement plus sombre vers le bas.
static func sheet_paper() -> TextureRect:
	var rect := TextureRect.new()
	var tex := gradient_tex(
			[Color("f3e9cd"), Color("e6d6b2"), Color("d8c49a")], [0.0, 0.7, 1.0]) \
			as GradientTexture2D
	tex.fill_to = Vector2(0, 1)  # dégradé vertical
	rect.texture = tex
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


# ------------------------------------------------------------------ Fonds

## La table : fond de cuir sombre, lucioles sépia qui montent lentement
## (profondeur, casse le noir uni) et vignette radiale qui concentre le
## regard. À ajouter en premier enfant d'une scène plein écran.
static func make_desk() -> Control:
	var desk := Control.new()
	desk.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	desk.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var base := ColorRect.new()
	base.color = DESK
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desk.add_child(base)

	var motes := _make_motes()
	desk.add_child(motes)
	# L'émetteur suit la taille de l'écran (spawn sur toute la surface, un peu
	# au-delà du bas pour que des lucioles « entrent » dans l'image).
	desk.resized.connect(func() -> void:
		motes.position = desk.size / 2.0
		motes.emission_rect_extents = Vector2(desk.size.x / 2.0, desk.size.y / 2.0 + 80.0))

	var vignette := TextureRect.new()
	vignette.texture = gradient_tex(
			[Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.4)],
			[0.0, 0.55, 1.0], true)
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desk.add_child(vignette)
	return desk


## Lucioles : petites boules de lumière sépia qui flottent vers le haut,
## en fondu additif — déjà réparties à l'ouverture (preprocess).
static func _make_motes() -> CPUParticles2D:
	var motes := CPUParticles2D.new()
	motes.amount = 26
	motes.lifetime = 16.0
	motes.preprocess = 16.0
	motes.texture = gradient_tex(
			[Color("e6c98a", 0.9), Color("c9a86a", 0.3), Color("c9a86a", 0.0)],
			[0.0, 0.45, 1.0], true)
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	motes.material = additive

	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	motes.emission_rect_extents = Vector2(960, 620)  # recalé par make_desk
	motes.direction = Vector2(0, -1)
	motes.spread = 22.0
	motes.gravity = Vector2(0, -4)
	motes.initial_velocity_min = 6.0
	motes.initial_velocity_max = 22.0
	motes.scale_amount_min = 0.03
	motes.scale_amount_max = 0.11  # texture 512 px → boules de ~15 à 56 px

	# Fondu d'apparition/disparition le long de la vie de chaque luciole.
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.55),
			Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.0)])
	fade.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	motes.color_ramp = fade
	return motes


## Couverture de cuir (livre, cartes du hub).
static func leather_style(radius := 12, margin := 14.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = LEATHER
	style.set_border_width_all(3)
	style.border_color = LEATHER_DARK
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0, 0, 0, 0.55)
	style.shadow_size = 26
	style.set_content_margin_all(margin)
	return style


# ------------------------------------------------------------------ Ornements

## Usure d'une page : coins légèrement assombris et quelques taches claires,
## déterministes (seed), à poser en surcouche d'un papier.
static func page_wear(seed_value: int) -> Control:
	var wear := Control.new()
	wear.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wear.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wear.clip_contents = true  # l'usure ne déborde jamais de son papier
	wear.draw.connect(func() -> void:
		var size := wear.size
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		# Taches de parchemin (cf. icon.svg), très discrètes.
		for i in 3:
			var center := Vector2(rng.randf_range(0.12, 0.88) * size.x,
					rng.randf_range(0.15, 0.9) * size.y)
			var radius := rng.randf_range(18.0, 42.0)
			wear.draw_set_transform(center, 0.0, Vector2(1.0, rng.randf_range(0.5, 0.7)))
			wear.draw_circle(Vector2.ZERO, radius, Color("bda678", 0.10))
			wear.draw_set_transform(Vector2.ZERO)
		# Coins : légère ombre d'usure, proportionnée au support.
		var corner_radius := minf(46.0, minf(size.x, size.y) * 0.11)
		for corner in [Vector2.ZERO, Vector2(size.x, 0), Vector2(0, size.y), size]:
			wear.draw_set_transform(corner, 0.0, Vector2.ONE)
			wear.draw_circle(Vector2.ZERO, corner_radius, Color("8a7146", 0.07))
			wear.draw_set_transform(Vector2.ZERO))
	return wear


## Fleuron séparateur (losange encadré de tirets), centré, à l'encre passée.
static func make_fleuron() -> Control:
	var fleuron := Control.new()
	fleuron.custom_minimum_size = Vector2(0, 14)
	fleuron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fleuron.draw.connect(func() -> void:
		var center := fleuron.size / 2.0
		var color := Color(INK_FADED, 0.8)
		var diamond := PackedVector2Array([
			center + Vector2(0, -4), center + Vector2(4, 0),
			center + Vector2(0, 4), center + Vector2(-4, 0)])
		fleuron.draw_colored_polygon(diamond, color)
		fleuron.draw_line(center + Vector2(-34, 0), center + Vector2(-10, 0), Color(color, 0.5), 1.0, true)
		fleuron.draw_line(center + Vector2(10, 0), center + Vector2(34, 0), Color(color, 0.5), 1.0, true))
	return fleuron


# ------------------------------------------------------------------ Widgets

## Étiquette prête à l'emploi (police du thème).
static func make_label(text: String, size: int, color: Color,
		italic := false, bold := false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", serif(italic, bold))
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


## Habille un bouton comme une réplique du livre : encre (ou parchemin sur
## fond sombre avec `on_dark`), survol au rouge du ruban / parchemin vif.
## `read` = action déjà connue (encre passée).
static func style_choice(button: Button, read := false, size := 18, on_dark := false) -> void:
	button.focus_mode = Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", serif())
	button.add_theme_font_size_override("font_size", size)
	var base: Color
	var hover: Color
	if on_dark:
		base = INK_FADED if read else PARCHMENT
		hover = PARCHMENT_BRIGHT
	else:
		base = INK_FADED if read else INK
		hover = RIBBON
	button.add_theme_color_override("font_color", base)
	button.add_theme_color_override("font_focus_color", base)
	button.add_theme_color_override("font_disabled_color", Color(base, 0.45))
	for state in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state, hover)
	var normal := StyleBoxEmpty.new()
	normal.set_content_margin_all(6)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("disabled", normal)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var hover_box := StyleBoxFlat.new()
	hover_box.bg_color = Color(PARCHMENT, 0.08) if on_dark else Color(SPINE, 0.12)
	hover_box.set_corner_radius_all(4)
	hover_box.set_content_margin_all(6)
	button.add_theme_stylebox_override("hover", hover_box)
	button.add_theme_stylebox_override("pressed", hover_box)
	# Mise en évidence du survol : léger grossissement depuis le centre, en
	# plus du passage à la couleur d'accent (les boutons désactivés restent tels).
	button.mouse_entered.connect(func() -> void:
		if not button.disabled:
			_animate_scale(button, 1.06))
	button.mouse_exited.connect(func() -> void: _animate_scale(button, 1.0))


## Grossit/repose un bouton au survol (pivot recentré à chaque fois : la
## taille n'est connue qu'après la mise en page).
static func _animate_scale(button: Button, target: float) -> void:
	var previous: Variant = button.get_meta("hover_tween") if button.has_meta("hover_tween") else null
	if previous is Tween and (previous as Tween).is_valid():
		(previous as Tween).kill()
	button.pivot_offset = button.size / 2.0
	var tween := button.create_tween()
	tween.tween_property(button, "scale", Vector2.ONE * target, 0.14) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	button.set_meta("hover_tween", tween)
