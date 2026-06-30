class_name StoryChoice
extends Resource
## Un choix proposé au joueur : un texte affiché et le nœud cible.

@export var text: String = ""
@export var target: String = ""

func _init(p_text: String = "", p_target: String = "") -> void:
	text = p_text
	target = p_target
