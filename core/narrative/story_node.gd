class_name StoryNode
extends Resource
## Un nœud narratif (équivalent d'un "knot" Ink), identifié par son id.
##
## Le contenu est une liste ordonnée d'instructions exécutées de haut en bas
## par le StoryRunner. Chaque instruction est un Dictionary avec une clé "type" :
##   - {"type": "text",    "value": String}
##   - {"type": "set",     "name": String, "value": String}
##   - {"type": "command", "name": String, "args": Array}      (ex: illustration, minigame)
##   - {"type": "cond",    "var": String, "value": String, "target": String}  (saut conditionnel)
##   - {"type": "divert",  "target": String}                   ("-> autre_noeud" ou "-> END")
##   - {"type": "choice",  "text": String, "target": String}
##
## Les tags (#Nadîtum, #miniGame, ...) servent au filtrage par personnage et
## au marquage du type de nœud.

@export var id: String = ""
@export var tags: Array = []
@export var instructions: Array = []

func _init(p_id: String = "") -> void:
	id = p_id
