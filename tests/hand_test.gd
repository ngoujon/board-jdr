extends Node
## Test (fenêtré) de la main : 1er clic = sélection, 2e clic = jouer, glisser = réordonner sans jouer,
## modes de tri, chrono, revanche, salon multijoueur et menu principal (captures d'écran).
## Lancement : godot --path . res://tests/hand_test.tscn -- --profile=handtest --name=Hand --shots-dir=C:/chemin

var _dir := "user://shots"
var _fails := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots-dir="):
			_dir = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_dir)
	Settings.set_hand_sort("manual")
	await _wait(0.5)
	var battle: Node = load("res://scenes/battle.tscn").instantiate()
	get_tree().root.add_child(battle)
	# Attend notre tour, choix de pioche fait.
	for i in 400:
		await _wait(0.1)
		if battle._can_choose():
			battle._pick_choice(0)
		if battle._can_act() and battle._hand_views.size() >= 3:
			break
	await _wait(0.8)
	var me: int = battle.me
	var gs: GameState = battle.gs
	gs.players[me].energy = 10
	gs.players[me].max_energy = 10
	battle._refresh()
	await _wait(0.4)

	# 1) Glisser une carte : elle change de place et n'est PAS jouée.
	var hand_before: int = gs.players[me].hand.size()
	var cv: CardView = battle._hand_views[0]
	var start: Vector2 = cv.get_global_rect().get_center() + Vector2(0, 20)
	await _mouse_button(start, true)
	for k in 12:
		await _mouse_move(start + Vector2(30.0 * (k + 1), -10))
	await _mouse_button(start + Vector2(360, -10), false)
	await _wait(0.5)
	_check(gs.players[me].hand.size() == hand_before, "le glisser-déposer ne joue pas la carte")
	_check(battle._hand_views.find(cv) > 0, "la carte glissée a changé de place (%d)" % battle._hand_views.find(cv))
	_check(Settings.hand_sort == "manual", "rangement manuel")
	_shot("h1_apres_glisser")

	# 2) Premier clic : sélection seulement.
	var target: CardView = null
	for v in battle._hand_views:
		if gs.can_play(me, v.hand_uid) and not gs.needs_target(v.card_id):
			target = v
			break
	if target:
		var p: Vector2 = target.get_global_rect().get_center() + Vector2(0, 30)
		await _click(p)
		await _wait(0.4)
		_check(gs.players[me].hand.size() == hand_before, "1er clic : carte non jouée")
		_check(battle._selected_hand == target, "1er clic : carte sélectionnée")
		_shot("h2_carte_selectionnee")
		# 2e clic : la carte est jouée.
		p = target.get_global_rect().get_center() + Vector2(0, 30)
		await _click(p)
		await _wait(1.5)
		_check(gs.players[me].hand.size() == hand_before - 1, "2e clic : carte jouée")
	else:
		print("aucune carte jouable sans cible : étape 2 ignorée")

	# 3) Modes de tri.
	for m in ["cost", "attack", "health"]:
		battle._set_hand_sort(m)
		await _wait(0.4)
		var ok := true
		for i in battle._hand_views.size() - 1:
			if battle._hand_less(battle._hand_views[i + 1], battle._hand_views[i]):
				ok = false
		_check(ok, "tri « %s » respecté" % m)
		_shot("h3_tri_" + m)
	battle._set_hand_sort("manual")

	# 4) Chrono + revanche (écran de fin simulé en ligne).
	battle.mode = "client"
	gs.concede(1 - me)
	gs.pop_events()
	battle._show_game_over(me)
	await _wait(0.6)
	battle._on_rematch_changed("ask")
	await _wait(0.4)
	_shot("h4_revanche_demandee")
	_check(battle._clock.text.begins_with("Durée"), "chrono affiché : " + battle._clock.text)
	battle.mode = "ai"
	battle.queue_free()
	await _wait(0.3)

	# 5) Salon multijoueur (deux joueurs) et menu principal.
	Lobby.online = true
	Lobby.room = {"id": "r1", "name": "Partie de Hand", "host": {"name": "Hand", "avatar": 3, "border": "or", "title": "arcaniste"},
		"guest": {"name": "Bertrand", "avatar": 5, "border": "champion", "title": "champion"}}
	Lobby.role = "host"
	var mp: Node = load("res://scenes/multiplayer.tscn").instantiate()
	get_tree().root.add_child(mp)
	await _wait(0.8)
	mp._refresh()
	await _wait(0.4)
	_shot("h5_salon")
	mp.queue_free()
	Lobby.room = {}
	Lobby.role = ""
	Lobby.online = false
	await _wait(0.3)
	var menu: Node = load("res://scenes/main_menu.tscn").instantiate()
	get_tree().root.add_child(menu)
	await _wait(1.0)
	_shot("h6_menu")
	print("RÉSULTAT : %s (%d échec%s)" % ["OK" if _fails == 0 else "ÉCHEC", _fails, "s" if _fails > 1 else ""])
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, what: String) -> void:
	print(("  ok   " if cond else "  ÉCHEC ") + what)
	if not cond:
		_fails += 1


func _mouse_button(pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	Input.parse_input_event(e)
	await get_tree().process_frame
	await get_tree().process_frame


func _mouse_move(pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(e)
	await get_tree().process_frame


func _click(pos: Vector2) -> void:
	await _mouse_move(pos)
	await _wait(0.15)
	await _mouse_button(pos, true)
	await _mouse_button(pos, false)


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _shot(name: String) -> void:
	var path := _dir.path_join(name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("capture : ", path)
