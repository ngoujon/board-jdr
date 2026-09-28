extends Node
## Test headless : parties IA contre IA + vérification du déterminisme (base du multijoueur).
## Lancement : godot --headless --path . res://tests/sim_test.tscn

func _ready() -> void:
	var games := 200
	var wins := [0, 0, 0]
	var total_turns := 0
	var errors := 0
	var stats := {"enchant": 0, "enchant_destroyed": 0, "discard": 0, "aura": 0, "enchant_trigger": 0, "destroy": 0, "minion_trigger": 0, "resurrect": 0, "recall": 0, "purge": 0}
	var hard_games := 0
	var hard_wins := 0
	for g in games:
		var seed_value := 1000 + g
		var first := g % 2
		var gs := GameState.new()
		gs.setup(first, seed_value)
		# Les 80 dernières parties : Chevalier (J0) contre Difficile (J1).
		var hard := g >= games - 80
		var ais := [AIPlayer.new(0, 1), AIPlayer.new(1, 2 if hard else g % 2)]
		var log: Array = []
		var guard := 0
		while not gs.is_over() and guard < 2000:
			guard += 1
			var p := gs.current
			var act: Dictionary = ais[p].next_action(gs)
			# Défausse occasionnelle pour tester la règle (et le rejeu).
			if act.type != "choose" and not gs.players[p].hand.is_empty() and (guard * 7 + g) % 23 == 0:
				act = {"type": "discard", "hand_uid": gs.players[p].hand[0].uid}
			var ok := false
			match act.type:
				"play":
					ok = gs.play_card(p, act.hand_uid, act.target)
				"attack":
					ok = gs.attack(act.attacker, act.defender)
				"discard":
					ok = gs.discard(p, act.hand_uid)
				"choose":
					ok = gs.choose_draw(p, act.index)
					if not ok:
						errors += 1
						print("ERREUR : choix de pioche refusé (partie %d)" % g)
						break
			if act.type == "end" or not ok:
				act = {"type": "end_turn"}
				gs.end_turn()
			log.append([p, act])
			for ev in gs.pop_events():
				if stats.has(ev.t):
					stats[ev.t] += 1
			_check_invariants(gs)
		if not gs.is_over():
			errors += 1
			print("ERREUR : partie %d non terminée" % g)
			continue
		wins[gs.winner] += 1
		if hard:
			hard_games += 1
			hard_wins += 1 if gs.winner == 1 else 0
		total_turns += gs.turn_number
		# Rejeu déterministe (comme le client en ligne).
		var replay := GameState.new()
		replay.setup(first, seed_value)
		for entry in log:
			var a: Dictionary = entry[1]
			match a.type:
				"play":
					replay.play_card(entry[0], a.hand_uid, a.target)
				"attack":
					replay.attack(a.attacker, a.defender)
				"choose":
					replay.choose_draw(entry[0], a.index)
				"discard":
					replay.discard(entry[0], a.hand_uid)
				"end_turn":
					replay.end_turn()
		if replay.winner != gs.winner or replay.players[0].hero.health != gs.players[0].hero.health \
				or replay.players[1].hero.health != gs.players[1].hero.health:
			errors += 1
			print("ERREUR : rejeu non déterministe pour la partie %d" % g)
	print("Parties : %d | victoires J0 : %d | J1 : %d | égalités : %d | tours moyens : %.1f | erreurs : %d"
		% [games, wins[0], wins[1], wins[2], float(total_turns) / games, errors])
	print("Difficile contre Chevalier : %d victoires sur %d" % [hard_wins, hard_games])
	print("Événements : ", stats)
	get_tree().quit(1 if errors > 0 else 0)


func _check_invariants(gs: GameState) -> void:
	if not gs.pending_choice.is_empty():
		assert(gs.pending_choice.player == gs.current)
		assert(gs.pending_choice.options.size() >= 2)
	for p in gs.players:
		assert(p.board.size() <= CardDB.MAX_BOARD)
		assert(p.hand.size() <= CardDB.MAX_HAND)
		assert(p.energy >= 0 and p.energy <= p.max_energy and p.max_energy <= CardDB.MAX_ENERGY)
		assert(p.enchants.size() <= CardDB.MAX_ENCHANTS)
		var aura_atk := 0
		for e in p.enchants:
			assert(e.health > 0)
			aura_atk += int(CardDB.get_card(e.card_id).get("aura", {}).get("attack", 0))
		for m in p.board:
			assert(m.health > 0)
			var expected := aura_atk
			for n in p.board:
				if n != m:
					expected += int(CardDB.get_card(n.card_id).get("aura", {}).get("attack", 0))
			if m.aura_atk != expected:
				push_error("aura incohérente : %s a %d, attendu %d" % [m.card_id, m.aura_atk, expected])
