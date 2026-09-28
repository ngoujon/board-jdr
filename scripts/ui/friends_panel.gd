class_name FriendsPanel
extends Control
## Liste d'amis : ajout par pseudo, demandes reçues, statut en ligne, invitation à une partie.

const STATUS_TEXT := {
	"online": ["En ligne", Color("5fd068")],
	"lobby": ["Dans un salon", Color("f2c14e")],
	"in_game": ["En partie", Color("e8883a")],
	"offline": ["Hors ligne", Color("8a8580")],
}

var _list: VBoxContainer
var _add_edit: LineEdit
var _status: Label
var _msg_btn: Button


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("modal")   # Échap la ferme (voir PauseMenu)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 620)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	vb.add_child(UITheme.title_label(Loc.t("Amis"), 38))
	var msg_btn := UITheme.button(Loc.t("Messages"), 220)
	msg_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	msg_btn.pressed.connect(func():
		queue_free()
		Lobby.open_messages())
	vb.add_child(msg_btn)
	_msg_btn = msg_btn

	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 8)
	vb.add_child(add_row)
	_add_edit = LineEdit.new()
	_add_edit.placeholder_text = Loc.t("Pseudo du joueur à ajouter")
	_add_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_edit.text_submitted.connect(func(_t): _add())
	add_row.add_child(_add_edit)
	var add_btn := UITheme.button(Loc.t("Ajouter"), 140)
	add_btn.custom_minimum_size.y = 38
	add_btn.pressed.connect(_add)
	add_row.add_child(add_btn)

	_status = UITheme.label("", 15, Color("c9b79a"), 3)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(_status)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)

	var close := UITheme.button(Loc.t("Fermer"), 200)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(queue_free)
	vb.add_child(close)


func _ready() -> void:
	Lobby.friends_changed.connect(_rebuild)
	Lobby.connection_changed.connect(func(_on): _rebuild())
	Lobby.unread_changed.connect(_rebuild)
	Lobby.request_friends()
	_rebuild()


func _add() -> void:
	if _add_edit.text.strip_edges() == "":
		return
	Lobby.add_friend(_add_edit.text)
	_add_edit.clear()


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	var total := Lobby.total_unread()
	_msg_btn.text = (Loc.t("Messages (%d non lus)") if total > 1 else Loc.t("Messages (%d non lu)")) % total if total > 0 else Loc.t("Messages")
	_msg_btn.add_theme_color_override("font_color", UITheme.GOLD if total > 0 else UITheme.LIGHT_TEXT)
	if not Lobby.online:
		_status.text = Loc.t("Serveur communautaire hors ligne. Définissez votre pseudo et l'adresse du serveur dans Options > Profil.")
		return
	_status.text = Loc.t("Connecté en tant que %s. Invitez un ami en ligne pour créer une partie.") % Lobby.profile.get("name", "")
	if not Lobby.incoming.is_empty():
		_list.add_child(UITheme.label(Loc.t("Demandes reçues"), 17, UITheme.GOLD))
		for n in Lobby.incoming:
			var row := _row(n, 0, "")
			var yes := _small_btn(Loc.t("Accepter"))
			yes.pressed.connect(func(): Lobby.respond_friend(n, true))
			var no := _small_btn(Loc.t("Refuser"))
			no.pressed.connect(func(): Lobby.respond_friend(n, false))
			row.add_child(yes)
			row.add_child(no)
	_list.add_child(UITheme.label(Loc.t("Mes amis (%d)") % Lobby.friends.size(), 17, UITheme.GOLD))
	if Lobby.friends.is_empty():
		_list.add_child(UITheme.label(Loc.t("Aucun ami pour le moment : ajoutez-en avec leur pseudo !"), 15, Color("c9b79a")))
	for f in Lobby.friends:
		var row := _row(f.name, int(f.avatar), f.status, f)
		var fname: String = f.name
		var unread: int = Lobby.unread.get(fname, 0)
		var write := _small_btn(Loc.t("Écrire (%d)") % unread if unread > 0 else Loc.t("Écrire"))
		write.pressed.connect(func():
			queue_free()
			Lobby.open_messages(fname))
		row.add_child(write)
		if f.status == "online" or f.status == "lobby":
			var inv := _small_btn(Loc.t("Inviter"))
			inv.pressed.connect(func():
				queue_free()
				Lobby.invite_friend(f.name))
			row.add_child(inv)
		var rm := _small_btn(Loc.t("Retirer"))
		rm.pressed.connect(func(): Lobby.remove_friend(f.name))
		row.add_child(rm)
	if not Lobby.outgoing.is_empty():
		_list.add_child(UITheme.label(Loc.t("Demandes envoyées : %s") % ", ".join(PackedStringArray(Lobby.outgoing)), 14, Color("c9b79a")))


func _row(player_name: String, avatar_id: int, status: String, look := {}) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	if avatar_id > 0:
		row.add_child(AvatarBadge.new().setup(avatar_id, str(look.get("border", "none")), 44))
	else:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(44, 44)
		row.add_child(gap)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", -2)
	names.custom_minimum_size.x = 180
	names.add_child(UITheme.label(player_name, 18))
	var title := Cosmetics.title_name(look.get("title", ""))
	if title != "":
		names.add_child(UITheme.label(title, 12, Color("c9a0ff"), 2))
	row.add_child(names)
	if status != "":
		var st: Array = STATUS_TEXT.get(status, STATUS_TEXT.offline)
		var s := UITheme.label("● " + Loc.t(st[0]), 15, st[1], 3)
		s.custom_minimum_size.x = 140
		row.add_child(s)
	_list.add_child(row)
	return row


func _small_btn(text: String) -> Button:
	var b := UITheme.button(text, 100)
	b.custom_minimum_size.y = 34
	b.add_theme_font_size_override("font_size", 15)
	return b
