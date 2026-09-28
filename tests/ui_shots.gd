extends Node
## Captures d'écran de contrôle : pioche au choix, enchantements, défausse, personnalisation, menus.
## Lancement (fenêtré) : godot --path . res://tests/ui_shots.tscn -- --profile=shots --name=Shots --shots-dir=C:/chemin

var _dir := "user://shots"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots-dir="):
			_dir = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_dir)
	# Profil de test : personnalisation « Champion » débloquée.
	Settings.cosmetics_cache = {"equipped": {"title": "arcaniste", "border": "or", "card_back": "arcane", "board": "volcano"},
		"border": "champion", "title": "arcaniste", "champion": true,
		"unlocked": {"title": ["novice", "ecuyer", "arcaniste", "champion"], "avatar": [1, 2, 3, 4, 5, 6, 7, 8, 11],
			"border": ["none", "bronze", "or", "champion"], "card_back": ["default", "arcane"], "board": ["default", "volcano", "forest"]},
		"stats": {"games": 12, "wins": 8, "spells_played": 120, "minions_played": 60, "hero_damage": 230}}
	await _wait(0.5)
	var battle: Node = load("res://scenes/battle.tscn").instantiate()
	get_tree().root.add_child(battle)
	await _wait(1.0)
	_shot("0a_piece_en_vol")
	await _wait(1.9)
	_shot("0b_piece_resultat")
	for i in 240:
		if battle._choice_layer != null:
			break
		await _wait(0.25)
	await _wait(1.0)
	_shot("1_choix")
	battle._peek_board()
	await _wait(0.4)
	_shot("1b_tab_plateau")
	battle._back_to_choice()
	battle._close_choice()
	battle.gs.pending_choice = {}
	var me: int = battle.me
	var opp: int = battle.opp
	battle.gs._place_enchant(me, "etendard")
	battle.gs._place_enchant(me, "tour_mage")
	battle.gs._place_enchant(opp, "autel_vie")
	battle.gs._summon(me, "porte_etendard")
	battle.gs._summon(me, "guerisseuse")
	battle.gs._summon(me, "paladine")
	battle.gs._summon(opp, "tourmenteur")
	battle.gs._heal(battle.gs.players[me].hero, 6)
	battle.gs._summon(opp, "chevalier")
	await battle._process_events(battle.gs.pop_events(), true)
	battle.gs.current = me
	battle.busy = false
	battle._refresh()
	await _wait(0.6)
	if not battle._hand_views.is_empty():
		battle._on_hand_card_hovered(battle._hand_views[0], true)
	await _wait(0.5)
	_shot("2_enchantements")
	battle._discard_btn.pressed.emit()
	await _wait(0.3)
	_shot("3_defausse_confirmer")
	battle._discard_btn.pressed.emit()
	await _wait(0.8)
	for m in battle.gs.players[opp].board:
		battle.gs._damage(m, 20)
	battle.gs._resolve_deaths()
	await battle._process_events(battle.gs.pop_events(), true)
	await _wait(0.5)
	_shot("3b_compteurs")
	battle._on_deck_pressed(battle._hero_views[me])
	await _wait(0.5)
	_shot("3c_bibliotheque")
	for c in battle._overlay.get_children():
		if c is PileViewer:
			c.queue_free()
	battle._on_grave_pressed(battle._hero_views[me])
	await _wait(0.5)
	_shot("3d_cimetiere")
	battle.queue_free()
	await _wait(0.3)

	var coll: Node = load("res://scenes/collection.tscn").instantiate()
	get_tree().root.add_child(coll)
	await _wait(1.0)
	coll._filter = "enchantment"
	coll._fill_grid()
	coll._select("forge")
	await _wait(0.6)
	_shot("4_collection_enchantements")
	coll._filter = "all"
	coll._fill_grid()
	coll._select("goule")
	await _wait(0.6)
	_shot("4b_collection_goule")
	coll.queue_free()
	await _wait(0.3)

	var menu: Node = load("res://scenes/main_menu.tscn").instantiate()
	get_tree().root.add_child(menu)
	await _wait(1.2)
	_shot("5_menu")
	menu._on_play()
	await _wait(0.4)
	_shot("5b_difficulte")
	menu.on_escape()
	Lobby.online = true
	Lobby.profile = {"name": "Shots"}
	Lobby.friends = [{"name": "Morgane", "avatar": 3, "status": "online", "border": "or", "title": "arcaniste"},
		{"name": "Bertrand", "avatar": 5, "status": "offline"}]
	Lobby.unread = {"Bertrand": 2}
	Lobby.unread_changed.emit()
	await _wait(0.3)
	_shot("5c_menu_non_lus")
	Lobby.open_messages("Morgane")
	await _wait(0.3)
	var now := int(Time.get_unix_time_from_system())
	Lobby.dm_history_received.emit("Morgane", [
		{"from": "Morgane", "text": "Salut ! Une partie ce soir ?", "ts": now - 90000},
		{"from": "Shots", "text": "Carrément, je teste le nouveau deck [cimetière] d'abord", "ts": now - 600},
		{"from": "Morgane", "text": "Ok, invite-moi quand tu es prêt·e", "ts": now - 60}])
	Lobby._show_dm_notice("Bertrand", "Bien joué pour la partie d'hier, revanche quand tu veux !")
	await _wait(0.5)
	_shot("9_messages")
	assert(PauseMenu.close_top_modal())
	await _wait(0.3)
	assert(not is_instance_valid(Lobby._messages_panel) or Lobby._messages_panel.is_queued_for_deletion())
	_shot("9b_apres_echap")
	# Statistiques globales, recherche dans le classement, profil d'un joueur.
	var stats := StatsPanel.new()
	menu.add_child(stats)
	await _wait(0.2)
	var cards := []
	var k := 0
	for id in CardDB.COLLECTION_ORDER:
		k += 1
		cards.append({"card": id, "plays": 200 - k * 3, "games": 120 - k, "wins": 60 - (k * 7) % 25})
	Lobby.global_stats_received.emit({"mode": "all", "games": 1342, "by_mode": {"pvp": 512, "ai": 830},
		"avg_turns": 17.4, "avg_duration": 612, "first_games": 1300, "first_wins": 684, "sides": 2684,
		"ai": [{"difficulty": 0, "games": 200, "player_wins": 170}, {"difficulty": 1, "games": 450, "player_wins": 240},
			{"difficulty": 2, "games": 180, "player_wins": 61}], "cards": cards})
	await _wait(0.5)
	_shot("10_statistiques")
	stats.queue_free()
	var lb := LeaderboardPanel.new()
	menu.add_child(lb)
	await _wait(0.2)
	lb._search.text = "mor"
	lb._query = "mor"
	Lobby.players_found.emit("mor", [{"name": "Morgane", "avatar": 3, "border": "or", "title": "arcaniste", "rank": 4,
		"wins": 31, "losses": 12, "winrate": 72.1, "ai_wins": 40, "ai_losses": 9, "ai_winrate": 81.6, "online": true}])
	await _wait(0.4)
	_shot("11_classement_recherche")
	var prof := PlayerProfilePanel.new("Morgane")
	lb.add_child(prof)
	await _wait(0.2)
	Lobby.player_profile_received.emit({"name": "Morgane", "avatar": 3, "border": "or", "title": "arcaniste", "rank": 4,
		"online": true, "wins": 31, "losses": 12, "ai_wins": 40, "ai_losses": 9, "draws": 1, "games": 93, "streak": 3,
		"best_streak": 9, "friend": true, "stats": {"minions_played": 610, "spells_played": 240, "enchants_played": 35,
		"enchants_destroyed": 12, "hero_damage": 1830},
		"favorites": [{"card": "goule", "plays": 41}, {"card": "boule_feu", "plays": 37}, {"card": "templier", "plays": 30}]})
	var hist := []
	for i in 12:
		hist.append({"ts": now - i * 7200, "mode": "pvp" if i % 3 else "ai", "opponent": "Bertrand" if i % 3 else "IA Seigneur de guerre",
			"result": "win" if i % 2 else "loss", "turns": 12 + i, "duration": 420 + i * 30, "reason": "normal", "id": 100 + i, "replay": i < 8})
	Lobby.history_received.emit("Morgane", 93, hist)
	await _wait(0.5)
	_shot("12_profil_joueur")
	lb.queue_free()
	Lobby.online = false
	Lobby.friends = []
	Lobby.unread = {}
	var panel := CustomizePanel.new()
	menu.add_child(panel)
	await _wait(0.6)
	_shot("6_perso_titres")
	panel._tabs.current_tab = 2
	await _wait(0.4)
	_shot("7_perso_contours")
	panel._tabs.current_tab = 4
	await _wait(0.4)
	_shot("8_perso_plateaux")
	# Replay : la partie d'exemple est rejouée (barre de contrôle en haut).
	menu.queue_free()
	var f := FileAccess.open("res://tests/sample_replay.json", FileAccess.READ)
	Net.mode = "replay"
	Net.replay = JSON.parse_string(f.get_as_text())
	Net.replay["view"] = 0
	var rb: Node = load("res://scenes/battle.tscn").instantiate()
	get_tree().root.add_child(rb)
	await _wait(9.0)
	_shot("13_replay")
	get_tree().quit()


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _shot(name: String) -> void:
	var path := _dir.path_join(name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("capture : ", path)
