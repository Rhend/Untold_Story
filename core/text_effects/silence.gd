@tool
extends RichTextEffect
## Effet BBCode « silence » : texte plus petit et plus effacé (opacité réduite),
## pour un murmure ou une pensée en retrait.
##
## Valeurs PROVISOIRES (à ajuster visuellement) : voir constantes ci-dessous.

var bbcode := "silence"

## Facteur de taille appliqué au glyphe (< 1 = plus petit).
const SCALE := 0.75
## Facteur d'opacité appliqué (< 1 = plus effacé).
const ALPHA := 0.5


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	char_fx.transform = char_fx.transform.scaled(Vector2(SCALE, SCALE))
	var c := char_fx.color
	c.a *= ALPHA
	char_fx.color = c
	return true
