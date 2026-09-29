extends CanvasLayer
## Client du serveur communautaire (server/lobby_server.py) : profil (pseudo unique + avatar),
## classement, amis, présence, invitations, salons et relais des parties en ligne.
## Affiche aussi les notifications et les invitations reçues (où que soit le joueur).

signal connection_changed(online: bool)
signal profile_changed
signal friends_changed
signal leaderboard_received(rows: Array)
signal room_changed(room: Dictionary, role: String)
signal room_closed(msg: String)
signal peer_left
signal relay_received(kind: String, args: Array)
signal server_error(code: String, msg: String)
signal history_received(player_name: String, total: int, rows: Array)
signal rooms_received(rooms: Array)
signal dm_received(msg: Dictionary)                           # message privé reçu ou envoyé
signal dm_history_received(with_name: String, messages: Array)
signal unread_changed
signal reward_received(data: Dictionary)   # PO + XP de passe gagnés à la fin d'une partie
signal gold_changed
signal global_stats_received(data: Dictionary)
signal players_found(query: String, rows: Array)
signal player_profile_received(data: Dictionary)
signal sugg_list_received(topics: Array)                    # forum des suggestions : liste des sujets
signal sugg_thread_received(topic: Dictionary, created: bool)   # un sujet et ses réponses (created : on vient de le créer)
signal pass_claimed(data: Dictionary)   # récompenses du passe récupérées : {levels, po, gold}
signal cosmetics_unlocked(items: Array)   # nouveaux titres / avatars / contours / dos / plateaux   # liste publique des parties (écran Multijoueur)

const PROTOCOL_VERSION := 1
const MULTIPLAYER_SCENE := "res://scenes/multiplayer.tscn"
const RECONNECT_DELAY := 6.0
const RESTART_RECONNECT := 1.5   # le serveur redémarre pour une mise à jour : reconnexion rapide et silencieuse
var _server_restarting := false
var _pending_reports: Array[Dictionary] = []   # résultats de parties à envoyer dès la reconnexion

var online := false
var profile := {}
var friends: Array = []
var incoming: Array = []
var outgoing: Array = []
var room := {}
var role := ""
var last_error := ""

var _tcp := StreamPeerTCP.new()
var _tls: StreamPeerTLS = null   # connexion chiffrée au serveur officiel (le jeton de compte ne circule pas en clair)
var _use_tls := false
var _buffer := PackedByteArray()
var _connecting := false
var _reconnect_in := -1.0
var _pending_invite := ""
var _toasts: VBoxContainer
## Version publiée pendant la session : proposée à la fin de la partie en cours.
const TICKET_TIMEOUT_MS := 4000
var _ticket := {}
var _ticket_pending := false
var last_reward := {}     # dernière récompense de fin de partie (affichée sur l'écran de fin)
var unread := {}          # pseudo de l'ami -> messages non lus
var dm_open_with := ""    # conversation affichée dans la fenêtre Messages
var _messages_panel: Control
var pending_update := ""
var _update_dialog: Control
var fx: RewardFx               # animations de récompense (pièces d'or, personnalisations)
var _claim_from := Vector2(640, 360)
var _claim_to := Vector2(1190, 50)


func _ready() -> void:
	layer = 95
	process_mode = Node.PROCESS_MODE_ALWAYS
	_toasts = VBoxContainer.new()
	_toasts.position = Vector2(860, 108)
	_toasts.custom_minimum_size = Vector2(400, 0)
	_toasts.add_theme_constant_override("separation", 8)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toasts)
	fx = RewardFx.new()
	add_child(fx)
	if Settings.player_name != "" and not Updater.restarting and not Settings.verifier_mode:
		connect_to_server()


func has_profile() -> bool:
	return Settings.player_name.strip_edges().length() >= 3


func status_text() -> String:
	if online:
		return Loc.t("En ligne")
	if _connecting:
		return Loc.t("Connexion...")
	return Loc.t("Hors ligne")


# ------------------------------------------------------------------ connexion

func connect_to_server() -> void:
	disconnect_from_server(false)
	if not has_profile():
		last_error = Loc.t("Choisissez d'abord un pseudo (Options > Profil).")
		return
	var addr := Settings.server_address
	if not addr.is_valid_ip_address():
		addr = IP.resolve_hostname(addr, IP.TYPE_IPV4)
	if addr == "":
		last_error = Loc.t("Adresse du serveur introuvable.")
		connection_changed.emit(false)
		return
	_tcp = StreamPeerTCP.new()
	_tls = null
	_use_tls = Settings.uses_tls()
	if _tcp.connect_to_host(addr, Settings.OFFICIAL_TLS_PORT if _use_tls else Settings.server_port) != OK:
		last_error = Loc.t("Connexion impossible.")
		connection_changed.emit(false)
		return
	_connecting = true
	_buffer.clear()
	connection_changed.emit(false)


func disconnect_from_server(emit := true) -> void:
	if _tls:
		_tls.disconnect_from_stream()
		_tls = null
	if _tcp.get_status() != StreamPeerTCP.STATUS_NONE:
		_tcp.disconnect_from_host()
	var was := online
	online = false
	_connecting = false
	room = {}
	role = ""
	if emit and was:
		connection_changed.emit(false)


func _process(delta: float) -> void:
	if _reconnect_in > 0.0:
		_reconnect_in -= delta
		if _reconnect_in <= 0.0:
			connect_to_server()
	if _tcp.get_status() == StreamPeerTCP.STATUS_NONE and not _connecting:
		return
	_tcp.poll()
	var status := _tcp.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTED and _use_tls:
		if _tls == null:
			_tcp.set_no_delay(true)
			_tls = StreamPeerTLS.new()
			if _tls.connect_to_stream(_tcp, Settings.OFFICIAL_TLS_NAME, TLSOptions.client()) != OK:
				_tls = null
				status = StreamPeerTCP.STATUS_ERROR
		if _tls:
			_tls.poll()
			match _tls.get_status():
				StreamPeerTLS.STATUS_HANDSHAKING:
					return
				StreamPeerTLS.STATUS_CONNECTED:
					pass
				_:
					# Certificat invalide (interception ?) ou poignée de main échouée : pas de connexion.
					push_warning("[Lobby] connexion TLS refusée (statut %d)" % _tls.get_status())
					_tls = null
					_tcp.disconnect_from_host()
					status = StreamPeerTCP.STATUS_ERROR
	match status:
		StreamPeerTCP.STATUS_CONNECTED:
			if _connecting:
				_connecting = false
				_tcp.set_no_delay(true)
				send({"t": "hello", "version": PROTOCOL_VERSION, "game_version": Updater.current_version(), "lang": Settings.language,
					"token": Settings.account_token,
					"name": Settings.player_name, "avatar": Settings.avatar})
			_read()
		StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE:
			var was := online or _connecting
			online = false
			_connecting = false
			_tcp = StreamPeerTCP.new()
			if was:
				if _server_restarting:
					# Redémarrage annoncé (mise à jour du serveur) : pas de message d'erreur, on revient tout de suite.
					_reconnect_in = RESTART_RECONNECT
					connection_changed.emit(false)
					return
				last_error = Loc.t("Serveur injoignable (%s:%d).") % [Settings.server_address, Settings.server_port]
				connection_changed.emit(false)
				if not room.is_empty():
					room = {}
					room_closed.emit(Loc.t("Connexion au serveur perdue."))
				_reconnect_in = RECONNECT_DELAY
			elif _server_restarting:
				_reconnect_in = RESTART_RECONNECT   # le serveur n'est pas encore relancé : nouvel essai rapide


func _read() -> void:
	var peer: StreamPeer = _tls if _tls else _tcp
	var n := peer.get_available_bytes()
	if n <= 0:
		return
	var res := peer.get_data(n)
	if res[0] != OK:
		return
	_buffer.append_array(res[1])
	while true:
		var idx := _buffer.find(10)   # '\n'
		if idx == -1:
			break
		var line := _buffer.slice(0, idx).get_string_from_utf8()
		_buffer = _buffer.slice(idx + 1)
		var msg = JSON.parse_string(line)
		if msg is Dictionary:
			_handle(msg)


func send(msg: Dictionary) -> void:
	if _tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var data := (JSON.stringify(msg) + "\n").to_utf8_buffer()
	if not _use_tls:
		_tcp.put_data(data)
	elif _tls and _tls.get_status() == StreamPeerTLS.STATUS_CONNECTED:
		_tls.put_data(data)


# ------------------------------------------------------------------ messages du serveur

func _handle(msg: Dictionary) -> void:
	match msg.get("t", ""):
		"welcome":
			online = true
			last_error = ""
			_server_restarting = false
			Settings.account_token = msg.token
			profile = msg.profile
			_cache_cosmetics()
			Settings.save_settings()
			connection_changed.emit(true)
			profile_changed.emit()
			_update_status_from_scene()
			print("[Lobby] connecté en tant que ", profile.get("name"))
			for rep in _pending_reports:
				send(rep)   # partie terminée pendant une coupure : le ticket est toujours valable sur le serveur
			_pending_reports.clear()
			if Settings.auto_host != "":
				add_friend(Settings.auto_host)
			if Settings.auto_create:
				_auto_create_step()
			if Settings.auto_join_list:
				watch_rooms(true)
			if Settings.watch_replay > 0:
				request_replay(Settings.watch_replay)
			if Settings.auto_ai >= 0:
				Settings.set_difficulty(Settings.auto_ai)
				Settings.auto_ai = -1
				Net.close()
				get_tree().change_scene_to_file("res://scenes/battle.tscn")
		"sugg_list":
			sugg_list_received.emit(msg.get("topics", []))
		"sugg_thread":
			sugg_thread_received.emit(msg.get("topic", {}), bool(msg.get("created", false)))
		"profile":
			profile = msg.profile
			_cache_cosmetics()
			Settings.save_settings()
			profile_changed.emit()
		"unlocked":
			_on_unlocked(msg.get("items", []))
		"match_ticket":
			_ticket = {"id": str(msg.get("id", "")), "seed": int(msg.get("seed", 0)), "first": int(msg.get("first", 0))}
			_ticket_pending = false
		"match_ticket_refused":
			_ticket_pending = false
		"server_restart":
			_server_restarting = true
			print("[Lobby] le serveur redémarre (mise à jour) : reconnexion automatique")
		"match_rejected":
			if Settings.autoplay:
				print("[Lobby] PARTIE REFUSÉE : ", msg.get("msg", ""))
			toast(str(msg.get("msg", Loc.t("Partie non validée par le serveur."))), UITheme.RED, 6.0)
		"reward":
			profile["gold"] = int(msg.get("gold", profile.get("gold", 0)))
			last_reward = msg
			gold_changed.emit()
			reward_received.emit(msg)
			if int(msg.get("pass_po", 0)) > 0 or msg.get("level_up", false):
				toast(Loc.t("Passe de combat : niveau %d atteint !%s") % [int(msg.level),
					(Loc.t(" +%d PO") % int(msg.pass_po)) if int(msg.get("pass_po", 0)) > 0 else ""], UITheme.GOLD, 6.0)
			if msg.get("level_up", false) and int(msg.get("claimable", 0)) > 0:
				toast(Loc.t("Récompense à récupérer dans le passe de combat !"), UITheme.GOLD, 6.0)
		"pass_claimed":
			profile["gold"] = int(msg.get("gold", profile.get("gold", 0)))
			gold_changed.emit()
			if int(msg.get("po", 0)) > 0:
				fx.coins(int(msg.po), _claim_from, _claim_to)
			pass_claimed.emit(msg)
		"bought":
			profile["gold"] = int(msg.get("gold", 0))
			gold_changed.emit()
			Audio.play_sfx("end_turn", 0.0)
			toast(Loc.t("Achat effectué : « %s »") % Cosmetics.item_name(str(msg.kind), msg.id), UITheme.GOLD)
		"new_version":
			_on_new_version(str(msg.get("version", "")))
		"error":
			last_error = msg.get("msg", Loc.t("Erreur"))
			var code: String = msg.get("code", "")
			server_error.emit(code, last_error)
			toast(last_error, UITheme.RED)
			if code == "outdated":
				Updater.mark_outdated(str(msg.get("required", "")))
				_show_update_prompt()
			if code == "replaced":
				# Même compte ouvert dans une autre fenêtre du jeu : cette session est fermée par le serveur.
				last_error = Loc.t("Vous êtes connecté depuis une autre fenêtre du jeu.")
				disconnect_from_server()
				_reconnect_in = -1.0
			elif code == "not_logged":
				connect_to_server()   # session perdue côté serveur : on se ré-identifie
			elif code in ["name_taken", "name_invalid", "version", "outdated"] and not online:
				disconnect_from_server()
				_reconnect_in = -1.0
		"info":
			toast(msg.get("msg", ""))
		"friends":
			friends = msg.get("friends", [])
			incoming = msg.get("incoming", [])
			outgoing = msg.get("outgoing", [])
			friends_changed.emit()
			if Settings.auto_accept:
				for n in incoming:
					respond_friend(n, true)
			_auto_host_step()
		"leaderboard":
			leaderboard_received.emit(msg.get("rows", []))
		"rooms":
			rooms_received.emit(msg.get("rooms", []))
			_auto_join_step(msg.get("rooms", []))
		"history":
			history_received.emit(str(msg.get("name", "")), int(msg.get("total", 0)), msg.get("rows", []))
		"dm":
			_on_dm(msg)
		"global_stats":
			global_stats_received.emit(msg)
		"players_found":
			players_found.emit(str(msg.get("q", "")), msg.get("rows", []))
		"player_profile":
			player_profile_received.emit(msg)
		"replay":
			start_replay(msg)
		"dm_history":
			dm_history_received.emit(str(msg.get("with", "")), msg.get("messages", []))
		"invite":
			_show_invite(msg.get("from", "?"), int(msg.get("avatar", 1)), msg.get("room", ""))
		"room":
			room = msg.room
			role = msg.role
			room_changed.emit(room, role)
			if role == "host" and _pending_invite != "":
				send({"t": "invite", "name": _pending_invite})
				_pending_invite = ""
		"room_closed":
			room = {}
			role = ""
			room_closed.emit(msg.get("msg", ""))
			toast(msg.get("msg", Loc.t("Partie fermée.")), UITheme.RED)
		"peer_left":
			peer_left.emit()
		"relay":
			relay_received.emit(str(msg.get("kind", "")), msg.get("args", []))


# ------------------------------------------------------------------ actions

func update_profile() -> void:
	if online:
		send({"t": "set_profile", "name": Settings.player_name, "avatar": Settings.avatar})
	else:
		connect_to_server()


func set_status(status: String) -> void:
	send({"t": "status", "status": status})


func _update_status_from_scene() -> void:
	var scene := get_tree().current_scene
	if scene and scene.is_in_group("battle"):
		set_status("in_game")
	elif not room.is_empty():
		set_status("lobby")
	else:
		set_status("online")


func request_leaderboard() -> void:
	send({"t": "leaderboard"})


func request_friends() -> void:
	send({"t": "get_friends"})


func add_friend(friend_name: String) -> void:
	send({"t": "friend_request", "name": friend_name.strip_edges()})


func respond_friend(friend_name: String, accept: bool) -> void:
	send({"t": "friend_respond", "name": friend_name, "accept": accept})


func remove_friend(friend_name: String) -> void:
	send({"t": "friend_remove", "name": friend_name})


func create_room(room_name := "") -> void:
	send({"t": "create_room", "name": room_name})


## Abonnement à la liste des parties ouvertes (mise à jour en direct par le serveur).
func watch_rooms(on: bool) -> void:
	send({"t": "watch_rooms", "on": on})


## Rejoint une partie de la liste : la partie passe par le relais du serveur (aucun port à ouvrir).
func join_listed_room(room_id: String, host_name: String) -> void:
	Net.join_relay(host_name)
	join_room(room_id)


func leave_room() -> void:
	if not room.is_empty():
		send({"t": "leave_room"})
	room = {}
	role = ""


func join_room(room_id: String) -> void:
	send({"t": "join_room", "room": room_id})


## Invite un ami : crée le salon si besoin puis ouvre l'écran multijoueur.
func invite_friend(friend_name: String) -> void:
	if room.is_empty() or role != "host":
		_pending_invite = friend_name
		Net.host_relay()
		create_room()
	else:
		send({"t": "invite", "name": friend_name})
	if get_tree().current_scene == null or get_tree().current_scene.scene_file_path != MULTIPLAYER_SCENE:
		get_tree().change_scene_to_file(MULTIPLAYER_SCENE)


func relay(kind: String, args: Array) -> void:
	send({"t": "relay", "kind": kind, "args": args})


## details : {turns, duration (s), reason ("normal" | "concede" | "disconnect"), difficulty}
func report_ai_result(won: bool, details := {}) -> void:
	if won:
		Settings.local_ai_wins += 1
	else:
		Settings.local_ai_losses += 1
	Settings.save_settings()
	if str(details.get("ticket", "")) == "":
		return   # partie non enregistrée par le serveur (hors ligne) : rien à valider
	var msg := {"t": "report_ai", "won": won, "game_version": Updater.current_version()}
	msg.merge(details)
	if online:
		send(msg)
	else:
		_pending_reports.append(msg)   # envoyé à la reconnexion (le serveur garde le ticket 4 h)


## Demande au serveur d'enregistrer une partie : il fournit la graine et le premier joueur, puis rejouera
## la partie pour valider le résultat. Renvoie {id, seed, first} ou {} (hors ligne, pas de réponse).
func request_ticket(mode: String, difficulty := 0) -> Dictionary:
	if not online:
		return {}
	_ticket = {}
	_ticket_pending = true
	send({"t": "match_start", "mode": mode, "difficulty": difficulty})
	var deadline := Time.get_ticks_msec() + TICKET_TIMEOUT_MS
	while _ticket_pending and online and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_ticket_pending = false
	return _ticket


# ------------------------------------------------------------------ personnalisation

## Garde une copie locale du profil de personnalisation (affichage hors ligne).
func _cache_cosmetics() -> void:
	Settings.avatar = int(profile.get("avatar", Settings.avatar))
	var c := {}
	for k in ["equipped", "unlocked", "stats", "border", "title", "champion", "gold", "season"]:
		if profile.has(k):
			c[k] = profile[k]
	Settings.cosmetics_cache = c


## Personnalisation du joueur local : avatar, titre, contour, dos de cartes, plateau.
func my_look() -> Dictionary:
	var c: Dictionary = Settings.cosmetics_cache
	var eq: Dictionary = c.get("equipped", {})
	return {"avatar": Settings.avatar, "title": eq.get("title", "novice"), "border": c.get("border", eq.get("border", "none")),
		"card_back": eq.get("card_back", "default"), "board": eq.get("board", "default"),
		"champion": c.get("champion", false)}


func gold() -> int:
	return int(profile.get("gold", Settings.cosmetics_cache.get("gold", 0)))


func season() -> Dictionary:
	var s: Dictionary = profile.get("season", Settings.cosmetics_cache.get("season", {}))
	if s.is_empty() or int(s.get("end", 0)) <= int(Time.get_unix_time_from_system()):
		return Cosmetics.local_season()   # hors ligne, ou saison en cache terminée
	return s


## Récupère la récompense d'un niveau du passe (ou toutes : level = "all"). from / to : trajet des pièces d'or.
func claim_pass(level, from := Vector2(640, 360), to := Vector2(1190, 50)) -> void:
	_claim_from = from
	_claim_to = to
	send({"t": "claim_pass", "level": level})


## Récompenses du passe atteintes mais pas encore récupérées.
func claimable_levels() -> Array:
	return season().get("claimable", [])


func buy(kind: String, id) -> void:
	if not online:
		toast(Loc.t("Connectez-vous au serveur pour acheter."), UITheme.RED)
		return
	send({"t": "shop_buy", "kind": kind, "id": id})


func is_unlocked(kind: String, id) -> bool:
	var unlocked: Array = Settings.cosmetics_cache.get("unlocked", {}).get(kind, [])
	for u in unlocked:
		if str(u) == str(id):
			return true
	return Cosmetics.item(kind, id).get("rule") == null


func equip(kind: String, id) -> void:
	if not online:
		toast(Loc.t("Connectez-vous au serveur pour changer votre personnalisation."), UITheme.RED)
		return
	send({"t": "equip", "kind": kind, "id": id})


const KIND_SINGULAR := {"title": "Titre", "avatar": "Avatar", "border": "Contour", "card_back": "Dos de cartes", "board": "Plateau"}


func _on_unlocked(items: Array) -> void:
	if items.is_empty():
		return
	# Révélation animée (après la partie si une partie est en cours).
	fx.reveal(items)
	cosmetics_unlocked.emit(items)


func report_pvp_result(winner: String, details := {}) -> void:
	var msg := {"t": "report_pvp", "winner": winner, "game_version": Updater.current_version()}
	msg.merge(details)
	send(msg)


## Historique des parties d'un joueur ("" = soi-même), conservé sans limite sur le serveur.
func request_history(player_name := "", limit := 100) -> void:
	send({"t": "history", "name": player_name, "limit": limit})


## Mode test (--auto-host=Ami) : invite l'ami dès qu'il est en ligne.
func _auto_host_step() -> void:
	if Settings.auto_host == "" or not room.is_empty() or _pending_invite != "":
		return
	var scene := get_tree().current_scene
	if scene and scene.is_in_group("battle"):
		return
	for f in friends:
		if f.name == Settings.auto_host and f.status == "online":
			print("[Lobby] invitation automatique de ", f.name)
			invite_friend(f.name)
			Net.peer_joined.connect(func(_n):
				print("[Lobby] ", _n, " a rejoint : lancement de la partie")
				get_tree().create_timer(1.0).timeout.connect(Net.start_match), CONNECT_ONE_SHOT)
			return


## Mode test (--auto-create) : crée une partie publique et la lance dès qu'un joueur la rejoint.
func _auto_create_step() -> void:
	print("[Lobby] création automatique d'une partie publique")
	Net.host_relay()
	create_room("Partie test de %s" % Settings.player_name)
	Net.peer_joined.connect(func(_n):
		print("[Lobby] ", _n, " a rejoint depuis la liste : lancement de la partie")
		get_tree().create_timer(1.0).timeout.connect(Net.start_match), CONNECT_ONE_SHOT)


## Mode test (--auto-join-list) : rejoint la première partie en attente de la liste publique.
func _auto_join_step(rooms: Array) -> void:
	if not Settings.auto_join_list or not room.is_empty() or Net.is_online():
		return
	for r in rooms:
		if r.get("state", "") == "waiting" and r.host.name != profile.get("name", ""):
			print("[Lobby] rejoint depuis la liste : ", r.name)
			join_listed_room(r.id, r.host.name)
			return


# ------------------------------------------------------------------ notifications

## Le serveur annonce une nouvelle version. En pleine partie, on ne dérange pas le joueur :
## la scène de combat affiche la proposition à la fin de la partie (voir battle.gd).
func _on_new_version(version: String) -> void:
	if version == "" or Updater.compare(version, Updater.current_version()) <= 0:
		return
	pending_update = version
	Updater.mark_outdated(version)
	var scene := get_tree().current_scene
	if scene and scene.has_method("is_game_running") and scene.is_game_running():
		print("[Lobby] nouvelle version %s : proposée à la fin de la partie" % version)
		toast(Loc.t("La version %s est disponible : elle vous sera proposée à la fin de la partie.") % version, UITheme.GOLD, 6.0)
	else:
		show_update_dialog()


## Fenêtre « Nouvelle version disponible » : mettre à jour maintenant ou plus tard.
func show_update_dialog() -> void:
	if pending_update == "" or is_instance_valid(_update_dialog):
		return
	var scene := get_tree().current_scene
	if scene and scene.scene_file_path == "res://scenes/boot.tscn":
		return
	print("[Lobby] proposition de mise à jour vers ", pending_update)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.flat_style(Color(0.1, 0.07, 0.09, 0.97), UITheme.GOLD, 3, 6))
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	margin.add_child(box)
	var title := UITheme.title_label(Loc.t("Nouvelle version %s") % pending_update, 34)
	box.add_child(title)
	var text := UITheme.label(Loc.t("Une mise à jour du jeu vient d'être publiée.\nElle est nécessaire pour continuer à jouer en ligne : le jeu la télécharge puis redémarre tout seul."), 18, UITheme.LIGHT_TEXT)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.custom_minimum_size = Vector2(520, 0)
	box.add_child(text)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	box.add_child(buttons)
	var now := UITheme.button(Loc.t("Mettre à jour maintenant"), 280)
	now.pressed.connect(func():
		root.queue_free()
		go_to_update())
	buttons.add_child(now)
	var later := UITheme.button(Loc.t("Plus tard"), 160)
	later.pressed.connect(root.queue_free)
	buttons.add_child(later)
	root.add_to_group("modal")   # Échap = « Plus tard »
	add_child(root)
	_update_dialog = root
	Audio.play_sfx("end_turn", 0.0)
	root.modulate.a = 0.0
	root.create_tween().tween_property(root, "modulate:a", 1.0, 0.25)


## Quitte la partie / le menu et lance l'écran de mise à jour (téléchargement puis redémarrage).
func go_to_update() -> void:
	PauseMenu.close()
	Net.close()
	get_tree().change_scene_to_file("res://scenes/boot.tscn")


## Propose d'aller à l'écran de mise à jour (le serveur a refusé notre version).
func _show_update_prompt() -> void:
	if get_tree().current_scene and get_tree().current_scene.scene_file_path == "res://scenes/boot.tscn":
		return
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(400, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var l := UITheme.label(Loc.t("Mise à jour %s disponible : elle est requise pour jouer en ligne.") % Updater.latest.get("version", ""), 17, UITheme.GOLD)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(370, 0)
	box.add_child(l)
	var b := UITheme.button(Loc.t("Mettre à jour"), 200)
	b.pressed.connect(func():
		panel.queue_free()
		go_to_update())
	box.add_child(b)
	_toasts.add_child(panel)
	get_tree().create_timer(30.0).timeout.connect(panel.queue_free)


# ------------------------------------------------------------------ statistiques, profils, replays

func request_global_stats(mode := "all") -> void:
	send({"t": "global_stats", "mode": mode})


func search_players(query: String) -> void:
	send({"t": "search_players", "q": query.strip_edges()})


func request_player_profile(player_name := "") -> void:
	send({"t": "player_profile", "name": player_name})


func request_replay(match_id: int) -> void:
	send({"t": "replay", "id": match_id})


## Lance la lecture d'un replay : la partie est rejouée à l'identique (moteur déterministe).
func start_replay(data: Dictionary) -> void:
	if not data.has("actions"):
		return
	if is_instance_valid(_messages_panel):
		_messages_panel.queue_free()
	if PauseMenu.is_open():
		PauseMenu.close()
	Net.close()
	Net.mode = "replay"
	Net.replay = data
	# Vu du côté du joueur qui regarde s'il a participé à la partie.
	var names: Array = data.get("names", [])
	var mine := names.find(profile.get("name", Settings.player_name))
	Net.replay["view"] = mine if mine != -1 else int(data.get("me", 0))
	get_tree().change_scene_to_file("res://scenes/battle.tscn")


# ------------------------------------------------------------------ messagerie

func send_dm(to_name: String, text: String) -> void:
	send({"t": "dm", "to": to_name, "text": text.strip_edges().left(300)})


# ------------------------------------------------------------------ forum des suggestions

## Nouveau sujet : cartes visées (5 au plus), "buff" | "nerf" | "bug" | "autre", texte libre.
func send_suggestion(cards: Array, kind: String, text: String) -> void:
	send({"t": "suggest", "cards": cards.slice(0, 5), "kind": kind, "text": text.strip_edges().left(600)})


## Liste des sujets : filtre par type ("" = tous), recherche (texte, auteur, réponses et cartes `card_ids`),
## `open_only` : sans les sujets clôturés.
func request_sugg_list(kind := "", query := "", card_ids: Array = [], open_only := false) -> void:
	send({"t": "sugg_list", "kind": kind, "q": query.strip_edges().left(60), "cards": card_ids.slice(0, 40), "open_only": open_only})


## Clôture d'un sujet (tout joueur) / réouverture (auteur du sujet ou modérateur).
func lock_sugg(id: int) -> void:
	send({"t": "sugg_lock", "id": id})


func unlock_sugg(id: int) -> void:
	send({"t": "sugg_unlock", "id": id})


func request_sugg_thread(id: int) -> void:
	send({"t": "sugg_thread", "id": id})


func reply_sugg(id: int, text: String) -> void:
	send({"t": "sugg_reply", "id": id, "text": text.strip_edges().left(400)})


func close_sugg() -> void:
	send({"t": "sugg_close"})


func request_dm_history(with_name: String) -> void:
	send({"t": "dm_history", "with": with_name})


func mark_read(with_name: String) -> void:
	if unread.erase(with_name):
		unread_changed.emit()


func total_unread() -> int:
	var n := 0
	for k in unread:
		n += int(unread[k])
	return n


## Ouvre la fenêtre Messages (au-dessus de tout, y compris en partie), sur la conversation `with_name`.
func open_messages(with_name := "") -> void:
	if is_instance_valid(_messages_panel):
		_messages_panel.queue_free()
	_messages_panel = MessagesPanel.new(with_name)
	add_child(_messages_panel)
	move_child(_toasts, -1)


func _on_dm(msg: Dictionary) -> void:
	var from: String = msg.get("from", "")
	if from != profile.get("name", "") and from != dm_open_with:
		unread[from] = int(unread.get(from, 0)) + 1
		unread_changed.emit()
		_show_dm_notice(from, str(msg.get("text", "")))
	dm_received.emit(msg)


func _show_dm_notice(from: String, text: String) -> void:
	Audio.play_sfx("click", 0.0)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.flat_style(Color(0.08, 0.07, 0.12, 0.97), Color("9fd8ff"), 2, 4))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	var l := UITheme.label("✉ %s : %s" % [from, text if text.length() <= 70 else text.left(67) + "..."], 16, Color("dff1ff"), 3)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 380
	vb.add_child(l)
	var reply := UITheme.button(Loc.t("Répondre"), 140)
	reply.custom_minimum_size.y = 32
	reply.add_theme_font_size_override("font_size", 15)
	reply.size_flags_horizontal = Control.SIZE_SHRINK_END
	reply.pressed.connect(func():
		panel.queue_free()
		open_messages(from))
	vb.add_child(reply)
	_toasts.add_child(panel)
	var tw := panel.create_tween()
	tw.tween_interval(8.0)
	tw.tween_property(panel, "modulate:a", 0.0, 0.4)
	tw.tween_callback(panel.queue_free)


func toast(text: String, color := UITheme.LIGHT_TEXT, duration := 4.0) -> void:
	if text == "":
		return
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.flat_style(Color(0.1, 0.07, 0.09, 0.95), UITheme.GOLD, 2, 4))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UITheme.label(text, 16, color, 3)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size.x = 380
	panel.add_child(l)
	_toasts.add_child(panel)
	var tw := panel.create_tween()
	tw.tween_interval(duration)
	tw.tween_property(panel, "modulate:a", 0.0, 0.4)
	tw.tween_callback(panel.queue_free)


func _show_invite(from: String, avatar_id: int, room_id: String) -> void:
	Audio.play_sfx("end_turn", 0.0)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.flat_style(Color(0.12, 0.08, 0.05, 0.97), UITheme.GOLD, 3, 4))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	panel.add_child(hb)
	var av := TextureRect.new()
	av.texture = CardDB.avatar(avatar_id)
	av.custom_minimum_size = Vector2(56, 56)
	av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	hb.add_child(av)
	var vb := VBoxContainer.new()
	hb.add_child(vb)
	var l := UITheme.label(Loc.t("%s vous invite à une partie !") % from, 17, UITheme.GOLD)
	vb.add_child(l)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	var join := UITheme.button(Loc.t("Rejoindre"), 140)
	join.custom_minimum_size.y = 36
	var decline := UITheme.button(Loc.t("Refuser"), 120)
	decline.custom_minimum_size.y = 36
	row.add_child(join)
	row.add_child(decline)
	_toasts.add_child(panel)
	join.pressed.connect(func():
		panel.queue_free()
		if PauseMenu.is_open():
			PauseMenu.close()
		Net.join_relay(from)
		join_room(room_id)
		get_tree().change_scene_to_file(MULTIPLAYER_SCENE))
	decline.pressed.connect(panel.queue_free)
	# Connexion à une méthode du panneau : elle disparaît d'elle-même si le panneau est libéré avant.
	get_tree().create_timer(30.0, true).timeout.connect(panel.queue_free)
	if Settings.auto_accept:
		join.pressed.emit()
