@tool
extends VBoxContainer
## Base d'un volet de l'inspecteur de nœud (voir node_inspector.gd).
##
## Pour AJOUTER une fonctionnalité à l'outil : créer un script qui hérite de
## celui-ci, implémenter setup(ctx), et l'ajouter à la liste SECTIONS de
## node_inspector.gd. Rien d'autre à brancher.
##
## Contenu de ctx :
##   "node_id" : String            — id du nœud sélectionné
##   "node"    : StoryNode         — le nœud parsé
##   "story"   : Story             — l'histoire complète
##   "source"  : UntoldSource      — le fichier .untold (édition par blocs)
##   "meta"    : StoryMeta         — sidecar (positions, commentaires, ...)
##   "editor"  : graph_editor      — reload_and_select(id), set_status(msg)


func setup(_ctx: Dictionary) -> void:
	pass


## Titre de volet homogène.
func heading(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.modulate = Color(0.82, 0.76, 0.6)
	add_child(label)
	add_child(HSeparator.new())
