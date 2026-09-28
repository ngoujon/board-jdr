class_name PatchNotesPanel
extends Control
## Fenêtre modale des notes de mise à jour (data/patchnotes.json, la plus récente en premier).

const PATH := "res://data/patchnotes.json"
const SECTION_COLORS := {"Nouveautés": "#5fd068", "Améliorations": "#5ab4f0", "Corrections": "#ff9a7a"}


## Liste des versions : [{version, date, title, sections: [[titre, [lignes]]]}].
static func load_notes() -> Array:
	if not FileAccess.file_exists(PATH):
		return []
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return data if data is Array else []


static func format_date(iso: String) -> String:
	var p := iso.split("-")
	return "%s/%s/%s" % [p[2], p[1], p[0]] if p.size() == 3 else iso


## BBCode d'une version (pour le panneau complet et l'encart du menu).
static func entry_bbcode(entry: Dictionary, max_lines := -1) -> String:
	var out := ""
	var shown := 0
	for sec in entry.get("sections", []):
		var color: String = SECTION_COLORS.get(sec[0], "#f2c14e")
		out += "[color=%s][b]%s[/b][/color]\n" % [color, Loc.t(str(sec[0]))]
		for line in sec[1]:
			if max_lines >= 0 and shown >= max_lines:
				return out + "[color=#c9b79a]...[/color]"
			out += "• %s\n" % Loc.t(str(line))
			shown += 1
	return out


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(820, 620)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	vb.add_child(UITheme.title_label(Loc.t("Notes de mise à jour"), 38))

	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.custom_minimum_size = Vector2(780, 0)
	var current := Updater.current_version()
	var bb := ""
	for entry in load_notes():
		var mine: bool = entry.get("version", "") == current
		bb += Loc.t("[font_size=24][color=#f2c14e][b]Version %s[/b][/color][/font_size]  [color=#c9b79a]%s — %s%s[/color]\n") % [
			entry.get("version", "?"), format_date(entry.get("date", "")), Loc.t(str(entry.get("title", ""))),
			Loc.t("  (votre version)") if mine else ""]
		bb += entry_bbcode(entry) + "\n"
	text.text = bb if bb != "" else Loc.t("Aucune note de mise à jour.")
	vb.add_child(text)

	var close := UITheme.button(Loc.t("Fermer"), 200)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(queue_free)
	vb.add_child(close)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		queue_free()
		get_viewport().set_input_as_handled()
