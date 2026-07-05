@tool
extends RichTextEffect
## Effet BBCode « highlight » : met le texte en évidence par une teinte vive
## légèrement pulsée.
##
## LIMITE CONNUE : un RichTextEffect ne transforme que le GLYPHE (couleur,
## position, échelle) — l'API ne permet PAS de dessiner un rectangle de fond
## derrière le texte. La demande « fond coloré derrière le texte » est donc
## approchée par une surbrillance de la couleur du texte. Pour un VRAI fond
## coloré, utiliser la balise native [bgcolor=#RRGGBB]…[/bgcolor].
##
## Valeurs PROVISOIRES (à ajuster visuellement) : voir constantes ci-dessous.

var bbcode := "highlight"

## Teinte de surbrillance (jaune chaud).
const TINT := Color(1.0, 0.9, 0.4)
## Vitesse de la pulsation de luminosité (rad/s).
const SPEED := 4.0


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var pulse := 0.85 + 0.15 * sin(char_fx.elapsed_time * SPEED)
	char_fx.color = Color(TINT.r * pulse, TINT.g * pulse, TINT.b * pulse, char_fx.color.a)
	return true
