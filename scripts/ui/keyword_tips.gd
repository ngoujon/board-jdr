class_name KeywordTips
extends VBoxContainer
## Infobulles détaillées affichées à côté d'une carte survolée : type, effet, mots-clés
## (Provocation, Charge...) avec leur explication complète.

const WIDTH := 250.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)
	custom_minimum_size = Vector2(WIDTH, 0)
	visible = false


func show_card(id: String) -> void:
	for c in get_children():
		c.queue_free()
	for tip in CardDB.tips(id):
		add_child(_bubble(tip[0], tip[1]))
	visible = true
	reset_size()


## Place les bulles à droite du rectangle (ou à gauche s'il n'y a pas la place), sans sortir de l'écran.
func place_beside(rect: Rect2, screen := Vector2(1280, 720)) -> void:
	reset_size()
	await get_tree().process_frame   # la hauteur des bulles n'est connue qu'après une frame
	if not is_inside_tree():
		return
	var h := get_combined_minimum_size().y
	var x := rect.end.x + 10
	if x + WIDTH > screen.x - 6:
		x = rect.position.x - WIDTH - 10
	var y := clampf(rect.position.y, 6, screen.y - h - 6)
	position = Vector2(maxf(6, x), y)


func hide_tips() -> void:
	visible = false


func _bubble(title: String, text: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UITheme.flat_style(Color(0.07, 0.05, 0.09, 0.95), UITheme.GOLD, 2, 4)
	sb.set_content_margin_all(8)
	p.add_theme_stylebox_override("panel", sb)
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.custom_minimum_size = Vector2(WIDTH - 16, 0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_size_override("normal_font_size", 15)
	r.add_theme_font_size_override("bold_font_size", 17)
	r.text = "[b][color=#f2c14e]%s[/color][/b]\n%s" % [title, text]
	p.add_child(r)
	return p
