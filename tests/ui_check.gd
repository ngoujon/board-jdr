extends Node
## Test (fenêtré, hors ligne) : classement « Contre l'IA » (score pondéré par la difficulté), survol d'une carte
## dans les statistiques, recherche dans la collection (captures d'écran).
## Lancement : godot --path . res://tests/ui_check.tscn -- --profile=uicheck --server=127.0.0.1 --port=1 --shots-dir=C:/chemin

var _dir := "user://shots"
var _fails := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots-dir="):
			_dir = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_dir)
	await _wait(0.5)

	# 1) Classement : « Facile » gagne tout en Apprenti, « Brave » gagne la moitié contre le Challenger.
	var lb := LeaderboardPanel.new()
	get_tree().root.add_child(lb)
	await _wait(0.3)
	lb._set_rows([
		{"name": "Facile", "avatar": 3, "wins": 0, "losses": 0, "winrate": 0.0, "ai_wins": 40, "ai_losses": 0, "ai_winrate": 100.0,
			"ai_levels": [[40, 0], [0, 0], [0, 0], [0, 0]], "ai_score": 25.0},
		{"name": "Brave", "avatar": 15, "wins": 0, "losses": 0, "winrate": 0.0, "ai_wins": 12, "ai_losses": 8, "ai_winrate": 60.0,
			"ai_levels": [[2, 0], [3, 1], [2, 2], [5, 5]], "ai_score": 45.5, "me": true},
		{"name": "Novice", "avatar": 7, "wins": 0, "losses": 0, "winrate": 0.0, "ai_wins": 2, "ai_losses": 1, "ai_winrate": 66.7,
			"ai_levels": [[2, 1], [0, 0], [0, 0], [0, 0]], "ai_score": -1}])
	lb._set_tab("ai")
	await _wait(0.4)
	var first := ""
	for row in lb._list.get_children():
		for n in row.find_children("*", "", true, false):
			if (n is Button or n is Label) and n.text.strip_edges() != "" and not n.text.strip_edges().is_valid_int():
				first = n.text.strip_edges()
				break
		break
	_check(first.begins_with("Brave"), "onglet Contre l'IA : Brave (Challenger) devant Facile (Apprenti) : %s" % first)
	_shot("u1_classement_ia")
	lb.queue_free()

	# 2) Statistiques : survol d'une ligne -> carte + infobulles.
	var sp := StatsPanel.new()
	get_tree().root.add_child(sp)
	await _wait(0.3)
	sp._on_stats({"mode": "all", "games": 50, "by_mode": {"pvp": 20, "ai": 30}, "sides": 100,
		"cards": [{"card": "dragon", "plays": 30, "games": 25, "wins": 15}, {"card": "gardien_cryptes", "plays": 20, "games": 18, "wins": 9},
			{"card": "boule_feu", "plays": 44, "games": 30, "wins": 16}]})
	await _wait(0.3)
	var row: Control = sp._list.get_child(1)
	row.mouse_entered.emit()
	await _wait(0.4)
	_check(sp._preview.visible and sp._tips.visible, "statistiques : carte et infobulles au survol")
	_shot("u2_stats_survol")
	row.mouse_exited.emit()
	await _wait(0.1)
	_check(not sp._preview.visible, "statistiques : carte masquée en quittant la ligne")
	sp.queue_free()

	# 3) Collection : recherche.
	var col: Node = load("res://scenes/collection.tscn").instantiate()
	get_tree().root.add_child(col)
	await _wait(0.5)
	var all: int = col._grid.get_child_count()
	col._search.text = "provoc"
	col._search.text_changed.emit("provoc")
	await _wait(0.3)
	var n: int = _visible_cards(col)
	_check(n > 0 and n < all, "collection : recherche « provoc » (%d / %d cartes)" % [n, all])
	_shot("u3_collection_recherche")
	col._search.text = "dragon anc"
	col._search.text_changed.emit("dragon anc")
	await _wait(0.3)
	_check(_visible_cards(col) == 1, "collection : « dragon anc » -> 1 carte")
	col._search.text = "zzzz"
	col._search.text_changed.emit("zzzz")
	await _wait(0.3)
	_check(_visible_cards(col) == 0 and col._no_result.visible, "collection : aucun résultat affiché")
	col.queue_free()

	# 3b) Personnalisation : les récompenses de la saison 2 restent cachées pendant la saison 1.
	var cp := CustomizePanel.new()
	get_tree().root.add_child(cp)
	await _wait(0.5)
	var hidden := true
	var season1 := false
	for node in cp.find_children("*", "", true, false):
		if node is Control and node.tooltip_text != "":
			if node.tooltip_text.contains("saison 2"):
				hidden = false
			if node.tooltip_text.contains("saison 1"):
				season1 = true
	_check(season1 and hidden, "personnalisation : saison 1 visible, saison 2 masquée")
	cp.queue_free()

	# 4) Récompense de titre : la condition d'obtention est affichée.
	Lobby.fx.reveal([{"kind": "title", "id": "vainqueur_challenger"}])
	await _wait(1.6)
	var shown := false
	for l in Lobby.fx.find_children("*", "Label", true, false):
		if l.text.contains("Challenger") and l.text.contains(":"):
			shown = true
	_check(shown, "récompense de titre : condition d'obtention affichée")
	_shot("u4_recompense_titre")
	get_tree().quit(1 if _fails > 0 else 0)


func _visible_cards(col: Node) -> int:
	var k := 0
	for c in col._grid.get_children():
		if not c.is_queued_for_deletion():
			k += 1
	return k


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
