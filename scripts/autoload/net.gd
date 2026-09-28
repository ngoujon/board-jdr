extends Node
## Transport des parties en ligne. Deux transports possibles :
##  - "relay" : via le serveur communautaire (salons, invitations d'amis) — aucun port à ouvrir
##              côté joueurs, seul le serveur doit être joignable ;
##  - "enet"  : connexion directe par IP (UDP), l'hôte doit ouvrir son port (ou UPnP / VPN).
## L'hôte fait autorité :
##  - l'hôte est le joueur 0, le client le joueur 1 ;
##  - l'hôte choisit la graine aléatoire et qui commence, puis lance la partie des deux côtés ;
##  - les deux machines font tourner la même simulation (GameState déterministe) et
##    s'échangent uniquement les actions. Le client envoie ses actions à l'hôte, qui les
##    valide, les applique et les renvoie au client dans l'ordre.

signal status_changed(text: String)
signal peer_joined(name: String)
signal connected_to_host
signal connection_failed
signal opponent_left
signal action_received(player: int, action: Dictionary)
signal action_rejected
signal upnp_done(ok: bool, external_ip: String)
signal chat_received(sender: String, text: String)
signal rematch_changed(state: String)   # demande de l'adversaire : "ask" | "decline"

const DEFAULT_PORT := 7777
const PROTOCOL_VERSION := 1
const BATTLE_SCENE := "res://scenes/battle.tscn"
const RELAY_METHODS := ["_hello", "_start", "_request", "_apply", "_reject", "_chat", "_version_mismatch", "_rematch"]

## "ai" (solo contre l'IA), "host" ou "client"
var mode := "ai"
var transport := "enet"
var local_name := Loc.t("Joueur")
var remote_name := Loc.t("Adversaire")
var local_avatar := 1
var remote_avatar := 1
var remote_look := {}   # personnalisation de l'adversaire : titre, contour, dos de cartes
var replay := {}   # partie rejouée (mode "replay") : seed, first, names, avatars, actions, view
var games_played := 0         # parties enchaînées dans ce salon (tests de revanche)
var rematch_local := false    # nous avons demandé une revanche
var rematch_remote := false   # l'adversaire a demandé une revanche
var match_seed := 0
var _starting := false
var match_first := 0
var remote_peer_id := 0
var pending_actions: Array = []   # actions reçues avant que la scène de combat soit prête

var _upnp: UPNP
var _upnp_thread: Thread
var _upnp_port := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	Lobby.relay_received.connect(_on_relay)
	Lobby.room_changed.connect(_on_room_changed)
	Lobby.peer_left.connect(_on_relay_peer_left)
	Lobby.room_closed.connect(func(_m):
		if transport == "relay" and is_online():
			_on_relay_peer_left())


func is_online() -> bool:
	return mode == "host" or mode == "client"


func local_index() -> int:
	if mode == "replay":
		return int(replay.get("view", 0))
	return 1 if mode == "client" else 0


func _my_name() -> String:
	return Settings.player_name if Settings.player_name != "" else Loc.t("Joueur")


# ------------------------------------------------------------------ connexion directe (ENet)

func host(port: int) -> Error:
	close()
	local_name = _my_name()
	local_avatar = Settings.avatar
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 1)
	if err != OK:
		status_changed.emit(Loc.t("Impossible d'ouvrir le port %d (déjà utilisé ?).") % port)
		return err
	multiplayer.multiplayer_peer = peer
	mode = "host"
	transport = "enet"
	status_changed.emit(Loc.t("Partie hébergée sur le port %d. En attente d'un adversaire...") % port)
	return OK


func join(address: String, port: int) -> Error:
	close()
	local_name = _my_name()
	local_avatar = Settings.avatar
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		status_changed.emit(Loc.t("Adresse invalide."))
		return err
	multiplayer.multiplayer_peer = peer
	mode = "client"
	transport = "enet"
	status_changed.emit(Loc.t("Connexion à %s:%d...") % [address, port])
	return OK


# ------------------------------------------------------------------ via le serveur communautaire

func host_relay() -> void:
	close()
	local_name = _my_name()
	local_avatar = Settings.avatar
	mode = "host"
	transport = "relay"


func join_relay(host_name: String) -> void:
	close()
	local_name = _my_name()
	local_avatar = Settings.avatar
	remote_name = host_name
	mode = "client"
	transport = "relay"
	remote_peer_id = 1


func _on_room_changed(room: Dictionary, role: String) -> void:
	if transport != "relay" or not is_online():
		return
	if role == "host":
		var guest = room.get("guest")
		if guest is Dictionary and remote_peer_id == 0:
			remote_peer_id = 2
			remote_name = guest.name
			remote_avatar = int(guest.avatar)
			remote_look = guest
			status_changed.emit(Loc.t("%s a rejoint la partie !") % remote_name)
			peer_joined.emit(remote_name)
		elif guest == null and remote_peer_id != 0:
			remote_peer_id = 0
	else:
		var h = room.get("host")
		if h is Dictionary:
			remote_name = h.name
			remote_avatar = int(h.avatar)
			remote_look = h
		connected_to_host.emit()
		status_changed.emit(Loc.t("Salon rejoint ! En attente du lancement par %s...") % remote_name)


func _on_relay_peer_left() -> void:
	if transport != "relay" or not is_online():
		return
	remote_peer_id = 0 if mode == "host" else remote_peer_id
	status_changed.emit(Loc.t("L'adversaire a quitté la partie."))
	opponent_left.emit()


func _on_relay(kind: String, args: Array) -> void:
	if transport == "relay" and kind in RELAY_METHODS:
		callv(kind, _normalize(args))


## Le JSON transforme les entiers en flottants : on les reconvertit.
func _normalize(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			return int(v) if is_equal_approx(v, roundf(v)) else v
		TYPE_ARRAY:
			var a := []
			for x in v:
				a.append(_normalize(x))
			return a
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[k] = _normalize(v[k])
			return d
	return v


func close() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	if transport == "relay" and is_online():
		Lobby.leave_room()
	mode = "ai"
	replay = {}
	games_played = 0
	rematch_local = false
	rematch_remote = false
	transport = "enet"
	remote_peer_id = 0
	remote_look = {}
	pending_actions.clear()
	_remove_upnp_mapping()


## Adresses IPv4 locales (pour les joueurs du même réseau / VPN).
func local_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out


# ------------------------------------------------------------------ UPnP (ouverture du port sur la box)

func try_upnp(port: int) -> void:
	if _upnp_thread and _upnp_thread.is_alive():
		return
	_upnp_port = port
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_worker.bind(port))


func _upnp_worker(port: int) -> void:
	var upnp := UPNP.new()
	var ok := false
	var ext := ""
	if upnp.discover(2000, 2) == UPNP.UPNP_RESULT_SUCCESS and upnp.get_gateway() and upnp.get_gateway().is_valid_gateway():
		ok = upnp.add_port_mapping(port, port, "Arcanes & Lames", "UDP") == UPNP.UPNP_RESULT_SUCCESS
		ext = upnp.query_external_address()
	call_deferred("_upnp_finished", upnp if ok else null, ok, ext)


func _upnp_finished(upnp: UPNP, ok: bool, ext: String) -> void:
	_upnp_thread.wait_to_finish()
	_upnp = upnp
	upnp_done.emit(ok, ext)


func _remove_upnp_mapping() -> void:
	if _upnp:
		_upnp.delete_port_mapping(_upnp_port, "UDP")
		_upnp = null


func _exit_tree() -> void:
	close()


# ------------------------------------------------------------------ événements ENet

func _on_peer_connected(id: int) -> void:
	if mode == "host":
		if remote_peer_id != 0:
			multiplayer.multiplayer_peer.disconnect_peer(id)   # partie déjà complète
			return
		remote_peer_id = id
	elif mode == "client":
		remote_peer_id = 1


func _on_peer_disconnected(id: int) -> void:
	if id == remote_peer_id:
		remote_peer_id = 0
		status_changed.emit(Loc.t("L'adversaire s'est déconnecté."))
		opponent_left.emit()


func _on_connected_to_server() -> void:
	status_changed.emit(Loc.t("Connecté ! En attente du lancement par l'hôte..."))
	connected_to_host.emit()
	_send("_hello", [local_name, local_avatar, PROTOCOL_VERSION, Updater.current_version(), Lobby.my_look()])


func _on_connection_failed() -> void:
	status_changed.emit(Loc.t("Échec de la connexion."))
	close()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	status_changed.emit(Loc.t("L'hôte a fermé la partie."))
	opponent_left.emit()


# ------------------------------------------------------------------ envoi (RPC ou relais)

func _send(method: String, args: Array) -> void:
	if transport == "relay":
		Lobby.relay(method, args)
	else:
		var target := 1 if mode == "client" else remote_peer_id
		if target != 0:
			callv("rpc_id", [target, method] + args)


func _from_remote() -> bool:
	return transport == "relay" or multiplayer.get_remote_sender_id() == remote_peer_id


# ------------------------------------------------------------------ RPC

@rpc("any_peer", "reliable")
func _hello(player_name: String, avatar_id: int, version: int, game_version: String, look: Dictionary) -> void:
	if mode != "host" or not _from_remote():
		return
	if version != PROTOCOL_VERSION or game_version != Updater.current_version():
		# Les deux joueurs doivent avoir exactement la même version du jeu.
		_send("_version_mismatch", [Updater.current_version()])
		status_changed.emit(Loc.t("%s utilise la version %s (vous : %s) : connexion refusée.") % [
			player_name.substr(0, 16), game_version, Updater.current_version()])
		if transport == "enet":
			var peer := multiplayer.get_remote_sender_id()
			get_tree().create_timer(0.5).timeout.connect(func():
				if multiplayer.multiplayer_peer:
					multiplayer.multiplayer_peer.disconnect_peer(peer))
		return
	remote_name = clean_name(player_name)
	remote_avatar = clampi(avatar_id, 1, 99)
	remote_look = look
	status_changed.emit(Loc.t("%s a rejoint la partie !") % remote_name)
	peer_joined.emit(remote_name)


@rpc("any_peer", "reliable")
func _version_mismatch(host_version: String) -> void:
	if mode != "client" or not _from_remote():
		return
	var cmp := Updater.compare(Updater.current_version(), host_version)
	var advice := Loc.t("mettez votre jeu à jour") if cmp < 0 else Loc.t("l'hôte doit mettre son jeu à jour")
	status_changed.emit(Loc.t("Version différente de l'hôte (%s, vous : %s) : %s.") % [host_version, Updater.current_version(), advice])
	if cmp < 0:
		Updater.mark_outdated(host_version)


## L'hôte lance (ou relance) une partie des deux côtés. Via le serveur, la graine et le premier joueur
## sont tirés par le serveur, qui enregistre la partie pour la valider (anti-triche).
func start_match() -> void:
	if mode != "host" or remote_peer_id == 0 or _starting:
		return
	var seed_value := randi()
	var first := randi() % 2
	if transport == "relay":
		_starting = true
		var t: Dictionary = await Lobby.request_ticket("pvp")
		_starting = false
		if t.is_empty():
			Lobby.toast(Loc.t("Le serveur n'a pas pu lancer la partie : réessayez."), UITheme.RED)
			return
		seed_value = int(t.seed)
		first = int(t.first)
	_send("_start", [seed_value, first, local_name, local_avatar, remote_name, Lobby.my_look()])
	_begin(seed_value, first)


@rpc("any_peer", "reliable")
func _start(seed_value: int, first: int, host_name: String, host_avatar: int, client_name: String, host_look: Dictionary) -> void:
	if mode != "client" or not _from_remote():
		return
	remote_name = clean_name(host_name)
	remote_avatar = clampi(host_avatar, 1, 99)
	remote_look = host_look
	local_name = client_name
	_begin(seed_value, first)


func _begin(seed_value: int, first: int) -> void:
	rematch_local = false
	rematch_remote = false
	match_seed = seed_value
	match_first = first
	pending_actions.clear()
	get_tree().paused = false
	get_tree().change_scene_to_file(BATTLE_SCENE)


# ------------------------------------------------------------------ revanche
# Chaque joueur peut demander une revanche ; l'autre accepte ou refuse.
# Si les deux la demandent, elle est acceptée. C'est toujours l'hôte qui relance la partie.

func ask_rematch() -> void:
	if rematch_remote:
		accept_rematch()
		return
	rematch_local = true
	_send("_rematch", ["ask"])


func accept_rematch() -> void:
	rematch_remote = false
	if mode == "host":
		start_match()
	else:
		rematch_local = true
		_send("_rematch", ["accept"])


func decline_rematch() -> void:
	rematch_remote = false
	_send("_rematch", ["decline"])


@rpc("any_peer", "reliable")
func _rematch(state: String) -> void:
	if not is_online() or not _from_remote():
		return
	match state:
		"ask":
			rematch_remote = true
			if rematch_local:
				if mode == "host":
					start_match()   # les deux joueurs l'ont demandée
				return
		"accept":
			if mode == "host" and rematch_local:
				start_match()
			return
		"decline":
			rematch_local = false
	rematch_changed.emit(state)


## Envoi d'une action locale. Client -> requête à l'hôte ; hôte -> diffusion au client.
func send_request(action: Dictionary) -> void:
	_send("_request", [action])


func broadcast_action(player: int, action: Dictionary) -> void:
	_send("_apply", [player, action])


func reject_request() -> void:
	_send("_reject", [])


@rpc("any_peer", "reliable")
func _request(action: Dictionary) -> void:
	if mode == "host" and _from_remote():
		_deliver(1, action)


@rpc("any_peer", "reliable")
func _apply(player: int, action: Dictionary) -> void:
	if mode == "client" and _from_remote():
		_deliver(player, action)


@rpc("any_peer", "reliable")
func _reject() -> void:
	if mode == "client" and _from_remote():
		action_rejected.emit()


func _deliver(player: int, action: Dictionary) -> void:
	if action_received.get_connections().is_empty():
		pending_actions.append([player, action])
	else:
		action_received.emit(player, action)


## Canal « Discussion » du chat.
func send_chat(text: String) -> void:
	_send("_chat", [text.substr(0, 200)])


@rpc("any_peer", "reliable")
func _chat(text: String) -> void:
	if _from_remote():
		chat_received.emit(remote_name, text.substr(0, 200))


## Pseudo reçu d'un autre joueur : sans balises BBCode ni caractères de contrôle.
static func clean_name(n: String) -> String:
	var out := ""
	for ch in n.substr(0, 16):
		if ch.unicode_at(0) >= 32 and not ch in "[]":
			out += ch
	return out if out.strip_edges() != "" else Loc.t("Adversaire")


func take_pending() -> Array:
	var p := pending_actions
	pending_actions = []
	return p
