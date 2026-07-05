@tool
extends RichTextEffect
## Effet BBCode « danger » : couleur rouge/orange PULSANTE, avec un léger
## tremblement de position. Attire l'œil sur un passage menaçant.
##
## Valeurs PROVISOIRES (à ajuster visuellement) : voir constantes ci-dessous.

var bbcode := "danger"

## Vitesse de la pulsation (rad/s).
const SPEED := 6.0
## Amplitude du tremblement (px à la résolution de référence).
const TREMOR := 1.2
## Bornes de couleur entre lesquelles la teinte oscille.
const COLOR_A := Color(0.86, 0.12, 0.12)  # rouge
const COLOR_B := Color(0.98, 0.55, 0.12)  # orange


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var i := char_fx.relative_index
	var pulse := 0.5 + 0.5 * sin(char_fx.elapsed_time * SPEED + i * 0.2)
	var c := COLOR_A.lerp(COLOR_B, pulse)
	c.a = char_fx.color.a  # préserve le fondu de la machine à écrire
	char_fx.color = c
	char_fx.offset += Vector2(
		sin(char_fx.elapsed_time * SPEED * 2.1 + i) * TREMOR,
		cos(char_fx.elapsed_time * SPEED * 1.7 + i) * TREMOR)
	return true
