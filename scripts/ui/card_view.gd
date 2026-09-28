class_name CardView
extends Control
## Affichage d'une carte complète (main, collection, aperçu). Taille native 160x224.

signal hovered(card: CardView, on: bool)
signal pressed(card: CardView)
signal drag_moved(card: CardView, global_pos: Vector2)   # carte de la main déplacée (glisser-déposer)
signal drag_released(card: CardView)

const SIZE := Vector2(160, 224)

var card_id := ""
var hand_uid := -1
var face_down := false
var draggable := false   # main du joueur : clic (relâché sans bouger) ou glisser pour réordonner

var _press_pos := Vector2.ZERO
var _pressing := false
var _dragging := false
var _selected: Panel

var _glow: Panel
var _frame: TextureRect
var _art: TextureRect
var _name: Label
var _text: Label
var _text_bg: Panel
var _type: Label
var _cost: Label
var _atk: Label
var _hp: Label
var _atk_icon: TextureRect
var _hp_icon: TextureRect
var _cost_icon: TextureRect
var _cost_glow: TextureRect
var _back: TextureRect
var _flat_frame: Panel


func _init() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	pivot_offset = SIZE / 2
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func setup(id: String, uid := -1, show_back := false) -> CardView:
	card_id = id
	hand_uid = uid
	face_down = show_back
	_refresh()
	return self


func _build() -> void:
	_glow = Panel.new()
	_glow.position = Vector2(-5, -5)
	_glow.size = SIZE + Vector2(10, 10)
	var gs := StyleBoxFlat.new()
	gs.bg_color = Color(0, 0, 0, 0)
	gs.border_color = UITheme.GREEN
	gs.set_border_width_all(4)
	gs.set_corner_radius_all(6)
	gs.shadow_color = Color(UITheme.GREEN, 0.6)
	gs.shadow_size = 8
	_glow.add_theme_stylebox_override("panel", gs)
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.visible = false
	add_child(_glow)

	_flat_frame = Panel.new()
	_flat_frame.size = SIZE
	_flat_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flat_frame)

	_art = TextureRect.new()
	_art.position = Vector2(8, 22)
	_art.size = Vector2(144, 112)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.clip_contents = true
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)

	_frame = TextureRect.new()
	_frame.size = SIZE
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)

	_name = _mk_label(Vector2(8, 137), Vector2(144, 20), 14, UITheme.LIGHT_TEXT, 4)
	_name.add_theme_font_override("font", UITheme.font_bold)
	# Zone de texte sur parchemin clair : le texte foncé reste lisible (le bois du cadre était trop sombre).
	_text_bg = Panel.new()
	_text_bg.position = Vector2(8, 157)
	_text_bg.size = Vector2(144, 48)
	var tb := StyleBoxFlat.new()
	tb.bg_color = Color("f3e6c4")
	tb.border_color = Color("5a3a1e")
	tb.set_border_width_all(2)
	tb.set_corner_radius_all(3)
	tb.shadow_color = Color(0, 0, 0, 0.35)
	tb.shadow_size = 2
	tb.shadow_offset = Vector2(0, 1)
	_text_bg.add_theme_stylebox_override("panel", tb)
	_text_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_text_bg)
	_text = _mk_label(Vector2(12, 158), Vector2(136, 36), 12, Color("24140a"), 0)   # 2 lignes, au-dessus des icônes
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_text.add_theme_constant_override("line_spacing", -1)
	_type = _mk_label(Vector2(40, 206), Vector2(80, 14), 10, UITheme.LIGHT_TEXT, 3)

	# Cristal de coût agrandi, avec un halo pour mieux le repérer.
	_cost_glow = _mk_glow(Vector2(-26, -26), Vector2(78, 78))
	_cost_icon = _mk_icon("res://assets/ui/icon_energy.png", Vector2(-17, -17), Vector2(60, 60))
	_cost = _mk_num(Vector2(-17, -14), Vector2(60, 60), 20)
	_atk_icon = _mk_icon("res://assets/ui/icon_attack.png", Vector2(-12, 186), Vector2(44, 44))
	_atk = _mk_num(Vector2(-12, 189), Vector2(44, 44), 16)
	_hp_icon = _mk_icon("res://assets/ui/icon_health.png", Vector2(128, 186), Vector2(44, 44))
	_hp = _mk_num(Vector2(128, 188), Vector2(44, 44), 16)

	_back = TextureRect.new()
	_back.size = SIZE
	_back.texture = CardDB.texture("res://assets/ui/card_back.png")
	_back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_back.stretch_mode = TextureRect.STRETCH_SCALE
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back.visible = false
	add_child(_back)


func _mk_label(pos: Vector2, sz: Vector2, font_size: int, color: Color, outline: int) -> Label:
	var l := UITheme.label("", font_size, color, outline)
	l.position = pos
	l.size = sz
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.clip_text = false
	add_child(l)
	return l


func _mk_num(pos: Vector2, sz: Vector2, font_size: int) -> Label:
	var l := UITheme.num_label("", font_size, Color.WHITE, 7)
	l.position = pos
	l.size = sz
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


## Halo bleu radial derrière le cristal de coût.
func _mk_glow(pos: Vector2, sz: Vector2) -> TextureRect:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(0.45, 0.8, 1.0, 0.9), Color(0.25, 0.55, 1.0, 0.45), Color(0.2, 0.4, 1.0, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	var t := TextureRect.new()
	t.texture = gt
	t.position = pos
	t.size = sz
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(t)
	return t


func _mk_icon(path: String, pos: Vector2, sz: Vector2) -> TextureRect:
	var t := TextureRect.new()
	t.texture = CardDB.texture(path)
	t.position = pos
	t.size = sz
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(t)
	return t


func _refresh() -> void:
	_back.visible = face_down
	for c in [_frame, _art, _name, _text, _text_bg, _type, _cost, _atk, _hp, _atk_icon, _hp_icon, _cost_icon, _cost_glow, _flat_frame]:
		c.visible = not face_down
	if face_down or card_id == "":
		return
	var c := CardDB.get_card(card_id)
	var is_minion: bool = c.type == "minion"
	var is_enchant: bool = c.type == "enchantment"
	var frame_path := "res://assets/ui/card_frame_%s.png" % ("minion" if is_minion else "spell")
	if ResourceLoader.exists(frame_path):
		_frame.texture = load(frame_path)
		_flat_frame.visible = false
	else:
		_frame.texture = null
		_flat_frame.add_theme_stylebox_override("panel", UITheme.flat_style(
			Color("d8c39a") if is_minion else Color("b9c6d8"), UITheme.GOLD, 3, 4))
	_art.texture = CardDB.card_art(card_id)
	_name.text = c.name
	_name.add_theme_font_size_override("font_size", 14 if c.name.length() <= 16 else 12)
	_text.text = c.text
	_text_bg.visible = c.text != ""
	_text.add_theme_font_size_override("font_size", 12 if c.text.length() <= 36 else 11)
	_type.text = (Loc.t("Jeton") if c.get("token", false) else Loc.t("Serviteur")) if is_minion else (Loc.t("Enchantement") if is_enchant else Loc.t("Sort"))
	# Enchantement : cadre de sort teinté de violet, durabilité à la place des PV.
	_frame.modulate = Color(0.86, 0.68, 1.0) if is_enchant else Color.WHITE
	_cost.text = str(c.cost)
	_cost.add_theme_font_size_override("font_size", 20 if c.cost < 10 else 16)
	_atk.visible = is_minion
	_hp.visible = is_minion
	_atk_icon.visible = is_minion
	_hp_icon.visible = is_minion
	if is_minion:
		_atk.text = str(c.attack)
		_hp.text = str(c.health)


## Dos de carte personnalisé (celui du joueur à qui appartient la carte).
func set_back_texture(tex: Texture2D) -> void:
	if tex:
		_back.texture = tex


func set_playable(on: bool) -> void:
	_glow.visible = on and not face_down


func set_cost_color(affordable: bool) -> void:
	_cost.add_theme_color_override("font_color", Color.WHITE if affordable else Color("ff8080"))
	_cost_glow.modulate = Color.WHITE if affordable else Color(1, 1, 1, 0.25)


## Carte sélectionnée (1er clic) : halo doré derrière la carte + contour doré par-dessus.
func set_selected(on: bool) -> void:
	if on and _selected == null:
		_selected = Panel.new()
		_selected.position = Vector2(-6, -6)
		_selected.size = SIZE + Vector2(12, 12)
		var st := StyleBoxFlat.new()
		st.draw_center = false
		st.border_color = Color("ffd75e")
		st.set_border_width_all(5)
		st.set_corner_radius_all(12)
		_selected.add_theme_stylebox_override("panel", st)
		_selected.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_selected)
		var halo := Panel.new()
		halo.position = Vector2(-4, -4)
		halo.size = SIZE + Vector2(8, 8)
		var hs := StyleBoxFlat.new()
		hs.bg_color = Color(1, 0.8, 0.2, 0.9)
		hs.set_corner_radius_all(12)
		hs.shadow_color = Color(1, 0.8, 0.2, 0.7)
		hs.shadow_size = 16
		halo.add_theme_stylebox_override("panel", hs)
		halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		halo.show_behind_parent = true
		_selected.set_meta("halo", halo)
		add_child(halo)
	if _selected:
		_selected.visible = on
		(_selected.get_meta("halo") as Panel).visible = on


func _gui_input(event: InputEvent) -> void:
	if not draggable:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			pressed.emit(self)
			accept_event()
		return
	# Main du joueur : un clic n'est compté qu'au relâchement sans déplacement,
	# sinon c'est un glisser-déposer (réorganisation de la main), jamais une carte jouée.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressing = true
			_dragging = false
			_press_pos = event.global_position
		else:
			if _dragging:
				drag_released.emit(self)
			elif _pressing:
				pressed.emit(self)
			_pressing = false
			_dragging = false
		accept_event()
	elif event is InputEventMouseMotion and _pressing:
		if not _dragging and event.global_position.distance_to(_press_pos) > 12.0:
			_dragging = true
		if _dragging:
			drag_moved.emit(self, event.global_position)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		hovered.emit(self, true)
	elif what == NOTIFICATION_MOUSE_EXIT:
		hovered.emit(self, false)
