@tool
extends RichTextEffect
## Effet BBCode « shock » : à-coup BREF sur les caractères (secousse de position)
## qui décroît vite depuis l'apparition du texte, puis s'arrête. À la différence
## de [shake] natif (tremblement CONTINU), ici c'est un sursaut ponctuel.
##
## L'instant de départ est stocké dans l'instance (restart()) : story.gd le
## rappelle à chaque nouveau passage pour que l'à-coup reparte à l'affichage.
##
## Valeurs PROVISOIRES (à ajuster visuellement) : voir constantes ci-dessous.

var bbcode := "shock"

## Durée de l'à-coup avant retour au calme (secondes).
const DURATION := 0.35
## Amplitude initiale du décalage (px à la résolution de référence).
const MAGNITUDE := 6.0
## Vitesse de trépidation (rad/s).
const FREQ := 34.0

var _start_ms := 0


func _init() -> void:
	restart()


## Redémarre l'à-coup (à appeler quand un nouveau texte apparaît).
func restart() -> void:
	_start_ms = Time.get_ticks_msec()


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var t := float(Time.get_ticks_msec() - _start_ms) / 1000.0
	if t >= DURATION:
		return true  # à-coup terminé : plus aucun décalage
	# Décroissance quadratique : fort au début, s'éteint vite.
	var decay := 1.0 - t / DURATION
	var amp := MAGNITUDE * decay * decay
	var i := char_fx.relative_index
	char_fx.offset += Vector2(
		sin(t * FREQ + i * 1.7) * amp,
		cos(t * FREQ * 1.3 + i * 2.3) * amp)
	return true
