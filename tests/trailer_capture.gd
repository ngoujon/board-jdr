extends Node
## Séquences de jeu filmées pour la bande-annonce (IA des deux côtés, sans réseau).
## Enregistrement (images JPEG 1920 × 1080, temps fixe de 30 images/s, partie reproductible) :
##   godot --path . --fixed-fps 30 --resolution 1920x1080 res://tests/trailer_capture.tscn -- \
##     --profile=trailer --server=127.0.0.1 --port=1 --autoplay --frames-dir=<dossier>
## (Le Movie Maker de Godot enregistre à la taille logique 1280 × 720 : on capture donc nous-mêmes.)
## Chaque séquence affiche « [trailer] <nom> début=<image> » : sert au découpage (tools/trailer/build_trailer.py).

var battle: Node
var _frames_dir := ""
var _frame := 0


func _ready() -> void:
	seed(4242)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frames-dir="):
			_frames_dir = a.get_slice("=", 1)
	if _frames_dir != "":
		DirAccess.make_dir_recursive_absolute(_frames_dir)
		RenderingServer.frame_post_draw.connect(_save_frame)
	Settings.autoplay = true
	Settings.ai_difficulty = 2
	Settings.cosmetics_cache = {"equipped": {"title": "arcaniste", "border": "or", "card_back": "arcane", "board": "volcano"},
		"border": "or", "title": "arcaniste",
		"unlocked": {"title": ["arcaniste"], "avatar": [1, 2, 3, 4, 5, 6, 7, 8], "border": ["none", "or"],
			"card_back": ["default", "arcane"], "board": ["default", "volcano"]},
		"stats": {}}
	await _wait(0.5)
	await _sequence_draw()
	await _sequence_spells()
	await _sequence_natural()
	await _sequence_victory()
	_mark("fin")
	get_tree().quit()


func _process(_d: float) -> void:
	# L'autoplay de test défausse la carte la plus chère : désactivé pour garder les grands sorts.
	if is_instance_valid(battle) and battle.gs != null:
		battle._autoplay_discard_turn = battle.gs.turn_number


func _new_battle() -> void:
	if is_instance_valid(battle):
		battle.queue_free()
		await _wait(0.2)
	battle = load("res://scenes/battle.tscn").instantiate()
	get_tree().root.add_child(battle)
	for i in 400:
		if battle._started:
			break
		await _wait(0.05)


## Début de partie : la pièce, puis la pioche au choix.
func _sequence_draw() -> void:
	_mark("pioche")
	await _new_battle()
	for i in 200:
		if battle._choice_layer != null:
			break
		await _wait(0.1)
	await _wait(6.0)


## Plateaux remplis, main de grands sorts : l'IA du joueur les lance (effets 3D).
func _sequence_spells() -> void:
	await _new_battle()
	var gs = battle.gs
	var me: int = battle.me
	var opp: int = battle.opp
	# On attend notre tour, pioche faite (l'autoplay la choisit), puis on reprend la main.
	for i in 600:
		if battle._can_act():
			break
		await _wait(0.1)
	Settings.autoplay = false
	await _wait(1.0)
	while battle.busy:
		await _wait(0.1)
	for id in ["ogre", "golem", "gardien_cryptes", "tourmenteur", "chevalier_noir"]:
		gs._summon(opp, id)
	for id in ["paladine", "griffon", "templier"]:
		gs._summon(me, id)
	gs._place_enchant(me, "tour_mage")
	gs._place_enchant(opp, "cimetiere")
	# Main vidée (état et affichage) puis remplie de grands sorts.
	gs.players[me].hand.clear()
	for cv in battle._hand_views:
		cv.queue_free()
	battle._hand_views.clear()
	for id in ["blizzard", "eclair", "boule_feu", "meteores", "dragon"]:
		gs._add_to_hand(gs.players[me], id)
	gs.players[me].max_energy = 10
	gs.players[opp].max_energy = 10
	gs.current = me
	await battle._process_events(gs.pop_events(), true)
	battle.busy = false
	battle._refresh()
	await _wait(1.5)
	# Les sorts sont joués un par un (l'IA de test préfère souvent poser des serviteurs).
	_mark("sorts")
	for id in ["blizzard", "eclair", "boule_feu", "meteores", "dragon"]:
		gs.players[me].energy = 10
		var hc := {}
		for c in gs.players[me].hand:
			if c.card_id == id:
				hc = c
		if hc.is_empty():
			continue
		var target := -1
		if gs.needs_target(id):
			var foes: Array = gs.players[opp].board
			target = foes[0].uid if not foes.is_empty() else gs.players[opp].hero.uid
		battle._submit({"type": "play", "hand_uid": hc.uid, "target": target})
		await _wait(0.3)
		while battle.busy:
			await _wait(0.1)
		await _wait(1.2)
	# Attaques des serviteurs sur le héros adverse.
	for m in gs.players[me].board:
		if m.can_attack():
			battle._submit({"type": "attack", "attacker": m.uid, "defender": gs.players[opp].hero.uid})
			await _wait(0.3)
			while battle.busy:
				await _wait(0.1)
			await _wait(0.6)
	_mark("sorts_fin")
	await _wait(1.0)
	Settings.autoplay = true


## Partie naturelle, niveau Seigneur de guerre en face.
func _sequence_natural() -> void:
	_mark("partie")
	await _new_battle()
	await _wait_turns(10, 150.0)


## Fin de partie : le héros adverse est à terre, victoire.
func _sequence_victory() -> void:
	var gs = battle.gs
	if gs.is_over():
		await _new_battle()
		gs = battle.gs
	gs.pending_choice = {}
	var me: int = battle.me
	var opp: int = battle.opp
	gs.players[opp].hero.health = 3
	gs.players[opp].board.clear()
	gs.players[me].hand.clear()
	gs._add_to_hand(gs.players[me], "boule_feu")
	gs.players[me].energy = 10
	gs.players[me].max_energy = 10
	gs.current = me
	await battle._process_events(gs.pop_events(), true)
	battle.busy = false
	battle._refresh()
	_mark("victoire")
	for i in 300:
		if gs.is_over():
			break
		await _wait(0.1)
	await _wait(8.0)


func _wait_turns(turns: int, max_seconds: float) -> void:
	var start: int = battle.gs.turn_number
	var t := 0.0
	while t < max_seconds and not battle.gs.is_over() and battle.gs.turn_number < start + turns:
		await _wait(0.5)
		t += 0.5
	await _wait(1.5)


func _save_frame() -> void:
	var img := get_viewport().get_texture().get_image()
	if img.get_size() != Vector2i(1920, 1080):
		img.resize(1920, 1080, Image.INTERPOLATE_LANCZOS)
	img.save_jpg(_frames_dir.path_join("f%05d.jpg" % _frame), 0.93)
	_frame += 1


func _mark(name: String) -> void:
	print("[trailer] %s début=%d" % [name, _frame])


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout
