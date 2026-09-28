class_name ShopPanel
extends Control
## Boutique : dos de cartes, plateaux, contours d'avatar et cadres de cartes, achetés en pièces d'or (PO).
## Les PO se gagnent à chaque partie (plus en cas de victoire) et au fil du passe de combat.

const SHOP_KINDS := ["card_back", "board", "border"]

var _tabs: TabContainer
var _gold: Label
var _hint: Label


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("modal")   # Échap la ferme (voir PauseMenu)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1100, 640)
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	panel.add_child(root)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	root.add_child(head)
	var title := UITheme.title_label(Loc.t("Boutique"), 38)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.add_child(title)
	head.add_child(GoldCoin.new())
	_gold = UITheme.label("", 26, UITheme.GOLD, 4)
	_gold.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_gold)
	var close := UITheme.button(Loc.t("Fermer"), 160)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(queue_free)
	head.add_child(close)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size", 17)
	root.add_child(_tabs)
	for kind in SHOP_KINDS:
		var scroll := ScrollContainer.new()
		scroll.name = Cosmetics.KIND_NAMES[kind]
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var grid := GridContainer.new()
		grid.name = "Grid"
		grid.columns = 4 if kind == "board" else 6
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		scroll.add_child(grid)
		scroll.set_meta("kind", kind)
		_tabs.add_child(scroll)
		_tabs.set_tab_title(scroll.get_index(), Loc.t(Cosmetics.KIND_NAMES[kind]))
	_hint = UITheme.label("", 14, Color("c9b79a"), 2)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(_hint)


func _ready() -> void:
	Lobby.profile_changed.connect(_rebuild)
	Lobby.gold_changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	_gold.text = Loc.t("%d PO") % Lobby.gold()
	_hint.text = (Loc.t("Gagnez des pièces d'or (PO) à chaque partie : davantage en cas de victoire, un peu en cas de défaite selon la durée ")
		+ Loc.t("de votre résistance, et au fil des niveaux du passe de combat. Un objet acheté s'équipe ensuite dans Personnalisation.")) \
		if Lobby.online else Loc.t("Hors ligne : connectez-vous au serveur pour utiliser la boutique.")
	var look := Lobby.my_look()
	for scroll in _tabs.get_children():
		var kind: String = scroll.get_meta("kind")
		var grid: GridContainer = scroll.get_node("Grid")
		for c in grid.get_children():
			c.queue_free()
		for it in Cosmetics.items(kind):
			if Cosmetics.price(kind, it.id) > 0:
				grid.add_child(_tile(kind, it, look))


## Aperçu d'un objet de personnalisation (partagé avec la personnalisation et le passe de combat).
static func preview(kind: String, id, big := false) -> Control:
	match kind:
		"border":
			return AvatarBadge.new().setup(Settings.avatar, str(id), 96 if big else 84)
		"avatar":
			return AvatarBadge.new().setup(int(id), "none", 84)
		"card_back":
			var tr := TextureRect.new()
			tr.texture = Cosmetics.card_back_texture(id)
			tr.custom_minimum_size = Vector2(80, 112)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			return tr
		"board":
			var tb := TextureRect.new()
			tb.texture = Cosmetics.board_texture(id)
			tb.custom_minimum_size = Vector2(200, 110) if big else Vector2(180, 90)
			tb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tb.clip_contents = true
			return tb
		"title":
			var l := UITheme.label(Loc.t("« %s »") % Cosmetics.title_name(id), 16, Color("c9a0ff"), 3)
			l.custom_minimum_size = Vector2(150, 40)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			return l
	return Control.new()


func _tile(kind: String, it: Dictionary, look: Dictionary) -> Control:
	var owned := Lobby.is_unlocked(kind, it.id)
	var price := Cosmetics.price(kind, it.id)
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(240, 230) if kind == "board" else Vector2(160, 230)
	var st := UITheme.flat_style(Color(0.1, 0.07, 0.1, 0.92), UITheme.GOLD if owned else Color("6b5a3c"), 2, 6)
	st.set_content_margin_all(8)
	tile.add_theme_stylebox_override("panel", st)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 6)
	tile.add_child(vb)
	var visual := preview(kind, it.id)
	visual.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(visual)
	var name_l := UITheme.label(Cosmetics.item_name(kind, it.id), 15, UITheme.GOLD, 3)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.custom_minimum_size.x = tile.custom_minimum_size.x - 20
	vb.add_child(name_l)
	var b := Button.new()
	b.custom_minimum_size = Vector2(130, 34)
	b.add_theme_font_size_override("font_size", 15)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_NONE
	vb.add_child(b)
	if owned:
		var equipped := str(look.get(kind, "")) == str(it.id)
		b.text = Loc.t("Équipé") if equipped else Loc.t("Équiper")
		b.disabled = equipped
		b.pressed.connect(func(): Lobby.equip(kind, it.id))
	else:
		b.text = Loc.t("%d PO") % price
		b.disabled = not Lobby.online or Lobby.gold() < price
		b.tooltip_text = Loc.t("Il vous manque %d PO.") % (price - Lobby.gold()) if Lobby.gold() < price else Loc.t("Acheter")
		b.pressed.connect(func():
			if b.has_meta("confirm"):
				b.disabled = true
				Lobby.buy(kind, it.id)
			else:
				b.set_meta("confirm", true)
				b.text = Loc.t("Confirmer ?")
				Audio.play_sfx("click", 0.1))
	return tile
