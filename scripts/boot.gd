extends Control
## Écran de démarrage : vérifie auprès du serveur que le jeu est à jour.
##  - À jour, ou serveur injoignable : on passe au menu principal.
##  - Version obsolète : proposition de mise à jour (téléchargement + redémarrage automatique).
##    Sans mise à jour, seul le mode hors ligne (contre l'IA) reste accessible.

const MAIN_MENU := "res://scenes/main_menu.tscn"

var _status: Label
var _bar: ProgressBar
var _panel: PanelContainer
var _box: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	get_tree().paused = false
	if Updater.restarting:
		return
	Audio.play_music("menu")

	var bg := TextureRect.new()
	bg.texture = CardDB.texture("res://assets/bg/menu.png")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.modulate = Color(0.45, 0.42, 0.45)
	add_child(bg)

	var title := UITheme.title_label("ARCANES & LAMES", 72)
	title.position = Vector2(0, 120)
	title.size = Vector2(1280, 90)
	add_child(title)
	var ver := UITheme.label(Loc.t("Version %s") % Updater.current_version(), 18, Color("c9b79a"))
	ver.position = Vector2(0, 208)
	ver.size = Vector2(1280, 26)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(ver)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(620, 0)
	_panel.position = Vector2(330, 280)
	add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 14)
	_panel.add_child(_box)

	_status = UITheme.label(Loc.t("Vérification des mises à jour..."), 22)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_status)

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 26)
	_bar.show_percentage = false
	_bar.add_theme_stylebox_override("background", UITheme.flat_style(Color("2b1d14"), Color("6b5a3c"), 2))
	_bar.add_theme_stylebox_override("fill", UITheme.flat_style(Color("c98a2b"), Color("f2c14e"), 2))
	_bar.visible = false
	_box.add_child(_bar)

	Updater.check_finished.connect(_on_check_finished)
	Updater.download_progress.connect(_on_progress)
	Updater.download_finished.connect(_on_download_finished)
	if Updater.state in ["outdated", "ready"]:
		# Retour ici depuis le menu (ex. le serveur a refusé notre version).
		_on_check_finished.call_deferred(Updater.state)
	else:
		Updater.check()


func _on_check_finished(state: String) -> void:
	if not is_inside_tree():
		return   # on a déjà quitté l'écran (ex. invitation acceptée entre-temps)
	_clear_buttons()
	match state:
		"up_to_date":
			_status.text = Loc.t("Le jeu est à jour (version %s).") % Updater.current_version()
			await get_tree().create_timer(0.6, false).timeout
			_go_menu()
		"offline", "error":
			_status.text = Loc.t("Serveur de mise à jour injoignable.\nLancement en mode hors ligne...")
			await get_tree().create_timer(1.4).timeout
			_go_menu()
		"outdated":
			if OS.get_cmdline_user_args().has("--auto-update") and Updater.last_error == "":
				_start_download()   # mode test
				return
			if Settings.autoplay:
				_go_menu()
				return
			_show_outdated()
		"ready":
			_show_ready()


func _show_outdated() -> void:
	var latest: Dictionary = Updater.latest
	var txt := Loc.t("[center][color=#f2c14e][b]Nouvelle version disponible : %s[/b][/color]\nVotre version : %s") % [
		latest.get("version", "?"), Updater.current_version()]
	var size := float(latest.get("size", 0))
	if Updater.needs_app_download():   # application complète, pas le paquet .pck
		size = float(latest.get("downloads", {}).get(Updater.platform_key(), {}).get("size", 0))
	if size > 0:
		txt += Loc.t("  ·  %.1f Mo") % (size / 1048576.0)
	txt += "[/center]"
	if str(latest.get("notes", "")) != "":
		txt += Loc.t("\n\n[b]Nouveautés :[/b]\n") + str(latest.notes)
	txt += Loc.t("\n\n[color=#c9b79a]La mise à jour est obligatoire pour jouer en ligne : tout le monde joue sur la même version.[/color]")
	_status.text = ""
	var notes := RichTextLabel.new()
	notes.bbcode_enabled = true
	notes.fit_content = true
	notes.custom_minimum_size = Vector2(580, 0)
	notes.text = txt
	notes.set_meta("temp", true)
	_box.add_child(notes)
	_box.move_child(notes, 0)
	if Updater.last_error != "":
		_status.text = Updater.last_error
		_status.add_theme_color_override("font_color", UITheme.RED)
	var row := _button_row()
	var upd := UITheme.button(Loc.t("Mettre à jour"), 240)
	upd.pressed.connect(_start_download)
	row.add_child(upd)
	var off := UITheme.button(Loc.t("Jouer hors ligne"), 240)
	off.pressed.connect(_go_menu)
	row.add_child(off)
	upd.grab_focus()


func _start_download() -> void:
	if Updater.needs_app_download():
		if not Updater.latest.has("downloads"):
			Updater.check()   # on ne connaît que le numéro (refus du serveur) : on récupère le manifeste
			await Updater.check_finished
		OS.shell_open(Updater.app_download_url())
		_status.remove_theme_color_override("font_color")
		_status.text = Loc.t("Le téléchargement de la version %s s'ouvre dans le navigateur.\nInstallez le fichier téléchargé : vos données sont conservées.") % Updater.latest.get("version", "?")
		return
	_clear_buttons()
	_status.remove_theme_color_override("font_color")
	_status.text = Loc.t("Téléchargement de la version %s...") % Updater.latest.get("version", "?")
	_bar.visible = true
	_bar.value = 0
	Updater.download()


func _on_progress(done: int, total: int) -> void:
	if total > 0:
		_bar.max_value = total
		_bar.value = done
		_status.text = Loc.t("Téléchargement de la version %s... %.1f / %.1f Mo") % [
			Updater.latest.get("version", "?"), done / 1048576.0, total / 1048576.0]


func _on_download_finished(ok: bool, message: String) -> void:
	_bar.visible = false
	if not ok:
		Updater.last_error = message
		_on_check_finished("outdated")
		return
	_show_ready()


func _show_ready() -> void:
	_clear_buttons()
	if Updater.can_self_update():
		_status.text = Loc.t("Mise à jour %s installée !\nRedémarrage du jeu...") % Updater.latest.get("version", "")
		Audio.play_sfx("card_play")
		await get_tree().create_timer(1.2).timeout
		Updater.restart_on_update()
	else:
		# Lancé depuis l'éditeur Godot : impossible de se relancer sur le paquet.
		_status.text = Loc.t("Mise à jour %s téléchargée.\nLe jeu est lancé depuis l'éditeur : elle sera appliquée au prochain lancement de la version exportée (ou mettez à jour les sources du projet).") % Updater.latest.get("version", "")
		var row := _button_row()
		var cont := UITheme.button(Loc.t("Continuer hors ligne"), 280)
		cont.pressed.connect(_go_menu)
		row.add_child(cont)


func _button_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	row.set_meta("temp", true)
	_box.add_child(row)
	return row


func _clear_buttons() -> void:
	for c in _box.get_children():
		if c.has_meta("temp"):
			c.queue_free()


func _go_menu() -> void:
	if is_inside_tree():
		get_tree().change_scene_to_file(MAIN_MENU)
