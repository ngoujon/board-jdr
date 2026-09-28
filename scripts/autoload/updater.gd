extends Node
## Mises à jour du jeu.
##  - Le serveur communautaire publie la dernière version sur http://<serveur>:<port+1>/version.json
##    ({"version", "file", "sha256", "size", "notes"}) et le paquet .pck correspondant.
##  - Au lancement (scène boot), le client compare sa version ; s'il est en retard, il télécharge
##    le .pck dans user://updates/ et vérifie son SHA-256.
##  - Pour l'appliquer, le jeu se ferme et un petit script (PowerShell sous Windows, /bin/sh sous Linux
##    et macOS) remplace le .pck principal, puis relance le jeu. (Les modèles d'export de Godot 4.7 refusent --main-pack.)
##  - Chaque système a son paquet : champs principaux de latest.json pour Windows, "platforms" pour les autres.
##  - Si ce remplacement a échoué, _ready() le retente au lancement suivant.
##  - Le serveur refuse les clients obsolètes : tout le monde joue sur la même version.

signal check_finished(state: String)

## Clé publique des mises à jour : le manifeste (version.json) est signé avec la clé privée correspondante,
## conservée uniquement sur le PC de publication. Même un serveur compromis ne peut pas diffuser un faux paquet.
const UPDATE_PUBLIC_KEY := """-----BEGIN PUBLIC KEY-----
MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEA26m8CEe70dg7cOorHW6R
tkF5g4LOQY/qZ5b9Qc1M/YdRQnBwyi8t7+jgKhq2VseiJWC3LdoUhCT1sDD4r199
xmGdtmIOwAt3gLpInB+AB/qRRKujXmCbs5leh/uFBSnyvyYmuOyDgdXE3rVO9BIX
mlifPAr5JhpPsm2fs0dwqfK3OQ8vH/E9iimRPD0wxqcq5IKId4RHOKXXxNFh7zOx
BS5QMCkpDHiFcwG2tDHI86sFoslIlIgacLqwDT9ySpwYOapohhzSPQSjMa9EnYiJ
Gu44YrqCkxKGdNI6NhKjfaKfb6hm0goXX4KPpKgRuefCGNpnP1coWxo9Mj0NmPUo
0qd2StyriUpdMDtzuFqH1a2rgWFkXLvEZCU74M4SQzR5esgAgn+AcgsO/+H/1/6h
UwvB1XZAi1BxmTIm9qeOdNFUd8+6YtWC3ThwpOEUh/22+tMVrVhQHzO7MQaM8b02
SkiQG85baeqwua0bIt6lC1mS6SiKNCXD5FT3JACwa60vAgMBAAE=
-----END PUBLIC KEY-----"""
signal download_progress(done: int, total: int)
signal download_finished(ok: bool, message: String)

const UPDATE_DIR := "user://updates"
const INSTALLED_FILE := "user://updates/installed.json"
const CHECK_TIMEOUT := 5.0

## "idle" | "checking" | "up_to_date" | "outdated" | "offline" | "downloading" | "ready" | "error"
var state := "idle"
var restarting := false   # vrai quand le jeu se relance sur une mise à jour
var latest := {}
var last_error := ""

var _http: HTTPRequest
var _download_total := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Settings.verifier_mode:
		return
	_redirect_to_installed_update()


## Version du jeu en cours d'exécution (application/config/version), --fake-version=X pour les tests.
func current_version() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fake-version="):
			return a.get_slice("=", 1)
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


## -1 si a < b, 0 si égales, 1 si a > b (comparaison numérique "1.10.0" > "1.9.3").
func compare(a: String, b: String) -> int:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := pa[i].to_int() if i < pa.size() else 0
		var y := pb[i].to_int() if i < pb.size() else 0
		if x != y:
			return -1 if x < y else 1
	return 0


func update_url(path: String) -> String:
	# Serveur officiel : HTTPS (certificat Let's Encrypt) ; serveur perso : HTTP sur le port suivant.
	if Settings.server_address == Settings.OFFICIAL_SERVER:
		return "%s/%s" % [Settings.OFFICIAL_WEB, path]
	return "http://%s:%d/%s" % [Settings.server_address, Settings.server_port + 1, path]


## Un jeu exporté (ou lancé sur un paquet) peut se relancer sur le nouveau .pck.
## Depuis l'éditeur, le téléchargement fonctionne mais le redémarrage est impossible.
func can_self_update() -> bool:
	# Jeu exporté (pas l'éditeur) avec son paquet principal .pck à part.
	return OS.get_name() in ["Windows", "Linux", "macOS"] and OS.has_feature("template") \
		and FileAccess.file_exists(main_pack_path())


## Paquet principal du jeu exporté : à côté de l'exe (Windows, Linux),
## dans Contents/Resources de l'application (macOS).
static func main_pack_path() -> String:
	var exe := OS.get_executable_path()
	if OS.get_name() == "macOS":
		return exe.get_base_dir().get_base_dir().path_join("Resources").path_join(exe.get_file().get_basename() + ".pck")
	return exe.get_basename() + ".pck"


## Clé de la plateforme dans latest.json ("platforms") ; Windows utilise les champs principaux.
static func platform_key() -> String:
	match OS.get_name():
		"Linux":
			return "linux"
		"macOS":
			return "macos"
	return "windows"


## Manifeste ramené à la plateforme courante : chaque système a son propre paquet signé.
static func for_platform(data: Dictionary) -> Dictionary:
	var entry = data.get("platforms", {}).get(platform_key(), null)
	if not (entry is Dictionary):
		return data
	var out := data.duplicate()
	for k in ["file", "sha256", "size", "signature"]:
		if entry.has(k):
			out[k] = entry[k]
		else:
			out.erase(k)
	return out


# ------------------------------------------------------------------ vérification

func check() -> void:
	if state in ["checking", "downloading"]:
		return
	state = "checking"
	last_error = ""
	_reset_http()
	_http.timeout = CHECK_TIMEOUT
	_http.request_completed.connect(_on_check_completed, CONNECT_ONE_SHOT)
	if _http.request(update_url("version.json")) != OK:
		_finish_check("offline", Loc.t("Requête impossible."))


func _on_check_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_finish_check("offline", Loc.t("Serveur de mise à jour injoignable."))
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not (data is Dictionary) or not data.has("version"):
		_finish_check("error", Loc.t("Réponse du serveur invalide."))
		return
	data = for_platform(data)
	if not _signature_ok(data):
		push_warning("[Updater] signature du manifeste invalide : mise à jour ignorée")
		_finish_check("error", Loc.t("Mise à jour refusée : signature invalide."))
		return
	latest = data
	if compare(current_version(), str(data.version)) < 0:
		# Déjà téléchargée mais pas encore lancée (ex. depuis l'éditeur) : prête à appliquer.
		var inst := _read_installed()
		if inst.get("version", "") == str(data.version) and FileAccess.file_exists(inst.get("file", "")):
			_finish_check("ready")
		else:
			_finish_check("outdated")
	else:
		_finish_check("up_to_date")


## Texte signé : version, fichier, empreinte et taille du paquet (voir tools/publish_update.py).
static func signed_text(data: Dictionary) -> String:
	return "arcanes-update|%s|%s|%s|%d" % [str(data.get("version", "")), str(data.get("file", "")),
		str(data.get("sha256", "")).to_lower(), int(data.get("size", 0))]


## Serveur officiel : manifeste obligatoirement signé. Serveur de test (--server=) : signature facultative.
func _signature_ok(data: Dictionary) -> bool:
	if not data.has("signature"):
		return Settings.server_address != Settings.OFFICIAL_SERVER
	var key := CryptoKey.new()
	if key.load_from_string(UPDATE_PUBLIC_KEY, true) != OK:
		return false
	var sig := Marshalls.base64_to_raw(str(data.signature))
	return Crypto.new().verify(HashingContext.HASH_SHA256, signed_text(data).sha256_buffer(), sig, key)


func _finish_check(new_state: String, err := "") -> void:
	state = new_state
	last_error = err
	print("[Updater] version %s -> %s %s" % [current_version(), new_state, latest.get("version", "")])
	check_finished.emit(state)


## Appelé quand le serveur communautaire refuse notre version.
func mark_outdated(required_version: String) -> void:
	if state in ["checking", "downloading", "ready", "outdated"]:
		return   # déjà pris en charge par la vérification / le téléchargement en cours
	if latest.get("version", "") != required_version:
		latest = {"version": required_version}
	state = "outdated"
	check_finished.emit(state)


# ------------------------------------------------------------------ téléchargement

func download() -> void:
	if state == "downloading":
		return
	if not latest.has("file"):
		# On ne connaît que le numéro (refus du serveur) : on récupère d'abord le manifeste.
		check()
		await check_finished
		if state != "outdated":
			download_finished.emit(state == "ready", last_error)
			return
	var file_name := str(latest.file).get_file()   # pas de chemin : protège contre "../"
	if not file_name.ends_with(".pck"):
		download_finished.emit(false, Loc.t("Paquet de mise à jour invalide."))
		return
	DirAccess.make_dir_recursive_absolute(UPDATE_DIR)
	var part := "%s/%s.part" % [UPDATE_DIR, file_name]
	state = "downloading"
	_download_total = int(latest.get("size", 0))
	_reset_http()
	_http.timeout = 0.0
	_http.download_file = part
	_http.request_completed.connect(_on_download_completed.bind(file_name, part), CONNECT_ONE_SHOT)
	if _http.request(update_url("files/" + file_name)) != OK:
		_fail_download(Loc.t("Téléchargement impossible."))


func _process(_delta: float) -> void:
	if state == "downloading" and _http:
		var total := _http.get_body_size()
		download_progress.emit(_http.get_downloaded_bytes(), total if total > 0 else _download_total)


func _on_download_completed(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray, file_name: String, part: String) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		DirAccess.remove_absolute(part)
		_fail_download(Loc.t("Échec du téléchargement (code %d).") % code)
		return
	var sha := FileAccess.get_sha256(part)
	if latest.has("sha256") and sha != str(latest.sha256).to_lower():
		DirAccess.remove_absolute(part)
		_fail_download(Loc.t("Fichier corrompu (somme de contrôle invalide)."))
		return
	var final_path := "%s/%s" % [UPDATE_DIR, file_name]
	if FileAccess.file_exists(final_path):
		DirAccess.remove_absolute(final_path)
	DirAccess.rename_absolute(part, final_path)
	var f := FileAccess.open(INSTALLED_FILE, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": str(latest.version), "file": final_path, "sha256": sha}))
	f.close()
	_cleanup_old(file_name)
	state = "ready"
	download_finished.emit(true, Loc.t("Mise à jour %s installée.") % latest.version)


func _fail_download(msg: String) -> void:
	state = "outdated"
	last_error = msg
	download_finished.emit(false, msg)


func _cleanup_old(keep: String) -> void:
	var dir := DirAccess.open(UPDATE_DIR)
	if dir == null:
		return
	for f in dir.get_files():
		if f.ends_with(".pck") and f != keep:
			dir.remove(f)


# ------------------------------------------------------------------ application

## Relance le jeu sur le paquet installé. Renvoie false si impossible (lancé depuis l'éditeur).
func restart_on_update() -> bool:
	var inst := _read_installed()
	if inst.is_empty() or not can_self_update():
		return false
	_relaunch(ProjectSettings.globalize_path(inst.file))
	return true


func _relaunch(pck_path: String) -> void:
	var exe := OS.get_executable_path()
	var target := main_pack_path()
	var args := PackedStringArray()
	if DisplayServer.get_name() == "headless":
		args.append("--headless")
	args.append("--")
	for a in OS.get_cmdline_user_args():
		if a != "--from-update" and a != "--auto-update" and not a.begins_with("--fake-version="):
			args.append(a)
	args.append("--from-update")
	restarting = true
	print("[Updater] application de %s puis redémarrage" % pck_path)
	if OS.get_name() != "Windows":
		_relaunch_unix(exe, pck_path, target, args)
		get_tree().quit()
		return
	var quoted := PackedStringArray()
	for a in args:
		quoted.append(_ps_quote("\"%s\"" % a if " " in a else a))
	# Attend la fermeture du jeu (le .pck est verrouillé tant qu'il tourne), remplace le paquet, relance.
	var script := "$ErrorActionPreference = 'SilentlyContinue'; Wait-Process -Id %d -Timeout 60; " % OS.get_process_id() \
		+ "for ($i = 0; $i -lt 40; $i++) { try { Copy-Item -LiteralPath %s -Destination %s -Force -ErrorAction Stop; break } catch { Start-Sleep -Milliseconds 500 } }; " % [_ps_quote(pck_path), _ps_quote(target)] \
		+ "Start-Process -FilePath %s -WorkingDirectory %s -ArgumentList @(%s)" % [_ps_quote(exe), _ps_quote(exe.get_base_dir()), ", ".join(quoted)]
	OS.create_process("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-Command", script])
	get_tree().quit()


## Linux / macOS : même principe avec /bin/sh. Sur macOS, l'application est ensuite re-signée
## (signature ad hoc, codesign est fourni avec le système) car le paquet fait partie du bundle signé.
func _relaunch_unix(exe: String, pck_path: String, target: String, args: PackedStringArray) -> void:
	var quoted := PackedStringArray()
	for a in args:
		quoted.append(_sh_quote(a))
	var script := "i=0; while kill -0 %d 2>/dev/null && [ $i -lt 300 ]; do sleep 0.2; i=$((i+1)); done; " % OS.get_process_id() \
		+ "i=0; until cp -f %s %s; do i=$((i+1)); [ $i -ge 40 ] && break; sleep 0.5; done; " % [_sh_quote(pck_path), _sh_quote(target)]
	if OS.get_name() == "macOS":
		var app := exe.get_base_dir().get_base_dir().get_base_dir()   # .../Arcanes & Lames.app
		script += "codesign --force --deep --sign - %s >/dev/null 2>&1; " % _sh_quote(app)
	script += "cd %s && exec %s %s >/dev/null 2>&1" % [_sh_quote(exe.get_base_dir()), _sh_quote(exe), " ".join(quoted)]
	OS.create_process("/bin/sh", ["-c", script])


static func _ps_quote(t: String) -> String:
	return "'" + t.replace("'", "''") + "'"


static func _sh_quote(t: String) -> String:
	return "'" + t.replace("'", "'\\''") + "'"


## Au démarrage d'un jeu exporté : si un paquet plus récent est installé, on se relance dessus.
func _redirect_to_installed_update() -> void:
	if not can_self_update() or OS.get_cmdline_user_args().has("--from-update"):
		return
	var inst := _read_installed()
	if inst.is_empty() or compare(current_version(), str(inst.get("version", "0"))) >= 0:
		return
	if not FileAccess.file_exists(inst.file) or FileAccess.get_sha256(inst.file) != inst.get("sha256", ""):
		DirAccess.remove_absolute(INSTALLED_FILE)
		return
	_relaunch(ProjectSettings.globalize_path(inst.file))


func _read_installed() -> Dictionary:
	if not FileAccess.file_exists(INSTALLED_FILE):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(INSTALLED_FILE))
	return data if data is Dictionary else {}


func _reset_http() -> void:
	if _http:
		_http.queue_free()
	_http = HTTPRequest.new()
	_http.use_threads = true
	add_child(_http)
