extends Node
## Contrôles 1.9 : défausse à la souris, confirmation de fin de tour, zone d'enchantements, Zzz,
## aperçu depuis le journal, zoom de l'interface, nouvelles illustrations.
## Lancement (fenêtré, hors ligne) : godot --path . res://tests/shots19.tscn -- --profile=shots19 --server=127.0.0.1 --port=1 --shots-dir=C:/chemin

var _dir := "user://shots"
var _fails := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots-dir="):
			_dir = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_dir)
	await _wait(0.5)
	PauseMenu.open()
	await _wait(0.3)
	PauseMenu._select_avatar(15)
	await _wait(0.2)
	_shot("19_0_profil_avatars")
	PauseMenu._tabs.current_tab = 2
	await _wait(0.4)
	_shot("19_1_affichage")
	PauseMenu.close()

	Net.mode = "ai"
	Settings.ai_difficulty = 1
	var b: Node = load("res://scenes/battle.tscn").instantiate()
	get_tree().root.add_child(b)
	for i in 240:
		if b._choice_layer != null:
			break
		await _wait(0.25)
	await _wait(0.8)
	b._close_choice()
	b.gs.pending_choice = {}
	# Main connue, beaucoup d'énergie, un serviteur endormi, deux enchantements de chaque côté.
	var p: Object = b.gs.players[b.me]
	p.energy = 10
	p.max_energy = 10
	b.gs._summon(b.me, "paladine")
	b.gs._summon(b.opp, "liche")
	await b._process_events(b.gs.pop_events(), true)
	b.busy = false
	b._refresh()
	await _wait(0.8)

	# --- Défausse : la souris va du centre de la carte au bouton « X » en passant au-dessus de la voisine.
	var n: int = b._hand_views.size()
	_check(n >= 3, "au moins 3 cartes en main (%d)" % n)
	var cv: CardView = b._hand_views[n / 2 - 1]
	await _move_to(cv.get_global_rect().get_center())
	await _wait(0.4)
	_check(b._hovered_hand == cv, "carte survolée")
	_check(b._discard_btn != null and b._discard_btn.get_parent() == cv, "bouton X sur la carte survolée")
	var target: Vector2 = b._discard_btn.get_global_rect().get_center()
	var from: Vector2 = cv.get_global_rect().get_center()
	for k in range(1, 13):
		await _move_to(from.lerp(target, k / 12.0))
		await _wait(0.03)
	await _wait(0.3)
	_check(b._hovered_hand == cv, "survol conservé jusqu'au X")
	target = b._discard_btn.get_global_rect().get_center()
	_shot("19_2_defausse_x")
	await _click(target)
	await _wait(0.3)
	_check(b._discard_btn.get_meta("confirm", false), "1er clic : demande de confirmation")
	_shot("19_3_defausse_confirmer")
	var before: int = p.hand.size()
	await _click(b._discard_btn.get_global_rect().get_center())
	for i in 20:
		await _wait(0.2)
		if not b.busy:
			break
	_check(p.hand.size() == before - 1, "2e clic : carte défaussée (%d -> %d)" % [before, p.hand.size()])
	await _move_to(Vector2(640, 300))
	await _wait(0.4)

	# --- Enchantements (2 emplacements) et Zzz
	for id in CardDB.CARDS:
		if CardDB.CARDS[id].type == "enchantment" and b.gs.players[b.opp].enchants.size() < 2:
			b.gs._place_enchant(b.opp, id)
	await b._process_events(b.gs.pop_events(), true)
	b.busy = false
	b._refresh()
	await _wait(0.6)
	_shot("19_4_plateau_zzz_enchant")

	# --- Aperçu depuis le journal
	b._on_log_card_hovered("capitaine", true)
	await _wait(0.4)
	_shot("19_5_journal_apercu")
	b._on_log_card_hovered("capitaine", false)

	# --- Fin de tour avec des actions restantes : « Confirmer » d'abord
	b._refresh()
	_check(b._any_action, "il reste des actions")
	b._on_end_turn_pressed()
	await _wait(0.3)
	_check(b.gs.current == b.me and b._end_turn_btn.text == Loc.t("Confirmer"), "1er appui : bouton « Confirmer », tour non terminé")
	_shot("19_6_fin_tour_confirmer")
	b._on_end_turn_pressed()
	await _wait(0.5)
	_check(b.gs.current == b.opp, "2e appui : tour terminé")

	# --- Dézoom en plein écran (simulé : transformation du canevas seule)
	Settings.fullscreen = true
	Settings.ui_zoom = 0.8
	Settings._apply_zoom(false)
	await _wait(0.5)
	_shot("19_7_dezoom_80")
	Settings.fullscreen = false
	Settings.ui_zoom = 1.0
	Settings._apply_zoom(false)
	print("RESULTAT : ", "OK" if _fails == 0 else "%d ÉCHEC(S)" % _fails)
	get_tree().quit()


func _move_to(pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	get_viewport().warp_mouse(pos)
	Input.parse_input_event(ev)
	await get_tree().process_frame


func _click(pos: Vector2) -> void:
	await _move_to(pos)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		Input.parse_input_event(ev)
		await get_tree().process_frame


func _check(ok: bool, what: String) -> void:
	print(("OK    " if ok else "ÉCHEC ") + what)
	if not ok:
		_fails += 1


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _shot(name: String) -> void:
	var path := _dir.path_join(name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("capture : ", path)
