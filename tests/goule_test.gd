extends Node
## Goule affamée sans limite : +1/+1 par tranche de 4 cartes au cimetière (20 cartes -> +5/+5).
## Lancement : godot --headless --path . res://tests/goule_test.tscn -- --profile=gouletest --server=127.0.0.1 --port=1


func _ready() -> void:
	var gs := GameState.new()
	gs.setup(0, 1234)
	var p = gs.players[0]
	p.graveyard.clear()
	for i in 20:
		p.graveyard.append("loup")
	p.hand.clear()
	gs._add_to_hand(p, "goule")
	p.energy = 10
	p.max_energy = 10
	gs.current = 0
	gs.pending_choice = {}
	var hc: Dictionary = p.hand[0]
	var ok := gs.play_card(0, hc.uid)
	var g = p.board[p.board.size() - 1] if not p.board.is_empty() else null
	var good: bool = ok and g != null and g.attack == 2 + 5 and g.health == 2 + 5
	print(("  ok   " if good else "  ÉCHEC ") + "Goule affamée avec 20 cartes au cimetière : %s/%s" % [g.attack if g else "?", g.health if g else "?"])
	get_tree().quit(0 if good else 1)
