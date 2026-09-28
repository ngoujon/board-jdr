extends Node
## Captures de contrôle 1.8 : menu d'accueil (saison, icônes), passe de combat, boutique, cadres, fin de partie.
## Lancement (fenêtré) : godot --path . res://tests/shots18.tscn -- --profile=shots --name=Shots --shots-dir=C:/chemin

var _dir := "user://shots"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots-dir="):
			_dir = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_dir)
	var now := int(Time.get_unix_time_from_system())
	var seasons: Dictionary = Cosmetics.data().get("seasons", {})
	Lobby.online = true
	Lobby.profile = {"name": "Shots", "gold": 820,
		"season": {"n": 1, "start": now - 86400 * 3, "end": now + 86400 * 27 + 3600 * 5, "xp": 250 * 7 + 140, "level": 7,
			"levels": 30, "xp_per_level": 250, "name": "L'Éveil", "rewards": seasons.rewards["1"], "games": 12},
		"equipped": {"title": "obstine", "border": "emeraude", "card_back": "nuit", "board": "glacier"},
		"unlocked": {"title": ["novice", "obstine"], "avatar": [1, 2, 3], "border": ["none", "emeraude"],
			"card_back": ["default", "nuit", "aube"], "board": ["default", "glacier"]},
		"stats": {"games": 25}, "border": "emeraude", "title": "obstine"}
	Settings.cosmetics_cache = Lobby.profile.duplicate(true)
	await _wait(0.5)
	var menu: Node = load("res://scenes/main_menu.tscn").instantiate()
	get_tree().root.add_child(menu)
	await _wait(0.3)
	Lobby.profile_changed.emit()
	await _wait(1.0)
	_shot("18_1_menu")
	var bp := BattlePassPanel.new()
	menu.add_child(bp)
	await _wait(0.6)
	_shot("18_2_passe")
	bp.queue_free()
	var shop := ShopPanel.new()
	menu.add_child(shop)
	await _wait(0.6)
	_shot("18_3_boutique_dos")
	shop._tabs.current_tab = 3
	await _wait(0.5)
	_shot("18_4_boutique_cadres")
	shop._tabs.current_tab = 1
	await _wait(0.5)
	_shot("18_5_boutique_plateaux")
	shop.queue_free()
	var cp := CustomizePanel.new()
	menu.add_child(cp)
	await _wait(0.4)
	cp._tabs.current_tab = cp._tabs.get_tab_count() - 1
	await _wait(0.5)
	_shot("18_6_perso_cadres")
	cp._tabs.current_tab = 0
	await _wait(0.4)
	_shot("18_7_perso_titres")
	cp.queue_free()
	PauseMenu.open()
	await _wait(0.4)
	_shot("18_8_parametres")
	PauseMenu.close_top_modal()
	menu.queue_free()
	# Partie contre l'IA Challenger : cadre « or » en main, ligne de récompense en fin de partie.
	Net.mode = "ai"
	Settings.ai_difficulty = 3
	var battle: Node = load("res://scenes/battle.tscn").instantiate()
	get_tree().root.add_child(battle)
	for i in 240:
		if battle._choice_layer != null:
			break
		await _wait(0.25)
	await _wait(0.8)
	battle._close_choice()
	battle.gs.pending_choice = {}
	battle.gs._summon(battle.me, "chevalier")
	await battle._process_events(battle.gs.pop_events(), true)
	battle.busy = false
	battle._refresh()
	await _wait(0.8)
	_shot("18_9_partie_challenger")
	battle.gs.concede(battle.opp)
	await battle._process_events(battle.gs.pop_events(), true)
	await _wait(1.5)
	Lobby.reward_received.emit({"t": "reward", "po": 25, "bonus": 20, "pass_po": 30, "xp": 150, "gold": 895, "level": 8,
		"level_up": true, "result": "win"})
	await _wait(1.0)
	_shot("18_10_fin_recompense")
	get_tree().quit()


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _shot(name: String) -> void:
	var path := _dir.path_join(name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("capture : ", path)
