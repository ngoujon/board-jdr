extends Node
## Mode Inferno : partie complète IA contre IA (le joueur 0 joue avec l'IA Seigneur de guerre),
## puis vérification par MatchCheck (même score, même vainqueur). Sans affichage :
## godot --headless --path . res://tests/inferno_test.tscn


func _ready() -> void:
	var ok := true
	for seed_value in [11, 222, 3333]:
		ok = _one(seed_value) and ok
	print("INFERNO : ", "OK" if ok else "ÉCHEC")
	get_tree().quit(0 if ok else 1)


func _one(seed_value: int) -> bool:
	var gs := GameState.new()
	var ai_idx := 1
	var bonus := AIPlayer.inferno_bonus(ai_idx)
	gs.setup(seed_value % 2, seed_value, bonus)
	var bot := AIPlayer.new(ai_idx, 4)
	bot._rng.seed = MatchCheck.ai_seed(seed_value)
	var me := AIPlayer.new(0, 2)
	me._rng.seed = 99
	var actions := []
	var start_hp := gs.players[ai_idx].hero.health
	var guard := 0
	while not gs.is_over() and guard < 3000:
		guard += 1
		var p := gs.current if gs.pending_choice.is_empty() else int(gs.pending_choice.player)
		var act: Dictionary = (bot if p == ai_idx else me).next_action(gs)
		if act.get("type", "") == "end":
			act = {"type": "end_turn"}
		if not MatchCheck.apply_action(gs, p, act):
			act = {"type": "end_turn"}
			MatchCheck.apply_action(gs, p, act)
		actions.append(MatchCheck.encode(p, act))
		gs.pop_events()
	var res := MatchCheck.verify_ai({"seed": seed_value, "first": seed_value % 2, "bonus": bonus, "difficulty": 4,
		"ai": ai_idx, "actions": actions})
	print("  fin=%s gagnant=%d pv_ia=%d/%d" % [gs.is_over(), gs.winner, gs.players[ai_idx].hero.health, start_hp])
	var good: bool = gs.is_over() and gs.winner == ai_idx and gs.players[ai_idx].hero.health == start_hp \
		and res.get("ok", false) and int(res.get("score", -1)) == gs.inferno_damage
	print("graine %d : %d tours, score %d, vérif %s (score %s) -> %s" % [seed_value, gs.turn_number, gs.inferno_damage,
		res.get("ok", false), res.get("score", "?"), "OK" if good else "ÉCHEC " + str(res.get("error", ""))])
	return good
