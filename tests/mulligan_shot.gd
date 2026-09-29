extends Node
## Captures du changement de main (mode Inferno) : bouton au premier tour, puis nouvelle main.
## Lancement (fenêtré) : godot --path . res://tests/mulligan_shot.tscn -- --profile=shots --server=127.0.0.1 --port=1 --shots-dir=C:/chemin

var _dir := "user://shots"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots-dir="):
			_dir = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_dir)
	Settings.ai_difficulty = 4
	Settings.auto_end_turn = true
	await _wait(0.5)
	var battle: Node = load("res://scenes/battle.tscn").instantiate()
	get_tree().root.add_child(battle)
	for i in 240:
		if battle._can_choose() and battle._choice_layer != null:
			break
		await _wait(0.25)
	await _wait(1.0)
	_shot("0a_choix")
	battle._peek_board()
	await _wait(0.5)
	_shot("0b_plateau")
	battle._back_to_choice()
	await _wait(0.3)
	battle._submit({"type": "choose", "index": 0})
	for i in 40:
		if battle._can_act():
			break
		await _wait(0.25)
	await _wait(1.5)
	_shot("1_bouton_changer_de_main")
	battle._mulligan_btn.pressed.emit()
	await _wait(0.3)
	_shot("2_confirmer")
	battle._mulligan_btn.pressed.emit()
	await _wait(3.0)
	_shot("3_nouvelle_main")
	battle._open_suggestions()
	await _wait(1.5)
	_shot("3b_suggestion_en_partie")
	battle.queue_free()
	await _wait(0.3)
	var menu: Node = load("res://scenes/main_menu.tscn").instantiate()
	get_tree().root.add_child(menu)
	await _wait(1.5)
	_shot("4_accueil")
	var sp := SuggestionPanel.new()
	menu.add_child(sp)
	await _wait(1.5)
	_shot("5_liste")
	sp._search.text = "revanche"
	sp._request_list()
	await _wait(1.0)
	_shot("5b_recherche")
	Lobby.request_sugg_thread(1)
	await _wait(1.0)
	_shot("6_fil")
	sp._open_new()
	sp._kind = "bug"
	sp._rows["goule"].button_pressed = true
	sp._update_form()
	await _wait(0.3)
	_shot("7_nouveau_sujet")
	get_tree().quit()


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png(_dir.path_join(name + ".png"))


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout
