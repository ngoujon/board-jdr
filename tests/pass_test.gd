extends Node
## Test (fenêtré, hors ligne) du passe de combat : récompenses récupérées grisées, clic sur une case à récupérer.
## Lancement : godot --path . res://tests/pass_test.tscn -- --profile=passtest --server=127.0.0.1 --port=1 --shots-dir=C:/chemin

var _dir := "user://shots"
var _fails := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots-dir="):
			_dir = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_dir)
	var now := int(Time.get_unix_time_from_system())
	var seasons: Dictionary = Cosmetics.data().get("seasons", {})
	Lobby.profile = {"name": "PassTest", "gold": 820,
		"season": {"n": 1, "start": now - 86400 * 3, "end": now + 86400 * 27, "xp": 250 * 6 + 140, "level": 6,
			"levels": 30, "xp_per_level": 250, "name": "L'Éveil", "rewards": seasons.rewards["1"], "games": 12,
			"claimed": [1, 2, 3], "claimable": [4, 5, 6]}}
	await _wait(0.5)
	var bp := BattlePassPanel.new()
	get_tree().root.add_child(bp)
	await _wait(0.6)
	var tiles := _tiles(bp)
	_check(tiles.size() >= 6, "cases du passe (%d)" % tiles.size())
	_check(tiles[0].material != null and tiles[2].material != null, "niveaux 1 à 3 récupérés : cases grisées")
	_check(tiles[3].material == null and tiles[6].material == null, "niveaux 4 et 7 : non grisés")
	_shot("p1_passe")
	# Clic au milieu de la case du niveau 4 (sur la récompense, pas sur le bouton).
	var t: Control = tiles[3]
	var pos := t.get_global_rect().position + Vector2(t.size.x / 2, 60)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = pos
	e.global_position = pos
	Input.parse_input_event(e)
	await get_tree().process_frame
	await get_tree().process_frame
	var btn: Button = null
	for n in t.find_children("*", "Button", true, false):
		btn = n
	_check(btn != null and btn.disabled, "clic sur la récompense : récupération demandée")
	get_tree().quit(1 if _fails > 0 else 0)


func _tiles(root: Node) -> Array:
	for g in root.find_children("*", "GridContainer", true, false):
		return g.get_children()
	return []


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
