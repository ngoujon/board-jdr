class_name CustomizePanel
extends Control
## Personnalisation du profil : titre (sous le pseudo), avatar, contour d'avatar, dos de cartes, plateau.
## Les éléments se débloquent en jouant (voir data/cosmetics.json) ; le serveur valide chaque choix.

const TILE_SIZE := {"title": Vector2(200, 92), "avatar": Vector2(128, 150), "border": Vector2(128, 150),
	"card_back": Vector2(128, 190), "board": Vector2(200, 150)}

var _tabs: TabContainer
var _preview: AvatarBadge
var _name_label: Label
var _title_label: Label
var _hint: Label


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1180, 660)
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	panel.add_child(root)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	root.add_child(head)
	_preview = AvatarBadge.new().setup(Settings.avatar, "none", 96)
	head.add_child(_preview)
	var who := VBoxContainer.new()
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(who)
	who.add_child(UITheme.title_label(Loc.t("Personnalisation"), 34))
	_name_label = UITheme.label("", 22, UITheme.LIGHT_TEXT, 4)
	who.add_child(_name_label)
	_title_label = UITheme.label("", 17, UITheme.GOLD, 3)
	who.add_child(_title_label)
	var close := UITheme.button(Loc.t("Fermer"), 160)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(queue_free)
	head.add_child(close)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size", 17)
	root.add_child(_tabs)
	for kind in Cosmetics.KINDS:
		var scroll := ScrollContainer.new()
		scroll.name = Cosmetics.KIND_NAMES[kind]
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var grid := GridContainer.new()
		grid.name = "Grid"
		grid.columns = 5 if kind in ["title", "board"] else 8
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		scroll.add_child(grid)
		scroll.set_meta("kind", kind)
		_tabs.add_child(scroll)

	_hint = UITheme.label("", 14, Color("c9b79a"), 2)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_hint)


func _ready() -> void:
	Lobby.profile_changed.connect(_rebuild)
	_rebuild()


func _exit_tree() -> void:
	if Lobby.profile_changed.is_connected(_rebuild):
		Lobby.profile_changed.disconnect(_rebuild)


func _rebuild() -> void:
	var look := Lobby.my_look()
	_preview.set_texture(CardDB.avatar(Settings.avatar))
	_preview.set_border(look.border)
	_name_label.text = Settings.player_name if Settings.player_name != "" else Loc.t("Sans pseudo")
	_title_label.text = Cosmetics.title_name(look.title) + (Loc.t("   ·   n°1 du classement !") if look.champion else "")
	_hint.text = Loc.t("Cliquez un élément débloqué pour l'équiper. Le plateau n'est visible que par vous ; le titre, l'avatar, le contour et le dos de cartes sont vus par les autres joueurs.") \
		if Lobby.online else Loc.t("Hors ligne : connectez-vous au serveur pour changer votre personnalisation.")
	var stats: Dictionary = Settings.cosmetics_cache.get("stats", {})
	for scroll in _tabs.get_children():
		var kind: String = scroll.get_meta("kind")
		var grid: GridContainer = scroll.get_node("Grid")
		for c in grid.get_children():
			c.queue_free()
		var count := 0
		for it in Cosmetics.items(kind):
			var unlocked := Lobby.is_unlocked(kind, it.id)
			if unlocked:
				count += 1
			grid.add_child(_tile(kind, it, unlocked, _is_equipped(kind, it.id, look), stats))
		_tabs.set_tab_title(scroll.get_index(), "%s (%d/%d)" % [Loc.t(Cosmetics.KIND_NAMES[kind]), count, Cosmetics.items(kind).size()])


func _is_equipped(kind: String, id, look: Dictionary) -> bool:
	if kind == "avatar":
		return int(id) == Settings.avatar
	if kind == "border" and look.champion:
		return str(id) == "champion"
	return str(look.get(kind, "")) == str(id)


func _tile(kind: String, it: Dictionary, unlocked: bool, equipped: bool, stats: Dictionary) -> Control:
	var tile := PanelContainer.new()
	tile.custom_minimum_size = TILE_SIZE[kind]
	var border_col := UITheme.GOLD if equipped else (Color("6b5a3c") if unlocked else Color("3a3040"))
	var st := UITheme.flat_style(Color(0.1, 0.07, 0.1, 0.92) if unlocked else Color(0.06, 0.05, 0.07, 0.92), border_col, 3 if equipped else 2, 6)
	st.set_content_margin_all(6)
	tile.add_theme_stylebox_override("panel", st)
	tile.mouse_filter = Control.MOUSE_FILTER_STOP
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 4)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(vb)

	var visual: Control = null
	match kind:
		"avatar":
			visual = AvatarBadge.new().setup(int(it.id), "none", 84)
		"border":
			visual = AvatarBadge.new().setup(Settings.avatar, str(it.id), 84)
		"card_back":
			var tr := TextureRect.new()
			tr.texture = Cosmetics.card_back_texture(it.id)
			tr.custom_minimum_size = Vector2(80, 112)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			visual = tr
		"board":
			var tb := TextureRect.new()
			tb.texture = Cosmetics.board_texture(it.id)
			tb.custom_minimum_size = Vector2(180, 90)
			tb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tb.clip_contents = true
			visual = tb
	if visual:
		visual.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not unlocked:
			visual.modulate = Color(0.35, 0.33, 0.4)
		vb.add_child(visual)

	var name_l := UITheme.label(Cosmetics.item_name(kind, it.id), 18 if kind == "title" else 14, UITheme.GOLD if unlocked else Color("8a8090"), 3)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.custom_minimum_size.x = TILE_SIZE[kind].x - 16
	vb.add_child(name_l)
	var rule = it.get("rule")
	var info := ""
	if equipped:
		info = Loc.t("Équipé")
	elif unlocked:
		info = Loc.t("Cliquez pour équiper")
	else:
		var pr := Cosmetics.progress(rule, stats)
		info = Loc.t("Verrouillé") + ("  %d / %d" % pr if pr[1] > 0 else "")
	var info_l := UITheme.label(info, 12, Color("5fd068") if equipped else Color("c9b79a"), 2)
	info_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(info_l)
	tile.tooltip_text = Loc.t("%s\nCondition : %s") % [Cosmetics.item_name(kind, it.id), Cosmetics.rule_text(rule)]
	if unlocked and not equipped:
		tile.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
				Audio.play_sfx("click", 0.1)
				Lobby.equip(kind, it.id))
		tile.mouse_entered.connect(func(): tile.modulate = Color(1.2, 1.15, 1.0))
		tile.mouse_exited.connect(func(): tile.modulate = Color.WHITE)
	return tile


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		queue_free()
		get_viewport().set_input_as_handled()
