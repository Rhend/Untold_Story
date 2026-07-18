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


# ------------------------------------------------------------- Livre ouvert

## Construit le livre ouvert complet — cuir, tranches de papier, deux pages
## côte à côte et reliure centrale — identique dans toutes les scènes qui le
## montrent (histoire, sélection). Renvoie :
##   "root"  : le Control plein écran à ajouter à la scène (marges incluses) ;
##   "pages" : le HBoxContainer où poser la page de gauche puis celle de droite.
##
## Le livre est cadré MANUELLEMENT au ratio demandé (aspect-fit centré dans
## l'espace disponible) : un AspectRatioContainer couplerait la largeur du
## livre à la hauteur minimale de son contenu — couplage qui a déjà fait
## osciller la mise en page sans fin (jeu figé, cf. correctif dans story.gd).
## Un enfant posé à la main ne renvoie aucune contrainte : boucle impossible.
static func make_open_book(margin: int, top_offset := 0.0,
		ratio := 420.0 / 297.0, page_block := 9.0) -> Dictionary:
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_top = top_offset
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		root.add_theme_constant_override(side, margin)

	# L'espace du livre : un Control simple dont l'enfant est cadré à la main.
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)

	var book := PanelContainer.new()
	book.add_theme_stylebox_override("panel", leather_style(12, 18.0))
	box.add_child(book)
	var layout_book := func() -> void:
		var space := box.size
		if space.x <= 0.0 or space.y <= 0.0:
			return
		var book_size := Vector2(space.y * ratio, space.y)
		if book_size.x > space.x:  # trop large pour l'espace : la largeur gouverne
			book_size = Vector2(space.x, space.x / ratio)
		book.position = (space - book_size) * 0.5
		book.size = book_size
	box.resized.connect(layout_book)
	# Re-cadre AUSSI quand le minimum du livre se détend : au tout premier
	# calcul, un texte adaptatif encore sans largeur peut gonfler le minimum
	# (retour à la ligne à chaque mot) — set_size est alors clampé vers le
	# haut, et sans ce rappel le livre resterait démesuré. Connexion DIFFÉRÉE :
	# jamais de re-cadrage au milieu d'une passe de mise en page.
	book.minimum_size_changed.connect(layout_book, CONNECT_DEFERRED)

	# Épaisseur du livre : le bloc des pages (tranches empilées) dépasse du
	# cuir tout autour, et les pages ouvertes reposent dessus.
	book.add_child(make_page_block(page_block))
	var pages_margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pages_margin.add_theme_constant_override(side, int(page_block))
	book.add_child(pages_margin)

	var pages := HBoxContainer.new()
	pages.add_theme_constant_override("separation", 0)
	pages_margin.add_child(pages)

	# Reliure centrale : creux ombré ET renflement clair des pages de part et
	# d'autre du pli — le relief que le simple dégradé n'avait pas.
	var spine := TextureRect.new()
	spine.texture = gradient_tex(
			[Color(SPINE, 0.0), Color(PARCHMENT_BRIGHT, 0.16),
			Color(SPINE, 0.60), Color(SPINE, 0.60),
			Color(PARCHMENT_BRIGHT, 0.16), Color(SPINE, 0.0)],
			[0.44, 0.474, 0.494, 0.506, 0.526, 0.56])
	spine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	book.add_child(spine)

	return {"root": root, "pages": pages}


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
		# Taches de parchemin (cf. icon.svg), discrètes mais perceptibles.
		for i in 4:
			var center := Vector2(rng.randf_range(0.12, 0.88) * size.x,
					rng.randf_range(0.15, 0.9) * size.y)
			var radius := rng.randf_range(20.0, 48.0)
			wear.draw_set_transform(center, 0.0, Vector2(1.0, rng.randf_range(0.5, 0.7)))
			wear.draw_circle(Vector2.ZERO, radius, Color("bda678", 0.16))
			wear.draw_set_transform(Vector2.ZERO)
		# Coins : ombre d'usure, proportionnée au support.
		var corner_radius := minf(52.0, minf(size.x, size.y) * 0.12)
		for corner in [Vector2.ZERO, Vector2(size.x, 0), Vector2(0, size.y), size]:
			wear.draw_set_transform(corner, 0.0, Vector2.ONE)
			wear.draw_circle(Vector2.ZERO, corner_radius, Color("8a7146", 0.12))
			wear.draw_set_transform(Vector2.ZERO))
	return wear


## Bloc des pages : tranches de papier empilées qui dépassent de la couverture
## et donnent son épaisseur au livre — bandes concentriques, du bord sombre
## vers le papier clair, séparées de fins filets. À poser entre le cuir et les
## pages ouvertes (qui recouvrent le centre, à `depth` px des bords).
static func make_page_block(depth := 9.0) -> Control:
	var block := Control.new()
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.draw.connect(func() -> void:
		const STEPS := 4
		for i in STEPS:
			var inset := depth * float(i) / float(STEPS)
			var rect := Rect2(Vector2(inset, inset),
					block.size - Vector2(inset, inset) * 2.0)
			block.draw_rect(rect, Color("bda678").lerp(Color("efe3c4"),
					float(i + 1) / float(STEPS)), true)
			if i > 0:
				block.draw_rect(rect, Color(PAGE_EDGE, 0.45), false, 1.0))
	return block


## Enluminure simple d'une page : double filet doré au trait fin, coins ornés
## (équerres + losange rubriqué au rouge du ruban) et losanges médians haut et
## bas. À poser au-dessus du papier et de l'usure, sous le contenu.
static func make_page_frame() -> Control:
	var frame := Control.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.draw.connect(func() -> void:
		var gold := Color(PAGE_EDGE, 0.65)
		var gold_soft := Color(PAGE_EDGE, 0.35)
		var outer := Rect2(Vector2.ZERO, frame.size).grow(-11.0)
		frame.draw_rect(outer, gold, false, 1.2, true)
		frame.draw_rect(outer.grow(-4.0), gold_soft, false, 1.0, true)

		const ARM := 22.0  # longueur des équerres de coin
		for corner in [outer.position, Vector2(outer.end.x, outer.position.y),
				Vector2(outer.position.x, outer.end.y), outer.end]:
			var dx: float = ARM if corner.x < outer.get_center().x else -ARM
			var dy: float = ARM if corner.y < outer.get_center().y else -ARM
			frame.draw_line(corner, corner + Vector2(dx, 0), gold, 1.8, true)
			frame.draw_line(corner, corner + Vector2(0, dy), gold, 1.8, true)
			_draw_diamond(frame, corner, 4.0, Color(RIBBON, 0.8))
		for mid_y in [outer.position.y, outer.end.y]:
			_draw_diamond(frame, Vector2(outer.get_center().x, mid_y), 3.0, gold))
	return frame


## Petit losange plein (ornement d'enluminure) centré sur `center`.
static func _draw_diamond(canvas: CanvasItem, center: Vector2, radius: float,
		color: Color) -> void:
	canvas.draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -radius), center + Vector2(radius, 0),
		center + Vector2(0, radius), center + Vector2(-radius, 0)]), color)


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

## Lettrine : première lettre du texte grossie à l'encre du ruban — la même
## écriture en tête des passages du récit et des pages de garde. Sans effet si
## le texte commence par une balise BBCode ou un caractère non alphabétique.
static func with_drop_cap(text: String) -> String:
	var i := 0
	while i < text.length() and text[i] in [" ", "\t", "\n"]:
		i += 1
	if i >= text.length():
		return text
	var first := text[i]
	if first == "[" or first.to_upper() == first.to_lower():
		return text
	return text.substr(0, i) \
			+ "[font_size=44][color=#7a3126]%s[/color][/font_size]" % first \
			+ text.substr(i + 1)


## Grossissement au survol : à connecter sur n'importe quel Control cliquable
## (portraits, couvertures du hub…). `grow` = échelle atteinte au survol.
static func connect_hover_scale(control: Control, grow := 1.06) -> void:
	control.mouse_entered.connect(func() -> void: hover_scale(control, grow))
	control.mouse_exited.connect(func() -> void: hover_scale(control, 1.0))


## Tue le tween de survol en cours d'un contrôle (posé par hover_scale sous la
## méta « hover_tween ») — pour les transitions qui reprennent la main sur la
## géométrie du contrôle (ex. plongeon du hub) sans se faire écraser.
static func kill_hover_tween(control: Control) -> void:
	var previous: Variant = control.get_meta("hover_tween") \
			if control.has_meta("hover_tween") else null
	if previous is Tween and (previous as Tween).is_valid():
		(previous as Tween).kill()


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
			hover_scale(button, 1.06))
	button.mouse_exited.connect(func() -> void: hover_scale(button, 1.0))


## Grossit/repose un contrôle au survol (pivot recentré à chaque fois : la
## taille n'est connue qu'après la mise en page). Le tween en cours est tué
## avant d'en relancer un (survols rapides). `tint` optionnel : le modulate
## glisse en parallèle vers cette couleur (éclaircissement des couvertures).
static func hover_scale(control: Control, target: float, tint: Variant = null) -> void:
	kill_hover_tween(control)
	control.pivot_offset = control.size / 2.0
	var tween := control.create_tween()
	tween.tween_property(control, "scale", Vector2.ONE * target, 0.14) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if tint is Color:
		tween.set_parallel()
		tween.tween_property(control, "modulate", tint, 0.14)
	control.set_meta("hover_tween", tween)
