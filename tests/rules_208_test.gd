extends Node
## Règles 2.0.8 : changement de main au premier tour, fatigue et soins de l'IA en mode Inferno.
## Lancement : godot --headless --path . res://tests/rules_208_test.tscn -- --profile=rulestest --server=127.0.0.1 --port=1

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  ÉCHEC ") + what)
	if not ok:
		_fails += 1


func _ready() -> void:
	# --- Changement de main
	var gs := GameState.new()
	gs.setup(0, 4321)
	gs.choose_draw(0, 0)
	var p = gs.players[0]
	var n: int = p.hand.size()
	var old_ids: Array = []
	for hc in p.hand:
		old_ids.append(hc.card_id)
	var grave_before: int = p.graveyard.size()
	_check(gs.can_mulligan(0), "changement de main possible au premier tour")
	_check(not gs.can_mulligan(1), "impossible pour l'adversaire pendant votre tour")
	_check(MatchCheck.apply_action(gs, 0, {"type": "mulligan"}), "action « mulligan » acceptée")
	_check(p.hand.size() == n - 1, "nouvelle main d'une carte de moins (%d -> %d)" % [n, p.hand.size()])
	_check(p.graveyard.size() == grave_before + n, "ancienne main au cimetière (%d cartes)" % (p.graveyard.size() - grave_before))
	_check(not gs.can_mulligan(0), "une seule fois")
	_check(MatchCheck.decode(MatchCheck.encode(0, {"type": "mulligan"})).get("type", "") == "mulligan", "encodage « m »")
	# Après une défausse : plus possible ; au 2e tour : plus possible.
	var gs2 := GameState.new()
	gs2.setup(0, 99)
	gs2.choose_draw(0, 0)
	gs2.discard(0, gs2.players[0].hand[0].uid)
	_check(not gs2.can_mulligan(0), "impossible après une autre action")
	gs2.end_turn()
	_check(gs2.current == 1 and gs2.players[1].mulligan_ready, "le second joueur peut changer de main à son premier tour")
	gs2.choose_draw(1, 0)
	gs2.end_turn()
	gs2.choose_draw(0, 0)
	_check(not gs2.can_mulligan(0), "impossible au deuxième tour")
	var copy := gs2.clone(1)
	_check(copy.players[1].turns == gs2.players[1].turns, "clone : compteur de tours copié")

	# --- Inferno : fatigue et soins
	var gi := GameState.new()
	gi.setup(0, 7, AIPlayer.inferno_bonus(1))
	var ai = gi.players[1]
	ai.deck.clear()
	gi._draw(ai)
	gi._draw(ai)
	_check(gi.inferno_damage == 3, "fatigue de l'IA comptée dans le score (1 + 2 = %d)" % gi.inferno_damage)
	gi._heal(ai.hero, 2)
	_check(gi.inferno_damage == 1, "soin de l'IA : score diminué (%d)" % gi.inferno_damage)
	gi._heal(ai.hero, 5)
	_check(gi.inferno_damage == 0, "le score ne descend pas sous 0")
	var heal_ev := false
	for ev in gi.pop_events():
		if ev.t == "heal" and ev.has("inferno"):
			heal_ev = true
	_check(heal_ev, "événement de soin avec le score Inferno")

	# --- Vérification d'une partie IA complète avec changement de main (joueur 0 joue comme l'IA)
	var job := _play_ai_game(1357)
	var res := MatchCheck.verify_ai(job)
	_check(res.get("ok", false), "partie contre l'IA avec changement de main vérifiée (%s)" % res.get("error", "ok"))
	get_tree().quit(1 if _fails > 0 else 0)


func _play_ai_game(seed_value: int) -> Dictionary:
	var gs := GameState.new()
	var bonus := AIPlayer.inferno_bonus(1)
	gs.setup(0, seed_value, bonus)
	var me := AIPlayer.new(0, 1)
	var ai := AIPlayer.new(1, 4)
	ai._rng.seed = MatchCheck.ai_seed(seed_value)
	var actions: Array = []
	var mulled := false
	for _i in 3000:
		if gs.is_over():
			break
		var p := gs.current if gs.pending_choice.is_empty() else int(gs.pending_choice.player)
		var act: Dictionary
		if p == 0 and not mulled and gs.can_mulligan(0):
			mulled = true
			act = {"type": "mulligan"}
		else:
			act = (me if p == 0 else ai).next_action(gs)
			if act.type == "end":
				act = {"type": "end_turn"}
		if not MatchCheck.apply_action(gs, p, act):
			if act.type == "end_turn":
				break
			act = {"type": "end_turn"}
			MatchCheck.apply_action(gs, p, act)
		actions.append(MatchCheck.encode(p, act))
		gs.pop_events()
	if not gs.is_over():
		gs.concede(0)
		actions.append([0, "x"])
	_check(mulled, "le joueur a changé de main pendant la partie simulée")
	return {"seed": seed_value, "first": 0, "bonus": bonus, "difficulty": 4, "ai": 1, "actions": actions}
