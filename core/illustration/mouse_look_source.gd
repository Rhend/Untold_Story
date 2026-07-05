class_name MouseLookSource
extends LookSource
## Source de regard pilotée par le pointeur de la souris.
## Renvoie la position de la souris relative au centre de l'écran, normalisée
## dans [-1, 1] : (0,0) au centre, (-1,-1) en haut à gauche, (1,1) en bas à droite.

func sample(viewport: Viewport) -> Vector2:
	var size := viewport.get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return Vector2.ZERO
	var mouse := viewport.get_mouse_position()
	var look := Vector2(
		(mouse.x / size.x) * 2.0 - 1.0,
		(mouse.y / size.y) * 2.0 - 1.0
	)
	# Sensibilité appliquée AVANT le clamp : au-delà de 1, le regard atteint les
	# bords plus tôt (l'appliquer après le clamp n'aurait aucun effet > 1).
	look *= Settings.mouse_sensitivity
	look.x = clampf(look.x, -1.0, 1.0)
	look.y = clampf(look.y, -1.0, 1.0)
	return look
