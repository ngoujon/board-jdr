class_name BattlePassPanel
extends Control
## Passe de combat de la saison en cours (une saison dure un mois) : 30 niveaux, XP gagnée à chaque partie,
## récompenses (PO, dos de cartes, contours, plateau, titre) à récupérer une fois le niveau atteint.

var _body: VBoxContainer
var _gold_label: Label


static func days_left_text(season: Dictionary) -> String:
	var left := int(season.get("end", 0)) - int(Time.get_unix_time_from_system())
	if left <= 0:
		return Loc.t("Saison terminée")
	var d := left / 86400
	var h := (left % 86400) / 3600
	return (Loc.t("%d j %d h restants") % [d, h]) if d > 0 else (Loc.t("%d h restantes") % maxi(1, h))


static func reward_text(r: Dictionary) -> String:
	if r.has("po"):
		return Loc.t("%d PO") % int(r.po)
	var t := Loc.t("%s : %s") % [Loc.t(Lobby.KIND_SINGULAR.get(str(r.kind), str(r.kind))), Cosmetics.item_name(str(r.kind), r.id)]
	if r.has("extra"):
		t += "\n+ " + Loc.t("%s : %s") % [Loc.t(Lobby.KIND_SINGULAR.get(str(r.extra.kind), "")), Cosmetics.item_name(str(r.extra.kind), r.extra.id)]
	return t


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
	panel.custom_minimum_size = Vector2(1180, 660)
	center.add_child(panel)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	panel.add_child(_body)


func _ready() -> void:
	Lobby.profile_changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	for c in _body.get_children():
		c.queue_free()
	var s := Lobby.season()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	_body.add_child(head)
	var tb := VBoxContainer.new()
	tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tb)
	var sname := Loc.t(str(s.get("name", "")))
	var title_text := Loc.t("Passe de combat · Saison %d%s") % [int(s.get("n", 1)), (" — " + Loc.t(sname)) if sname != "" else ""]
	# Nom de saison long : titre plus petit pour que le panneau garde sa largeur.
	tb.add_child(UITheme.title_label(title_text, 32 if title_text.length() <= 40 else 26))
	tb.add_child(UITheme.label((Loc.t("Hors ligne : connectez-vous au serveur pour suivre votre progression.") if s.get("offline", false) else days_left_text(s)), 16, Color("c9b79a"), 3))
	# Les nombres reçus en JSON sont des décimaux (1.0) : « 1 in [1.0] » est faux, d'où la conversion en entiers.
	var claimable: Array = s.get("claimable", []).map(func(x): return int(x))
	if not claimable.is_empty():
		var all := UITheme.button(Loc.t("Tout récupérer (%d)") % claimable.size(), 230)
		all.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		all.add_theme_color_override("font_color", Color("fff2a0"))
		all.pressed.connect(func():
			all.disabled = true
			Lobby.claim_pass("all", all.get_global_rect().get_center(), _gold_target()))
		head.add_child(all)
		var pulse := all.create_tween().set_loops()
		pulse.tween_property(all, "modulate", Color(1.3, 1.2, 0.8), 0.6)
		pulse.tween_property(all, "modulate", Color.WHITE, 0.6)
	head.add_child(GoldCoin.new())
	_gold_label = UITheme.label(Loc.t("%d PO") % Lobby.gold(), 24, UITheme.GOLD, 4)
	head.add_child(_gold_label)
	var close := UITheme.button(Loc.t("Fermer"), 150)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(queue_free)
	head.add_child(close)

	var level := int(s.get("level", 0))
	var levels := int(s.get("levels", 30))
	var per := maxi(1, int(s.get("xp_per_level", 250)))
	var xp := int(s.get("xp", 0))
	var bar_row := HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 12)
	_body.add_child(bar_row)
	bar_row.add_child(UITheme.label(Loc.t("Niveau %d / %d") % [level, levels], 20, UITheme.GOLD, 3))
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(620, 22)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.max_value = per
	bar.value = per if level >= levels else xp % per
	bar.show_percentage = false
	bar.add_theme_stylebox_override("fill", UITheme.flat_style(Color("e0a82e"), Color("ffe08a"), 1, 4))
	bar.add_theme_stylebox_override("background", UITheme.flat_style(Color(0.1, 0.07, 0.06), Color("6b5a3c"), 2, 4))
	bar_row.add_child(bar)
	bar_row.add_child(UITheme.label(Loc.t("Passe terminé !") if level >= levels else Loc.t("%d / %d XP") % [xp % per, per], 16, Color("e8d6b0"), 3))

	var grid := GridContainer.new()
	grid.columns = 10
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_body.add_child(grid)
	var rewards: Array = s.get("rewards", [])
	# Serveur d'avant la 2.0 (pas de liste « claimed ») : les niveaux atteints sont déjà obtenus.
	var claimed: Array = s.get("claimed", []).map(func(x): return int(x)) if s.has("claimed") else rewards.map(func(r): return int(r.level)).filter(func(l): return l <= level)
	for r in rewards:
		var lv := int(r.level)
		var state := "claimed" if lv in claimed and lv <= level else ("claimable" if lv in claimable else "locked")
		grid.add_child(_tier(r, state, lv == level + 1))

	var info := UITheme.label(Loc.t("XP à chaque partie : victoire 100, défaite 50, +3 par tour joué (abandon : 10). Contre l'IA : ×0,5 à ×1,25 selon la difficulté. ")
		+ Loc.t("Niveau atteint : cliquez sur « Récupérer » pour obtenir sa récompense (avant la fin de la saison). Les objets de la saison restent à vous pour toujours."), 14, Color("c9b79a"), 2)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_body.add_child(info)


## Nom sans le suffixe « (saison N) », trop long pour une case.
static func _short(n: String) -> String:
	var i := n.find(" (")
	return n.substr(0, i) if i > 0 else n


func _gold_target() -> Vector2:
	return _gold_label.get_global_rect().get_center() if is_instance_valid(_gold_label) else Vector2(1000, 60)


func _tier(r: Dictionary, state: String, next: bool) -> Control:
	var done := state == "claimed"
	var claimable := state == "claimable"
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(108, 150)
	var border := Color("fff2a0") if claimable else (UITheme.GOLD if done else (Color("9fd8ff") if next else Color("4a3e30")))
	var st := UITheme.flat_style(Color(0.32, 0.22, 0.05, 0.98) if claimable else (Color(0.2, 0.15, 0.06, 0.95) if done else Color(0.08, 0.06, 0.08, 0.92)),
		border, 3 if done or next or claimable else 2, 6)
	st.set_content_margin_all(4)
	tile.add_theme_stylebox_override("panel", st)
	tile.tooltip_text = Loc.t("Niveau %d : %s") % [int(r.level), reward_text(r)]
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(vb)
	var lvl := UITheme.label(Loc.t("Niv. %d") % int(r.level), 14, UITheme.GOLD if done else Color("c9b79a"), 2)
	lvl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(lvl)
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(96, 84)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(holder)
	if r.has("po"):
		var hb := HBoxContainer.new()
		hb.add_child(GoldCoin.new(16))
		hb.add_child(UITheme.label(str(int(r.po)), 22, UITheme.GOLD, 4))
		holder.add_child(hb)
	else:
		var pv := ShopPanel.preview(str(r.kind), r.id)
		var box := Control.new()
		var sz := pv.custom_minimum_size
		var k := minf(1.0, minf(92.0 / maxf(1.0, sz.x), 80.0 / maxf(1.0, sz.y)))
		box.custom_minimum_size = sz * k
		pv.scale = Vector2.ONE * k
		pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(pv)
		holder.add_child(box)
	if claimable:
		# Niveau atteint : bouton « Récupérer » qui scintille.
		var b := Button.new()
		b.text = Loc.t("Récupérer")
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 12)
		b.add_theme_color_override("font_color", Color("2a1a04"))
		b.add_theme_color_override("font_hover_color", Color("2a1a04"))
		for sn in ["normal", "hover", "pressed"]:
			var sb := UITheme.flat_style(Color("ffd24a") if sn != "hover" else Color("fff08a"), Color("fff8d0"), 1, 4)
			sb.set_content_margin_all(1)
			b.add_theme_stylebox_override(sn, sb)
		var lv := int(r.level)
		var claim := func():
			if b.disabled:
				return
			b.disabled = true
			Audio.play_sfx("click", 0.1)
			Lobby.claim_pass(lv, tile.get_global_rect().get_center(), _gold_target())
		b.pressed.connect(claim)
		vb.add_child(b)
		# Toute la case est cliquable : un clic sur la récompense la récupère.
		tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tile.tooltip_text = Loc.t("Cliquez pour récupérer : %s") % reward_text(r)
		tile.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				claim.call())
		var glow := tile.create_tween().set_loops()
		glow.tween_property(tile, "modulate", Color(1.25, 1.15, 0.85), 0.7).set_trans(Tween.TRANS_SINE)
		glow.tween_property(tile, "modulate", Color.WHITE, 0.7).set_trans(Tween.TRANS_SINE)
		return tile
	var name_l := UITheme.label(Loc.t("Obtenu") if done else (Loc.t("%d PO") % int(r.po) if r.has("po") else _short(Cosmetics.item_name(str(r.kind), r.id))), 11,
		UITheme.GREEN if done else Color("e8d6b0"), 2)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.clip_text = true
	name_l.custom_minimum_size.x = 100
	vb.add_child(name_l)
	if done:
		_grey_out(tile)   # déjà récupérée : case grisée
	else:
		tile.modulate = Color(0.85, 0.85, 0.9)
	return tile


static var _grey_mat: ShaderMaterial


## Case et tout son contenu en niveaux de gris (le contenu utilise le matériau de la case).
static func _grey_out(tile: Control) -> void:
	if _grey_mat == null:
		_grey_mat = ShaderMaterial.new()
		_grey_mat.shader = load("res://assets/shaders/grayscale.gdshader")
	tile.material = _grey_mat
	var stack: Array[Node] = tile.get_children()
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CanvasItem:
			if n.material != null:
				n.self_modulate = Color(0.45, 0.45, 0.45)   # élément animé par son propre shader (contour) : assombri
			else:
				n.use_parent_material = true
		stack.append_array(n.get_children())
	# Coche verte en haut à droite (hors du gris) : récompense déjà récupérée.
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(overlay)
	var check := CheckMark.new(24)
	check.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	check.offset_left = -26
	check.offset_right = -2
	check.offset_top = -2
	check.offset_bottom = 22
	overlay.add_child(check)
