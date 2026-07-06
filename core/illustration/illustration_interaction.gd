@tool
class_name IllustrationInteraction
extends Resource
## Une zone interactive (cliquable) posée sur un calque d'illustration.
##
## Le polygone est défini en coordonnées NORMALISÉES [0,1] dans l'espace de la
## texture NON transformée du calque (avant parallaxe) : il suit donc le calque
## quand celui-ci se décale. Les zones se dessinent à la souris dans l'outil
## narratif (section_interactions.gd), sérialisées dans illustrations_defs.json.
##
## Effets déclenchés au clic (cf. story.gd) — chacun optionnel :
##   - dialogue_lines : lignes ajoutées à la suite du texte courant ;
##   - item_id/item_qty : objet donné (via le futur Inventory, point 10).
## L'effet « nouvelle sortie » n'est PAS une donnée de zone : il émerge de
## l'usage du prédicat de garde zone_clicked("id") ailleurs dans le .untold.

## Identifiant unique de la zone, posé par l'auteur (sert à zone_clicked("id")).
@export var id: String = ""

## Sommets du polygone, coordonnées normalisées [0,1] (espace texture du calque).
@export var polygon: PackedVector2Array = PackedVector2Array()

## Lignes de dialogue ajoutées au clic (vide = pas d'effet dialogue).
@export var dialogue_lines: Array[String] = []

## Objet donné au clic (id vide = pas d'effet objet) et quantité.
@export var item_id: String = ""
@export var item_qty: int = 1
