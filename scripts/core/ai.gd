class_name AIPlayer
extends RefCounted
## IA de l'adversaire. Renvoie une action à la fois pour que l'interface puisse l'animer.
## Actions : {"type": "play", "hand_uid", "target"} | {"type": "attack", "attacker", "defender"} | {"type": "end"}

var me := 1
var difficulty := 1   # 0 = Apprenti, 1 = Chevalier, 2 = Seigneur de guerre (simule ses coups), 3 = Challenger, 4 = Inferno
var _seeds_n := 3        # tirages simulés par coup candidat
var _next_turn := false  # Challenger : simule aussi notre tour suivant avant d'évaluer
var _rng := RandomNumberGenerator.new()


func _init(player_index := 1, diff := 1) -> void:
	me = player_index
	difficulty = diff

	_rng.randomize()


## Challenger : même réflexion que le Seigneur de guerre, avec un avantage de départ (annoncé au joueur).
static func challenger_bonus(ai_index: int) -> Dictionary:
	return {"player": ai_index, "health": 5, "cards": 1}   # ~65 % de victoires contre le Seigneur de guerre


## Inferno : réflexion du Challenger, une carte de départ en plus et des PV infinis (identique à INFERNO_BONUS du serveur).
static func inferno_bonus(ai_index: int) -> Dictionary:
	return {"player": ai_index, "health": 0, "cards": 1, "inferno": true}


func next_action(gs: GameState) -> Dictionary:
	if gs.is_over() or gs.current != me:
		return {"type": "end"}
	if not gs.pending_choice.is_empty():
		if gs.pending_choice.player != me:
			return {"type": "end"}
		return {"type": "choose", "index": _best_choice(gs)}
	if difficulty >= 2:
		return _search(gs)
	# Apprenti : joue parfois une action au hasard et ignore les calculs de létal.
	if difficulty == 0 and _rng.randf() < 0.45:
		var r := _random_action(gs)
		if not r.is_empty():
			return r
	if difficulty >= 1:
		var lethal := _lethal_attack(gs)
		if not lethal.is_empty():
			return lethal
	var play := _best_play(gs)
	if not play.is_empty():
		return play
	var atk := _best_attack(gs)
	if not atk.is_empty():
		return atk
	return {"type": "end"}


# ------------------------------------------------------------------ évaluation

func _value(m: GameState.Entity) -> float:
	var v := m.attack * 1.5 + m.health
	if m.taunt:
		v += 2
	if m.shield:
		v += m.attack
	return v


func _ready_minions(gs: GameState) -> Array[GameState.Entity]:
	var r: Array[GameState.Entity] = []
	for m in gs.me(me).board:
		if m.can_attack():
			r.append(m)
	r.sort_custom(func(a, b): return a.attack > b.attack)
	return r


func _enemy_has_taunt(gs: GameState) -> bool:
	for m in gs.opponent(me).board:
		if m.taunt:
			return true
	return false


func _lethal_attack(gs: GameState) -> Dictionary:
	if _enemy_has_taunt(gs):
		return {}
	var enemy_hero := gs.opponent(me).hero
	var total := 0
	for m in _ready_minions(gs):
		total += m.attack
	# Sorts de dégâts directs jouables.
	var energy := gs.me(me).energy
	var burn := 0
	for hc in gs.me(me).hand:
		var c := CardDB.get_card(hc.card_id)
		if c.type == "spell" and c.spell.kind == "damage" and c.spell.target == "chosen" and c.cost <= energy:
			energy -= c.cost
			burn += c.spell.amount
	if total >= enemy_hero.health and total > 0:
		return {"type": "attack", "attacker": _ready_minions(gs)[0].uid, "defender": enemy_hero.uid}
	if burn > 0 and total + burn >= enemy_hero.health:
		# Envoie d'abord le sort au visage.
		for hc in gs.me(me).hand:
			var c := CardDB.get_card(hc.card_id)
			if c.type == "spell" and c.spell.kind == "damage" and c.spell.target == "chosen" and gs.can_play(me, hc.uid):
				return {"type": "play", "hand_uid": hc.uid, "target": enemy_hero.uid}
	return {}


func _best_play(gs: GameState) -> Dictionary:
	var best := {}
	var best_score := 0.0
	var p := gs.me(me)
	var opp := gs.opponent(me)
	for hc in p.hand:
		if not gs.can_play(me, hc.uid):
			continue
		var c := CardDB.get_card(hc.card_id)
		var score := 0.0
		var target := -1
		if c.type == "minion":
			score = 10.0 + c.cost * 4 + c.attack + c.health
			var bc: Dictionary = c.get("battlecry", {})
			if bc.get("kind", "") == "damage" and bc.get("target", "") in ["all_other_minions", "all_enemy_minions"]:
				# Évite de brûler son propre plateau pour rien.
				score += _area_score(p, opp, bc.amount, bc.target != "all_enemy_minions", false) * 0.7
			elif bc.get("kind", "") == "buff" and bc.get("target", "") == "own_minions":
				score += p.board.size() * 4
			elif bc.get("kind", "") == "destroy":
				score += _enchant_threat(opp) * 0.8 if not opp.enchants.is_empty() else -4.0
			elif bc.get("kind", "") == "grave_buff":
				var k: int = p.graveyard.size() / int(bc.per)
				score += (mini(int(bc.max), k) if int(bc.get("max", 0)) > 0 else k) * 3
			elif bc.get("kind", "") == "recall_spell":
				score += 4 if _grave_has(p, "spell", 99) else 0
			if CardDB.card_keywords(hc.card_id).has("ongoing"):
				score += 4
			if p.board.size() >= CardDB.MAX_BOARD:
				score = 0.0
		elif c.type == "enchantment":
			score = 12.0 + c.cost * 4
			var aura: Dictionary = c.get("aura", {})
			if not aura.is_empty():
				score += p.board.size() * (int(aura.get("attack", 0)) + int(aura.get("health", 0))) * 3 - 6
		else:
			var sp: Dictionary = c.spell
			match sp.kind:
				"destroy":
					if sp.target == "chosen":
						var best_e: GameState.Entity = null
						for e in opp.enchants:
							if best_e == null or CardDB.get_card(e.card_id).cost > CardDB.get_card(best_e.card_id).cost:
								best_e = e
						if best_e:
							score = 14.0 + CardDB.get_card(best_e.card_id).cost * 4
							target = best_e.uid
					elif opp.enchants.size() >= 1:
						score = 8.0 + _enchant_threat(opp)
				"damage":
					if sp.target == "chosen":
						var r := _best_damage_target(gs, sp.amount)
						score = r.score
						target = r.target
					else:
						score = _area_score(p, opp, sp.amount, sp.target == "all_minions", sp.target == "all_enemies")
				"heal":
					var missing := p.hero.max_health - p.hero.health
					if gs.inferno == me:
						missing = mini(gs.inferno_damage, int(sp.amount))   # Inferno : le soin fait baisser le score adverse
					if missing >= 5:
						score = 12.0 + missing
						target = p.hero.uid
				"buff" when sp.target == "own_minions":
					if p.board.size() >= 2:
						score = 10.0 + p.board.size() * 5
				"summon":
					var room := CardDB.MAX_BOARD - p.board.size()
					if room > 0:
						score = 12.0 + mini(room, int(sp.get("count", 1))) * 6
				"buff":
					var best_m: GameState.Entity = null
					for m in p.board:
						if best_m == null or _value(m) + (5 if m.can_attack() else 0) > _value(best_m):
							best_m = m
					if best_m:
						score = 22.0 + best_m.attack
						target = best_m.uid
				"draw":
					if p.hand.size() <= 5:
						score = 18.0
				"resurrect":
					if p.board.size() < CardDB.MAX_BOARD and _grave_has(p, "minion", int(sp.max_cost)):
						score = 14.0 + sp.max_cost * 2
				"purge_deck":
					if sp.get("side", "own") == "enemy":
						var hits := 0
						for id in opp.deck:
							if CardDB.get_card(id).cost >= int(sp.get("min_cost", 0)):
								hits += 1
						score = 6.0 + mini(hits, int(sp.count)) * 4 if hits > 0 else 0.0
					elif gs.turn_number >= 8:
						score = 8.0   # plus tard, les petites cartes ne servent plus
		if score > best_score:
			best_score = score
			best = {"type": "play", "hand_uid": hc.uid, "target": target}
	return best


## Intérêt d'un effet de zone : valeur des serviteurs adverses tués / blessés,
## moins celle des nôtres si l'effet touche aussi notre camp.
func _area_score(p: GameState.Player, opp: GameState.Player, amount: int, hits_own: bool, hits_hero: bool) -> float:
	var killed := 0.0
	var dmg := 0
	for m in opp.board:
		if m.shield:
			continue
		dmg += mini(amount, m.health)
		if m.health <= amount:
			killed += _value(m)
	var lost := 0.0
	if hits_own:
		for m in p.board:
			if not m.shield and m.health <= amount:
				lost += _value(m)
	if hits_hero:
		dmg += amount
		if opp.hero.health <= amount:
			return 999.0
	var s := killed * 3 + dmg * 2 - lost * 3
	return s if (killed > 0 or dmg >= 4) and s > 0 else 0.0


## Intérêt de détruire les enchantements adverses.
func _enchant_threat(opp: GameState.Player) -> float:
	var t := 0.0
	for e in opp.enchants:
		t += 6.0 + CardDB.get_card(e.card_id).cost * 3
	return t


func _best_damage_target(gs: GameState, amount: int) -> Dictionary:
	var opp := gs.opponent(me)
	var best := {"score": 0.0, "target": -1}
	for m in opp.board:
		if m.shield:
			continue
		if m.health <= amount:
			var s := 10.0 + _value(m) * 3
			if s > best.score:
				best = {"score": s, "target": m.uid}
	if opp.hero.health <= amount:
		best = {"score": 999.0, "target": opp.hero.uid}
	return best


func _best_attack(gs: GameState) -> Dictionary:
	var opp := gs.opponent(me)
	for a in _ready_minions(gs):
		var targets := gs.valid_attack_targets(a.uid)
		if targets.is_empty():
			continue
		var best_t := -1
		var best_s := -INF
		for t_uid in targets:
			var t := gs.get_entity(t_uid)
			var s := 0.0
			if t.is_hero:
				s = 4.0 + a.attack * 0.5
			else:
				var kills := t.health <= a.attack and not t.shield
				var dies := a.health <= t.attack and not a.shield
				if kills and not dies:
					s = 8.0 + _value(t) * 2
				elif kills and dies:
					s = _value(t) * 2 - _value(a) * 1.5
				elif t.shield:
					s = 3.0 if not dies else -5.0
				else:
					s = -10.0 + (a.attack * 0.5)
				# Élimine en priorité les grosses menaces.
				if kills and t.attack >= 4:
					s += 6
			if s > best_s:
				best_s = s
				best_t = t_uid
		# Si seules des provocations sont ciblables, on attaque quand même.
		if best_t != -1 and (best_s > 0 or _enemy_has_taunt(gs)):
			return {"type": "attack", "attacker": a.uid, "defender": best_t}
		if best_t != -1 and targets.has(opp.hero.uid):
			return {"type": "attack", "attacker": a.uid, "defender": opp.hero.uid}
	return {}


## Choix de pioche : garde la carte la plus utile maintenant ou au prochain tour.
func _best_choice(gs: GameState) -> int:
	var options: Array = gs.pending_choice.options
	if difficulty == 0:
		return _rng.randi_range(0, options.size() - 1)
	var p := gs.me(me)
	var opp := gs.opponent(me)
	var best := 0
	var best_score := -INF
	for i in options.size():
		var c := CardDB.get_card(options[i])
		var s := 0.0
		if c.cost <= p.energy:
			s += 10 + c.cost * 2
		else:
			s += c.cost - (c.cost - p.energy) * 2
		if c.type == "minion":
			s += c.attack + c.health
			if p.board.is_empty():
				s += 3
			if c.get("keywords", []).has("taunt") and p.hero.health <= 12:
				s += 5
			if not opp.enchants.is_empty() and c.has("battlecry") and c.battlecry.kind == "destroy":
				s += 6
		elif c.type == "enchantment":
			s += 4 if p.enchants.size() < CardDB.MAX_ENCHANTS else -8
		else:
			var sp: Dictionary = c.spell
			match sp.kind:
				"damage":
					for m in opp.board:
						if m.health <= sp.amount:
							s += 4
				"heal":
					if p.hero.max_health - p.hero.health >= 8:
						s += 8
				"buff":
					s += 4 if not p.board.is_empty() else -6
				"summon":
					s += 5 if p.board.size() < CardDB.MAX_BOARD - 1 else -4
				"destroy":
					s += 8 if not opp.enchants.is_empty() else -8
				"resurrect":
					s += 4 if _grave_has(p, "minion", int(sp.max_cost)) else -6
				"draw":
					s += 4 if p.hand.size() <= 4 else 0
		if s > best_score:
			best_score = s
			best = i
	return best


func _grave_has(p: GameState.Player, type: String, max_cost: int) -> bool:
	for id in p.graveyard:
		var c := CardDB.get_card(id)
		if c.type == type and c.cost <= max_cost:
			return true
	return false


# ------------------------------------------------------------------ Difficile
# Pour chaque action légale, l'IA joue la suite de son tour sur une copie de la partie
# (avec la stratégie « Chevalier »), puis le tour adverse, et garde l'action qui mène
# à la meilleure position. Dans les copies, la main et le deck adverses sont remplacés
# par un tirage au hasard parmi ses cartes inconnues, et les decks sont re-mélangés :
# l'IA ne triche pas.

func _search(gs: GameState) -> Dictionary:
	var best := {"type": "end"}
	var best_score := -INF
	var candidates: Array[Dictionary] = [{"type": "end"}]
	candidates.append_array(_legal_actions(gs))
	# Mêmes tirages pour tous les candidats : les scores restent comparables entre eux.
	var seeds: Array[int] = []
	for k in _seeds_n:
		seeds.append(_rng.randi())
	for a in candidates:
		var total := 0.0
		for sd in seeds:
			var g := _fair_clone(gs, sd)
			if a.type != "end":
				if not _apply(g, a, me):
					total = -INF
					break
				_rollout(g, sd + 1)
			_opponent_turn(g, sd + 2)
			if _next_turn and not g.is_over() and g.current == me:
				_rollout(g, sd + 3)   # notre tour suivant : repère les létaux préparés et les menaces
			total += _evaluate(g)
		var score := total / _seeds_n
		if score > best_score + 0.01:
			best_score = score
			best = a
	return best


## Copie de la partie sans informations cachées : la main adverse est retirée au hasard
## parmi ses cartes inconnues (main + deck), et les deux decks sont re-mélangés.
func _fair_clone(gs: GameState, seed_value: int) -> GameState:
	var g := gs.clone(seed_value)
	var o := g.opponent(me)
	var pool: Array[String] = o.deck.duplicate()
	for hc in o.hand:
		pool.append(hc.card_id)
	g._shuffle(pool)
	for i in o.hand.size():
		o.hand[i].card_id = pool[i]
	o.deck.clear()
	for i in range(o.hand.size(), pool.size()):
		o.deck.append(pool[i])
	g._shuffle(g.me(me).deck)
	return g


## Termine notre tour puis joue le tour adverse avec la stratégie « Chevalier ».
func _opponent_turn(g: GameState, seed_value: int) -> void:
	if g.is_over() or g.current != me or not g.pending_choice.is_empty():
		return
	g.end_turn()
	var who := 1 - me
	var helper := AIPlayer.new(who, 1)
	helper._rng.seed = seed_value
	for i in 40:
		if g.is_over() or g.current != who:
			return
		var a := helper.next_action(g)
		if a.type == "end" or not _apply(g, a, who):
			g.end_turn()
			return


func _legal_actions(gs: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var p := gs.me(me)
	for hc in p.hand:
		if not gs.can_play(me, hc.uid):
			continue
		if gs.needs_target(hc.card_id):
			for t in gs.valid_spell_targets(me, hc.card_id):
				out.append({"type": "play", "hand_uid": hc.uid, "target": t})
		else:
			out.append({"type": "play", "hand_uid": hc.uid, "target": -1})
	for m in p.board:
		for t in gs.valid_attack_targets(m.uid):
			out.append({"type": "attack", "attacker": m.uid, "defender": t})
	return out


func _apply(g: GameState, a: Dictionary, who: int) -> bool:
	match a.type:
		"play":
			return g.play_card(who, a.hand_uid, a.target)
		"attack":
			return g.attack(a.attacker, a.defender)
		"choose":
			return g.choose_draw(who, a.index)
	return false


## Fin du tour simulée avec la stratégie « Chevalier ».
func _rollout(g: GameState, seed_value: int) -> void:
	var helper := AIPlayer.new(me, 1)
	helper._rng.seed = seed_value
	for i in 25:
		if g.is_over() or g.current != me:
			return
		var a := helper.next_action(g)
		if a.type == "end" or not _apply(g, a, me):
			return


func _hp_value(hp: int) -> float:
	return hp + mini(hp, 12) * 0.8   # les derniers PV comptent davantage


## Valeur d'une position du point de vue de l'IA (plus c'est haut, mieux c'est).
func _evaluate(g: GameState) -> float:
	if g.is_over():
		if g.winner == me:
			return 100000.0
		return -100000.0 if g.winner != 2 else -50000.0
	var p := g.me(me)
	var opp := g.opponent(me)
	var s := _hp_value(p.hero.health) - _hp_value(opp.hero.health) * 1.1
	var my_atk := 0
	var my_taunt := false
	for m in p.board:
		s += _value(m) + _ongoing_bonus(m.card_id)
		my_atk += m.attack
		my_taunt = my_taunt or m.taunt
	var opp_atk := 0
	var opp_taunt := false
	for m in opp.board:
		s -= (_value(m) + _ongoing_bonus(m.card_id)) * 1.15
		opp_atk += m.attack
		opp_taunt = opp_taunt or m.taunt
	for e in p.enchants:
		s += 4.0 + CardDB.get_card(e.card_id).cost * 2
	for e in opp.enchants:
		s -= 4.0 + CardDB.get_card(e.card_id).cost * 2
	s += mini(p.hand.size(), 8) * 2.0 - mini(opp.hand.size(), 8) * 0.5
	# Menace de létal au prochain tour adverse (sans compter ses sorts).
	if not my_taunt and opp_atk >= p.hero.health:
		s -= 400.0
	elif opp_atk >= p.hero.health:
		s -= 60.0
	# Évaluée au début de notre tour : si notre plateau suffit pour tuer, la partie est quasi gagnée.
	if not opp_taunt and my_atk >= opp.hero.health:
		s += 300.0
	return s



func _ongoing_bonus(card_id: String) -> float:
	var c := CardDB.get_card(card_id)
	var b := 0.0
	if c.has("aura"):
		b += 3.0
	if c.has("turn_end") or c.has("turn_start"):
		b += 4.0
	return b


func _random_action(gs: GameState) -> Dictionary:
	var options: Array[Dictionary] = []
	var p := gs.me(me)
	for hc in p.hand:
		if gs.can_play(me, hc.uid):
			var target := -1
			if gs.needs_target(hc.card_id):
				var ts := gs.valid_spell_targets(me, hc.card_id)
				target = ts[_rng.randi_range(0, ts.size() - 1)]
			options.append({"type": "play", "hand_uid": hc.uid, "target": target})
	for m in p.board:
		var ts := gs.valid_attack_targets(m.uid)
		if not ts.is_empty():
			options.append({"type": "attack", "attacker": m.uid, "defender": ts[_rng.randi_range(0, ts.size() - 1)]})
	if options.is_empty():
		return {}
	return options[_rng.randi_range(0, options.size() - 1)]
