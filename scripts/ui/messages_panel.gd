class_name MessagesPanel
extends Control
## Messagerie privée avec les amis : liste des amis (non-lus) + conversation avec historique.
## On ne peut écrire qu'aux amis connectés ; l'historique reste consultable hors ligne.

const MAX_LEN := 300

var _with := ""
var _friend_list: VBoxContainer
var _title: Label
var _log: RichTextLabel
var _input: LineEdit
var _send_btn: Button
var _hint: Label
var _log_empty := false   # le journal n'affiche que « Aucun message pour le moment »


func _init(with_name := "") -> void:
	_with = with_name
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("modal")   # Échap la ferme (voir PauseMenu)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 580)
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)
	root.add_child(UITheme.title_label(Loc.t("Messages"), 38))

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(hb)

	# Colonne de gauche : les amis.
	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(250, 0)
	left.add_theme_stylebox_override("panel", UITheme.flat_style(Color(0.08, 0.06, 0.09, 0.85), Color("6b5a3c"), 2, 4))
	hb.add_child(left)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_friend_list = VBoxContainer.new()
	_friend_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_friend_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_friend_list)

	# Colonne de droite : la conversation.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	hb.add_child(right)
	_title = UITheme.label("", 22, UITheme.GOLD, 4)
	right.add_child(_title)
	var log_panel := PanelContainer.new()
	log_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_panel.add_theme_stylebox_override("panel", UITheme.flat_style(Color(0.06, 0.05, 0.07, 0.9), Color("6b5a3c"), 2, 4))
	right.add_child(log_panel)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.add_theme_font_size_override("normal_font_size", 16)
	_log.add_theme_font_size_override("bold_font_size", 16)
	log_panel.add_child(_log)
	_hint = UITheme.label("", 14, Color("c9b79a"), 3)
	right.add_child(_hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	right.add_child(row)
	_input = LineEdit.new()
	_input.max_length = MAX_LEN
	_input.placeholder_text = Loc.t("Votre message (Entrée pour envoyer)")
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.text_submitted.connect(func(_t): _send())
	row.add_child(_input)
	_send_btn = UITheme.button(Loc.t("Envoyer"), 140)
	_send_btn.custom_minimum_size.y = 38
	_send_btn.pressed.connect(_send)
	row.add_child(_send_btn)

	var close_btn := UITheme.button(Loc.t("Fermer"), 200)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(close)
	root.add_child(close_btn)


func _ready() -> void:
	Lobby.friends_changed.connect(_rebuild_friends)
	Lobby.connection_changed.connect(func(_on): _refresh_state())
	Lobby.dm_received.connect(_on_dm)
	Lobby.dm_history_received.connect(_on_history)
	Lobby.unread_changed.connect(_rebuild_friends)
	if _with == "" and not Lobby.friends.is_empty():
		_with = _first_friend()
	_select(_with)


func _exit_tree() -> void:
	if Lobby.dm_open_with == _with:
		Lobby.dm_open_with = ""


func close() -> void:
	queue_free()


## Ami à afficher par défaut : celui qui a des messages non lus, sinon le premier connecté.
func _first_friend() -> String:
	for f in Lobby.friends:
		if Lobby.unread.get(f.name, 0) > 0:
			return f.name
	return Lobby.friends[0].name


func _friend(friend_name: String) -> Dictionary:
	for f in Lobby.friends:
		if f.name == friend_name:
			return f
	return {}


func _select(friend_name: String) -> void:
	_with = friend_name
	Lobby.dm_open_with = friend_name
	_log.clear()
	if friend_name != "":
		Lobby.mark_read(friend_name)
		Lobby.request_dm_history(friend_name)
		_log.append_text(Loc.t("[color=#8a8580]Chargement de l'historique...[/color]\n"))
	_rebuild_friends()
	_refresh_state()
	if _input.editable:
		_input.grab_focus()


func _rebuild_friends() -> void:
	for c in _friend_list.get_children():
		c.queue_free()
	if Lobby.friends.is_empty():
		var l := UITheme.label(Loc.t("Aucun ami. Ajoutez-en depuis le menu Amis."), 15, Color("c9b79a"), 3)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		l.custom_minimum_size.x = 220
		_friend_list.add_child(l)
		return
	for f in Lobby.friends:
		var on: bool = f.status != "offline"
		var n: int = Lobby.unread.get(f.name, 0)
		var text: String = ("● " if on else "○ ") + str(f.name) + (" (%d)" % n if n > 0 else "")
		var b := UITheme.button(text, 230)
		b.custom_minimum_size.y = 36
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 16)
		var col := Color("5fd068") if on else Color("8a8580")
		if n > 0:
			col = UITheme.GOLD
		b.add_theme_color_override("font_color", col)
		if f.name == _with:
			b.add_theme_stylebox_override("normal", UITheme.flat_style(Color(0.3, 0.22, 0.1, 0.95), UITheme.GOLD, 2, 4))
		var fname: String = f.name
		b.pressed.connect(func(): _select(fname))
		_friend_list.add_child(b)
	_refresh_state()


func _refresh_state() -> void:
	var f := _friend(_with)
	var on: bool = Lobby.online and not f.is_empty() and f.status != "offline"
	if _with == "":
		_title.text = Loc.t("Choisissez un ami")
	else:
		_title.text = Loc.t("Conversation avec %s") % _with + ("" if on else Loc.t("  (hors ligne)"))
	_input.editable = on
	_send_btn.disabled = not on
	if not Lobby.online:
		_hint.text = Loc.t("Serveur hors ligne : la messagerie est indisponible.")
	elif _with != "" and not on:
		_hint.text = Loc.t("%s est hors ligne : vous pourrez écrire dès son retour (l'historique reste consultable).") % _with
	else:
		_hint.text = Loc.t("%d caractères maximum. Seuls vos amis connectés reçoivent vos messages.") % MAX_LEN


func _send() -> void:
	var text := _input.text.strip_edges()
	if text == "" or _with == "" or not _input.editable:
		return
	Lobby.send_dm(_with, text)
	_input.clear()
	_input.grab_focus()


func _on_history(with_name: String, messages: Array) -> void:
	if with_name != _with:
		return
	_log.clear()
	_log_empty = messages.is_empty()
	if messages.is_empty():
		_log.append_text(Loc.t("[color=#8a8580]Aucun message pour le moment. Dites bonjour ![/color]\n"))
	for m in messages:
		_append(m)


func _on_dm(msg: Dictionary) -> void:
	var other: String = msg.to if msg.from == Lobby.profile.get("name", "") else msg.from
	if other != _with:
		return
	if _log_empty:
		_log.clear()
		_log_empty = false
	_append(msg)


func _append(m: Dictionary) -> void:
	var mine: bool = m.get("from", "") == Lobby.profile.get("name", "")
	var col := "#f2c14e" if mine else "#9fd8ff"
	var text := str(m.get("text", "")).replace("[", "[lb]")
	_log.append_text("[color=#8a8580]%s[/color] [color=%s][b]%s[/b][/color] : %s\n"
		% [_time(int(m.get("ts", 0))), col, Loc.t("Vous") if mine else str(m.get("from", "?")), text])


static func _time(ts: int) -> String:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(ts + bias)
	var now := Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_system()) + bias)
	var hm := "%02d:%02d" % [d.hour, d.minute]
	if d.year == now.year and d.month == now.month and d.day == now.day:
		return hm
	return "%02d/%02d %s" % [d.day, d.month, hm]
