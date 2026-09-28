extends Node
## Test (fenêtré, hors ligne) de l'accueil des nouveaux joueurs : 3 diapositives, pseudo et avatar.
## Profil neuf obligatoire (supprimer settings_welcometest.cfg avant) :
##   godot --path . res://tests/welcome_test.tscn -- --profile=welcometest --server=127.0.0.1 --port=1 --shots-dir=C:/chemin

var _dir := "user://shots"
var _fails := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots-dir="):
			_dir = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_dir)
	_check(Settings.player_name == "" and not Settings.welcome_done, "profil neuf")
	await _wait(0.5)
	var menu: Node = load("res://scenes/main_menu.tscn").instantiate()
	get_tree().root.add_child(menu)
	await _wait(0.8)
	var wp: WelcomePanel = null
	for c in menu.get_children():
		if c is WelcomePanel:
			wp = c
	_check(wp != null, "accueil affiché au premier lancement")
	if wp == null:
		get_tree().quit(1)
		return
	for i in 3:
		_shot("w%d_diapo" % (i + 1))
		wp._next.pressed.emit()
		await _wait(0.4)
	_check(wp._name_edit != null, "page du pseudo après les 3 diapositives")
	_shot("w4_pseudo")
	wp._name_edit.text = "ab"
	wp._register()
	_check(wp._status.text != "" and Settings.player_name == "", "pseudo trop court refusé")
	wp._name_edit.text = "Nouveau"
	wp._select_avatar(5)
	wp._register()
	_check(Settings.player_name == "Nouveau" and Settings.avatar == 5, "pseudo et avatar enregistrés")
	_shot("w5_verification")
	await _wait(9.0)   # serveur injoignable : l'accueil se ferme et le pseudo sera réservé plus tard
	_check(not is_instance_valid(wp) and Settings.welcome_done, "accueil fermé, ne reviendra pas")
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, what: String) -> void:
	print(("  ok   " if cond else "  ÉCHEC ") + what)
	if not cond:
		_fails += 1


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _shot(name: String) -> void:
	var path := _dir.path_join(name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("capture : ", path)
