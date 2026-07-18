class_name Typewriter
extends RefCounted
## Machine à écrire du récit : révèle progressivement le texte d'un
## RichTextLabel (via visible_ratio), à la vitesse des Réglages, en marquant
## une pause à chaque balise dramatique [Soupir:X] extraite par prepare().
##
## Contrat :
##   - prepare(brut) sépare le texte affichable des pauses ;
##   - play(pauses, départ) lance la frappe (départ > 0 : ne dévoile que la
##     suite — lignes de dialogue ajoutées au clic d'une zone) ;
##   - skip() révèle tout d'un coup (clic du lecteur pendant la frappe) ;
##   - stop() interrompt SANS rien révéler ni signaler (nouveau passage qui
##     remplace l'ancien) ;
##   - `finished` est émis quand le texte est entièrement révélé — fin de
##     frappe naturelle, saut, ou texte vide. L'hôte y accroche l'UI différée
##     (choix, boutons de fin — cf. story.gd).

signal finished

var _label: RichTextLabel
var _tween: Tween


func _init(label: RichTextLabel) -> void:
	_label = label


## Retire les balises de pause [Soupir:X] du texte et renvoie :
##   "text"   : le texte à afficher (balises de pause ôtées, BBCode conservé) ;
##   "pauses" : Array de { "visible": int, "duration": float } — nombre de
##              caractères visibles précédant la pause, et sa durée en secondes.
## La position est convertie en caractères VISIBLES (hors BBCode) via un
## RichTextLabel de mesure, cohérent avec get_total_character_count().
static func prepare(raw: String) -> Dictionary:
	var re := RegEx.create_from_string("\\[Soupir:\\s*([0-9]*\\.?[0-9]+)[^\\]]*\\]")
	var clean := ""
	var marks: Array = []  # { "pos": index dans clean, "duration": float }
	var last := 0
	for m in re.search_all(raw):
		clean += raw.substr(last, m.get_start() - last)
		marks.append({"pos": clean.length(), "duration": float(m.get_string(1))})
		last = m.get_end()
	clean += raw.substr(last)

	var pauses: Array = []
	if not marks.is_empty():
		var scratch := RichTextLabel.new()
		scratch.bbcode_enabled = true
		for mark in marks:
			scratch.text = clean.substr(0, mark["pos"])
			pauses.append({
				"visible": scratch.get_total_character_count(),
				"duration": mark["duration"],
			})
		scratch.free()
	return {"text": clean, "pauses": pauses}


## Lance la frappe : révèle le texte du label de start_visible caractères
## jusqu'à la fin, à vitesse Settings.text_speed, en marquant chaque pause
## située au-delà du point de départ. Un texte vide (ou déjà entièrement
## révélé) émet `finished` immédiatement.
func play(pauses: Array, start_visible := 0) -> void:
	stop()
	var total := _label.get_total_character_count()
	var remaining := total - start_visible
	if total <= 0 or remaining <= 0:
		_label.visible_ratio = 1.0
		finished.emit()
		return
	_label.visible_ratio = float(start_visible) / float(total)
	var full := clampf(remaining * Settings.text_speed, 0.3, 6.0)  # frappe (hors pauses)
	_tween = _label.create_tween()
	var cursor := start_visible
	for p in pauses:
		var v: int = p["visible"]
		if v <= start_visible:
			continue  # pause déjà dépassée avant le point de départ
		if v > cursor:
			_tween.tween_property(_label, "visible_ratio",
				float(v) / float(total), full * float(v - cursor) / float(remaining))
			cursor = v
		if p["duration"] > 0.0:
			_tween.tween_interval(p["duration"])
	if cursor < total:
		_tween.tween_property(_label, "visible_ratio",
			1.0, full * float(total - cursor) / float(remaining))
	_tween.finished.connect(func() -> void:
		_tween = null
		finished.emit())


## La frappe est-elle en cours ?
func is_typing() -> bool:
	return _tween != null and _tween.is_valid() and _tween.is_running()


## Saute la frappe en cours : tout est révélé d'un coup et `finished` est
## émis. Renvoie false (sans rien faire) si aucune frappe n'était en cours.
func skip() -> bool:
	if not is_typing():
		return false
	stop()
	_label.visible_ratio = 1.0
	finished.emit()
	return true


## Interrompt la frappe SANS émettre `finished` : pour remplacer le passage
## affiché (l'hôte purge lui-même son UI différée).
func stop() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
