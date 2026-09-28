extends Control
## Écran multijoueur (tout passe par le serveur officiel : aucun port à ouvrir) :
##  - à gauche : liste des parties ouvertes (rejoindre) et création d'une partie ;
##  - à droite : votre partie (joueurs, lancer, quitter) et invitation d'amis connectés.

const STATE_TEXT := {
	"waiting": ["En attente d'un joueur", UITheme.GREEN],
	"full": ["Complète", Color("e8b04a")],
	"in_game": ["En cours", Color("8a8580")],
}

var _rooms_box: VBoxContainer
var _list_status: Label
var _name_edit: LineEdit
var _create_btn: Button

var _room_status: Label
var _slots: HBoxContainer
var _friends_box: VBoxContainer
var _start_btn: Button
var _leave_btn: Button
var _rooms: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	get_tree().paused = false
	Audio.play_music("menu")
	var bg := TextureRect.new()
	bg.texture = CardDB.texture("res://assets/bg/menu.png")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.modulate = Color(0.45, 0.42, 0.45)
	add_child(bg)

	var title := UITheme.title_label(Loc.t("Multijoueur"), 48)
	title.position = Vector2(0, 8)
	title.size = Vector2(1280, 60)
	add_child(title)

	_build_list_panel()
	_build_room_panel()

	var back := UITheme.button(Loc.t("Retour"), 200)
	back.position = Vector2(540, 660)
	back.pressed.connect(func():
		Net.close()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	add_child(back)

	Lobby.rooms_received.connect(_on_rooms)
	Lobby.room_changed.connect(func(_r, _role): _refresh())
	Lobby.room_closed.connect(func(_m): _refresh())
	Lobby.friends_changed.connect(_refresh)
	Lobby.connection_changed.connect(func(on):
		if on:
			Lobby.watch_rooms(true)
		_refresh())
	Net.peer_joined.connect(func(_n):
		Audio.play_sfx("end_turn")
		_refresh())
	Net.opponent_left.connect(_refresh)
	Lobby.request_friends()
	Lobby.watch_rooms(true)
	_refresh()


func _exit_tree() -> void:
	Lobby.watch_rooms(false)


# ------------------------------------------------------------------ liste des parties

func _build_list_panel() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(30, 80)
	panel.custom_minimum_size = Vector2(640, 560)
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	vb.add_child(UITheme.label(Loc.t("Parties ouvertes"), 24, UITheme.GOLD))

	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 10)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = Loc.t("Nom de votre partie (facultatif)")
	_name_edit.max_length = 32
	_name_edit.custom_minimum_size = Vector2(360, 40)
	_name_edit.text_submitted.connect(func(_t): _create())
	crow.add_child(_name_edit)
	_create_btn = UITheme.button(Loc.t("Créer une partie"), 240)
	_create_btn.pressed.connect(_create)
	crow.add_child(_create_btn)
	vb.add_child(crow)

	_list_status = UITheme.label("", 15, Color("c9b79a"), 3)
	_list_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_list_status.custom_minimum_size.x = 600
	vb.add_child(_list_status)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	_rooms_box = VBoxContainer.new()
	_rooms_box.add_theme_constant_override("separation", 6)
	_rooms_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rooms_box)


func _create() -> void:
	if not Lobby.online or not Lobby.room.is_empty():
		return
	Net.host_relay()
	Lobby.create_room(_name_edit.text.strip_edges())
	_name_edit.text = ""


func _on_rooms(rooms: Array) -> void:
	_rooms = rooms
	_fill_rooms()


func _fill_rooms() -> void:
	for c in _rooms_box.get_children():
		c.queue_free()
	var in_room := not Lobby.room.is_empty()
	var my_room: String = Lobby.room.get("id", "")
	var waiting := 0
	for r in _rooms:
		var row := PanelContainer.new()
		var mine: bool = r.id == my_room
		row.add_theme_stylebox_override("panel", UITheme.flat_style(
			Color(0.16, 0.11, 0.06, 0.9) if mine else Color(0.08, 0.06, 0.1, 0.85),
			UITheme.GOLD if mine else Color("6b5a3c"), 2, 4))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		row.add_child(hb)
		hb.add_child(AvatarBadge.new().setup(int(r.host.avatar), str(r.host.get("border", "none")), 48))
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", 0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var n := UITheme.label(str(r.name), 18, UITheme.GOLD if mine else UITheme.LIGHT_TEXT)
		n.clip_text = true
		n.custom_minimum_size.x = 280
		info.add_child(n)
		var st: Array = STATE_TEXT.get(r.state, STATE_TEXT.waiting)
		info.add_child(UITheme.label(Loc.t("Hôte : %s  ·  %d/2  ·  %s") % [r.host.name, int(r.players), Loc.t(st[0])], 14, st[1], 3))
		hb.add_child(info)
		if mine:
			hb.add_child(UITheme.label(Loc.t("Votre partie"), 15, UITheme.GOLD))
		else:
			var join := UITheme.button(Loc.t("Rejoindre"), 150)
			join.custom_minimum_size.y = 40
			join.disabled = r.state != "waiting" or in_room or not Lobby.online
			var id: String = r.id
			var host_name: String = r.host.name
			join.pressed.connect(func(): Lobby.join_listed_room(id, host_name))
			hb.add_child(join)
		_rooms_box.add_child(row)
		if r.state == "waiting":
			waiting += 1
	if not Lobby.online:
		_list_status.text = Loc.t("Connexion au serveur... %s") % Lobby.last_error
		if not Lobby.has_profile():
			_list_status.text = Loc.t("Choisissez d'abord votre pseudo : Échap > Profil.")
	elif _rooms.is_empty():
		_list_status.text = Loc.t("Aucune partie ouverte pour le moment : créez la vôtre !")
	else:
		# Singulier / pluriel en deux textes distincts (chaque langue accorde à sa façon).
		_list_status.text = (Loc.t("%d parties en attente d'un joueur. La liste se met à jour automatiquement.") if waiting > 1
			else Loc.t("%d partie en attente d'un joueur. La liste se met à jour automatiquement.")) % waiting


# ------------------------------------------------------------------ votre partie

func _build_room_panel() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(690, 80)
	panel.custom_minimum_size = Vector2(560, 560)
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	vb.add_child(UITheme.label(Loc.t("Votre partie"), 24, UITheme.GOLD))
	_room_status = UITheme.label("", 16, Color("e8d6b0"), 3)
	_room_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_room_status.custom_minimum_size.x = 520
	vb.add_child(_room_status)

	_slots = HBoxContainer.new()
	_slots.alignment = BoxContainer.ALIGNMENT_CENTER
	_slots.add_theme_constant_override("separation", 30)
	vb.add_child(_slots)

	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 12)
	vb.add_child(btns)
	_start_btn = UITheme.button(Loc.t("Lancer la partie"), 230)
	_start_btn.pressed.connect(func(): Net.start_match())
	btns.add_child(_start_btn)
	_leave_btn = UITheme.button(Loc.t("Quitter"), 170)
	_leave_btn.pressed.connect(func():
		Net.close()
		_refresh())
	btns.add_child(_leave_btn)

	vb.add_child(UITheme.label(Loc.t("Inviter un ami connecté"), 18, UITheme.GOLD))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	_friends_box = VBoxContainer.new()
	_friends_box.add_theme_constant_override("separation", 4)
	scroll.add_child(_friends_box)


func _slot(title: String, info) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.custom_minimum_size.x = 150
	# Avatar de taille fixe (100 x 100), centré et rogné : il ne dépasse plus du cadre.
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(150, 118)   # marge pour la couronne du Champion
	vb.add_child(holder)
	if info:
		var badge := AvatarBadge.new().setup(int(info.avatar), str(info.get("border", "none")), 100)
		holder.add_child(badge)
	else:
		var frame := Panel.new()
		frame.add_theme_stylebox_override("panel", UITheme.flat_style(Color("1a1220"), UITheme.GOLD, 3, 4))
		frame.custom_minimum_size = Vector2(100, 100)
		holder.add_child(frame)
	var l := UITheme.label(title, 14, Color("c9b79a"), 3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(l)
	var n := UITheme.label(Loc.t("En attente...") if info == null else info.name, 18, UITheme.GOLD if info else Color("8a8580"))
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(n)
	if info:
		var player_title := Cosmetics.title_name(info.get("title", ""))
		if player_title != "":
			var t := UITheme.label(player_title, 13, Color("c9a0ff"), 2)
			t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vb.add_child(t)
	return vb


func _refresh() -> void:
	for c in _slots.get_children():
		c.queue_free()
	for c in _friends_box.get_children():
		c.queue_free()
	var in_room := not Lobby.room.is_empty()
	var is_host := in_room and Lobby.role == "host"
	_create_btn.disabled = not Lobby.online or in_room
	_name_edit.editable = Lobby.online and not in_room
	_leave_btn.visible = in_room
	_start_btn.visible = is_host
	_start_btn.disabled = not (is_host and Lobby.room.get("guest") != null and Net.remote_peer_id != 0)
	_fill_rooms()
	if not Lobby.online:
		_room_status.text = Loc.t("Serveur hors ligne pour le moment. %s") % Lobby.last_error
		return
	if not in_room:
		_room_status.text = Loc.t("Créez une partie (elle apparaît dans la liste pour tous les joueurs) ou rejoignez-en une à gauche.")
	elif is_host:
		if Lobby.room.get("guest") == null:
			_room_status.text = Loc.t("« %s » est ouverte : en attente d'un adversaire. Vous pouvez aussi inviter un ami.") % Lobby.room.get("name", "")
		else:
			_room_status.text = Loc.t("%s a rejoint votre partie : lancez-la quand vous êtes prêts !") % Lobby.room.guest.name
	else:
		_room_status.text = Loc.t("Vous avez rejoint la partie de %s. En attente du lancement...") % Net.remote_name
	if in_room:
		_slots.add_child(_slot(Loc.t("Hôte"), Lobby.room.get("host")))
		_slots.add_child(UITheme.title_label(Loc.t("VS"), 40))
		_slots.add_child(_slot(Loc.t("Adversaire"), Lobby.room.get("guest")))
	var any := false
	for f in Lobby.friends:
		if f.status == "offline":
			continue
		any = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(AvatarBadge.new().setup(int(f.avatar), str(f.get("border", "none")), 36))
		var l := UITheme.label(f.name, 17)
		l.custom_minimum_size.x = 190
		row.add_child(l)
		var st: Array = FriendsPanel.STATUS_TEXT.get(f.status, FriendsPanel.STATUS_TEXT.offline)
		var s := UITheme.label(Loc.t(st[0]), 15, st[1], 3)
		s.custom_minimum_size.x = 130
		row.add_child(s)
		if not in_room or is_host:
			var inv := UITheme.button(Loc.t("Inviter"), 110)
			inv.custom_minimum_size.y = 32
			inv.add_theme_font_size_override("font_size", 15)
			inv.disabled = f.status == "in_game"
			inv.pressed.connect(func(): Lobby.invite_friend(f.name))
			row.add_child(inv)
		_friends_box.add_child(row)
	if not any:
		_friends_box.add_child(UITheme.label(Loc.t("Aucun ami connecté (menu principal > Amis)."), 15, Color("c9b79a")))
