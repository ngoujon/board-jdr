class_name MatchCheck
extends RefCounted
## Vérification d'une partie (anti-triche) : la partie est rejouée à partir de la graine fournie par le serveur
## et des actions enregistrées. Chaque action doit être légale ; contre l'IA, les coups de l'IA sont recalculés
## (IA déterministe : sa graine dérive de celle de la partie) et doivent correspondre. Le résultat (vainqueur,
## tours, statistiques, cartes jouées) est ensuite calculé ici plutôt que déclaré par le joueur.
## Utilisé par la partie elle-même (application des actions) et par le vérificateur du serveur (scenes/tools/verifier.tscn).

const MAX_ACTIONS := 4000
const STAT_KEYS := ["minions_played", "spells_played", "enchants_played", "taunt_played", "charge_played",
	"shield_played", "deathrattle_played", "enchants_destroyed", "hero_damage"]


## Graine de l'IA dérivée de celle de la partie : l'IA joue les mêmes coups lors de la vérification.
static func ai_seed(game_seed: int) -> int:
	return hash([game_seed, "ai"]) & 0x7fffffff


## Applique une action de joueur (identique en jeu et lors de la vérification).
static func apply_action(gs: GameState, p: int, act: Dictionary) -> bool:
	if gs.is_over():
		return false
	match act.get("type", ""):
		"play":
			return gs.play_card(p, int(act.get("hand_uid", -1)), int(act.get("target", -1)))
		"attack":
			var a := gs.get_entity(int(act.get("attacker", -1)))
			if a == null or a.owner != p:
				return false
			return gs.attack(int(act.attacker), int(act.get("defender", -1)))
		"choose":
			return gs.choose_draw(p, int(act.get("index", -1)))
		"discard":
			return gs.discard(p, int(act.get("hand_uid", -1)))
		"end_turn":
			if gs.current != p or not gs.pending_choice.is_empty():
				return false
			gs.end_turn()
			return true
		"concede":
			gs.concede(p)
			return true
	return false


static func encode(p: int, act: Dictionary) -> Array:
	match act.get("type", ""):
		"play":
			return [p, "p", int(act.hand_uid), int(act.get("target", -1))]
		"attack":
			return [p, "a", int(act.attacker), int(act.defender)]
		"choose":
			return [p, "c", int(act.get("index", 0))]
		"discard":
			return [p, "d", int(act.hand_uid)]
		"end_turn":
			return [p, "e"]
		"concede":
			return [p, "x"]
	return [p, "?"]


static func decode(a: Array) -> Dictionary:
	if a.size() < 2:
		return {}
	match str(a[1]):
		"p":
			return {"type": "play", "hand_uid": int(a[2]), "target": int(a[3])} if a.size() >= 4 else {}
		"a":
			return {"type": "attack", "attacker": int(a[2]), "defender": int(a[3])} if a.size() >= 4 else {}
		"c":
			return {"type": "choose", "index": int(a[2])} if a.size() >= 3 else {}
		"d":
			return {"type": "discard", "hand_uid": int(a[2])} if a.size() >= 3 else {}
		"e":
			return {"type": "end_turn"}
		"x":
			return {"type": "concede"}
	return {}


## Normalise une action reçue en JSON (nombres flottants -> entiers).
static func normalize(act: Dictionary) -> Dictionary:
	var out := {}
	for k in act:
		var v = act[k]
		out[str(k)] = int(v) if v is float else v
	return out


## Statistiques de partie (par joueur) et cartes jouées (par camp), à partir des événements du moteur.
static func track(ev: Dictionary, stats: Array, plays: Array) -> void:
	match ev.get("t", ""):
		"play":
			var p := int(ev.player)
			var cp: Dictionary = plays[p]
			cp[ev.card_id] = int(cp.get(ev.card_id, 0)) + 1
			var c := CardDB.get_card(ev.card_id)
			_add(stats[p], {"minion": "minions_played", "spell": "spells_played", "enchantment": "enchants_played"}.get(c.get("type", ""), ""), 1)
			for kw in c.get("keywords", []):
				_add(stats[p], {"taunt": "taunt_played", "charge": "charge_played", "divine_shield": "shield_played",
					"deathrattle": "deathrattle_played"}.get(kw, ""), 1)
		"damage":
			var uid := int(ev.uid)
			if uid in GameState.HERO_UIDS:
				_add(stats[1 - GameState.HERO_UIDS.find(uid)], "hero_damage", int(ev.amount))
		"enchant_destroyed":
			# Enchantement du joueur ev.player détruit : compté pour son adversaire.
			_add(stats[1 - int(ev.player)], "enchants_destroyed", 1)


static func _add(d: Dictionary, key: String, n: int) -> void:
	if key != "":
		d[key] = int(d.get(key, 0)) + n


static func _result(gs: GameState, stats: Array, plays: Array, reason: String, actions: Array) -> Dictionary:
	return {"ok": true, "winner": gs.winner, "turns": gs.turn_number, "reason": reason, "stats": stats, "cards": plays,
		"actions": actions, "score": gs.inferno_damage if gs.inferno >= 0 else 0}


static func _fail(why: String) -> Dictionary:
	return {"ok": false, "error": why}


## Partie contre l'IA : job = {seed, first, bonus, difficulty, ai, actions: [[p, code, ...], ...]}.
## Les actions du joueur sont rejouées telles quelles, celles de l'IA sont recalculées et comparées.
static func verify_ai(job: Dictionary) -> Dictionary:
	var actions: Array = job.get("actions", [])
	if actions.size() > MAX_ACTIONS:
		return _fail("trop d'actions")
	var ai_idx := int(job.get("ai", 1))
	var gs := GameState.new()
	gs.setup(int(job.get("first", 0)), int(job.get("seed", 0)), job.get("bonus", {}))
	var ai := AIPlayer.new(ai_idx, int(job.get("difficulty", 1)))
	ai._rng.seed = ai_seed(int(job.get("seed", 0)))
	var stats := [{}, {}]
	var plays := [{}, {}]
	var reason := "normal"
	var ai_turn_actions := 0
	var last_turn := -1
	for ev in gs.pop_events():
		track(ev, stats, plays)
	for i in actions.size():
		var raw = actions[i]
		if not raw is Array or raw.size() < 2:
			return _fail("action %d mal formée" % i)
		var p := int(raw[0])
		var act := decode(raw)
		if act.is_empty() or p < 0 or p > 1:
			return _fail("action %d inconnue" % i)
		if gs.is_over():
			return _fail("action %d après la fin de la partie" % i)
		if p == ai_idx:
			if act.type == "concede":
				return _fail("abandon attribué à l'IA")
			if gs.turn_number != last_turn:
				last_turn = gs.turn_number
				ai_turn_actions = 0
			# Même logique que Battle._run_ai_turn : coup de l'IA, fin de tour si le coup est refusé.
			var expected := ai.next_action(gs)
			if expected.get("type", "") == "end":
				expected = {"type": "end_turn"}
			ai_turn_actions += 1
			if expected.type != "end_turn" and act.type == "end_turn":
				# Le coup calculé a été refusé par le moteur : l'IA a terminé son tour à la place.
				if apply_action(gs, ai_idx, expected):
					return _fail("coup de l'IA différent (action %d)" % i)
				for ev in gs.pop_events():
					track(ev, stats, plays)
			elif encode(ai_idx, expected) != encode(ai_idx, act):
				return _fail("coup de l'IA différent (action %d) : %s au lieu de %s" % [i, act, expected])
		if not apply_action(gs, p, act):
			return _fail("action %d illégale : joueur %d %s" % [i, p, act])
		if act.type == "concede":
			reason = "concede"
		for ev in gs.pop_events():
			track(ev, stats, plays)
	if not gs.is_over():
		return _fail("partie non terminée")
	return _result(gs, stats, plays, reason, actions)


## Partie en ligne : job = {seed, first, events, leaver}. Les événements sont enregistrés par le serveur :
##   ["q", action]      demande de l'invité (joueur 1) transmise à l'hôte
##   ["a", p, action]   action appliquée et diffusée par l'hôte (joueur 0)
##   ["r"]              demande de l'invité refusée par l'hôte
## Une action de l'invité n'est valable que s'il l'a réellement demandée, un refus doit être justifié.
## leaver (0/1, facultatif) : joueur parti en cours de partie, compté comme ayant abandonné.
static func verify_pvp(job: Dictionary) -> Dictionary:
	var events: Array = job.get("events", [])
	if events.size() > MAX_ACTIONS * 2:
		return _fail("trop d'actions")
	var gs := GameState.new()
	gs.setup(int(job.get("first", 0)), int(job.get("seed", 0)))
	var stats := [{}, {}]
	var plays := [{}, {}]
	var reason := "normal"
	var pending: Array = []
	var actions: Array = []
	for ev in gs.pop_events():
		track(ev, stats, plays)
	for i in events.size():
		var e = events[i]
		if not e is Array or e.is_empty():
			return _fail("événement %d mal formé" % i)
		match str(e[0]):
			"q":
				if e.size() >= 2 and e[1] is Dictionary:
					pending.append(normalize(e[1]))
			"r":
				if pending.is_empty():
					continue
				var req: Dictionary = pending.pop_front()
				if not gs.is_over():
					var probe := gs.clone(0)
					if apply_action(probe, 1, req):
						return _fail("refus injustifié d'une action de l'invité (%s)" % req)
			"a":
				if e.size() < 3 or not e[2] is Dictionary:
					return _fail("événement %d mal formé" % i)
				var p := int(e[1])
				var act := normalize(e[2])
				if p < 0 or p > 1:
					return _fail("joueur inconnu")
				if gs.is_over():
					continue
				if p == 1:
					if pending.is_empty() or encode(1, pending[0]) != encode(1, act):
						return _fail("action de l'invité non demandée (%s)" % act)
					pending.pop_front()
				if not apply_action(gs, p, act):
					return _fail("action %d illégale : joueur %d %s" % [i, p, act])
				if act.get("type", "") == "concede":
					reason = "concede"
				actions.append(encode(p, act))
				for ev in gs.pop_events():
					track(ev, stats, plays)
	if not gs.is_over() and job.has("leaver"):
		var lv := int(job.leaver)
		gs.concede(lv)
		actions.append([lv, "x"])
		reason = "disconnect"
		gs.pop_events()
	if not gs.is_over():
		return _fail("partie non terminée")
	return _result(gs, stats, plays, reason, actions)
