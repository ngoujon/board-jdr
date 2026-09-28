extends Node
## Paramètres persistants : volumes, affichage, difficulté et raccourcis clavier.

signal settings_changed

## Options de lancement (après « -- ») :
##   --profile=X    fichier de paramètres séparé (deux instances sur le même PC)
##   --name=X       impose le pseudo
##   --autoplay     l'IA joue à la place du joueur local (tests)
##   --auto-accept  accepte automatiquement invitations et demandes d'ami (tests)
var SAVE_PATH := "user://settings.cfg"
var autoplay := false
var auto_accept := false
var auto_create := false     # --auto-create : crée une partie publique (tests)
var auto_join_list := false  # --auto-join-list : rejoint une partie de la liste (tests)
var auto_host := ""          # --auto-host=Pseudo : ajoute cet ami, crée un salon, l'invite et lance la partie
var quit_after_game := false # --quit-after-game
var auto_ai := -1              # --auto-ai=N : lance une partie contre l'IA de niveau N une fois connecté (tests)
var auto_rematch := false    # --auto-rematch : demande une revanche après la 1re partie (tests)
var watch_replay := 0         # --watch-replay=ID : lance ce replay dès la connexion (tests)

## Actions reconfigurables : nom interne -> [libellé affiché, touche par défaut]
const REBINDABLE := {
	"pause": ["Menu pause / options", KEY_ESCAPE],
	"end_turn": ["Terminer le tour", KEY_SPACE],
	"fast_anim": ["Accélérer les animations (maintenir)", KEY_SHIFT],
	"toggle_fullscreen": ["Plein écran", KEY_F11],
	"open_chat": ["Écrire dans le chat", KEY_ENTER],
}

const BUS_NAMES := ["Master", "Music", "SFX"]

var volumes := {"Master": 0.8, "Music": 0.6, "SFX": 0.8}
var fullscreen := false
var vsync := true
var show_fps := false
## 0 = Apprenti (facile), 1 = Chevalier (normal), 2 = Seigneur de guerre (difficile)
var ai_difficulty := 1
var language_chosen := false  # vrai quand le joueur a choisi sa langue dans les paramètres
var language := ""            # fr | en | de | es | it | pt ("" : langue du système au premier lancement)
var hand_sort := "manual"   # rangement de la main : manual | cost | health | attack
var auto_end_turn := false   # termine le tour tout seul quand il n'y a plus rien à jouer
var anim_speed := 1.0
var ui_zoom := 1.0           # zoom de l'interface (Paramètres > Affichage), de 0,7 à 1,3
const BASE_SIZE := Vector2(1280, 720)
var keybinds := {}

# Profil et serveur communautaire
var player_name := ""
var avatar := 1
var account_token := ""
## Serveur officiel (VPS) : comptes, salons, relais des parties et mises à jour. Aucun port à ouvrir chez les joueurs.
const OFFICIAL_SERVER := "203.0.113.10"
const OFFICIAL_PORT := 7778
const OFFICIAL_WEB := "https://arcanes.example.com"
const OFFICIAL_TLS_PORT := 7780                        # connexion chiffrée (TLS) au serveur officiel
const OFFICIAL_TLS_NAME := "arcanes.example.com"   # nom attendu dans le certificat du serveur   # mises à jour, page de téléchargement, installateur
## Mode vérificateur (serveur) : rejoue une partie, sans réseau, sans mise à jour ni fichier de réglages.
var verifier_mode := "--verifier" in OS.get_cmdline_user_args()
var server_address := OFFICIAL_SERVER
var server_port := OFFICIAL_PORT
var local_ai_wins := 0
var local_ai_losses := 0
var ai_beaten: Array = []     # niveaux d'IA battus sur ce PC (0 à 3) : coche verte, même hors ligne
var inferno_best := 0         # meilleur score Inferno sur ce PC
var cosmetics_cache := {}   # dernier profil de personnalisation reçu du serveur (utilisé hors ligne)
var last_seen_patch := ""   # dernière version dont les notes de mise à jour ont été vues


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	for action in REBINDABLE:
		keybinds[action] = REBINDABLE[action][1]
	var forced_name := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile="):
			SAVE_PATH = "user://settings_%s.cfg" % arg.get_slice("=", 1).validate_filename()
		elif arg.begins_with("--name="):
			forced_name = arg.get_slice("=", 1)
		elif arg == "--autoplay":
			autoplay = true
		elif arg == "--auto-accept":
			auto_accept = true
		elif arg == "--auto-create":
			auto_create = true
		elif arg == "--auto-join-list":
			auto_join_list = true
		elif arg.begins_with("--auto-host="):
			auto_host = arg.get_slice("=", 1)
		elif arg.begins_with("--auto-ai="):
			auto_ai = int(arg.get_slice("=", 1))
		elif arg == "--quit-after-game":
			quit_after_game = true
		elif arg == "--auto-rematch":
			auto_rematch = true
		elif arg.begins_with("--watch-replay="):
			watch_replay = int(arg.get_slice("=", 1))
	load_settings()
	if forced_name != "":
		player_name = forced_name
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--server="):
			server_address = arg.get_slice("=", 1)
		elif arg.begins_with("--port="):
			server_port = int(arg.get_slice("=", 1))
	apply_all()


func _ensure_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


func apply_all() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lang="):
			language = arg.get_slice("=", 1)   # tests
	if verifier_mode:
		language = "fr"
	elif language == "":
		language = Loc.system_language()
	Loc.set_language(language)
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)
	_apply_zoom.call_deferred(not is_equal_approx(ui_zoom, 1.0))   # au démarrage, 100 % : fenêtre laissée telle quelle
	for bus_name in BUS_NAMES:
		_apply_volume(bus_name)
	_apply_display()
	for action in keybinds:
		_apply_keybind(action)
	Engine.time_scale = anim_speed
	settings_changed.emit()


func set_volume(bus_name: String, value: float) -> void:
	volumes[bus_name] = clampf(value, 0.0, 1.0)
	_apply_volume(bus_name)
	save_settings()
	settings_changed.emit()


func _apply_volume(bus_name: String) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	var v: float = volumes.get(bus_name, 1.0)
	AudioServer.set_bus_mute(idx, v <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))


func set_fullscreen(value: bool) -> void:
	fullscreen = value
	_apply_display()
	_apply_zoom.call_deferred()
	save_settings()
	settings_changed.emit()


func set_vsync(value: bool) -> void:
	vsync = value
	_apply_display()
	save_settings()


## Zoom de l'interface. En fenêtre : la fenêtre grandit ou rétrécit (70 à 130 % de 1280 × 720, dans la limite
## de l'écran). En plein écran, l'interface occupe déjà tout l'écran : seul le dézoom s'applique (jeu réduit, centré).
func set_ui_zoom(value: float) -> void:
	ui_zoom = clampf(snappedf(value, 0.05), 0.7, 1.3)
	_apply_zoom()
	save_settings()


func _apply_zoom(resize := true) -> void:
	if verifier_mode or DisplayServer.get_name() == "headless":
		return
	var root := get_tree().root
	var f := minf(ui_zoom, 1.0) if fullscreen else 1.0
	root.canvas_transform = Transform2D(0.0, Vector2(f, f), 0.0, BASE_SIZE * (1.0 - f) / 2.0)
	RenderingServer.set_default_clear_color(Color("0d0a10"))
	if not resize or fullscreen or DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		return
	if OS.get_cmdline_args().has("--resolution"):
		return   # taille de fenêtre imposée au lancement (captures vidéo) : on la garde
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var want := BASE_SIZE * ui_zoom
	var k := minf(1.0, minf(screen.size.x * 0.96 / want.x, screen.size.y * 0.92 / want.y))
	var sz := Vector2i((want * k).round())
	DisplayServer.window_set_size(sz)
	DisplayServer.window_set_position(screen.position + (screen.size - sz) / 2)


## Les calques (menus, fenêtres, superpositions) suivent le zoom de l'interface.
func _on_node_added(n: Node) -> void:
	if n is CanvasLayer:
		(n as CanvasLayer).follow_viewport_enabled = true


func set_anim_speed(value: float) -> void:
	anim_speed = clampf(value, 0.5, 3.0)
	Engine.time_scale = anim_speed
	save_settings()


## Change la langue du jeu (Paramètres > Langue) ; l'écran en cours est ensuite reconstruit.
func set_language(lang: String) -> void:
	language = lang if lang in Loc.LANGS else "fr"
	language_chosen = true
	Loc.set_language(language)
	CardDB.localize()
	save_settings()


func set_auto_end_turn(on: bool) -> void:
	auto_end_turn = on
	save_settings()


func mark_ai_beaten(level: int) -> void:
	if level >= 0 and level <= 3 and not level in ai_beaten:
		ai_beaten.append(level)
		save_settings()


func set_inferno_best(score: int) -> void:
	if score > inferno_best:
		inferno_best = score
		save_settings()


## Niveau d'IA déjà battu : sur ce PC ou d'après le profil du serveur.
func has_beaten(level: int) -> bool:
	return level in ai_beaten or int(Lobby.profile.get("stats", {}).get("ai_beaten_%d" % level, 0)) > 0


func set_hand_sort(mode: String) -> void:
	hand_sort = mode if mode in ["manual", "cost", "health", "attack"] else "manual"
	save_settings()


func set_difficulty(value: int) -> void:
	ai_difficulty = value
	save_settings()


func _apply_display() -> void:
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


func set_keybind(action: String, keycode: int) -> void:
	keybinds[action] = keycode
	_apply_keybind(action)
	save_settings()
	settings_changed.emit()


func reset_keybinds() -> void:
	for action in REBINDABLE:
		keybinds[action] = REBINDABLE[action][1]
		_apply_keybind(action)
	save_settings()
	settings_changed.emit()


func _apply_keybind(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keybinds[action] as Key
	InputMap.action_add_event(action, ev)


func key_label(action: String) -> String:
	var code: int = keybinds.get(action, KEY_NONE)
	return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(code as Key))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		set_fullscreen(not fullscreen)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("fast_anim"):
		Engine.time_scale = anim_speed * 3.0
	elif event.is_action_released("fast_anim"):
		Engine.time_scale = anim_speed


func save_settings() -> void:
	if verifier_mode:
		return
	var cfg := ConfigFile.new()
	for bus_name in volumes:
		cfg.set_value("audio", bus_name, volumes[bus_name])
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "vsync", vsync)
	cfg.set_value("display", "show_fps", show_fps)
	cfg.set_value("game", "ai_difficulty", ai_difficulty)
	cfg.set_value("game", "hand_sort", hand_sort)
	cfg.set_value("game", "auto_end_turn", auto_end_turn)
	cfg.set_value("game", "language", language)
	cfg.set_value("game", "language_chosen", language_chosen)
	cfg.set_value("game", "anim_speed", anim_speed)
	cfg.set_value("display", "ui_zoom", ui_zoom)
	for action in keybinds:
		cfg.set_value("keys", action, keybinds[action])
	cfg.set_value("profile", "name", player_name)
	cfg.set_value("profile", "avatar", avatar)
	cfg.set_value("profile", "token", account_token)
	cfg.set_value("profile", "ai_wins", local_ai_wins)
	cfg.set_value("profile", "ai_losses", local_ai_losses)
	cfg.set_value("profile", "ai_beaten", ai_beaten)
	cfg.set_value("profile", "inferno_best", inferno_best)
	cfg.set_value("profile", "last_seen_patch", last_seen_patch)
	cfg.set_value("profile", "cosmetics", cosmetics_cache)
	cfg.set_value("online", "address", server_address)
	cfg.set_value("online", "port", server_port)
	cfg.set_value("online", "migrated_official", true)
	cfg.save(SAVE_PATH)


func set_profile(new_name: String, new_avatar: int) -> void:
	player_name = new_name.strip_edges()
	avatar = new_avatar if new_avatar in CardDB.BASE_AVATARS else clampi(new_avatar, 1, 8)
	save_settings()
	settings_changed.emit()


## Le serveur officiel est joint en TLS (certificat vérifié) ; un serveur local ou de test reste en clair.
func uses_tls() -> bool:
	return server_address == OFFICIAL_SERVER and server_port == OFFICIAL_PORT and not "--no-tls" in OS.get_cmdline_user_args()


func set_server(address: String, port: int) -> void:
	server_address = address.strip_edges()
	server_port = port
	save_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for bus_name in volumes.keys():
		volumes[bus_name] = cfg.get_value("audio", bus_name, volumes[bus_name])
	fullscreen = cfg.get_value("display", "fullscreen", fullscreen)
	vsync = cfg.get_value("display", "vsync", vsync)
	show_fps = cfg.get_value("display", "show_fps", show_fps)
	ai_difficulty = cfg.get_value("game", "ai_difficulty", ai_difficulty)
	hand_sort = str(cfg.get_value("game", "hand_sort", hand_sort))
	auto_end_turn = bool(cfg.get_value("game", "auto_end_turn", auto_end_turn))
	language_chosen = bool(cfg.get_value("game", "language_chosen", false))
	# Langue choisie par le joueur uniquement ; sinon le français (la 1.8.0 prenait la langue du système).
	language = str(cfg.get_value("game", "language", language)) if language_chosen else "fr"
	anim_speed = cfg.get_value("game", "anim_speed", anim_speed)
	ui_zoom = clampf(float(cfg.get_value("display", "ui_zoom", ui_zoom)), 0.7, 1.3)
	for action in keybinds.keys():
		keybinds[action] = cfg.get_value("keys", action, keybinds[action])
	player_name = cfg.get_value("profile", "name", player_name)
	avatar = cfg.get_value("profile", "avatar", avatar)
	account_token = cfg.get_value("profile", "token", account_token)
	local_ai_wins = cfg.get_value("profile", "ai_wins", 0)
	local_ai_losses = cfg.get_value("profile", "ai_losses", 0)
	ai_beaten = Array(cfg.get_value("profile", "ai_beaten", []))
	inferno_best = int(cfg.get_value("profile", "inferno_best", 0))
	last_seen_patch = cfg.get_value("profile", "last_seen_patch", "")
	cosmetics_cache = cfg.get_value("profile", "cosmetics", {})
	server_address = cfg.get_value("online", "address", server_address)
	server_port = cfg.get_value("online", "port", server_port)
	# Anciennes versions : l'adresse par défaut était 127.0.0.1 -> on passe au serveur officiel.
	if server_address in ["", "127.0.0.1", "localhost"] and not cfg.get_value("online", "migrated_official", false):
		server_address = OFFICIAL_SERVER
		server_port = OFFICIAL_PORT
