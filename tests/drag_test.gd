extends Node
## Test (fenêtré) du plateau : glisser une carte sur le plateau la joue, sur la zone en bas à droite la défausse,
## dans la main la range ; case « Confirmer la fin du tour » ; pile de la bibliothèque (captures d'écran).
## Lancement : godot --path . res://tests/drag_test.tscn -- --profile=dragtest --server=127.0.0.1 --port=1 --shots-dir=C:/chemin

var _dir := "user://shots"
var _fails := 0
var battle: Node


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots-dir="):
			_dir = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_dir)
	Settings.set_hand_sort("manual")
	Settings.set_auto_end_turn(false)
	Settings.set_confirm_end_turn(true)
	await _wait(0.5)
	battle = load("res://scenes/battle.tscn").instantiate()
	get_tree().root.add_child(battle)
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
	# Main connue : un serviteur, un sort sans cible, un sort à cible, une carte à défausser.
	gs.players[me].hand.clear()
	for cv in battle._hand_views:
		cv.queue_free()
	battle._hand_views.clear()
	for id in ["chevalier", "golem", "boule_feu", "archer"]:
		gs._add_to_hand(gs.players[me], id)
	await battle._process_events(gs.pop_events(), true)
	battle.busy = false
	battle._refresh()
	await _wait(0.6)
	_check(battle._deck_piles[me].visible and battle._deck_pile_counts[me].text != "", "pile de la bibliothèque affichée (%s)" % battle._deck_pile_counts[me].text)
	var opp_pile: Control = battle._deck_piles[battle.opp]
	var opp_back: TextureRect = opp_pile.get_node("pile_back_2")
	_check(opp_pile.visible and opp_back.texture == battle._back_tex(battle.opp), "pile adverse affichée avec son dos de cartes (%s)" % battle._deck_pile_counts[battle.opp].text)
	_shot("d0_plateau")

	# 1) Glisser dans la main : range sans jouer.
	var n0: int = gs.players[me].hand.size()
	var cv: CardView = battle._hand_views[0]
	await _drag(cv, cv.get_global_rect().get_center() + Vector2(300, 0), "")
	_check(gs.players[me].hand.size() == n0, "glisser dans la main : carte non jouée")
	_check(battle._hand_views.find(cv) > 0, "glisser dans la main : carte déplacée")

	# 2) Glisser un serviteur sur le plateau : il est joué.
	cv = _hand_card("chevalier")
	var board_before: int = gs.players[me].board.size()
	await _drag(cv, Vector2(640, 420), "d1_glisser_plateau")
	await _idle()
	_check(gs.players[me].board.size() == board_before + 1, "serviteur glissé sur le plateau : joué")

	# 3) Sort à cible glissé sur le plateau : passe en ciblage.
	cv = _hand_card("boule_feu")
	await _drag(cv, Vector2(500, 300), "")
	await _wait(0.3)
	_check(not battle._targeting.is_empty(), "sort à cible glissé : mode ciblage")
	_shot("d2_ciblage")
	battle._cancel_targeting()
	await _wait(0.3)

	# 4) Glisser en bas à droite : défaussée.
	cv = _hand_card("archer")
	var grave_before: int = gs.players[me].graveyard.size()
	var dz: Rect2 = battle._discard_zone.get_global_rect()
	await _drag(cv, dz.get_center(), "d3_zone_defausse")
	await _idle()
	_check(_hand_card("archer") == null, "carte déposée en bas à droite : retirée de la main")
	_check(gs.players[me].graveyard.size() == grave_before + 1, "carte déposée en bas à droite : au cimetière")
	_check(not battle._discard_zone.visible, "zone de défausse masquée après le dépôt")

	# 5) Confirmer la fin du tour (cochée) : 1er appui = « Confirmer ».
	battle._refresh()
	await _wait(0.2)
	if battle._any_action:
		battle._on_end_turn_pressed()
		await _wait(0.2)
		_check(battle._end_confirm and gs.current == me, "case cochée : confirmation demandée")
		_shot("d4_confirmer")
		# Décochée : le tour se termine au 1er appui.
		Settings.set_confirm_end_turn(false)
		battle._end_confirm = false
		battle._refresh()
		battle._on_end_turn_pressed()
		await _wait(0.5)
		_check(gs.current != me, "case décochée : fin du tour immédiate")
	else:
		_check(false, "il devrait rester une action (golem jouable)")
	Settings.set_confirm_end_turn(true)
	get_tree().quit(1 if _fails > 0 else 0)


func _hand_card(id: String) -> CardView:
	for v in battle._hand_views:
		if v.card_id == id:
			return v
	return null


func _idle() -> void:
	for i in 60:
		await _wait(0.1)
		if not battle.busy:
			break
	await _wait(0.4)


func _drag(cv: CardView, to: Vector2, shot: String) -> void:
	var start: Vector2 = cv.get_global_rect().get_center() + Vector2(0, 20)
	await _mouse_move(start)
	await _wait(0.1)
	await _mouse_button(start, true)
	for k in 16:
		await _mouse_move(start.lerp(to, (k + 1) / 16.0))
	await _wait(0.2)
	if shot != "":
		_shot(shot)
	await _mouse_button(to, false)
	await _wait(0.4)


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


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _shot(name: String) -> void:
	var path := _dir.path_join(name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("capture : ", path)
