class_name PileViewer
extends Control
## Consultation d'une pile de cartes pendant une partie :
##  - bibliothèque : composition des cartes restantes, regroupées et triées par coût (l'ordre de pioche reste caché) ;
##  - cimetière : cartes mortes, jouées, détruites ou défaussées, de la plus récente à la plus ancienne.

const CARD_SCALE := 0.62


## `grouped` : regroupe les exemplaires identiques (« ×3 ») et trie par coût.
func setup(title: String, subtitle: String, cards: Array, grouped: bool) -> PileViewer:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			close())
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1060, 620)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	vb.add_child(UITheme.title_label(title, 34))
	var sub := UITheme.label(subtitle, 16, Color("c9b79a"), 2)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 9
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)

	var entries: Array = []   # [card_id, nombre]
	if grouped:
		var counts := {}
		for id in cards:
			counts[id] = int(counts.get(id, 0)) + 1
		for id in counts:
			entries.append([id, counts[id]])
		entries.sort_custom(func(a, b):
			var ca := CardDB.get_card(a[0])
			var cb := CardDB.get_card(b[0])
			return ca.cost < cb.cost if ca.cost != cb.cost else str(ca.name) < str(cb.name))
	else:
		for i in range(cards.size() - 1, -1, -1):
			entries.append([cards[i], 1])
	if entries.is_empty():
		var empty := UITheme.label(Loc.t("Aucune carte."), 20, Color("8a8090"))
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.add_child(empty)
	for e in entries:
		var holder := Control.new()
		holder.custom_minimum_size = CardView.SIZE * CARD_SCALE + Vector2(0, 4)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cv := CardView.new().setup(e[0])
		cv.pivot_offset = Vector2.ZERO
		cv.scale = Vector2.ONE * CARD_SCALE
		cv.mouse_filter = Control.MOUSE_FILTER_PASS
		cv.tooltip_text = "%s — %s" % [CardDB.get_card(e[0]).name, CardDB.get_card(e[0]).text]
		holder.add_child(cv)
		if e[1] > 1:
			var badge := PanelContainer.new()
			badge.add_theme_stylebox_override("panel", UITheme.flat_style(Color("2a1a12"), UITheme.GOLD, 2, 10))
			badge.position = Vector2(CardView.SIZE.x * CARD_SCALE - 30, -6)
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var n := UITheme.num_label("×%d" % e[1], 13, UITheme.GOLD, 4)
			n.custom_minimum_size = Vector2(34, 22)
			badge.add_child(n)
			holder.add_child(badge)
		grid.add_child(holder)

	var close_btn := UITheme.button(Loc.t("Fermer"), 180)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(close)
	vb.add_child(close_btn)
	return self


func close() -> void:
	Audio.play_sfx("click", 0.1)
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()
