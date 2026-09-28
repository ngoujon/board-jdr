extends Node
## Captures de contrôle 2.0 : coches vertes et Inferno dans le menu, classement (onglets, tri), partie Inferno
## (PV infinis, score, fin du tour automatique), passe de combat à récupérer, pluie de PO, révélation d'objet.
## Lancement (fenêtré, hors ligne) : godot --path . res://tests/shots20.tscn -- --profile=shots20 --server=127.0.0.1 --port=1 --shots-dir=C:/chemin

var _dir := "user://shots"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots-dir="):
			_dir = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_dir)
	Settings.ai_beaten = [0, 1]
	Settings.inferno_best = 42
	var now := int(Time.get_unix_time_from_system())
	var seasons: Dictionary = Cosmetics.data().get("seasons", {})
	Lobby.profile = {"name": "Shots20", "gold": 820, "stats": {"ai_beaten_2": 1},
		"season": {"n": 1, "start": now - 86400 * 3, "end": now + 86400 * 27, "xp": 250 * 6 + 140, "level": 6,
			"levels": 30, "xp_per_level": 250, "name": "L'Éveil", "rewards": seasons.rewards["1"], "games": 12,
			"claimed": [1, 2, 3], "claimable": [4, 5, 6]},
		"equipped": {"title": "vainqueur_challenger", "border": "ia_challenger", "card_back": "challenger", "board": "challenger"},
		"unlocked": {"title": ["novice", "vainqueur_challenger"], "avatar": [1], "border": ["none", "ia_challenger"],
			"card_back": ["default", "challenger"], "board": ["default", "challenger"]},
		"border": "ia_challenger", "title": "vainqueur_challenger"}
	await _wait(0.5)
	var menu: Node = load("res://scenes/main_menu.tscn").instantiate()
	get_tree().root.add_child(menu)
	await _wait(0.4)
	Lobby.profile_changed.emit()
	await _wait(0.5)
	_shot("20_1_menu_passe")
	menu._on_play()
	await _wait(0.4)
	_shot("20_2_niveaux_coches")

	var lb := LeaderboardPanel.new()
	menu.add_child(lb)
	await _wait(0.3)
	lb._set_rows([
		{"name": "Rakcha", "avatar": 3, "wins": 12, "losses": 4, "winrate": 75.0, "ai_wins": 20, "ai_losses": 5, "ai_winrate": 80.0, "inferno": 57, "inferno_games": 4, "inferno_ts": now - 86400},
		{"name": "Dupond", "avatar": 15, "wins": 9, "losses": 6, "winrate": 60.0, "ai_wins": 31, "ai_losses": 2, "ai_winrate": 93.9, "inferno": 124, "inferno_games": 9, "inferno_ts": now - 3600, "me": true, "title": "vainqueur_challenger", "border": "ia_challenger"},
		{"name": "Munkey", "avatar": 7, "wins": 2, "losses": 9, "winrate": 18.2, "ai_wins": 4, "ai_losses": 8, "ai_winrate": 33.3, "inferno": 0, "inferno_games": 0, "inferno_ts": 0}])
	await _wait(0.3)
	_shot("20_3_classement_general")
	lb._sort_by("inferno")
	await _wait(0.3)
	_shot("20_4_classement_tri_inferno")
	lb._set_tab("inferno")
	await _wait(0.3)
	_shot("20_5_classement_onglet_inferno")
	lb.queue_free()

	var bp := BattlePassPanel.new()
	menu.add_child(bp)
	await _wait(0.6)
	_shot("20_6_passe_a_recuperer")
	Lobby.fx.coins(90, Vector2(400, 300), Vector2(1000, 60))
	await _wait(0.45)
	_shot("20_7_pluie_de_po")
	await _wait(1.5)
	bp.queue_free()
	Lobby.fx.reveal([{"kind": "card_back", "id": "challenger"}, {"kind": "border", "id": "ia_challenger"}])
	await _wait(1.6)
	_shot("20_8_revelation_dos")
	Lobby.fx._close(Lobby.fx.get_child(Lobby.fx.get_child_count() - 1))
	await _wait(2.0)
	_shot("20_9_revelation_contour")
	Lobby.fx._close(Lobby.fx.get_child(Lobby.fx.get_child_count() - 1))
	await _wait(0.5)
	menu.queue_free()

	# Partie Inferno (hors ligne) : PV infinis, score, case « fin du tour automatique ».
	Net.mode = "ai"
	Settings.ai_difficulty = 4
	var b: Node = load("res://scenes/battle.tscn").instantiate()
	get_tree().root.add_child(b)
	for i in 240:
		if b._choice_layer != null:
			break
		await _wait(0.25)
	await _wait(0.8)
	b._close_choice()
	b.gs.pending_choice = {}
	b.gs._damage(b.gs.players[b.opp].hero, 7)
	b.gs._damage(b.gs.players[b.opp].hero, 5)
	await b._process_events(b.gs.pop_events(), true)
	b.busy = false
	b._refresh()
	await _wait(0.8)
	_shot("20_10_partie_inferno")
	b.gs.concede(b.me)
	await b._process_events(b.gs.pop_events(), true)
	await _wait(1.5)
	_shot("20_11_fin_inferno")
	get_tree().quit()


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _shot(name: String) -> void:
	var path := _dir.path_join(name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("capture : ", path)
