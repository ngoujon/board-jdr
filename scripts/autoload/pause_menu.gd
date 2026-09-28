extends CanvasLayer
## Menu accessible avec Échap depuis n'importe quel écran : volumes, affichage,
## options de jeu et raccourcis clavier reconfigurables.

const MAIN_MENU := "res://scenes/main_menu.tscn"

var _root: Control
var _tabs: TabContainer
var _title: Label
var _btn_resume: Button
var _btn_concede: Button
var _btn_menu: Button
var _key_buttons := {}
var _capturing := ""
var _fullscreen_check: CheckButton


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.hide()
	Settings.settings_changed.connect(_refresh)
	# Connexions faites une seule fois (le menu est reconstruit quand la langue change).
	Lobby.connection_changed.connect(func(_on): _refresh_profile_status())
	Lobby.profile_changed.connect(_refresh_profile_status)
	Lobby.server_error.connect(func(_code, msg):
		if is_instance_valid(_profile_status):
			_profile_status.text = msg)


func is_open() -> bool:
	return _root.visible


func open() -> void:
	_update_header()
	_refresh()
	_root.show()
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.15)
	# En ligne, on ne met pas le jeu en pause (l'adversaire continue de jouer).
	get_tree().paused = not Net.is_online()
	_tabs.current_tab = 0
	_btn_resume.grab_focus()


## Titre et boutons du bas selon l'écran en cours (partie ou menus).
func _update_header() -> void:
	var scene := get_tree().current_scene
	var in_battle := _in_battle()
	var in_main := scene != null and scene.scene_file_path == MAIN_MENU
	_title.text = Loc.t("PAUSE") if in_battle else Loc.t("OPTIONS")
	_btn_concede.visible = in_battle and Net.mode != "replay"
	_btn_menu.visible = not in_main
	_btn_resume.text = Loc.t("Reprendre") if in_battle else Loc.t("Fermer")


func _in_battle() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.is_in_group("battle")


func close() -> void:
	_capturing = ""
	_root.hide()
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if _capturing != "":
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if is_open():
			close()
		elif close_top_modal():
			pass
		else:
			var scene := get_tree().current_scene
			if not (scene and scene.has_method("on_escape") and scene.on_escape()):
				open()


## Échap ferme d'abord la fenêtre modale ouverte la plus récente (groupe « modal »).
func close_top_modal() -> bool:
	var modals := get_tree().get_nodes_in_group("modal")
	for i in range(modals.size() - 1, -1, -1):
		var m: Node = modals[i]
		if not is_instance_valid(m) or m.is_queued_for_deletion() or (m is CanvasItem and not m.is_visible_in_tree()):
			continue
		if m.has_method("close"):
			m.close()
		else:
			m.queue_free()
		Audio.play_sfx("click", 0.1)
		return true
	return false


## Android : le bouton Retour agit comme Échap (fermer la fenêtre ouverte, sinon le menu pause).
## Le jeu ne se ferme plus sur Retour (application/config/quit_on_go_back=false).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		for pressed in [true, false]:
			var ev := InputEventKey.new()
			ev.keycode = KEY_ESCAPE
			ev.physical_keycode = KEY_ESCAPE
			ev.pressed = pressed
			Input.parse_input_event(ev)


func _input(event: InputEvent) -> void:
	if _capturing == "" or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	var k := event as InputEventKey
	if k.physical_keycode == KEY_ESCAPE and _capturing != "pause":
		_capturing = ""
		_refresh()
		return
	Settings.set_keybind(_capturing, k.physical_keycode)
	_capturing = ""
	_refresh()


# ---------------------------------------------------------------- construction

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.05, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(700, 540)
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)

	_title = UITheme.title_label(Loc.t("PAUSE"), 40)
	vb.add_child(_title)

	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(640, 330)
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_tabs)
	_tabs.add_child(_build_profile_tab())
	_tabs.add_child(_build_audio_tab())
	_tabs.add_child(_build_display_tab())
	_tabs.add_child(_build_game_tab())
	_tabs.add_child(_build_keys_tab())
	_tabs.add_child(_build_rules_tab())
	# Titres des onglets traduits (le nom du nœud reste l'identifiant français).
	for i in _tabs.get_tab_count():
		_tabs.set_tab_title(i, Loc.t(String(_tabs.get_tab_control(i).name)))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 10)
	vb.add_child(buttons)

	_btn_resume = UITheme.button(Loc.t("Reprendre"), 150)
	_btn_resume.pressed.connect(close)
	buttons.add_child(_btn_resume)

	_btn_concede = UITheme.button(Loc.t("Abandonner"), 150)
	_btn_concede.pressed.connect(_on_concede)
	buttons.add_child(_btn_concede)

	_btn_menu = UITheme.button(Loc.t("Menu principal"), 170)
	_btn_menu.pressed.connect(_on_main_menu)
	buttons.add_child(_btn_menu)


## Reconstruit tout le menu (après un changement de langue) en conservant l'onglet affiché.
func _rebuild() -> void:
	var was_open := is_open()
	var tab := _tabs.current_tab
	_capturing = ""
	_key_buttons.clear()
	_avatar_buttons.clear()
	_fullscreen_check = null
	_name_edit = null
	remove_child(_root)
	_root.queue_free()
	_build()
	_tabs.current_tab = tab
	_update_header()
	_refresh()
	_root.visible = was_open


func _on_language_selected(code: String) -> void:
	if code == Settings.language:
		return
	Settings.set_language(code)
	Lobby.send({"t": "set_lang", "lang": code})   # le serveur traduira ses messages
	if _in_battle():
		Lobby.toast(Loc.t("La langue sera appliquée à la fin de la partie."), UITheme.GOLD)
	elif get_tree().current_scene:
		get_tree().reload_current_scene()
	# On attend que la scène rechargée soit en place (le titre et les boutons du bas en dépendent).
	await get_tree().process_frame
	await get_tree().process_frame
	_rebuild()


func _tab_box(tab_name: String) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.name = tab_name
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	margin.add_child(vb)
	return vb


func _build_audio_tab() -> Control:
	var vb := _tab_box("Audio")
	var labels := {"Master": "Volume général", "Music": "Musique", "SFX": "Effets sonores"}
	for bus_name in labels:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var l := UITheme.label(Loc.t(labels[bus_name]))
		l.custom_minimum_size.x = 200
		row.add_child(l)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.custom_minimum_size = Vector2(300, 28)
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.value = Settings.volumes[bus_name]
		var pct := UITheme.label("%d %%" % roundi(slider.value * 100))
		pct.custom_minimum_size.x = 70
		slider.value_changed.connect(func(v: float):
			Settings.set_volume(bus_name, v)
			pct.text = "%d %%" % roundi(v * 100))
		if bus_name == "SFX":
			slider.drag_ended.connect(func(_c): Audio.play_sfx("attack"))
		row.add_child(slider)
		row.add_child(pct)
		vb.add_child(row)
	return vb.get_parent()


func _build_display_tab() -> Control:
	var vb := _tab_box("Affichage")
	_fullscreen_check = CheckButton.new()
	_fullscreen_check.text = Loc.t("Plein écran")
	_fullscreen_check.button_pressed = Settings.fullscreen
	_fullscreen_check.toggled.connect(func(on: bool): Settings.set_fullscreen(on))
	vb.add_child(_fullscreen_check)

	var vs := CheckButton.new()
	vs.text = Loc.t("Synchronisation verticale (V-Sync)")
	vs.button_pressed = Settings.vsync
	vs.toggled.connect(func(on: bool): Settings.set_vsync(on))
	vb.add_child(vs)

	var zrow := HBoxContainer.new()
	zrow.add_theme_constant_override("separation", 12)
	var zl := UITheme.label(Loc.t("Zoom de l'interface"))
	zl.custom_minimum_size.x = 260
	zrow.add_child(zl)
	var zoom := HSlider.new()
	zoom.min_value = 0.7
	zoom.max_value = 1.3
	zoom.step = 0.05
	zoom.value = Settings.ui_zoom
	zoom.custom_minimum_size = Vector2(220, 28)
	zoom.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var zpct := UITheme.label("%d %%" % roundi(zoom.value * 100))
	zoom.value_changed.connect(func(v: float): zpct.text = "%d %%" % roundi(v * 100))
	# Appliqué au relâchement du curseur (la fenêtre change de taille : pas à chaque cran).
	zoom.drag_ended.connect(func(_c: bool): Settings.set_ui_zoom(zoom.value))
	zrow.add_child(zoom)
	zrow.add_child(zpct)
	var zreset := UITheme.button(Loc.t("100 %"), 90)
	zreset.pressed.connect(func():
		zoom.value = 1.0
		Settings.set_ui_zoom(1.0))
	zrow.add_child(zreset)
	vb.add_child(zrow)
	var zhint := UITheme.label(Loc.t("En fenêtre, le zoom agrandit ou réduit la fenêtre. En plein écran, l'interface occupe déjà tout l'écran : seul le dézoom s'applique."), 14, Color("c9b79a"))
	zhint.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(zhint)
	return vb.get_parent()


func _build_game_tab() -> Control:
	var vb := _tab_box("Jeu")
	# Langue du jeu (les noms des langues ne se traduisent pas).
	var lrow := HBoxContainer.new()
	lrow.add_theme_constant_override("separation", 12)
	var ll := UITheme.label(Loc.t("Langue"))
	ll.custom_minimum_size.x = 260
	lrow.add_child(ll)
	var lang_opt := OptionButton.new()
	lang_opt.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for i in Loc.LANGS.size():
		lang_opt.add_item(Loc.LANG_NAMES[Loc.LANGS[i]], i)
	lang_opt.selected = maxi(Loc.LANGS.find(Settings.language), 0)
	lang_opt.item_selected.connect(func(i: int): _on_language_selected(Loc.LANGS[i]))
	lang_opt.custom_minimum_size.x = 240
	lrow.add_child(lang_opt)
	vb.add_child(lrow)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := UITheme.label(Loc.t("Difficulté de l'IA"))
	l.custom_minimum_size.x = 260
	row.add_child(l)
	var opt := OptionButton.new()
	opt.add_item(Loc.t("Apprenti (facile)"), 0)
	opt.add_item(Loc.t("Chevalier (normal)"), 1)
	opt.add_item(Loc.t("Seigneur de guerre (difficile)"), 2)
	opt.add_item(Loc.t("Challenger (extrême)"), 3)
	opt.add_item(Loc.t("Inferno (score)"), 4)
	opt.selected = Settings.ai_difficulty
	opt.item_selected.connect(func(i: int): Settings.set_difficulty(i))
	opt.custom_minimum_size.x = 240
	row.add_child(opt)
	vb.add_child(row)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	var l2 := UITheme.label(Loc.t("Vitesse des animations"))
	l2.custom_minimum_size.x = 260
	row2.add_child(l2)
	var speed := HSlider.new()
	speed.min_value = 0.5
	speed.max_value = 3.0
	speed.step = 0.25
	speed.value = Settings.anim_speed
	speed.custom_minimum_size = Vector2(220, 28)
	speed.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sl := UITheme.label("x%.2f" % speed.value)
	speed.value_changed.connect(func(v: float):
		Settings.set_anim_speed(v)
		sl.text = "x%.2f" % v)
	row2.add_child(speed)
	row2.add_child(sl)
	vb.add_child(row2)

	var hint := UITheme.label(Loc.t("Astuce : maintenez la touche « Accélérer » pendant le tour de l'IA."), 15, Color("c9b79a"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(hint)
	return vb.get_parent()


func _build_keys_tab() -> Control:
	var vb := _tab_box("Raccourcis")
	for action in Settings.REBINDABLE:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var l := UITheme.label(Loc.t(Settings.REBINDABLE[action][0]), 17)
		l.custom_minimum_size.x = 360
		row.add_child(l)
		var b := UITheme.button("", 200)
		b.custom_minimum_size.y = 38
		b.pressed.connect(func():
			_capturing = action
			b.text = Loc.t("Appuyez sur une touche..."))
		row.add_child(b)
		_key_buttons[action] = b
		vb.add_child(row)
	var mouse := UITheme.label(Loc.t("Souris : clic gauche = jouer / attaquer / cibler, clic droit = annuler."), 15, Color("c9b79a"))
	mouse.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(mouse)
	var reset := UITheme.button(Loc.t("Réinitialiser les touches"), 280)
	reset.custom_minimum_size.y = 38
	reset.pressed.connect(func(): Settings.reset_keybinds())
	vb.add_child(reset)
	return vb.get_parent()


var _name_edit: LineEdit
var _avatar_buttons: Array[Button] = []
var _selected_avatar := 1
var _profile_status: Label
var _server_status: Label


func _build_profile_tab() -> Control:
	var vb := _tab_box("Profil")
	vb.add_theme_constant_override("separation", 8)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(UITheme.label(Loc.t("Pseudo"), 18))
	_name_edit = LineEdit.new()
	_name_edit.max_length = 16
	_name_edit.placeholder_text = Loc.t("3 à 16 caractères")
	_name_edit.custom_minimum_size.x = 230
	row.add_child(_name_edit)
	var save := UITheme.button(Loc.t("Enregistrer"), 150)
	save.custom_minimum_size.y = 36
	save.pressed.connect(_save_profile)
	row.add_child(save)
	vb.add_child(row)

	vb.add_child(UITheme.label(Loc.t("Avatar"), 16, UITheme.GOLD))
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 6)
	vb.add_child(grid)
	for i in CardDB.BASE_AVATARS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(62, 62)
		b.set_meta("avatar", i)
		b.icon = CardDB.avatar(i)
		b.expand_icon = true
		b.tooltip_text = Loc.t(CardDB.AVATAR_NAMES[i])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		var off := UITheme.flat_style(Color("1a1220"), Color("6b5a3c"), 2, 4)
		var on := UITheme.flat_style(Color("3a2a10"), UITheme.GOLD, 4, 4)
		for sb in [off, on]:
			sb.set_content_margin_all(3)
		b.add_theme_stylebox_override("normal", off)
		b.add_theme_stylebox_override("hover", on)
		b.add_theme_stylebox_override("pressed", on)
		b.add_theme_stylebox_override("hover_pressed", on)
		b.pressed.connect(func(): _select_avatar(i))
		grid.add_child(b)
		_avatar_buttons.append(b)

	var custom := UITheme.button(Loc.t("Personnalisation (titres, avatars, contours, dos, plateaux)"), 560)
	custom.custom_minimum_size.y = 40
	custom.pressed.connect(func(): add_child(CustomizePanel.new()))
	vb.add_child(custom)

	_profile_status = UITheme.label("", 15, Color("c9b79a"), 3)
	_profile_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(_profile_status)

	# Serveur officiel : aucune adresse ni port à saisir (--server=/--port= restent possibles pour les tests).
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 12)
	_server_status = UITheme.label("", 15, Color("c9b79a"), 3)
	_server_status.custom_minimum_size.x = 360
	srow.add_child(_server_status)
	var connect_btn := UITheme.button(Loc.t("Se reconnecter"), 190)
	connect_btn.custom_minimum_size.y = 36
	connect_btn.pressed.connect(_save_profile)
	srow.add_child(connect_btn)
	vb.add_child(srow)
	return vb.get_parent()


func _select_avatar(i: int) -> void:
	_selected_avatar = i
	for b in _avatar_buttons:
		var sel: bool = b.get_meta("avatar") == i
		b.set_pressed_no_signal(sel)
		b.modulate = Color.WHITE if sel else Color(0.6, 0.6, 0.6)


func _save_profile() -> void:
	var n := _name_edit.text.strip_edges()
	if n.length() < 3:
		_profile_status.text = Loc.t("Le pseudo doit contenir au moins 3 caractères.")
		return
	Settings.set_profile(n, _selected_avatar)
	_profile_status.text = Loc.t("Vérification du pseudo auprès du serveur...")
	Lobby.update_profile()


func _refresh_profile_status() -> void:
	if not is_instance_valid(_profile_status) or not is_instance_valid(_server_status):
		return
	if Lobby.online:
		_profile_status.text = Loc.t("Profil enregistré : %s. Pseudo réservé sur le serveur.") % Lobby.profile.get("name", "")
	elif Lobby.last_error != "":
		_profile_status.text = Lobby.last_error
	var official := Settings.server_address == Settings.OFFICIAL_SERVER
	_server_status.text = "%s : %s" % [Loc.t("Serveur officiel") if official else Loc.t("Serveur %s") % Settings.server_address, Lobby.status_text()]


func _build_rules_tab() -> Control:
	var rt := RichTextLabel.new()
	rt.name = "Règles"
	rt.bbcode_enabled = true
	rt.text = RulesPanel.rules_bbcode()
	rt.add_theme_font_size_override("normal_font_size", 15)
	rt.add_theme_font_size_override("bold_font_size", 15)
	return rt


func open_rules() -> void:
	open()
	_tabs.current_tab = _tabs.get_tab_count() - 1


func open_profile() -> void:
	open()
	_tabs.current_tab = 0


func _refresh() -> void:
	if _name_edit and not _name_edit.has_focus():
		_name_edit.text = Settings.player_name
		_select_avatar(Settings.avatar)
		_refresh_profile_status()
	for action in _key_buttons:
		if action != _capturing:
			_key_buttons[action].text = Settings.key_label(action)
	if _fullscreen_check:
		_fullscreen_check.set_pressed_no_signal(Settings.fullscreen)


func _on_concede() -> void:
	var scene := get_tree().current_scene
	close()
	if scene and scene.has_method("concede"):
		scene.concede()


func _on_main_menu() -> void:
	close()
	Net.close()
	get_tree().change_scene_to_file(MAIN_MENU)
