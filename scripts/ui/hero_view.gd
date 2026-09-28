class_name HeroView
extends Control
## Portrait du héros, PV, énergie et compteurs (deck / main).

signal pressed(view: HeroView)
signal deck_pressed(view: HeroView)    # bouton « Deck » : composition de la bibliothèque
signal grave_pressed(view: HeroView)   # bouton « Cimetière »

const SIZE := Vector2(200, 200)

var uid := -1
var player_index := 0

var _portrait: TextureRect
var _frame: Panel
var _hp: Label
var infinite := false   # mode Inferno : PV infinis (symbole ∞ dessiné sur le cœur)
var _inf_icon: Control
var _name: Label
var _energy_box: HBoxContainer
var _energy_label: Label
var _crystal: Control          # grand cristal d'énergie (à gauche du portrait, loin du pseudo et des PV)
var _crystal_glow: TextureRect
var _last_energy := -1
var _deck_btn: Button
var _grave_btn: Button
var _hand_label: Label
var _target_mark: Panel


func _init() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## `look` : personnalisation du joueur ({title, border}) ; vide = héros par défaut (IA, hors ligne).
func setup(index: int, hero_uid: int, display_name := "", portrait: Texture2D = null, look := {}) -> HeroView:
	player_index = index
	uid = hero_uid
	var info: Dictionary = CardDB.HEROES[index].duplicate()
	info.title = Loc.t(info.title)
	if display_name != "":
		info.name = display_name
	var title := Cosmetics.title_name(look.get("title", ""))
	if title != "":
		info.title = title
	var border: String = str(look.get("border", "none"))

	var click := Control.new()
	click.position = Vector2(40, 0)
	click.size = Vector2(120, 120)
	click.mouse_filter = Control.MOUSE_FILTER_STOP
	click.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			pressed.emit(self))
	add_child(click)

	_frame = Panel.new()
	_frame.position = Vector2(40, 0)
	_frame.size = Vector2(120, 120)
	var fs := UITheme.flat_style(Color("1a1220"), UITheme.GOLD, 4, 4)
	fs.shadow_color = Color(0, 0, 0, 0.6)
	fs.shadow_size = 8
	_frame.add_theme_stylebox_override("panel", fs)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)

	_portrait = TextureRect.new()
	_portrait.position = Vector2(44, 4)
	_portrait.size = Vector2(112, 112)
	_portrait.texture = portrait if portrait else CardDB.texture("res://assets/art/%s.png" % info.portrait)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait)

	var frame_path := "res://assets/ui/hero_frame.png"
	if border != "none" and border != "":
		# Contour débloqué (ou Champion pour le n°1 du classement) à la place du cadre doré.
		var ring := AvatarBadge.new().setup(0, border, 132)
		ring.position = Vector2(34, -6)
		add_child(ring)
	elif ResourceLoader.exists(frame_path):
		var over := TextureRect.new()
		over.texture = load(frame_path)
		over.position = Vector2(36, -4)
		over.size = Vector2(128, 128)
		over.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		over.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(over)

	_target_mark = Panel.new()
	_target_mark.position = Vector2(36, -4)
	_target_mark.size = Vector2(128, 128)
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color(1, 0.2, 0.2, 0.15)
	ts.border_color = UITheme.RED
	ts.set_border_width_all(4)
	_target_mark.add_theme_stylebox_override("panel", ts)
	_target_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_target_mark.visible = false
	add_child(_target_mark)

	var hp_icon := TextureRect.new()
	hp_icon.texture = CardDB.texture("res://assets/ui/icon_health.png")
	hp_icon.position = Vector2(132, 82)
	hp_icon.size = Vector2(52, 52)
	hp_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hp_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hp_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hp_icon)
	_hp = UITheme.num_label("25", 16, Color.WHITE, 7)
	_hp.position = Vector2(132, 86)
	_hp.size = Vector2(52, 52)
	add_child(_hp)
	_inf_icon = _Infinity.new()
	_inf_icon.position = Vector2(140, 98)
	_inf_icon.size = Vector2(36, 24)
	_inf_icon.visible = false
	add_child(_inf_icon)

	# Grand cristal d'énergie, symétrique du cœur des PV : énergie disponible ce tour.
	_crystal = Control.new()
	_crystal.position = Vector2(-22, 50)
	_crystal.size = Vector2(64, 64)
	_crystal.pivot_offset = Vector2(32, 32)
	_crystal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crystal)
	_crystal_glow = TextureRect.new()
	_crystal_glow.texture = _glow_texture()
	_crystal_glow.position = Vector2(-18, -18)
	_crystal_glow.size = Vector2(100, 100)
	_crystal_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_crystal_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crystal.add_child(_crystal_glow)
	var gem_big := TextureRect.new()
	gem_big.texture = CardDB.texture("res://assets/ui/icon_energy.png")
	gem_big.size = Vector2(64, 64)
	gem_big.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gem_big.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gem_big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crystal.add_child(gem_big)
	_energy_label = UITheme.num_label("0", 16, Color.WHITE, 7)
	_energy_label.position = Vector2(0, 3)
	_energy_label.size = Vector2(64, 64)
	_crystal.add_child(_energy_label)
	var tw := _crystal_glow.create_tween().set_loops()
	tw.tween_property(_crystal_glow, "scale", Vector2.ONE * 1.12, 0.9).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_crystal_glow, "scale", Vector2.ONE, 0.9).set_trans(Tween.TRANS_SINE)
	_crystal_glow.pivot_offset = Vector2(50, 50)

	_name = UITheme.label("%s\n%s" % [info.name, info.title], 15, UITheme.GOLD, 4)
	_name.position = Vector2(0, 122)
	_name.size = Vector2(200, 36)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_name)

	# Rangée des 10 cristaux : pleins = disponibles, sombres = dépensés, fantômes = pas encore gagnés.
	var bar := Panel.new()
	bar.position = Vector2(-2, 162)
	bar.size = Vector2(204, 34)
	bar.add_theme_stylebox_override("panel", UITheme.flat_style(Color(0.04, 0.05, 0.12, 0.8), Color("3d6fb0"), 2, 6))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	_energy_box = HBoxContainer.new()
	_energy_box.position = Vector2(2, 164)
	_energy_box.add_theme_constant_override("separation", 0)
	_energy_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_energy_box)
	for i in CardDB.MAX_ENERGY:
		var gem := TextureRect.new()
		gem.texture = CardDB.texture("res://assets/ui/icon_energy.png")
		gem.custom_minimum_size = Vector2(19.6, 30)
		gem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		gem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_energy_box.add_child(gem)

	# Deck (bibliothèque), main, cimetière : les boutons ouvrent la consultation des piles.
	var row := HBoxContainer.new()
	row.position = Vector2(0, 195)
	row.add_theme_constant_override("separation", 4)
	add_child(row)
	_deck_btn = _pile_button(Loc.t("Voir les cartes qui restent dans la bibliothèque (sans l'ordre de pioche)"))
	_deck_btn.pressed.connect(func(): deck_pressed.emit(self))
	row.add_child(_deck_btn)
	_hand_label = UITheme.label("", 13, Color("c9b79a"), 3)
	row.add_child(_hand_label)
	_grave_btn = _pile_button(Loc.t("Voir le cimetière : cartes mortes, jouées, détruites ou défaussées"))
	_grave_btn.pressed.connect(func(): grave_pressed.emit(self))
	row.add_child(_grave_btn)
	return self


func sync(p: GameState.Player) -> void:
	_hp.text = str(p.hero.health)
	var col := Color.WHITE
	_inf_icon.visible = infinite
	_hp.visible = not infinite
	if infinite:
		_sync_energy(p)
		return
	if p.hero.health < p.hero.max_health:
		col = Color("ff6b6b")
	elif p.hero.health > p.hero.max_health:
		col = Color("7dff8a")   # soigné au-delà des PV de départ
	_hp.add_theme_color_override("font_color", col)
	_sync_energy(p)


func _sync_energy(p: GameState.Player) -> void:
	for i in _energy_box.get_child_count():
		var gem: TextureRect = _energy_box.get_child(i)
		if i < p.energy:
			gem.modulate = Color(1.3, 1.3, 1.4)          # disponible : lumineux
		elif i < p.max_energy:
			gem.modulate = Color(0.3, 0.3, 0.42, 0.9)    # dépensé ce tour
		else:
			gem.modulate = Color(0.35, 0.38, 0.55, 0.35)  # pas encore débloqué
	_energy_label.text = str(p.energy)
	_energy_label.add_theme_font_size_override("font_size", 16 if p.energy < 10 else 14)
	_crystal_glow.visible = p.energy > 0
	_crystal.modulate = Color.WHITE if p.energy > 0 else Color(0.55, 0.55, 0.65)
	if p.energy != _last_energy:
		if _last_energy != -1:
			var tw := _crystal.create_tween()
			tw.tween_property(_crystal, "scale", Vector2.ONE * 1.25, 0.08)
			tw.tween_property(_crystal, "scale", Vector2.ONE, 0.15)
		_last_energy = p.energy
	_deck_btn.text = Loc.t("Deck %d") % p.deck.size()
	_hand_label.text = Loc.t("Main %d") % p.hand.size()
	_grave_btn.text = Loc.t("Cimetière %d") % p.graveyard.size()


func _pile_button(tip: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", Color("e8d6b0"))
	b.add_theme_color_override("font_hover_color", UITheme.GOLD)
	for st in ["normal", "hover", "pressed"]:
		var sb := UITheme.flat_style(Color(0.1, 0.07, 0.1, 0.8) if st == "normal" else Color(0.22, 0.15, 0.08, 0.9),
			Color("6b5a3c") if st == "normal" else UITheme.GOLD, 1, 4)
		sb.content_margin_left = 5
		sb.content_margin_right = 5
		sb.content_margin_top = 0
		sb.content_margin_bottom = 0
		b.add_theme_stylebox_override(st, sb)
	return b


func _glow_texture() -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	g.colors = PackedColorArray([Color(0.5, 0.85, 1.0, 0.95), Color(0.25, 0.55, 1.0, 0.5), Color(0.2, 0.4, 1.0, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	return gt


func add_hp(delta: int) -> void:
	_hp.text = str(int(_hp.text) + delta)
	if delta < 0:
		_hp.add_theme_color_override("font_color", Color("ff6b6b"))


func set_targetable(on: bool) -> void:
	_target_mark.visible = on


func center() -> Vector2:
	return global_position + Vector2(100, 60)


func shake() -> void:
	var base := position
	var tw := create_tween()
	for i in 6:
		tw.tween_property(self, "position", base + Vector2(randf_range(-8, 8), randf_range(-6, 6)), 0.04)
	tw.tween_property(self, "position", base, 0.04)


## Symbole ∞ dessiné (la police pixel n'a pas ce caractère) : PV infinis du mode Inferno.
class _Infinity extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var pts := PackedVector2Array()
		var c := size / 2
		for i in 49:
			var t := TAU * i / 48.0
			var d := 1.0 + sin(t) * sin(t)
			pts.append(c + Vector2(cos(t) / d * size.x * 0.46, sin(t) * cos(t) / d * size.y * 0.8))
		draw_polyline(pts, Color("2a0f08"), 7.0, true)
		draw_polyline(pts, Color("ff8a3a"), 3.5, true)
