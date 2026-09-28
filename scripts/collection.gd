extends Control
## Collection : consulter toutes les cartes, leurs effets, les mots-clés et un aperçu de l'effet 3D.

const GRID_SCALE := 0.78

var _grid: GridContainer
var _filter := "all"
var _selected := ""
var _big: CardView
var _info_name: Label
var _info_stats: Label
var _info_copies: Label
var _details: RichTextLabel
var _fx_btn: Button
var _fx: Fx3D


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Audio.play_music("menu")

	var bg := TextureRect.new()
	bg.texture = CardDB.texture("res://assets/bg/gallery.png")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.modulate = Color(0.55, 0.5, 0.5)
	add_child(bg)

	var title := UITheme.title_label(Loc.t("Collection de cartes"), 44)
	title.position = Vector2(20, 10)
	title.size = Vector2(740, 60)
	add_child(title)

	var filters := HBoxContainer.new()
	filters.position = Vector2(30, 74)
	filters.add_theme_constant_override("separation", 8)
	add_child(filters)
	for f in [["all", "Toutes"], ["minion", "Serviteurs"], ["spell", "Sorts"], ["enchantment", "Enchant."]]:
		var b := UITheme.button(Loc.t(f[1]), 80)
		b.add_theme_font_size_override("font_size", 15)
		b.custom_minimum_size.y = 40
		b.toggle_mode = true
		b.button_pressed = f[0] == _filter
		b.pressed.connect(func():
			_filter = f[0]
			for other in filters.get_children():
				other.set_pressed_no_signal(other == b)
			_fill_grid())
		filters.add_child(b)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(30, 124)
	scroll.size = Vector2(730, 586)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 16)
	scroll.add_child(_grid)

	# Panneau de détails
	var panel := PanelContainer.new()
	panel.position = Vector2(780, 20)
	panel.custom_minimum_size = Vector2(480, 690)
	add_child(panel)
	var detail := Control.new()
	detail.custom_minimum_size = Vector2(450, 660)
	panel.add_child(detail)

	_big = CardView.new()
	_big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_big.pivot_offset = Vector2.ZERO
	_big.scale = Vector2.ONE * 1.2
	_big.position = Vector2(8, 16)
	detail.add_child(_big)

	_info_name = UITheme.label("", 22, UITheme.GOLD, 5)
	_info_name.add_theme_font_override("font", UITheme.font_bold)
	_info_name.position = Vector2(214, 16)
	_info_name.size = Vector2(236, 60)
	_info_name.autowrap_mode = TextServer.AUTOWRAP_WORD
	detail.add_child(_info_name)
	_info_stats = UITheme.label("", 18)
	_info_stats.position = Vector2(214, 84)
	_info_stats.size = Vector2(236, 110)
	detail.add_child(_info_stats)
	_info_copies = UITheme.label("", 16, Color("c9b79a"), 3)
	_info_copies.position = Vector2(214, 200)
	_info_copies.size = Vector2(236, 60)
	_info_copies.autowrap_mode = TextServer.AUTOWRAP_WORD
	detail.add_child(_info_copies)

	_details = RichTextLabel.new()
	_details.bbcode_enabled = true
	_details.position = Vector2(4, 296)
	_details.size = Vector2(446, 290)
	detail.add_child(_details)

	_fx_btn = UITheme.button(Loc.t("Aperçu de l'effet 3D"), 280)
	_fx_btn.position = Vector2(84, 600)
	_fx_btn.pressed.connect(_preview_fx)
	detail.add_child(_fx_btn)

	var back := UITheme.button(Loc.t("Retour"), 150)
	back.custom_minimum_size.y = 40
	back.position = Vector2(592, 74)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	add_child(back)
	var rules := UITheme.button(Loc.t("Règles"), 100)
	rules.custom_minimum_size.y = 40
	rules.position = Vector2(482, 74)
	rules.pressed.connect(func(): add_child(RulesPanel.new()))
	add_child(rules)

	_fx = Fx3D.new()
	add_child(_fx)

	_fill_grid()
	_select(CardDB.COLLECTION_ORDER[0])


func _fill_grid() -> void:
	for c in _grid.get_children():
		c.queue_free()
	for id in CardDB.COLLECTION_ORDER:
		var card := CardDB.get_card(id)
		if _filter != "all" and card.type != _filter:
			continue
		var holder := Control.new()
		holder.custom_minimum_size = CardView.SIZE * GRID_SCALE
		var cv := CardView.new().setup(id)
		cv.pivot_offset = Vector2.ZERO
		cv.scale = Vector2.ONE * GRID_SCALE
		cv.pressed.connect(func(_c): _select(id))
		cv.hovered.connect(func(_c, on):
			cv.modulate = Color(1.25, 1.2, 1.05) if on else Color.WHITE)
		holder.add_child(cv)
		_grid.add_child(holder)


func _select(id: String) -> void:
	_selected = id
	Audio.play_sfx("card_draw", 0.1, -6.0)
	var c := CardDB.get_card(id)
	_big.setup(id)
	_info_name.text = c.name
	var type_name: String = Loc.t({"minion": "Serviteur", "spell": "Sort", "enchantment": "Enchantement"}.get(c.type, "Sort"))
	var stats := Loc.t("Type : %s\nCoût : %d énergie") % [type_name, c.cost]
	if c.type == "minion":
		stats += Loc.t("\nAttaque : %d\nPoints de vie : %d") % [c.attack, c.health]
	elif c.type == "enchantment":
		stats += Loc.t("\nReste en jeu (%d maximum)") % CardDB.MAX_ENCHANTS
	_info_stats.text = stats
	var copies: int = CardDB.DECK_LIST.get(id, 0)
	if c.get("token", false):
		_info_copies.text = Loc.t("Jeton : n'est pas dans le deck, il est créé par un effet.")
	else:
		_info_copies.text = Loc.t("Exemplaires dans le deck : %d\n(identique pour vous et l'IA)") % copies
	var txt := ("[color=#f2c14e][b]" + Loc.t("Effet") + "[/b][/color]\n%s\n\n") % (c.text if c.text != "" else Loc.t("Aucun effet : un serviteur simple."))
	for tip in CardDB.tips(id):
		txt += "[color=#f2c14e][b]%s[/b][/color]\n%s\n\n" % tip
	txt += "[i][color=#c9b79a]« %s »[/color][/i]" % c.flavor
	_details.text = txt
	_fx_btn.visible = _fx_name(id) != ""


func _fx_name(id: String) -> String:
	var c := CardDB.get_card(id)
	if c.has("spell"):
		return c.spell.get("fx", "")
	if c.has("battlecry"):
		return c.battlecry.get("fx", "")
	if c.has("deathrattle"):
		return c.deathrattle.get("fx", "")
	for when in ["turn_start", "turn_end"]:
		if c.has(when):
			return c[when].get("fx", "")
	if CardDB.card_keywords(id).has("divine_shield"):
		return "shield"
	return ""


func _preview_fx() -> void:
	var fx_name := _fx_name(_selected)
	var src := Vector2(900, 190)
	var single := [Vector2(620, 300)]
	var many := [Vector2(170, 260), Vector2(390, 300), Vector2(620, 260)]
	_fx_btn.disabled = true
	match fx_name:
		"frost":
			await _fx.frost(many)
		"dragon_fire":
			await _fx.dragon_fire(src, many)
		"heal", "buff", "summon":
			await _fx.play_card_fx(fx_name, src, [src])
		"shield":
			await _fx.shield_pop(src)
		"draw":
			await _fx.draw_cards(src, Vector2(400, 600), 2)
		_:
			await _fx.play_card_fx(fx_name, src, single)
	_fx_btn.disabled = false
