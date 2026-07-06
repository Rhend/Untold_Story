class_name InventoryOverlay
extends Control
## Overlay modal d'inventaire (touche I, même principe que la carte : pas de
## bouton permanent à l'écran). Une case carrée par objet actuellement possédé
## (Progress.inventory_items()), icône affichée. Survol → tooltip unique nom +
## description (via _make_custom_tooltip sur chaque case). Pas de tri, pas de
## combinaison d'objets (décision actée). DA basique en attendant l'artiste.

signal close_requested()

const COLUMNS := 6
const CELL_SIZE := Vector2(96, 96)


func setup() -> void:
	_build_ui()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Fond modal : bloque les clics vers la scène en dessous.
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.045, 0.075, 0.98)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.09, 0.12, 0.98)
	style.set_border_width_all(1)
	style.border_color = Color(0.3, 0.3, 0.4)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 20)
	panel.add_child(col)

	var title := Label.new()
	title.text = "Inventaire"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.85, 0.8, 0.65))
	col.add_child(title)

	var items := Progress.inventory_items()
	if items.is_empty():
		var empty := Label.new()
		empty.text = "Tu ne portes aucun objet."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.modulate = Color(0.6, 0.6, 0.72)
		empty.custom_minimum_size = Vector2(CELL_SIZE.x * COLUMNS, 60)
		col.add_child(empty)
	else:
		var grid := GridContainer.new()
		grid.columns = COLUMNS
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		col.add_child(grid)
		for item_id in items:
			grid.add_child(_make_cell(str(item_id), int(items[item_id])))

	var close := Button.new()
	close.text = "✕  Fermer (I)"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: close_requested.emit())
	col.add_child(close)


## Case d'un objet : icône (ou pastille de repli), badge de quantité si > 1, et
## un tooltip personnalisé (nom + description) porté par la case elle-même.
func _make_cell(item_id: String, qty: int) -> Control:
	var data := ItemLibrary.get_item(item_id)
	var cell := ItemCell.new()
	cell.custom_minimum_size = CELL_SIZE
	cell.item_name = data.display_name if data != null else item_id
	cell.item_description = data.description if data != null else ""
	# tooltip_text non vide → Godot appelle _make_custom_tooltip au survol.
	cell.tooltip_text = cell.item_name

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.13, 0.17)
	style.set_border_width_all(2)
	style.border_color = Color(0.4, 0.36, 0.3)
	style.set_corner_radius_all(6)
	cell.add_theme_stylebox_override("panel", style)

	if data != null and data.icon != null:
		var icon := TextureRect.new()
		icon.texture = data.icon
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE  # le survol reste sur la case
		cell.add_child(icon)
	else:
		# Repli sans icône : initiale de l'objet.
		var glyph := Label.new()
		glyph.text = cell.item_name.substr(0, 1).to_upper()
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		glyph.add_theme_font_size_override("font_size", 36)
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(glyph)

	if qty > 1:
		var badge := Label.new()
		badge.text = "×%d" % qty
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		badge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		badge.add_theme_font_size_override("font_size", 18)
		badge.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(badge)

	return cell


## Case cliquable/survolable d'un objet : porte le nom + la description et rend un
## tooltip personnalisé UNIQUE (nom en tête, description dessous) au survol.
class ItemCell extends PanelContainer:
	var item_name := ""
	var item_description := ""

	func _make_custom_tooltip(_for_text: String) -> Object:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 6)

		var name_label := Label.new()
		name_label.text = item_name
		name_label.add_theme_font_size_override("font_size", 18)
		name_label.add_theme_color_override("font_color", Color(0.92, 0.86, 0.7))
		box.add_child(name_label)

		if not item_description.is_empty():
			var desc := Label.new()
			desc.text = item_description
			desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			desc.custom_minimum_size = Vector2(280, 0)
			desc.modulate = Color(0.75, 0.72, 0.66)
			box.add_child(desc)
		return box
