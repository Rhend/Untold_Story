class_name LookSource
extends RefCounted
## Source d'entrée abstraite pour le parallaxe.
## Renvoie un vecteur "regard" normalisé dans [-1, 1] sur X et Y.
##
## Implémentation actuelle : la souris (cf. MouseLookSource).
## Pour le mobile, il suffira de fournir une autre sous-classe (gyroscope ou
## glissement du doigt) sans toucher au reste du système d'illustration.

func sample(_viewport: Viewport) -> Vector2:
	return Vector2.ZERO
