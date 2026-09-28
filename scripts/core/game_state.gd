class_name GameState
extends RefCounted
## Règles du jeu, indépendantes de l'affichage.
## Chaque action remplit `events`, que l'interface lit pour jouer les animations.
##
## Règles de base :
##  - Chaque héros a 25 PV. Le premier à 0 PV perd.
##  - Énergie : +1 maximum par tour (jusqu'à 10), entièrement rechargée au début du tour.
##    Jouer une carte coûte son nombre d'énergie.
##  - Début de tour : on révèle les 3 cartes du dessus du deck, le joueur en garde une et
##    les autres retournent au fond du deck (action "choose"). Deck vide = fatigue croissante.
##  - Un serviteur ne peut pas attaquer le tour où il arrive (sauf Charge), puis 1 attaque par tour.
##  - Les héros n'attaquent pas ; ils sont ciblés par les serviteurs et les sorts.
##  - Enchantements : restent en jeu (2 maximum par joueur). Effet permanent (« aura » sur vos
##    serviteurs) ou déclenché au début / à la fin de votre tour. Seules les cartes de destruction
##    les retirent (Dissipation, Purification, Briseur de sorts).
##  - Certains serviteurs ont aussi un effet tant qu'ils sont en jeu (aura, début / fin de tour).
##  - Pas de maximum de PV : les soins peuvent dépasser les PV de départ.
##  - Cimetière : cartes mortes, jouées, détruites, défaussées ou retirées du deck (certaines cartes s'en servent).
##  - Défausse : pendant son tour, un joueur peut défausser gratuitement une carte de sa main.

const HERO_UIDS := [1, 2]


class Entity:
	var uid: int
	var owner: int
	var is_hero := false
	var card_id := ""
	var attack := 0
	var health := 0
	var max_health := 0
	var taunt := false
	var charge := false
	var shield := false
	var is_enchant := false   # enchantement (pas de PV : `health` passe à 0 quand il est détruit)
	var aura_atk := 0         # bonus actuellement donnés par les enchantements (auras)
	var aura_hp := 0
	var attacks_left := 0
	var sleeping := true

	func copy() -> Entity:
		var e := Entity.new()
		e.uid = uid
		e.owner = owner
		e.is_hero = is_hero
		e.card_id = card_id
		e.attack = attack
		e.health = health
		e.max_health = max_health
		e.taunt = taunt
		e.charge = charge
		e.shield = shield
		e.is_enchant = is_enchant
		e.aura_atk = aura_atk
		e.aura_hp = aura_hp
		e.attacks_left = attacks_left
		e.sleeping = sleeping
		return e

	func can_attack() -> bool:
		return not is_hero and not is_enchant and attack > 0 and attacks_left > 0 and (not sleeping or charge)


class Player:
	var index: int
	var hero: Entity
	var deck: Array[String] = []
	var hand: Array[Dictionary] = []   # {uid, card_id}
	var board: Array[Entity] = []
	var enchants: Array[Entity] = []
	var graveyard: Array[String] = []   # cartes mortes, jouées (sorts), détruites, défaussées ou brûlées
	var energy := 0
	var max_energy := 0
	var fatigue := 0

	func copy() -> Player:
		var p := Player.new()
		p.index = index
		p.hero = hero.copy()
		p.deck = deck.duplicate()
		for c in hand:
			p.hand.append(c.duplicate())
		for m in board:
			p.board.append(m.copy())
		for e in enchants:
			p.enchants.append(e.copy())
		p.graveyard = graveyard.duplicate()
		p.energy = energy
		p.max_energy = max_energy
		p.fatigue = fatigue
		return p


var players: Array[Player] = []
var current := 0
var turn_number := 0
var winner := -1   # -1 = en cours, 0/1 = gagnant, 2 = égalité
## Choix de pioche en attente : {} ou {"player": int, "options": Array[String]}
var pending_choice := {}
const CHOICE_COUNT := 3
var events: Array[Dictionary] = []
var _next_uid := 100
var _rng := RandomNumberGenerator.new()
## Mode Inferno : camp dont le héros a des PV infinis (l'IA), -1 en partie normale.
## Le score est la somme des dégâts infligés à ce héros (la fatigue ne compte pas).
var inferno := -1
var inferno_damage := 0
var _fatigue_hit := false


## `bonus` (difficulté Challenger) : {"player": i, "health": PV en plus, "cards": cartes de départ en plus}.
## Mode Inferno : bonus["inferno"] = true, le héros de bonus["player"] a des PV infinis.
func setup(first_player: int, seed_value := -1, bonus := {}) -> void:
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	players.clear()
	for i in 2:
		var p := Player.new()
		p.index = i
		var h := Entity.new()
		h.uid = HERO_UIDS[i]
		h.owner = i
		h.is_hero = true
		h.health = CardDB.HERO_HEALTH
		h.max_health = CardDB.HERO_HEALTH
		p.hero = h
		p.deck = CardDB.build_deck()
		_shuffle(p.deck)
		players.append(p)
	current = first_player
	for i in CardDB.START_HAND:
		_draw(players[first_player])
	for i in CardDB.START_HAND + 1:   # le second joueur pioche une carte de plus
		_draw(players[1 - first_player])
	if not bonus.is_empty():
		var bp := players[clampi(int(bonus.get("player", 1)), 0, 1)]
		bp.hero.health += int(bonus.get("health", 0))
		bp.hero.max_health += int(bonus.get("health", 0))
		for i in int(bonus.get("cards", 0)):
			_draw(bp)
		if bonus.get("inferno", false):
			inferno = bp.index
	_start_turn()


## Copie complète de la partie (utilisée par l'IA difficile pour simuler ses coups).
## Le hasard de la copie est tiré différemment : l'IA ne connaît pas l'issue des effets aléatoires.
func clone(seed_value: int) -> GameState:
	var g := GameState.new()
	for pl in players:
		g.players.append(pl.copy())
	g.current = current
	g.turn_number = turn_number
	g.winner = winner
	g.inferno = inferno
	g.inferno_damage = inferno_damage
	g.pending_choice = pending_choice.duplicate(true)
	g._next_uid = _next_uid
	g._rng.seed = seed_value
	return g


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func pop_events() -> Array[Dictionary]:
	var e := events
	events = []
	return e


func _emit(ev: Dictionary) -> void:
	events.append(ev)


# ------------------------------------------------------------------ requêtes

func me(i: int) -> Player:
	return players[i]


func opponent(i: int) -> Player:
	return players[1 - i]


func get_entity(uid: int) -> Entity:
	for p in players:
		if p.hero.uid == uid:
			return p.hero
		for m in p.board:
			if m.uid == uid:
				return m
		for e in p.enchants:
			if e.uid == uid:
				return e
	return null


func hand_card(p: int, hand_uid: int) -> Dictionary:
	for c in players[p].hand:
		if c.uid == hand_uid:
			return c
	return {}


func is_over() -> bool:
	return winner != -1


func can_play(p: int, hand_uid: int) -> bool:
	if is_over() or p != current or not pending_choice.is_empty():
		return false
	var hc := hand_card(p, hand_uid)
	if hc.is_empty():
		return false
	var card := CardDB.get_card(hc.card_id)
	if card.cost > players[p].energy:
		return false
	if card.type == "minion" and players[p].board.size() >= CardDB.MAX_BOARD:
		return false
	if card.type == "enchantment" and players[p].enchants.size() >= CardDB.MAX_ENCHANTS:
		return false
	if needs_target(hc.card_id) and valid_spell_targets(p, hc.card_id).is_empty():
		return false
	return true


func needs_target(card_id: String) -> bool:
	var card := CardDB.get_card(card_id)
	return card.type == "spell" and card.spell.get("target", "") == "chosen"


func valid_spell_targets(p: int, card_id: String) -> Array[int]:
	var result: Array[int] = []
	var card := CardDB.get_card(card_id)
	var rule: String = card.spell.get("target_rule", "any")
	if rule == "enemy_enchant":
		for e in opponent(p).enchants:
			result.append(e.uid)
		return result
	for pl in players:
		if rule == "any":
			result.append(pl.hero.uid)
		for m in pl.board:
			if rule == "any" or (rule == "friendly_minion" and pl.index == p):
				result.append(m.uid)
	return result


func valid_attack_targets(attacker_uid: int) -> Array[int]:
	var result: Array[int] = []
	var a := get_entity(attacker_uid)
	if a == null or not a.can_attack() or a.owner != current or not pending_choice.is_empty():
		return result
	var opp := opponent(a.owner)
	var taunts: Array[int] = []
	for m in opp.board:
		if m.taunt:
			taunts.append(m.uid)
	if not taunts.is_empty():
		return taunts
	result.append(opp.hero.uid)
	for m in opp.board:
		result.append(m.uid)
	return result


# ------------------------------------------------------------------ tour

func _start_turn() -> void:
	turn_number += 1
	var p := players[current]
	p.max_energy = mini(p.max_energy + 1, CardDB.MAX_ENERGY)
	p.energy = p.max_energy
	for m in p.board:
		m.sleeping = false
		m.attacks_left = 1
	_emit({"t": "turn_start", "player": current, "turn": turn_number})
	_trigger_permanents(p, "turn_start")
	if is_over():
		return
	_offer_draw_choice(p)
	_check_game_over()


## Pioche du tour : révèle les cartes du dessus. S'il n'y en a qu'une, elle est piochée directement.
func _offer_draw_choice(p: Player) -> void:
	if p.deck.size() <= 1:
		_draw(p)
		return
	var options: Array[String] = []
	for i in mini(CHOICE_COUNT, p.deck.size()):
		options.append(p.deck.pop_back())
	pending_choice = {"player": p.index, "options": options}
	_emit({"t": "draw_choice", "player": p.index, "options": options.duplicate()})


func can_choose(p: int, index: int) -> bool:
	return not is_over() and not pending_choice.is_empty() and pending_choice.player == p \
		and index >= 0 and index < pending_choice.options.size()


## Le joueur garde l'option `index` ; les autres retournent au fond du deck.
func choose_draw(p: int, index: int) -> bool:
	if not can_choose(p, index):
		return false
	var pl := players[p]
	var options: Array = pending_choice.options
	pending_choice = {}
	var kept: String = options[index]
	var others := 0
	for i in options.size():
		if i != index:
			pl.deck.insert(0, options[i])   # le fond du deck est l'indice 0 (on pioche par la fin)
			others += 1
	_emit({"t": "chosen", "player": p, "card_id": kept, "index": index, "to_bottom": others})
	_add_to_hand(pl, kept)
	_check_game_over()
	return true


func end_turn() -> void:
	if is_over() or not pending_choice.is_empty():
		return
	_trigger_permanents(players[current], "turn_end")
	if is_over():
		return
	_emit({"t": "turn_end", "player": current})
	current = 1 - current
	_start_turn()


func _draw(p: Player) -> void:
	if p.deck.is_empty():
		p.fatigue += 1
		_emit({"t": "fatigue", "player": p.index, "amount": p.fatigue})
		_fatigue_hit = true
		_damage(p.hero, p.fatigue)
		_fatigue_hit = false
		return
	_add_to_hand(p, p.deck.pop_back())


func _add_to_hand(p: Player, id: String) -> void:
	if p.hand.size() >= CardDB.MAX_HAND:
		_emit({"t": "burn", "player": p.index, "card_id": id})
		p.graveyard.append(id)
		return
	var hc := {"uid": _new_uid(), "card_id": id}
	p.hand.append(hc)
	_emit({"t": "draw", "player": p.index, "uid": hc.uid, "card_id": id})


func _new_uid() -> int:
	_next_uid += 1
	return _next_uid


# ------------------------------------------------------------------ actions

## Joue une carte. `target_uid` pour les sorts ciblés, `board_index` pour la position du serviteur.
func play_card(p: int, hand_uid: int, target_uid := -1, board_index := -1) -> bool:
	if not can_play(p, hand_uid):
		return false
	var hc := hand_card(p, hand_uid)
	var card := CardDB.get_card(hc.card_id)
	if needs_target(hc.card_id) and not valid_spell_targets(p, hc.card_id).has(target_uid):
		return false
	var pl := players[p]
	pl.energy -= card.cost
	pl.hand.erase(hc)
	_emit({"t": "play", "player": p, "hand_uid": hand_uid, "card_id": hc.card_id, "target": target_uid})
	if card.type == "minion":
		var m := _summon(p, hc.card_id, board_index)
		if card.has("battlecry"):
			_resolve_effect(p, card.battlecry, m.uid, target_uid)
	elif card.type == "enchantment":
		_place_enchant(p, hc.card_id)
	else:
		_resolve_effect(p, card.spell, pl.hero.uid, target_uid)
		pl.graveyard.append(hc.card_id)
	_resolve_deaths()
	_check_game_over()
	return true


func attack(attacker_uid: int, defender_uid: int) -> bool:
	if is_over() or not valid_attack_targets(attacker_uid).has(defender_uid):
		return false
	var a := get_entity(attacker_uid)
	var d := get_entity(defender_uid)
	a.attacks_left -= 1
	_emit({"t": "attack", "attacker": a.uid, "defender": d.uid})
	var dmg_to_d := a.attack
	var dmg_to_a := d.attack if not d.is_hero and not d.is_enchant else 0
	_damage(d, dmg_to_d)
	if dmg_to_a > 0:
		_damage(a, dmg_to_a)
	_resolve_deaths()
	_check_game_over()
	return true


## Défausse gratuite d'une carte de la main (pendant son tour, hors choix de pioche).
func can_discard(p: int, hand_uid: int) -> bool:
	return not is_over() and p == current and pending_choice.is_empty() and not hand_card(p, hand_uid).is_empty()


func discard(p: int, hand_uid: int) -> bool:
	if not can_discard(p, hand_uid):
		return false
	var hc := hand_card(p, hand_uid)
	players[p].hand.erase(hc)
	players[p].graveyard.append(hc.card_id)
	_emit({"t": "discard", "player": p, "hand_uid": hand_uid, "card_id": hc.card_id})
	return true


func concede(p: int) -> void:
	if is_over():
		return
	players[p].hero.health = 0
	_check_game_over()


# ------------------------------------------------------------------ effets

func _summon(p: int, card_id: String, index := -1) -> Entity:
	var pl := players[p]
	if pl.board.size() >= CardDB.MAX_BOARD:
		return null
	var card := CardDB.get_card(card_id)
	var m := Entity.new()
	m.uid = _new_uid()
	m.owner = p
	m.card_id = card_id
	m.attack = card.attack
	m.health = card.health
	m.max_health = card.health
	var kw: Array = card.get("keywords", [])
	m.taunt = kw.has("taunt")
	m.charge = kw.has("charge")
	m.shield = kw.has("divine_shield")
	m.sleeping = true
	m.attacks_left = 1
	if index < 0 or index > pl.board.size():
		index = pl.board.size()
	pl.board.insert(index, m)
	_emit({"t": "summon", "player": p, "uid": m.uid, "card_id": card_id, "index": index})
	_recompute_auras()
	return m


func _place_enchant(p: int, card_id: String) -> Entity:
	var pl := players[p]
	if pl.enchants.size() >= CardDB.MAX_ENCHANTS:
		return null
	var card := CardDB.get_card(card_id)
	var e := Entity.new()
	e.uid = _new_uid()
	e.owner = p
	e.card_id = card_id
	e.is_enchant = true
	e.health = 1
	e.max_health = 1
	pl.enchants.append(e)
	_emit({"t": "enchant", "player": p, "uid": e.uid, "card_id": card_id})
	_recompute_auras()
	return e


## Effets « début / fin de votre tour » des enchantements, puis des serviteurs en jeu.
func _trigger_permanents(p: Player, when: String) -> void:
	var sources: Array[Entity] = []
	sources.append_array(p.enchants)
	sources.append_array(p.board)
	for e in sources:
		if is_over():
			return
		if e.health <= 0 or not (p.enchants.has(e) or p.board.has(e)):
			continue
		var card := CardDB.get_card(e.card_id)
		if card.has(when):
			_emit({"t": "enchant_trigger" if e.is_enchant else "minion_trigger", "uid": e.uid, "card_id": e.card_id, "player": p.index})
			_resolve_effect(p.index, card[when], e.uid, -1)
			_resolve_deaths()
			_check_game_over()


## Auras (enchantements et serviteurs « tant qu'il est en jeu ») : recalcule le bonus de chaque
## serviteur et applique la différence. Un serviteur ne profite pas de sa propre aura.
## Quand une aura disparaît, le bonus de PV est retiré sans pouvoir tuer.
func _recompute_auras() -> void:
	for pl in players:
		var base_atk := 0
		var base_hp := 0
		for e in pl.enchants:
			var aura: Dictionary = CardDB.get_card(e.card_id).get("aura", {})
			base_atk += int(aura.get("attack", 0))
			base_hp += int(aura.get("health", 0))
		for m in pl.board:
			var atk := base_atk
			var hp := base_hp
			for n in pl.board:
				if n != m and n.health > 0:
					var aura: Dictionary = CardDB.get_card(n.card_id).get("aura", {})
					atk += int(aura.get("attack", 0))
					hp += int(aura.get("health", 0))
			var da := atk - m.aura_atk
			var dh := hp - m.aura_hp
			if da == 0 and dh == 0:
				continue
			m.aura_atk = atk
			m.aura_hp = hp
			m.attack = maxi(0, m.attack + da)
			m.max_health = maxi(1, m.max_health + dh)
			m.health = maxi(1, m.health + dh) if m.health > 0 else m.health
			_emit({"t": "aura", "uid": m.uid, "attack": da, "health": dh})


func _resolve_effect(p: int, eff: Dictionary, source_uid: int, chosen_uid: int) -> void:
	var targets: Array[Entity] = []
	match eff.get("target", ""):
		"chosen":
			var t := get_entity(chosen_uid)
			if t:
				targets.append(t)
		"random_enemy":
			var pool: Array[Entity] = [opponent(p).hero]
			pool.append_array(opponent(p).board)
			targets.append(pool[_rng.randi_range(0, pool.size() - 1)])
		"enemy_hero":
			targets.append(opponent(p).hero)
		"own_hero":
			targets.append(players[p].hero)
		"all_enemy_minions":
			targets.append_array(opponent(p).board)
		"all_other_minions":
			for pl in players:
				for m in pl.board:
					if m.uid != source_uid:
						targets.append(m)
		"all_minions":
			for pl in players:
				targets.append_array(pl.board)
		"all_enemies":
			targets.append(opponent(p).hero)
			targets.append_array(opponent(p).board)
		"own_minions":
			for m in players[p].board:
				if m.uid != source_uid:
					targets.append(m)
		"all_enemy_enchants":
			targets.append_array(opponent(p).enchants)
		"random_enemy_enchant":
			var pool: Array[Entity] = opponent(p).enchants
			if not pool.is_empty():
				targets.append(pool[_rng.randi_range(0, pool.size() - 1)])
	var target_uids: Array[int] = []
	for t in targets:
		target_uids.append(t.uid)
	_emit({"t": "fx", "fx": eff.get("fx", ""), "player": p, "source": source_uid, "targets": target_uids})
	match eff.kind:
		"damage":
			for t in targets:
				_damage(t, eff.amount)
		"heal":
			for t in targets:
				_heal(t, eff.amount)
		"buff":
			for t in targets:
				t.attack += eff.attack
				t.health += eff.health
				t.max_health += eff.health
				_emit({"t": "buff", "uid": t.uid, "attack": eff.attack, "health": eff.health})
		"draw":
			var n: int = eff.amount
			var bonus: Dictionary = eff.get("bonus_grave", {})
			if not bonus.is_empty() and players[p].graveyard.size() >= int(bonus.min):
				n += int(bonus.amount)
			for i in n:
				_draw(players[p])
		"grave_buff":
			# +1/+1 par tranche de `per` cartes dans le cimetière (au plus `max` si indiqué, sinon sans limite).
			var src := get_entity(source_uid)
			var k: int = players[p].graveyard.size() / int(eff.per)
			if int(eff.get("max", 0)) > 0:
				k = mini(int(eff.max), k)
			if src and k > 0:
				src.attack += k
				src.health += k
				src.max_health += k
				_emit({"t": "buff", "uid": src.uid, "attack": k, "health": k})
		"resurrect":
			var pool: Array[int] = []
			var grave := players[p].graveyard
			for i in grave.size():
				var c := CardDB.get_card(grave[i])
				if c.type == "minion" and c.cost <= int(eff.max_cost):
					pool.append(i)
			if not pool.is_empty() and players[p].board.size() < CardDB.MAX_BOARD:
				var idx := pool[_rng.randi_range(0, pool.size() - 1)]
				var id: String = grave[idx]
				grave.remove_at(idx)
				_emit({"t": "resurrect", "player": p, "card_id": id})
				_summon(p, id)
		"recall_spell":
			var grave := players[p].graveyard
			for i in range(grave.size() - 1, -1, -1):
				if CardDB.get_card(grave[i]).type == "spell":
					var id: String = grave[i]
					grave.remove_at(i)
					_emit({"t": "recall", "player": p, "card_id": id})
					_add_to_hand(players[p], id)
					break
		"purge_deck":
			# Retire du deck (le sien ou celui de l'adversaire) des cartes selon leur coût, vers le cimetière.
			var victim := players[p] if eff.get("side", "own") == "own" else opponent(p)
			var match_idx: Array[int] = []
			for i in victim.deck.size():
				var c := CardDB.get_card(victim.deck[i])
				if c.cost <= int(eff.get("max_cost", 99)) and c.cost >= int(eff.get("min_cost", 0)):
					match_idx.append(i)
			var removed: Array[String] = []
			for i in mini(int(eff.count), match_idx.size()):
				var pick := _rng.randi_range(0, match_idx.size() - 1)
				removed.append(victim.deck[match_idx[pick]])
				match_idx.remove_at(pick)
			for id in removed:
				victim.deck.erase(id)
				victim.graveyard.append(id)
			_emit({"t": "purge", "player": victim.index, "cards": removed})
		"destroy":
			for t in targets:
				if not t.is_hero:
					t.health = 0
					_emit({"t": "destroy", "uid": t.uid})
		"summon":
			var index: int = eff.get("index", -1)
			for i in int(eff.get("count", 1)):
				var m := _summon(p, eff.card, index)
				if m != null and index >= 0:
					index += 1


func _damage(t: Entity, amount: int) -> void:
	if amount <= 0 or t == null:
		return
	if t.is_enchant:
		return   # les enchantements n'ont pas de PV
	if t.shield:
		t.shield = false
		_emit({"t": "shield_pop", "uid": t.uid})
		return
	if t.is_hero and t.owner == inferno:
		# PV infinis : les dégâts s'ajoutent au score au lieu de faire baisser les PV.
		if not _fatigue_hit:
			inferno_damage += amount
		_emit({"t": "damage", "uid": t.uid, "amount": amount, "hero": true, "inferno": inferno_damage})
		return
	t.health -= amount
	_emit({"t": "damage", "uid": t.uid, "amount": amount, "hero": t.is_hero})


## Pas de maximum de PV : un soin peut dépasser les PV de départ.
func _heal(t: Entity, amount: int) -> void:
	if amount <= 0 or t == null or t.is_enchant:
		return
	if t.is_hero and t.owner == inferno:
		return   # PV infinis : rien à soigner
	t.health += amount
	_emit({"t": "heal", "uid": t.uid, "amount": amount})


func _resolve_deaths() -> void:
	# Boucle : un râle d'agonie peut provoquer d'autres morts.
	for _guard in 10:
		var dead: Array[Dictionary] = []
		for pl in players:
			for i in range(pl.board.size()):
				var m := pl.board[i]
				if m.health <= 0:
					dead.append({"m": m, "index": i})
		var broken := false
		for pl in players:
			for e in pl.enchants.duplicate():
				if e.health <= 0:
					pl.enchants.erase(e)
					pl.graveyard.append(e.card_id)
					broken = true
					_emit({"t": "enchant_destroyed", "uid": e.uid, "card_id": e.card_id, "player": e.owner})
		if broken:
			_recompute_auras()
		if dead.is_empty():
			return
		for d in dead:
			var m: Entity = d.m
			players[m.owner].board.erase(m)
			players[m.owner].graveyard.append(m.card_id)
			_emit({"t": "death", "uid": m.uid, "card_id": m.card_id, "player": m.owner})
		_recompute_auras()   # l'aura d'un serviteur mort disparaît
		for d in dead:
			var m: Entity = d.m
			var card := CardDB.get_card(m.card_id)
			if card.has("deathrattle"):
				var eff: Dictionary = card.deathrattle.duplicate()
				eff["index"] = mini(d.index, players[m.owner].board.size())
				_resolve_effect(m.owner, eff, m.uid, -1)


func _check_game_over() -> void:
	if winner != -1:
		return
	var dead0 := players[0].hero.health <= 0
	var dead1 := players[1].hero.health <= 0
	if dead0 and dead1:
		winner = 2
	elif dead0:
		winner = 1
	elif dead1:
		winner = 0
	if winner != -1:
		_emit({"t": "game_over", "winner": winner})
