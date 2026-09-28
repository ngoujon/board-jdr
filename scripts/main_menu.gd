extends Control
## Menu principal.

var _buttons: VBoxContainer
var _difficulty_box: VBoxContainer
var _level_btns: Array[Button] = []   # boutons des niveaux 0 à 3 (coche verte si déjà battu)
var _inferno_record: Label
var _friends_btn: Button
var _title: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	get_tree().paused = false
	Engine.time_scale = Settings.anim_speed
	Audio.play_music("menu")

	# Le fond est sur une couche inférieure pour que les braises 3D passent entre lui et l'interface.
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -2
	add_child(bg_layer)
	var bg := TextureRect.new()
	bg.texture = CardDB.texture("res://assets/bg/menu.png")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg_layer.add_child(bg)

	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([Color(0.02, 0.01, 0.04, 0.85), Color(0.02, 0.01, 0.04, 0.35), Color(0, 0, 0, 0)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	shade.texture = gt
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	bg_layer.add_child(shade)

	var fx := Fx3D.new()
	fx.layer = -1   # braises derrière l'interface
	add_child(fx)
	fx.ambient_embers()

	_title = UITheme.title_label(Loc.t("ARCANES & LAMES"), 72)
	_title.position = Vector2(60, 70)
	_title.size = Vector2(620, 90)
	_title.pivot_offset = Vector2(310, 45)
	add_child(_title)
	var sub := UITheme.label(Loc.t("Duel de cartes au cœur du Royaume"), 22, Color("e8d6b0"), 5)
	sub.position = Vector2(60, 160)
	sub.size = Vector2(620, 30)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub)

	_buttons = VBoxContainer.new()
	_buttons.position = Vector2(220, 212)
	_buttons.add_theme_constant_override("separation", 7)
	add_child(_buttons)
	_add_btn(_buttons, Loc.t("Défier l'IA"), _on_play)
	_add_btn(_buttons, Loc.t("Multijoueur"), func(): get_tree().change_scene_to_file("res://scenes/multiplayer.tscn"))
	_add_btn(_buttons, Loc.t("Collection de cartes"), func(): get_tree().change_scene_to_file("res://scenes/collection.tscn"))
	_add_btn(_buttons, Loc.t("Classement"), func(): add_child(LeaderboardPanel.new()))
	_add_btn(_buttons, Loc.t("Statistiques"), func(): add_child(StatsPanel.new()))
	_add_btn(_buttons, Loc.t("Boutique"), func(): add_child(ShopPanel.new()))
	_friends_btn = _add_btn(_buttons, Loc.t("Amis"), func(): add_child(FriendsPanel.new()))
	_add_btn(_buttons, Loc.t("Règles du jeu"), func(): add_child(RulesPanel.new()))

	# Icônes en bas à gauche : quitter le jeu (déconnexion) et paramètres (engrenage).
	var quit_icon := IconButton.new("logout", Loc.t("Quitter le jeu"))
	quit_icon.position = Vector2(20, 648)
	quit_icon.pressed.connect(func(): get_tree().quit())
	add_child(quit_icon)
	var gear := IconButton.new("gear", Loc.t("Paramètres"))
	gear.position = Vector2(86, 648)
	gear.pressed.connect(func(): PauseMenu.open())
	add_child(gear)

	_difficulty_box = VBoxContainer.new()
	_difficulty_box.position = Vector2(220, 212)
	_difficulty_box.add_theme_constant_override("separation", 14)
	_difficulty_box.visible = false
	add_child(_difficulty_box)
	var choose := UITheme.label(Loc.t("Choisissez votre adversaire :"), 20, UITheme.GOLD)
	_difficulty_box.add_child(choose)
	_level_btns = [
		_add_btn(_difficulty_box, Loc.t("Apprenti (facile)"), func(): _launch(0)),
		_add_btn(_difficulty_box, Loc.t("Chevalier (normal)"), func(): _launch(1)),
		_add_btn(_difficulty_box, Loc.t("Seigneur de guerre (difficile)"), func(): _launch(2)),
		_add_btn(_difficulty_box, Loc.t("Challenger (extrême)"), func(): _launch(3))]
	_level_btns[3].tooltip_text = Loc.t("Réfléchit comme le Seigneur de guerre et commence avec 5 PV et 1 carte de plus.")
	for i in _level_btns.size():
		var mark := CheckMark.new(26)
		mark.name = "Beaten"
		mark.position = Vector2(308, 9)   # à droite du bouton : les libellés longs vont jusqu'au bord
		_level_btns[i].add_child(mark)
	var inf := _add_btn(_difficulty_box, Loc.t("Inferno (score)"), func(): _launch(4))
	inf.add_theme_color_override("font_color", Color("ffa060"))
	inf.add_theme_color_override("font_hover_color", Color("ffc890"))
	inf.tooltip_text = Loc.t("L'IA la plus forte, avec des PV infinis : infligez-lui un maximum de dégâts avant de tomber. Votre meilleur score entre au classement Inferno.")
	_inferno_record = UITheme.label("", 15, Color("ffa060"), 3)
	_inferno_record.position = Vector2(312, 12)
	_inferno_record.custom_minimum_size.x = 240
	inf.add_child(_inferno_record)
	_add_btn(_difficulty_box, Loc.t("Retour"), func():
		_difficulty_box.visible = false
		_buttons.visible = true)

	Lobby.unread_changed.connect(_refresh_unread)
	_refresh_unread()
	_build_profile_badge()
	_build_season_widget()
	_build_patch_notes()
	Lobby.set_status("online" if Lobby.room.is_empty() else "lobby")
	if Settings.player_name == "" and not Settings.welcome_done and not Settings.autoplay:
		# Premier lancement : accueil (présentation du jeu, puis pseudo et avatar).
		add_child(WelcomePanel.new())
	elif Settings.player_name == "":
		# Accueil déjà passé : simple rappel pour choisir un pseudo et un avatar.
		get_tree().create_timer(0.6).timeout.connect(func():
			Lobby.toast(Loc.t("Bienvenue ! Choisissez votre pseudo et votre avatar dans Paramètres > Profil."), UITheme.GOLD, 6.0))

	var ver := UITheme.label(Loc.t("v%s · Échap : paramètres") % Updater.current_version(), 14, Color("c9b79a"), 3)
	ver.position = Vector2(960, 690)
	add_child(ver)
	if Updater.state in ["outdated", "ready"]:
		var upd := UITheme.button(Loc.t("Mise à jour %s disponible") % Updater.latest.get("version", ""), 280)
		upd.position = Vector2(960, 630)
		upd.add_theme_color_override("font_color", UITheme.GOLD)
		upd.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/boot.tscn"))
		add_child(upd)

	var tw := create_tween().set_loops()
	tw.tween_property(_title, "position:y", 62.0, 1.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_title, "position:y", 70.0, 1.6).set_trans(Tween.TRANS_SINE)
	_buttons.get_child(0).grab_focus()


## Encart « Nouveautés » (dernière version) + ouverture automatique des notes après une mise à jour.
func _build_patch_notes() -> void:
	var notes := PatchNotesPanel.load_notes()
	if notes.is_empty():
		return
	var latest: Dictionary = notes[0]
	var panel := PanelContainer.new()
	panel.position = Vector2(760, 118)
	panel.custom_minimum_size = Vector2(490, 382)   # le passe de combat est affiché dessous
	panel.size = panel.custom_minimum_size
	var sb := UITheme.flat_style(Color(0.07, 0.05, 0.09, 0.88), UITheme.GOLD, 2, 6)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	var head := UITheme.label(Loc.t("Nouveautés  ·  version %s") % latest.get("version", "?"), 20, UITheme.GOLD)
	head.add_theme_font_override("font", UITheme.font_bold)
	vb.add_child(head)
	var sub := UITheme.label("%s — %s" % [PatchNotesPanel.format_date(latest.get("date", "")), Loc.t(str(latest.get("title", "")))], 14, Color("c9b79a"), 3)
	vb.add_child(sub)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.scroll_active = true   # notes longues : barre de défilement
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", 15)
	text.add_theme_font_size_override("bold_font_size", 15)
	text.text = PatchNotesPanel.entry_bbcode(latest)
	vb.add_child(text)
	var all := UITheme.button(Loc.t("Toutes les notes de mise à jour"), 300)
	all.custom_minimum_size.y = 38
	all.add_theme_font_size_override("font_size", 16)
	all.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	all.pressed.connect(func(): add_child(PatchNotesPanel.new()))
	vb.add_child(all)

	# Première fois qu'on lance cette version (après une mise à jour) : notes complètes à l'écran.
	var current := Updater.current_version()
	if Settings.last_seen_patch != current:
		var after_update := Settings.last_seen_patch != ""
		Settings.last_seen_patch = current
		Settings.save_settings()
		if after_update and not Settings.autoplay:
			get_tree().create_timer(0.5).timeout.connect(func():
				if is_inside_tree():
					add_child(PatchNotesPanel.new()))


func _add_btn(box: VBoxContainer, text: String, cb: Callable) -> Button:
	var b := UITheme.button(text, 300)
	b.custom_minimum_size.y = 44
	b.pressed.connect(cb)
	box.add_child(b)
	return b


var _season_box: VBoxContainer


## Passe de combat de la saison en cours (sous les notes de mise à jour).
func _build_season_widget() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(760, 510)
	panel.custom_minimum_size = Vector2(490, 148)
	panel.size = panel.custom_minimum_size
	var sb := UITheme.flat_style(Color(0.1, 0.06, 0.04, 0.9), Color("ffcf5a"), 2, 6)
	sb.set_content_margin_all(12)
	sb.shadow_color = Color(1, 0.75, 0.2, 0.25)
	sb.shadow_size = 8
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	_season_box = VBoxContainer.new()
	_season_box.add_theme_constant_override("separation", 6)
	panel.add_child(_season_box)
	Lobby.profile_changed.connect(_refresh_season)
	Lobby.connection_changed.connect(func(_o): _refresh_season())
	_refresh_season()


func _refresh_season() -> void:
	if not is_instance_valid(_season_box):
		return
	for c in _season_box.get_children():
		c.queue_free()
	var s := Lobby.season()
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	_season_box.add_child(top)
	var sname := Loc.t(str(s.get("name", "")))
	var t := UITheme.label(Loc.t("Passe de combat · Saison %d%s") % [int(s.get("n", 1)), (" — " + sname) if sname != "" else ""], 19, UITheme.GOLD)
	t.add_theme_font_override("font", UITheme.font_bold)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(t)
	if s.is_empty():
		var off := UITheme.label(Loc.t("Connectez-vous au serveur pour participer à la saison et gagner des PO."), 15, Color("c9b79a"), 3)
		off.autowrap_mode = TextServer.AUTOWRAP_WORD
		_season_box.add_child(off)
		return
	top.add_child(UITheme.label(BattlePassPanel.days_left_text(s), 14, Color("c9b79a"), 3))
	var level := int(s.get("level", 0))
	var levels := int(s.get("levels", 30))
	var per := maxi(1, int(s.get("xp_per_level", 250)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_season_box.add_child(row)
	row.add_child(UITheme.label(Loc.t("Niv. %d / %d") % [level, levels], 17, UITheme.LIGHT_TEXT, 3))
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(200, 18)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.max_value = per
	bar.value = per if level >= levels else int(s.get("xp", 0)) % per
	bar.show_percentage = false
	bar.add_theme_stylebox_override("fill", UITheme.flat_style(Color("e0a82e"), Color("ffe08a"), 1, 4))
	bar.add_theme_stylebox_override("background", UITheme.flat_style(Color(0.1, 0.07, 0.06), Color("6b5a3c"), 2, 4))
	row.add_child(bar)
	row.add_child(GoldCoin.new(11))
	row.add_child(UITheme.label(Loc.t("%d PO") % Lobby.gold(), 16, UITheme.GOLD, 3))
	var next := {}
	for r in s.get("rewards", []):
		if int(r.level) > level:
			next = r
			break
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	_season_box.add_child(bottom)
	var nl := UITheme.label((Loc.t("Prochaine récompense (niv. %d) : %s") % [int(next.level), BattlePassPanel.reward_text(next).replace("\n", " ")]) if not next.is_empty() else Loc.t("Passe terminé : bravo !"), 14, Color("e8d6b0"), 3)
	var to_claim := Lobby.claimable_levels().size()
	if to_claim > 0:
		nl.text = (Loc.t("%d récompenses à récupérer !") if to_claim > 1 else Loc.t("%d récompense à récupérer !")) % to_claim
		nl.add_theme_color_override("font_color", Color("fff2a0"))
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nl.clip_text = true
	bottom.add_child(nl)
	var open := UITheme.button(Loc.t("Voir le passe"), 160)
	open.custom_minimum_size.y = 34
	open.add_theme_font_size_override("font_size", 15)
	open.pressed.connect(func(): add_child(BattlePassPanel.new()))
	if to_claim > 0:
		open.text = Loc.t("Récupérer")
		var pulse := open.create_tween().set_loops()
		pulse.tween_property(open, "modulate", Color(1.35, 1.2, 0.7), 0.6)
		pulse.tween_property(open, "modulate", Color.WHITE, 0.6)
	bottom.add_child(open)


var _badge_name: Label
var _badge_info: Label
var _badge_avatar: AvatarBadge
var _badge_title: Label
var _badge_gold: Label


func _build_profile_badge() -> void:
	var badge := Button.new()
	badge.position = Vector2(860, 16)
	badge.custom_minimum_size = Vector2(400, 84)
	badge.size = Vector2(400, 84)
	badge.focus_mode = Control.FOCUS_NONE
	badge.tooltip_text = Loc.t("Modifier le profil")
	badge.pressed.connect(func(): PauseMenu.open_profile())
	add_child(badge)
	_badge_avatar = AvatarBadge.new().setup(Settings.avatar, "none", 70)
	_badge_avatar.position = Vector2(8, 7)
	badge.add_child(_badge_avatar)
	_badge_name = UITheme.label("", 22, UITheme.GOLD, 5)
	_badge_name.position = Vector2(90, 2)
	_badge_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(_badge_name)
	# Titre débloqué, affiché sous le pseudo.
	_badge_title = UITheme.label("", 14, Color("c9a0ff"), 3)
	_badge_title.position = Vector2(92, 31)
	_badge_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(_badge_title)
	_badge_info = UITheme.label("", 13, Color("e8d6b0"), 3)
	_badge_info.position = Vector2(92, 54)
	_badge_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(_badge_info)
	# Pièces d'or (PO), en haut à droite du badge.
	var coin := GoldCoin.new(12)
	coin.position = Vector2(312, 8)
	badge.add_child(coin)
	_badge_gold = UITheme.label("", 18, UITheme.GOLD, 3)
	_badge_gold.position = Vector2(342, 6)
	_badge_gold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(_badge_gold)
	Lobby.gold_changed.connect(_refresh_badge)
	Lobby.profile_changed.connect(_refresh_badge)
	Lobby.connection_changed.connect(func(_o): _refresh_badge())
	Settings.settings_changed.connect(_refresh_badge)
	_refresh_badge()


func _refresh_badge() -> void:
	if not is_instance_valid(_badge_name):
		return
	var look := Lobby.my_look()
	_badge_avatar.set_texture(CardDB.avatar(Settings.avatar))
	_badge_avatar.set_border(look.border)
	_badge_title.text = Cosmetics.title_name(look.title) if Settings.player_name != "" else ""
	_badge_name.text = Settings.player_name if Settings.player_name != "" else Loc.t("Profil à créer")
	_badge_gold.text = str(Lobby.gold())
	var p := Lobby.profile
	if Lobby.online:
		var played := int(p.get("wins", 0)) + int(p.get("losses", 0))
		var wr := 100.0 * int(p.get("wins", 0)) / played if played > 0 else 0.0
		_badge_info.text = Loc.t("● En ligne · %d V / %d D (%.0f %%)") % [int(p.get("wins", 0)), int(p.get("losses", 0)), wr]
		_badge_info.add_theme_color_override("font_color", UITheme.GREEN)
	else:
		_badge_info.text = Loc.t("● %s · vs IA : %d V / %d D") % [Lobby.status_text(), Settings.local_ai_wins, Settings.local_ai_losses]
		_badge_info.add_theme_color_override("font_color", Color("c9b79a"))


func _on_play() -> void:
	_buttons.visible = false
	_difficulty_box.visible = true
	_refresh_levels()
	_difficulty_box.get_child(clampi(Settings.ai_difficulty, 0, 4) + 1).grab_focus()


## Coche verte sur les niveaux déjà battus, record Inferno à côté de son bouton.
func _refresh_levels() -> void:
	for i in _level_btns.size():
		var beaten := Settings.has_beaten(i)
		var mark: Control = _level_btns[i].get_node("Beaten")
		mark.visible = beaten
		mark.tooltip_text = Loc.t("Niveau déjà battu")
	var best := maxi(Settings.inferno_best, int(Lobby.profile.get("inferno_best", 0)))
	_inferno_record.text = Loc.t("Record : %d") % best if best > 0 else ""


## Nombre de messages non lus sur le bouton « Amis ».
func _refresh_unread() -> void:
	var n := Lobby.total_unread()
	_friends_btn.text = Loc.t("Amis  ✉ %d") % n if n > 0 else Loc.t("Amis")
	_friends_btn.add_theme_color_override("font_color", UITheme.GOLD if n > 0 else UITheme.LIGHT_TEXT)


## Échap sur le choix de l'adversaire : retour au menu (appelé par PauseMenu).
func on_escape() -> bool:
	if _difficulty_box.visible:
		_difficulty_box.visible = false
		_buttons.visible = true
		_buttons.get_child(0).grab_focus()
		return true
	return false


func _launch(difficulty: int) -> void:
	Settings.set_difficulty(difficulty)
	Net.close()   # mode "ai"
	get_tree().change_scene_to_file("res://scenes/battle.tscn")
