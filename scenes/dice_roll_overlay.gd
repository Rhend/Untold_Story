class_name DiceRollOverlay
extends Control
## Animation d'un jet de compétence (@roll) : une petite feuille de parchemin
## se pose au-dessus du livre, un dé y roule (faces qui défilent, tremblement),
## s'arrête sur la valeur tirée, puis le détail du calcul et le verdict
## apparaissent — et tout s'efface. Autonome : s'ajoute à la scène, joue,
## et se détruit tout seul (queue_free). Ne bloque ni la souris ni le récit.
##
## Usage (cf. story.gd) :
##   var overlay := DiceRollOverlay.new()
##   add_child(overlay)
##   overlay.play(skill, die, bonus, total, difficulty, success)

const SUCCESS_COLOR := Color(0.23, 0.42, 0.2)   # encre verte sobre
const FAILURE_COLOR := Color("7a3126")           # rouge du ruban (BookTheme)

## Durées des phases (secondes) : apparition, roulement, verdict, tenue, fondu.
const APPEAR := 0.25
const ROLLING := 0.9
const HOLD := 2.1
const FADE := 0.45

var _card: PanelContainer
var _die: DieFace
var _title: Label
var _detail: Label
var _verdict: Label

var _die_value := 1
var _elapsed := 0.0
var _playing := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_card()


## Lance l'animation avec le résultat DÉJÀ résolu par le moteur (le dé affiché
## finit exactement sur `die` — le visuel raconte, il ne décide pas).
func play(skill: String, die: int, bonus: int, total: int,
		difficulty: int, success: bool) -> void:
	_die_value = die
	var pretty := skill.capitalize()
	var elide := pretty.left(1).to_lower() in ["a", "e", "i", "o", "u", "h", "é", "à"]
	_title.text = "Jet %s%s" % ["d'" if elide else "de ", pretty]
	_detail.text = "dé %d  +  %s %d   =   %d    (difficulté %d)" \
			% [die, skill, bonus, total, difficulty]
	_verdict.text = "Réussite !" if success else "Échec…"
	_verdict.add_theme_color_override("font_color",
			SUCCESS_COLOR if success else FAILURE_COLOR)
	_detail.modulate.a = 0.0
	_verdict.modulate.a = 0.0
	modulate.a = 0.0
	_elapsed = 0.0
	_playing = true


func _process(delta: float) -> void:
	if not _playing:
		return
	_elapsed += delta
	var t := _elapsed

	# Apparition : fondu + légère pose de la feuille.
	modulate.a = clampf(t / APPEAR, 0.0, 1.0)
	_card.rotation_degrees = lerpf(-6.0, -1.5, clampf(t / APPEAR, 0.0, 1.0))

	if t < APPEAR + ROLLING:
		# Roulement : faces qui défilent, tremblement qui s'amortit.
		var damp := 1.0 - (t - APPEAR) / ROLLING
		_die.rolling_face(damp)
	elif t < APPEAR + ROLLING + HOLD:
		# Arrêt net sur la valeur tirée, puis le détail et le verdict.
		_die.settle(_die_value)
		var reveal := t - APPEAR - ROLLING
		_detail.modulate.a = clampf(reveal / 0.3, 0.0, 1.0)
		_verdict.modulate.a = clampf((reveal - 0.25) / 0.3, 0.0, 1.0)
	elif t < APPEAR + ROLLING + HOLD + FADE:
		modulate.a = 1.0 - (t - APPEAR - ROLLING - HOLD) / FADE
	else:
		_playing = false
		queue_free()


## La feuille de parchemin et son contenu (titre, dé, détail, verdict).
func _build_card() -> void:
	_card = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = BookTheme.PARCHMENT_BRIGHT
	style.set_border_width_all(1)
	style.border_color = BookTheme.PAGE_EDGE
	style.set_corner_radius_all(4)
	style.set_content_margin_all(22)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 14
	_card.add_theme_stylebox_override("panel", style)
	add_child(_card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_card.add_child(col)

	_title = Label.new()
	_title.add_theme_font_override("font", BookTheme.serif(false, true))
	_title.add_theme_font_size_override("font_size", 24)
	_title.add_theme_color_override("font_color", BookTheme.INK)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)

	var die_row := CenterContainer.new()
	col.add_child(die_row)
	_die = DieFace.new()
	_die.custom_minimum_size = Vector2(84, 84)
	_die.pivot_offset = Vector2(42, 42)
	die_row.add_child(_die)

	_detail = Label.new()
	_detail.add_theme_font_override("font", BookTheme.serif(true))
	_detail.add_theme_font_size_override("font_size", 17)
	_detail.add_theme_color_override("font_color", BookTheme.INK_MUTED)
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_detail)

	_verdict = Label.new()
	_verdict.add_theme_font_override("font", BookTheme.serif(false, true))
	_verdict.add_theme_font_size_override("font_size", 26)
	_verdict.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_verdict)

	# Centre la feuille quelle que soit sa taille (la sienne comme celle de
	# l'écran), pivot au milieu pour la rotation « feuille posée ».
	_card.resized.connect(_center_card)
	resized.connect(_center_card)


func _center_card() -> void:
	_card.position = (size - _card.size) * 0.5
	_card.pivot_offset = _card.size * 0.5


## La face du dé : carré ivoire aux coins arrondis, points à l'encre.
class DieFace extends Control:
	const IVORY := Color("f7f0dd")
	const EDGE := Color("a38a5c")
	const PIP := Color("312216")

	## Emplacements des points par valeur (coordonnées normalisées).
	const PIPS := {
		1: [Vector2(0.5, 0.5)],
		2: [Vector2(0.27, 0.27), Vector2(0.73, 0.73)],
		3: [Vector2(0.25, 0.25), Vector2(0.5, 0.5), Vector2(0.75, 0.75)],
		4: [Vector2(0.28, 0.28), Vector2(0.72, 0.28), Vector2(0.28, 0.72), Vector2(0.72, 0.72)],
		5: [Vector2(0.26, 0.26), Vector2(0.74, 0.26), Vector2(0.5, 0.5),
			Vector2(0.26, 0.74), Vector2(0.74, 0.74)],
		6: [Vector2(0.28, 0.24), Vector2(0.72, 0.24), Vector2(0.28, 0.5),
			Vector2(0.72, 0.5), Vector2(0.28, 0.76), Vector2(0.72, 0.76)],
	}

	var _value := 1
	var _spin_clock := 0.0

	## Pendant le roulement : la face change vite, le dé tremble (amorti par
	## `damp` : 1 = plein régime, 0 = presque arrêté).
	func rolling_face(damp: float) -> void:
		_spin_clock += get_process_delta_time()
		if _spin_clock > 0.07:
			_spin_clock = 0.0
			_value = randi_range(1, 6)
		rotation_degrees = sin(Time.get_ticks_msec() / 37.0) * 9.0 * damp
		scale = Vector2.ONE * (1.0 + 0.06 * damp)
		queue_redraw()

	func settle(value: int) -> void:
		_value = clampi(value, 1, 6)
		rotation_degrees = 0.0
		scale = Vector2.ONE
		queue_redraw()

	func _draw() -> void:
		var box := StyleBoxFlat.new()
		box.bg_color = IVORY
		box.set_border_width_all(2)
		box.border_color = EDGE
		box.set_corner_radius_all(int(size.x * 0.18))
		box.shadow_color = Color(0, 0, 0, 0.25)
		box.shadow_size = 5
		draw_style_box(box, Rect2(Vector2.ZERO, size))
		for pip: Vector2 in PIPS.get(_value, []):
			draw_circle(pip * size, size.x * 0.075, PIP)
