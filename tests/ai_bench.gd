extends Node
## Banc d'essai de l'IA : Difficile (2) contre Chevalier (1), sièges alternés.
## Lancement : godot --headless --path . res://tests/ai_bench.tscn -- --games=200

func _ready() -> void:
	var games := 200
	var a_diff := 2
	var b_diff := 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--games="):
			games = int(arg.get_slice("=", 1))
		elif arg.begins_with("--a="):
			a_diff = int(arg.get_slice("=", 1))
		elif arg.begins_with("--b="):
			b_diff = int(arg.get_slice("=", 1))
	var a_wins := 0
	var t0 := Time.get_ticks_msec()
	for g in games:
		var gs := GameState.new()
		var a_seat := (g / 2) % 2
		var bonus := {}
		if a_diff >= 3:
			bonus = AIPlayer.challenger_bonus(a_seat)
		gs.setup(g % 2, 5000 + g, bonus)
		var ais := [null, null]
		ais[a_seat] = AIPlayer.new(a_seat, a_diff)
		ais[1 - a_seat] = AIPlayer.new(1 - a_seat, b_diff)
		var guard := 0
		while not gs.is_over() and guard < 3000:
			guard += 1
			var p := gs.current
			var act: Dictionary = ais[p].next_action(gs)
			var ok := false
			match act.type:
				"play":
					ok = gs.play_card(p, act.hand_uid, act.target)
				"attack":
					ok = gs.attack(act.attacker, act.defender)
				"choose":
					ok = gs.choose_draw(p, act.index)
			if act.type == "end" or not ok:
				gs.end_turn()
			gs.pop_events()
		if gs.winner == a_seat:
			a_wins += 1
	print("IA %d contre IA %d : %d victoires sur %d (%.0f %%) en %.1f s" % [a_diff, b_diff, a_wins, games,
		100.0 * a_wins / games, (Time.get_ticks_msec() - t0) / 1000.0])
	get_tree().quit()
