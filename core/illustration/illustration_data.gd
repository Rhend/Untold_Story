@tool
class_name IllustrationData
extends Resource
## Une illustration complète (équivalent de l'IllustrationData Unity) :
## un nom (référencé par @illustration("Nom") dans le .untold) et ses calques.

## CHARACTER ajouté en fin d'énum pour préserver les valeurs existantes
## (PORTRAIT=0, LANDSCAPE=1) : petit portrait carré ancré en haut à gauche.
enum Template { PORTRAIT, LANDSCAPE, CHARACTER }

@export var illustration_name: String = ""
@export var template: Template = Template.LANDSCAPE
@export var layers: Array[IllustrationLayer] = []
## false = illustration figée : aucun décalage de parallaxe n'est appliqué,
## quels que soient les parallax_multiplier des calques. Utile pour un cadrage
## « contain » sans marge, qui ne peut pas absorber un décalage sans découvrir
## un bord vide.
@export var parallax_enabled: bool = true
