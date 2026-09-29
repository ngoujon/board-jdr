extends Control
## Scène de combat. Trois modes (Net.mode) :
##  - "ai"     : le joueur (index 0) affronte l'IA (index 1) ;
##  - "host"   : partie en ligne, l'hôte est le joueur 0 et fait autorité ;
##  - "client" : partie en ligne, le client est le joueur 1.
## Le joueur local est toujours affiché en bas de l'écran.
## Toutes les actions passent par une file (_queue) appliquée dans le même ordre sur les deux machines.

signal queue_idle

const ENEMY_BOARD_Y := 250.0
const PLAYER_BOARD_Y := 432.0
const HAND_SCALE := 0.8
const HAND_HOVER_SCALE := 1.3
const HAND_Y := 476.0   # position (pivot en bas de carte) : le bas des cartes reste à l'écran
const BOARD_SPACING := 112.0

const AI_CHAT := [
	"Tes cartes ne te sauveront pas.",
	"Hmpf. Continue de parler, mortel.",
	"Les ombres approchent...",
	"Mes squelettes ont faim.",
	"Bien joué... pour un simple chevalier.",
	"Je n'ai pas le temps pour tes bavardages.",
]

var mode := "ai"
var me := 0
var opp := 1
var gs := GameState.new()
var ai: AIPlayer
var fx: Fx3D

var busy := true
var _started := false
var _awaiting_server := false
var _queue: Array = []
var _queue_running := false
var _ai_running := false
var _last_ok := false
var _start_msec := 0          # pour la durée de la partie (historique)
var _end_reason := "normal"   # "normal" | "concede" | "disconnect"
var _record: Array = []        # actions de la partie (replay compact envoyé au serveur en fin de partie)
var _card_plays := [{}, {}]    # cartes jouées par chaque camp (statistiques globales)
var _first := 0
var _seed := 0
var _ticket := ""               # partie enregistrée par le serveur (graine fournie par lui, résultat vérifié)
var _bonus := {}               # avantage de départ du Challenger (rejoué à l'identique)
var _replay_paused := false
var _replay_speed := 1.0
var _targeting := {}   # {kind: "attack"|"spell", source, hand_uid, card, valid: Array[int]}

var _board_root: Control
var _hand_root: Control
var _enemy_hand_root: Control
var _overlay: CanvasLayer
var _arrow: Line2D
var _arrow_head: Polygon2D
var _hero_views: Array[HeroView] = []
var _minion_views := {}      # uid -> MinionView
var _hand_views: Array[CardView] = []
var _enemy_hand_views: Array[CardView] = []
var _end_turn_btn: Button
var _mulligan_btn: Button   # « Changer de main » : premier tour du joueur, avant toute action
var _mulligan_confirm := false
const AI_NAMES := ["Apprenti", "Chevalier", "Seigneur de guerre", "Challenger", "Inferno"]
var _inferno_label: Label        # score du mode Inferno (dégâts infligés au héros aux PV infinis)
var _auto_end_check: CheckBox    # « Fin du tour automatique »
var _auto_end_pending := false
var _any_action := false        # il reste une carte jouable ou un serviteur prêt à attaquer
var _end_confirm := false       # 1er appui sur « Fin du tour » alors qu'il reste des actions : on attend « Confirmer »
var _preview: CardView
var _tips: KeywordTips          # explications détaillées de la carte survolée
var _banner: Label
var _hovered_hand: CardView
var _selected_hand: CardView     # carte sélectionnée (1er clic) : un 2e clic la joue
var _dragging_card: CardView     # carte déplacée à la souris (rangement manuel de la main)
var _sort_btns := {}             # mode de rangement -> bouton
var _clock: Label                # chrono de la partie
var _turn_label: Label           # numéro du tour, sous la durée
var _clock_stop_msec := 0        # figé à la fin de la partie
var _rematch_btn: Button
var _game_over_vb: VBoxContainer
var _rematch_row: HBoxContainer
var _game_over_box: HBoxContainer
var _choice_layer: CanvasLayer   # overlay « choisissez une carte » (pioche au choix)
var _enchant_views := {}         # uid -> EnchantView
var _enchant_zone_labels: Array[Label] = []   # libellé « Enchantements » des zones vides (index = joueur)
var _stats := {}                 # statistiques de la partie (déblocage des titres, avatars...)
var _discard_zone: PanelContainer   # zone « Défausser » en bas à droite, visible pendant le glisser d'une carte
var _deck_piles := {}            # joueur -> pile de dos de cartes de sa bibliothèque
var _deck_pile_counts := {}      # joueur -> nombre de cartes affiché sous la pile
var _play_zone: Panel            # zone de jeu en surbrillance pendant le glisser d'une carte
var _play_zone_label: Label
var _first_token: Panel          # jeton « a commencé » à côté du portrait du premier joueur
var _chat_notice: PanelContainer # bandeau « nouveau message » en haut de la discussion
const DISCARD_RECT := Rect2(1040, 500, 132, 164)   # zone de défausse (coordonnées du plateau)
const DECK_PILE_POS := Vector2(1184, 500)      # votre bibliothèque : en bas à droite, à côté de la main
const ENEMY_PILE_POS := Vector2(940, 14)        # bibliothèque adverse : en haut, à droite de sa main
var _choice_return: CanvasLayer  # bouton « Revenir au choix des cartes » pendant la consultation du plateau

# Chat : canal « Journal » (actions) et canal « Discussion » (messages).
var _chat_tabs: TabContainer
var _log: RichTextLabel
const PREVIEW_POS := Vector2(1076, 440)   # aperçu d'une carte survolée sur le plateau
var _chat_log: RichTextLabel
var _chat_input: LineEdit
var _unread := 0


func _ready() -> void:
	add_to_group("battle")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mode = Net.mode
	me = Net.local_index()
	opp = 1 - me
	if mode == "ai":
		ai = AIPlayer.new(opp, Settings.ai_difficulty)
	_build_ui()
	Audio.play_music("battle")
	Lobby.reward_received.connect(_on_reward)
	if mode == "replay":
		_chat_input.editable = false
		_chat_input.placeholder_text = Loc.t("Replay : discussion désactivée")
	else:
		Lobby.set_status("in_game")
	if Net.is_online():
		Net.action_received.connect(_on_net_action)
		Net.action_rejected.connect(_on_net_rejected)
		Net.opponent_left.connect(_on_opponent_left)
		Net.chat_received.connect(_on_chat_received)
		Net.rematch_changed.connect(_on_rematch_changed)
		for p in Net.take_pending():
			_queue.append(p)
	await get_tree().process_frame
	_start_game()


func _pname(i: int) -> String:
	if mode == "replay":
		var names: Array = Net.replay.get("names", [])
		return _display_name(str(names[i])) if i < names.size() else CardDB.HEROES[i].name
	if Net.is_online():
		return Net.local_name if i == me else Net.remote_name
	if i == me and Settings.player_name != "":
		return Settings.player_name
	return CardDB.HEROES[i].name


## Nom affiché d'un joueur de replay : le nom d'IA enregistré en français (« IA Chevalier ») est traduit.
static func _display_name(n: String) -> String:
	if n.begins_with("IA "):
		return Loc.t("IA ") + Loc.t(n.substr(3))
	return n


## Personnalisation d'un joueur (titre, contour, dos de cartes, plateau) ; {} pour l'IA.
func _look(i: int) -> Dictionary:
	if mode == "replay":
		return {}
	if i == me and Settings.player_name != "":
		return Lobby.my_look()
	if i != me and Net.is_online():
		return Net.remote_look
	return {}


func _back_tex(i: int) -> Texture2D:
	return Cosmetics.card_back_texture(_look(i).get("card_back", "default"))


func _portrait(i: int) -> Texture2D:
	if mode == "replay":
		var avatars: Array = Net.replay.get("avatars", [0, 0])
		var av := int(avatars[i]) if i < avatars.size() else 0
		return CardDB.avatar(av) if av > 0 else null
	if Net.is_online():
		return CardDB.avatar(Net.local_avatar if i == me else Net.remote_avatar)
	if i == me and Settings.player_name != "":
		return CardDB.avatar(Settings.avatar)
	return null


# ======================================================================== UI

func _build_ui() -> void:
	var bg := TextureRect.new()
	# Plateau choisi par le joueur local (visible uniquement par lui).
	bg.texture = Cosmetics.board_texture(_look(me).get("board", "default"))
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.modulate = Color(0.5, 0.47, 0.47)
	add_child(bg)

	_board_root = Control.new()
	_board_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_board_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_board_root)

	for y in [ENEMY_BOARD_Y, PLAYER_BOARD_Y]:
		var lane := Panel.new()
		lane.position = Vector2(270, y - 74)
		lane.size = Vector2(740, 148)
		lane.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lane.add_theme_stylebox_override("panel", UITheme.flat_style(Color(0.05, 0.03, 0.06, 0.45), Color(0.95, 0.76, 0.3, 0.35), 2, 10))
		_board_root.add_child(lane)

	# Zones d'enchantements, entre les deux héros.
	for i in 2:
		_enchant_zone_labels.append(null)
	for i in 2:
		var zone := Panel.new()
		zone.position = Vector2(59, _enchant_zone_y(i) - 4)   # 2 emplacements (CardDB.MAX_ENCHANTS), centrés
		zone.size = Vector2(162, 96)
		zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
		zone.add_theme_stylebox_override("panel", UITheme.flat_style(Color(0.08, 0.03, 0.12, 0.45), Color(0.7, 0.48, 1.0, 0.35), 2, 8))
		_board_root.add_child(zone)
		var zl := UITheme.label(Loc.t("Enchantements"), 13, Color(0.8, 0.65, 1.0, 0.45), 2)
		zl.position = Vector2(0, 36)
		zl.size = Vector2(162, 20)
		zl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		zone.add_child(zl)
		_enchant_zone_labels[i] = zl

	for i in 2:
		var hv := HeroView.new().setup(i, GameState.HERO_UIDS[i], _pname(i), _portrait(i), _look(i))
		hv.position = Vector2(30, 8) if i == opp else Vector2(30, 500)
		hv.pressed.connect(_on_hero_pressed)
		hv.deck_pressed.connect(_on_deck_pressed)
		hv.grave_pressed.connect(_on_grave_pressed)
		_board_root.add_child(hv)
		_hero_views.append(hv)

	_enemy_hand_root = Control.new()
	_enemy_hand_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board_root.add_child(_enemy_hand_root)
	_hand_root = Control.new()
	_hand_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board_root.add_child(_hand_root)

	_build_chat()

	_end_turn_btn = UITheme.button(Loc.t("Fin du tour"), 200)
	_end_turn_btn.position = Vector2(1054, 318)
	_end_turn_btn.custom_minimum_size = Vector2(200, 60)
	_end_turn_btn.focus_mode = Control.FOCUS_NONE
	_end_turn_btn.pressed.connect(_on_end_turn_pressed)
	_board_root.add_child(_end_turn_btn)

	_mulligan_btn = UITheme.button(Loc.t("Changer de main"), 200)
	_mulligan_btn.position = Vector2(540, 408)
	_mulligan_btn.custom_minimum_size = Vector2(200, 52)
	_mulligan_btn.focus_mode = Control.FOCUS_NONE
	_mulligan_btn.tooltip_text = Loc.t("Premier tour seulement : toute votre main part au cimetière et vous piochez une nouvelle main d'une carte de moins.")
	_mulligan_btn.visible = false
	_mulligan_btn.pressed.connect(_on_mulligan_pressed)
	_board_root.add_child(_mulligan_btn)

	var key_hint := UITheme.label("", 13, Color("c9b79a"), 3)
	key_hint.position = Vector2(1040, 382)
	key_hint.size = Vector2(228, 20)
	key_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_hint.text = Loc.t("[%s] fin du tour · [Échap] menu") % Settings.key_label("end_turn")
	_board_root.add_child(key_hint)

	_clock = UITheme.label(Loc.t("Durée %02d:%02d") % [0, 0], 16, Color("e8d6b0"), 3)
	_clock.position = Vector2(1040, 400)
	_clock.size = Vector2(228, 22)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock.tooltip_text = Loc.t("Durée de la partie")
	_clock.mouse_filter = Control.MOUSE_FILTER_PASS
	_board_root.add_child(_clock)
	_turn_label = UITheme.label(Loc.t("Tour %d") % 1, 16, Color("e8d6b0"), 3)
	_turn_label.position = Vector2(1040, 420)
	_turn_label.size = Vector2(228, 22)
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_label.tooltip_text = Loc.t("Numéro du tour : un tour comprend le jeu des deux joueurs (celui qui commence, puis l'autre).")
	_turn_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_board_root.add_child(_turn_label)
	_auto_end_check = CheckBox.new()
	_auto_end_check.text = Loc.t("Fin du tour automatique")
	_auto_end_check.button_pressed = Settings.auto_end_turn
	_auto_end_check.focus_mode = Control.FOCUS_NONE
	_auto_end_check.add_theme_font_size_override("font_size", 14)
	_auto_end_check.add_theme_color_override("font_color", Color("e8d6b0"))
	_auto_end_check.tooltip_text = Loc.t("Termine votre tour dès que vous n'avez plus rien à jouer (plus de carte jouable ni d'attaque possible).")
	_auto_end_check.toggled.connect(func(on: bool):
		Settings.set_auto_end_turn(on)
		if on:
			_maybe_auto_end_turn())
	# Centrée sous la durée (même colonne que le bouton « Fin du tour »), loin du bord de la fenêtre.
	var auto_box := CenterContainer.new()
	auto_box.position = Vector2(1040, 442)
	auto_box.size = Vector2(228, 28)
	auto_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	auto_box.visible = mode != "replay"
	auto_box.add_child(_auto_end_check)
	_board_root.add_child(auto_box)
	# « Confirmer la fin du tour » : cochée, un appui sur « Fin du tour » alors qu'il reste des actions
	# demande une confirmation ; décochée, le tour se termine tout de suite.
	var confirm_check := CheckBox.new()
	confirm_check.text = Loc.t("Confirmer la fin du tour")
	confirm_check.button_pressed = Settings.confirm_end_turn
	confirm_check.focus_mode = Control.FOCUS_NONE
	confirm_check.add_theme_font_size_override("font_size", 14)
	confirm_check.add_theme_color_override("font_color", Color("e8d6b0"))
	confirm_check.tooltip_text = Loc.t("Demande une confirmation si vous terminez votre tour alors qu'il vous reste des cartes jouables ou des attaques.")
	confirm_check.toggled.connect(func(on: bool):
		Settings.set_confirm_end_turn(on)
		if not on and _end_confirm:
			_end_confirm = false
			_style_end_turn_btn(true))
	var confirm_box := CenterContainer.new()
	confirm_box.position = Vector2(1040, 468)
	confirm_box.size = Vector2(228, 28)
	confirm_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	confirm_box.visible = mode != "replay"
	confirm_box.add_child(confirm_check)
	_board_root.add_child(confirm_box)
	_build_deck_pile(me, DECK_PILE_POS)
	_build_deck_pile(opp, ENEMY_PILE_POS)
	_build_discard_zone()
	_build_play_zone()
	# Petit bouton « Suggestion / bug » : ouvre le forum des suggestions par-dessus la partie.
	var sugg_btn := UITheme.button(Loc.t("Suggestion / bug"), 150)
	sugg_btn.position = Vector2(206, 6)
	sugg_btn.custom_minimum_size = Vector2(150, 28)
	sugg_btn.add_theme_font_size_override("font_size", 13)
	sugg_btn.focus_mode = Control.FOCUS_NONE
	sugg_btn.tooltip_text = Loc.t("Proposer une amélioration de carte ou signaler un bug, sans quitter la partie.")
	sugg_btn.visible = mode != "replay"
	sugg_btn.pressed.connect(_open_suggestions)
	_board_root.add_child(sugg_btn)
	_inferno_label = UITheme.label("", 22, Color("ff8a3a"), 4)
	_inferno_label.position = Vector2(206, 40)
	_inferno_label.visible = false
	_board_root.add_child(_inferno_label)
	_build_sort_bar()

	_preview = CardView.new()
	_preview.position = PREVIEW_POS
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.visible = false
	_board_root.add_child(_preview)

	fx = Fx3D.new()
	add_child(fx)

	_overlay = CanvasLayer.new()
	_overlay.layer = 60
	add_child(_overlay)
	_arrow = Line2D.new()
	_arrow.width = 10
	_arrow.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_arrow.visible = false
	_overlay.add_child(_arrow)
	_arrow_head = Polygon2D.new()
	_arrow_head.polygon = PackedVector2Array([Vector2(0, -16), Vector2(28, 0), Vector2(0, 16)])
	_arrow_head.visible = false
	_overlay.add_child(_arrow_head)

	_tips = KeywordTips.new()
	_overlay.add_child(_tips)

	_banner = UITheme.title_label("", 54)
	_banner.position = Vector2(0, 300)
	_banner.size = Vector2(1280, 80)
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.modulate.a = 0.0
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_banner)


func _build_chat() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(1036, 8)
	panel.custom_minimum_size = Vector2(236, 302)
	panel.size = Vector2(236, 302)
	var ps := UITheme.flat_style(Color(0.08, 0.06, 0.09, 0.88), Color("6b5a3c"), 2, 4)
	ps.set_content_margin_all(4)
	panel.add_theme_stylebox_override("panel", ps)
	_board_root.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)

	_chat_tabs = TabContainer.new()
	_chat_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_tabs.add_theme_font_size_override("font_size", 14)
	_chat_tabs.focus_mode = Control.FOCUS_NONE
	vb.add_child(_chat_tabs)
	_log = _make_channel("Journal")
	_log.meta_underlined = false
	_log.meta_hover_started.connect(_on_log_card_hovered.bind(true))
	_log.meta_hover_ended.connect(_on_log_card_hovered.bind(false))
	_chat_log = _make_channel("Discussion")
	_chat_tabs.tab_changed.connect(func(tab: int):
		if tab == 1:
			_unread = 0
			_chat_tabs.set_tab_title(1, Loc.t("Discussion"))
			if _chat_notice:
				_chat_notice.visible = false)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	vb.add_child(row)
	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = Loc.t("Écrire un message...")
	_chat_input.max_length = 200
	_chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_input.add_theme_font_size_override("font_size", 14)
	_chat_input.text_submitted.connect(_send_chat)
	row.add_child(_chat_input)
	var send := Button.new()
	send.text = Loc.t("OK")
	send.focus_mode = Control.FOCUS_NONE
	send.add_theme_font_size_override("font_size", 14)
	send.pressed.connect(func(): _send_chat(_chat_input.text))
	row.add_child(send)


func _make_channel(title: String) -> RichTextLabel:
	var rt := RichTextLabel.new()
	rt.name = title
	rt.bbcode_enabled = true
	rt.scroll_following = true
	rt.selection_enabled = true
	rt.add_theme_font_size_override("normal_font_size", 14)
	rt.add_theme_font_size_override("bold_font_size", 14)
	rt.add_theme_constant_override("outline_size", 2)
	_chat_tabs.add_child(rt)
	_chat_tabs.set_tab_title(_chat_tabs.get_tab_count() - 1, Loc.t(title))
	return rt


# ======================================================================== CHAT

func _send_chat(text: String) -> void:
	text = text.strip_edges()
	_chat_input.clear()
	_chat_input.release_focus()
	if text == "":
		return
	_chat_tabs.current_tab = 1
	_chat_line(_pname(me), text, true)
	if Net.is_online():
		Net.send_chat(text)
	else:
		await _wait(randf_range(0.8, 1.6))
		_chat_line(_pname(opp), Loc.t(AI_CHAT[randi() % AI_CHAT.size()]), false)


func _on_chat_received(sender: String, text: String) -> void:
	_chat_line(sender, text, false)


func _chat_line(sender: String, text: String, mine: bool) -> void:
	var col := "#7fc8ff" if mine else "#ff9a7a"
	_chat_log.append_text("[color=%s][b]%s[/b][/color] : %s\n" % [col, sender, _escape_bb(text)])
	if not mine and _chat_tabs.current_tab != 1:
		_unread += 1
		_chat_tabs.set_tab_title(1, Loc.t("Discussion (%d)") % _unread)
		Audio.play_sfx("click", 0.1, -8.0)
		_show_chat_notice(sender, text)


## Bandeau en haut de la discussion quand un message arrive alors que l'onglet Journal est affiché :
## qui a écrit et le début du message ; un clic ouvre l'onglet Discussion.
func _show_chat_notice(sender: String, text: String) -> void:
	if _chat_notice == null:
		_chat_notice = PanelContainer.new()
		_chat_notice.position = Vector2(1040, 36)
		_chat_notice.custom_minimum_size = Vector2(228, 0)
		_chat_notice.size = Vector2(228, 0)
		_chat_notice.z_index = 20
		_chat_notice.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var sb := UITheme.flat_style(Color(0.45, 0.12, 0.08, 0.96), Color("ffb080"), 2, 6)
		sb.set_content_margin_all(6)
		_chat_notice.add_theme_stylebox_override("panel", sb)
		var l := UITheme.label("", 14, Color.WHITE, 3)
		l.name = "notice_text"
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 214
		l.max_lines_visible = 3
		_chat_notice.add_child(l)
		_chat_notice.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed:
				_chat_tabs.current_tab = 1)
		_board_root.add_child(_chat_notice)
	var short := text if text.length() <= 70 else text.substr(0, 67) + "…"
	(_chat_notice.get_node("notice_text") as Label).text = Loc.t("Nouveau message de %s : %s") % [sender, short]
	_chat_notice.tooltip_text = Loc.t("Cliquez pour ouvrir la discussion")
	_chat_notice.reset_size()
	_chat_notice.visible = true
	_chat_notice.modulate.a = 1.0
	if _chat_notice.has_meta("tw"):
		var old: Tween = _chat_notice.get_meta("tw")
		if old and old.is_valid():
			old.kill()
	var tw := _chat_notice.create_tween()
	tw.tween_property(_chat_notice, "scale", Vector2.ONE * 1.05, 0.12)
	tw.tween_property(_chat_notice, "scale", Vector2.ONE, 0.12)
	tw.tween_interval(6.0)
	tw.tween_property(_chat_notice, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func(): _chat_notice.visible = false)
	_chat_notice.set_meta("tw", tw)


func _system_chat(text: String) -> void:
	_chat_log.append_text("[color=#c9b79a][i]%s[/i][/color]\n" % text)


func _escape_bb(t: String) -> String:
	return t.replace("[", "[lb]")


func _log_line(bb: String) -> void:
	_log.append_text(bb + "\n")
	if Settings.autoplay:
		var plain := RegEx.create_from_string("\\[[^\\]]*\\]").sub(bb, "", true)
		print("[%s] %s" % [_pname(me), plain])


# ======================================================================== DÉROULEMENT

func _start_game() -> void:
	var first := randi() % 2
	var seed_value := randi() % 2147483647   # graine connue : la partie pourra être revue (replay)
	if mode == "ai" and Lobby.online:
		# Le serveur fournit la graine et le premier joueur : il pourra rejouer et vérifier la partie.
		var t: Dictionary = await Lobby.request_ticket("ai", Settings.ai_difficulty)
		if not t.is_empty():
			first = int(t.first)
			seed_value = int(t.seed)
			_ticket = str(t.id)
	if Net.is_online():
		first = Net.match_first
		seed_value = Net.match_seed
		_system_chat(Loc.t("Partie en ligne contre %s. Appuyez sur [%s] pour écrire.") % [_pname(opp), Settings.key_label("open_chat")])
	elif mode == "replay":
		first = int(Net.replay.get("first", 0))
		seed_value = int(Net.replay.get("seed", 0))
		_system_chat(Loc.t("Replay : %s contre %s.") % [_pname(0), _pname(1)])
		var played_on := str(Net.replay.get("game", ""))
		if played_on != "" and played_on != Updater.current_version():
			_system_chat(Loc.t("Partie jouée en version %s : si des cartes ont changé depuis, le replay peut différer légèrement.") % played_on)
	else:
		_system_chat(Loc.t("Duel contre %s. Appuyez sur [%s] pour écrire.") % [_pname(opp), Settings.key_label("open_chat")])
		_chat_line(_pname(opp), Loc.t("Prépare-toi à tomber, chevalier !"), false)
	_first = first
	_seed = seed_value
	if mode == "ai" and Settings.ai_difficulty == 4:
		_bonus = AIPlayer.inferno_bonus(opp)
		_system_chat(Loc.t("Inferno : %s a des PV infinis. Infligez-lui un maximum de dégâts avant de tomber !") % _pname(opp))
		_system_chat(Loc.t("Ses dégâts de fatigue (deck vide) comptent dans votre score, mais chacun de ses soins le fait baisser."))
	elif mode == "ai" and Settings.ai_difficulty >= 3:
		_bonus = AIPlayer.challenger_bonus(opp)
		_system_chat(Loc.t("Challenger : %s commence avec %d PV et %d carte de plus.") % [_pname(opp), int(_bonus.health), int(_bonus.cards)])
	elif mode == "replay":
		_bonus = Net.replay.get("bonus", {})
	if ai:
		ai._rng.seed = MatchCheck.ai_seed(seed_value)   # IA déterministe : ses coups sont vérifiables
	gs.setup(first, seed_value, _bonus)
	if gs.inferno >= 0:
		_hero_views[gs.inferno].infinite = true
		_update_inferno_score()
	_start_msec = Time.get_ticks_msec()
	_log_line(Loc.t("[color=#f2c14e]Le duel commence ![/color]"))
	await _coin_toss(first)
	_add_first_token(first)
	_log_line(Loc.t("La pièce désigne [b]%s[/b] pour commencer.") % _pname(first))
	await _show_banner(Loc.t("Vous commencez !") if first == me and mode != "replay" else Loc.t("%s commence !") % _pname(first), 1.2)
	await _process_events(gs.pop_events(), true)
	_started = true
	busy = false
	_kick_queue()
	if mode == "ai" and gs.current == opp:
		_run_ai_turn()
	_refresh()
	if mode == "replay":
		_run_replay()


## Action du joueur local.
func _submit(act: Dictionary) -> void:
	if mode == "client":
		_awaiting_server = true
		_refresh()
		Net.send_request(act)
	else:
		_enqueue(me, act)


func _enqueue(player: int, act: Dictionary) -> void:
	_queue.append([player, act])
	_kick_queue()


func _kick_queue() -> void:
	if _started and not _queue_running and not _queue.is_empty():
		_run_queue()


func _run_queue() -> void:
	_queue_running = true
	busy = true
	_cancel_targeting()
	_refresh()
	while not _queue.is_empty():
		var item: Array = _queue.pop_front()
		var p: int = item[0]
		var act: Dictionary = item[1]
		var ok := _apply(p, act)
		_last_ok = ok
		if ok and mode != "replay":
			_record.append(_encode_action(p, act))
		elif not ok and mode == "replay" and Settings.autoplay:
			print("[replay] action refusée : joueur %d %s (tour %d)" % [p, act, gs.turn_number])
		if mode == "host":
			if ok:
				Net.broadcast_action(p, act)
			elif p != me:
				Net.reject_request()
		if p == me:
			_awaiting_server = false
		if ok:
			await _process_events(gs.pop_events())
	_queue_running = false
	busy = false
	_refresh()
	queue_idle.emit()
	if mode == "ai" and gs.current == opp and not gs.is_over() and not _ai_running:
		_run_ai_turn()


func _apply(p: int, act: Dictionary) -> bool:
	var ok := MatchCheck.apply_action(gs, p, act)
	if ok and act.get("type", "") == "concede":
		_end_reason = "concede"
	return ok


func _run_ai_turn() -> void:
	_ai_running = true
	await _wait(0.6)
	var guard := 0
	while gs.current == opp and not gs.is_over() and guard < 40:
		guard += 1
		var act := ai.next_action(gs)
		if act.type == "end":
			act = {"type": "end_turn"}
		_enqueue(opp, act)
		if _queue_running:
			await queue_idle
		if act.type == "end_turn":
			break
		if not _last_ok:
			_enqueue(opp, {"type": "end_turn"})
			if _queue_running:
				await queue_idle
			break
		await _wait(0.4)
	_ai_running = false


func _on_net_action(player: int, act: Dictionary) -> void:
	_enqueue(player, act)


func _on_net_rejected() -> void:
	_awaiting_server = false
	if _choice_layer:
		_choice_layer.remove_meta("picked")
	_refresh()
	_float_text(Vector2(640, 360), Loc.t("Action refusée"), UITheme.RED)


func _on_opponent_left() -> void:
	_system_chat(Loc.t("%s a quitté la partie.") % _pname(opp))
	if not gs.is_over():
		_end_reason = "disconnect"
		gs.concede(opp)
		_log_line(Loc.t("[color=#ff9a7a]%s s'est déconnecté : victoire par forfait.[/color]") % _pname(opp))
		await _process_events(gs.pop_events())
	elif _game_over_box:
		for c in _game_over_box.get_children():
			if c.has_meta("rematch"):
				c.queue_free()
		_clear_rematch_row()
		if _rematch_row and is_instance_valid(_rematch_row):
			_rematch_row.add_child(UITheme.label(Loc.t("%s est parti : pas de revanche possible.") % _pname(opp), 18, Color("c9b79a")))


func _on_rematch_pressed() -> void:
	Net.ask_rematch()
	if _rematch_btn:
		_rematch_btn.disabled = true
		_rematch_btn.text = Loc.t("Demande envoyée...")
	_clear_rematch_row()
	if _rematch_row and not Net.rematch_remote:
		_rematch_row.add_child(UITheme.label(Loc.t("En attente de la réponse de %s...") % _pname(opp), 18, Color("c9b79a")))


func _clear_rematch_row() -> void:
	if _rematch_row and is_instance_valid(_rematch_row):
		for c in _rematch_row.get_children():
			c.queue_free()


## Réponse ou demande de l'adversaire.
func _on_rematch_changed(state: String) -> void:
	if not gs.is_over() or _rematch_row == null or not is_instance_valid(_rematch_row):
		return
	_clear_rematch_row()
	match state:
		"ask":
			if Settings.auto_accept:
				print("[%s] revanche demandée par %s : acceptée" % [_pname(me), _pname(opp)])
				Net.accept_rematch()
				return
			Audio.play_sfx("end_turn", 0.0)
			_rematch_row.add_child(UITheme.label(Loc.t("%s propose une revanche !") % _pname(opp), 20, UITheme.GOLD))
			var yes := UITheme.button(Loc.t("Accepter"), 150)
			yes.pressed.connect(func():
				_clear_rematch_row()
				_rematch_row.add_child(UITheme.label(Loc.t("Revanche acceptée : lancement..."), 18, UITheme.GREEN))
				if _rematch_btn:
					_rematch_btn.disabled = true
				Net.accept_rematch())
			_rematch_row.add_child(yes)
			var no := UITheme.button(Loc.t("Refuser"), 150)
			no.pressed.connect(func():
				_clear_rematch_row()
				Net.decline_rematch())
			_rematch_row.add_child(no)
		"decline":
			_rematch_row.add_child(UITheme.label(Loc.t("%s a refusé la revanche.") % _pname(opp), 18, UITheme.RED))
			if _rematch_btn:
				_rematch_btn.disabled = false
				_rematch_btn.text = Loc.t("Revanche")


## Gains de la partie (envoyés par le serveur) : pièces d'or et XP du passe de combat.
func _on_reward(r: Dictionary) -> void:
	if Settings.autoplay:
		print("[%s] RÉCOMPENSE : %s" % [_pname(me), r])
	if _game_over_vb == null or not is_instance_valid(_game_over_vb):
		return
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 10)
	hb.add_child(GoldCoin.new(15))
	var po := int(r.get("po", 0)) + int(r.get("bonus", 0)) + int(r.get("pass_po", 0))
	var parts := [Loc.t("+%d PO") % po]
	if int(r.get("bonus", 0)) > 0:
		parts.append(Loc.t("dont %d de 1re victoire du jour") % int(r.bonus))
	parts.append(Loc.t("+%d XP de passe (niveau %d)") % [int(r.get("xp", 0)), int(r.get("level", 0))])
	hb.add_child(UITheme.label("  ·  ".join(parts), 20, UITheme.GOLD, 4))
	_game_over_vb.add_child(hb)
	_game_over_vb.move_child(hb, 2)
	if po > 0:
		Lobby.fx.coins(po, Vector2(640, 560), Vector2(600, 300))
	if r.get("level_up", false):
		_float_text(Vector2(640, 250), Loc.t("Niveau %d du passe !") % int(r.level), UITheme.GOLD, 30)


func concede() -> void:
	_cancel_targeting()
	_submit({"type": "concede"})


# ======================================================================== ÉVÉNEMENTS

func _process_events(events: Array[Dictionary], quick := false) -> void:
	for ev in events:
		_track_stats(ev)
		match ev.t:
			"turn_start":
				_refresh_heroes()
				if not quick or ev.turn > 1:
					Audio.play_sfx("end_turn", 0.02)
				var mine: bool = ev.player == me
				_log_line(Loc.t("[color=#f2c14e]— Tour %d : %s —[/color]") % [_round(int(ev.turn)), Loc.t("vous") if mine else _pname(opp)])
				await _show_banner(Loc.t("Votre tour") if mine else Loc.t("Tour de %s") % _pname(opp), 0.8)
			"draw_choice":
				if ev.player == me:
					_log_line(Loc.t("Vous révélez %d cartes : choisissez-en une.") % ev.options.size())
				else:
					_log_line(Loc.t("%s choisit une carte parmi %d.") % [_pname(opp), ev.options.size()])
					_float_text(_hero_views[opp].center() + Vector2(0, 60), Loc.t("Choisit une carte..."), UITheme.GOLD, 22)
			"chosen":
				_close_choice()
				var n := int(ev.to_bottom)
				if n > 0:
					var who := Loc.t("Vous remettez") if ev.player == me else Loc.t("%s remet") % _pname(opp)
					_log_line((Loc.t("%s %d cartes au fond du deck.") if n > 1 else Loc.t("%s %d carte au fond du deck.")) % [who, n])
			"draw":
				await _on_draw(ev, quick)
			"burn":
				_log_line(Loc.t("Main pleine : [b]%s[/b] est détruite.") % _cn(ev.card_id))
				_float_text(_hero_views[ev.player].center(), Loc.t("Main pleine !"), UITheme.RED)
			"fatigue":
				_log_line(Loc.t("%s : deck vide, fatigue (%d dégâts).") % [_pname(ev.player), ev.amount])
				_float_text(_hero_views[ev.player].center() + Vector2(0, -40), Loc.t("Fatigue !"), UITheme.RED)
			"play":
				await _on_play(ev)
			"summon":
				_on_summon(ev)
				if CardDB.get_card(ev.card_id).get("token", false):
					await fx.summon(_minion_views[ev.uid].center())
				else:
					await _wait(0.25)
			"fx":
				await _on_fx(ev)
			"attack":
				await _on_attack(ev)
			"damage":
				_on_damage(ev)
			"heal":
				_float_text(_entity_pos(ev.uid), "+%d" % ev.amount, UITheme.GREEN)
				if ev.has("inferno"):
					_update_inferno_score(int(ev.inferno))
					_float_text(_inferno_label.global_position + Vector2(20, 30), Loc.t("Score -%d") % ev.amount, UITheme.RED, 20)
				else:
					_view_add_hp(ev.uid, ev.amount)
				if int(ev.uid) == GameState.HERO_UIDS[me]:
					_log_line(Loc.t("Vous récupérez %d PV.") % ev.amount)
				else:
					_log_line(Loc.t("%s récupère %d PV.") % [_entity_name(ev.uid), ev.amount])
			"buff":
				_float_text(_entity_pos(ev.uid), "+%d/+%d" % [ev.attack, ev.health], UITheme.GOLD)
				_log_line(Loc.t("%s gagne +%d/+%d.") % [_entity_name(ev.uid), ev.attack, ev.health])
				var e := gs.get_entity(ev.uid)
				if e and _minion_views.has(ev.uid):
					_minion_views[ev.uid].sync(e, false)
			"enchant":
				await _on_enchant(ev)
			"enchant_trigger":
				_log_line(Loc.t("[color=#c9a0ff]%s[/color] se déclenche.") % _cn(ev.card_id))
				if _enchant_views.has(ev.uid):
					_enchant_views[ev.uid].pulse()
				await _wait(0.3)
			"enchant_destroyed":
				await _on_enchant_destroyed(ev)
			"minion_trigger":
				_log_line(Loc.t("[color=#f2c14e]%s[/color] : effet continu.") % _cn(ev.card_id))
				if _minion_views.has(ev.uid):
					_minion_views[ev.uid].pulse()
				await _wait(0.3)
			"resurrect":
				var who := Loc.t("Vous ramenez") if ev.player == me else Loc.t("%s ramène") % _pname(ev.player)
				_log_line(Loc.t("%s [b]%s[/b] du cimetière.") % [who, _cn(ev.card_id)])
				_float_text(_hero_views[ev.player].center() + Vector2(0, -60), Loc.t("Résurrection !"), Color("c9a0ff"), 24)
				await _wait(0.2)
			"recall":
				if ev.player == me:
					_log_line(Loc.t("Vous récupérez [b]%s[/b] depuis votre cimetière.") % _cn(ev.card_id))
				else:
					_log_line(Loc.t("%s récupère [b]%s[/b] depuis son cimetière.") % [_pname(ev.player), _cn(ev.card_id)])
			"purge":
				var names: Array[String] = []
				for id in ev.cards:
					names.append(_cn(id))
				var whose := Loc.t("votre deck") if ev.player == me else Loc.t("le deck de %s") % _pname(ev.player)
				if names.is_empty():
					_log_line(Loc.t("Aucune carte ne correspond dans %s.") % whose)
				else:
					_log_line((Loc.t("%d cartes retirées de %s : %s.") if names.size() > 1 else Loc.t("%d carte retirée de %s : %s.")) % [
						names.size(), whose, ", ".join(names)])
					_float_text(_hero_views[ev.player].center() + Vector2(0, -60), Loc.t("-%d au deck") % names.size(), Color("c9a0ff"), 22)
				await _wait(0.3)
			"destroy":
				_float_text(_entity_pos(ev.uid), Loc.t("Détruit !"), UITheme.RED, 26)
			"aura":
				var txt := "%+d/%+d" % [ev.attack, ev.health]
				_float_text(_entity_pos(ev.uid), txt, Color("c9a0ff") if ev.attack + ev.health > 0 else Color("9a8aa8"), 22)
				var ae := gs.get_entity(ev.uid)
				if ae and _minion_views.has(ev.uid):
					_minion_views[ev.uid].sync(ae, false)
			"discard":
				await _on_discard(ev)
			"mulligan":
				await _on_mulligan(ev)
			"shield_pop":
				_log_line(Loc.t("Le bouclier divin de %s se brise.") % _entity_name(ev.uid))
				if _minion_views.has(ev.uid):
					_minion_views[ev.uid].pop_shield()
				await fx.shield_pop(_entity_pos(ev.uid))
			"death":
				await _on_death(ev)
			"game_over":
				_refresh()
				await _wait(0.6)
				_show_game_over(ev.winner)
				return
	_refresh()


## Statistiques du joueur local, envoyées au serveur en fin de partie.
func _track_stats(ev: Dictionary) -> void:
	match ev.t:
		"play":
			var cp: Dictionary = _card_plays[int(ev.player)]
			cp[ev.card_id] = int(cp.get(ev.card_id, 0)) + 1
			if ev.player != me:
				return
			var c := CardDB.get_card(ev.card_id)
			var kind: String = {"minion": "minions_played", "spell": "spells_played", "enchantment": "enchants_played"}.get(c.type, "")
			_add_stat(kind, 1)
			for kw in c.get("keywords", []):
				_add_stat({"taunt": "taunt_played", "charge": "charge_played", "divine_shield": "shield_played",
					"deathrattle": "deathrattle_played"}.get(kw, ""), 1)
		"damage":
			if int(ev.uid) == GameState.HERO_UIDS[opp]:
				_add_stat("hero_damage", int(ev.amount))
		"enchant_destroyed":
			if ev.player == opp:
				_add_stat("enchants_destroyed", 1)


func _add_stat(key: String, n: int) -> void:
	if key != "":
		_stats[key] = int(_stats.get(key, 0)) + n


## Rangement de la main (en bas à droite) : manuel (glisser-déposer) ou tri automatique.
func _build_sort_bar() -> void:
	var hb := HBoxContainer.new()
	hb.position = Vector2(1004, 674)
	hb.add_theme_constant_override("separation", 4)
	_board_root.add_child(hb)
	var l := UITheme.label(Loc.t("Main :"), 14, Color("e8d6b0"), 3)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(l)
	for m in [["manual", "Manuel", 66, "Rangement libre : glissez les cartes pour les déplacer"],
			["cost", "Coût", 50, "Du plus petit au plus grand coût d'énergie"],
			["health", "PV", 40, "Par points de vie (les sorts à la fin)"],
			["attack", "Attaque", 70, "Par attaque (les sorts à la fin)"]]:
		var b := Button.new()
		b.text = Loc.t(m[1])
		b.tooltip_text = Loc.t(m[3])
		b.custom_minimum_size = Vector2(m[2], 30)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 13)
		var key: String = m[0]
		b.pressed.connect(func(): _set_hand_sort(key))
		hb.add_child(b)
		_sort_btns[key] = b
	_update_sort_btns()


func _set_hand_sort(mode_name: String) -> void:
	Settings.set_hand_sort(mode_name)
	Audio.play_sfx("click", 0.1)
	_update_sort_btns()
	_layout_hand()


func _update_sort_btns() -> void:
	for k in _sort_btns:
		var on: bool = k == Settings.hand_sort
		var b: Button = _sort_btns[k]
		b.add_theme_color_override("font_color", UITheme.GOLD if on else UITheme.LIGHT_TEXT)
		b.add_theme_stylebox_override("normal", UITheme.flat_style(Color(0.32, 0.22, 0.08, 0.95) if on else Color(0.12, 0.09, 0.08, 0.9),
			UITheme.GOLD if on else Color("6b5a3c"), 2, 4))


## Clé de tri d'une carte de la main selon le mode choisi (les sorts sans stats vont à la fin).
func _sort_key(cv: CardView) -> Array:
	var c := CardDB.get_card(cv.card_id)
	match Settings.hand_sort:
		"health":
			return [0 if c.type == "minion" else 1, int(c.get("health", 0)), int(c.cost), cv.hand_uid]
		"attack":
			return [0 if c.type == "minion" else 1, int(c.get("attack", 0)), int(c.cost), cv.hand_uid]
	return [int(c.cost), 0, 0, cv.hand_uid]


func _hand_less(a: CardView, b: CardView) -> bool:
	var ka := _sort_key(a)
	var kb := _sort_key(b)
	for i in ka.size():
		if ka[i] != kb[i]:
			return ka[i] < kb[i]
	return false


## Main : les cartes rapetissent quand la main grandit, pour rester côte à côte sans se chevaucher
## (PV et attaque toujours lisibles) dans la largeur entre les héros et la colonne de droite.
const HAND_WIDTH := 710.0   # de x 285 à 995 : ni les héros ni la colonne de droite (« Main : ») ne sont recouverts
const HAND_GAP := 6.0


func _hand_scale(n: int) -> float:
	return minf(HAND_SCALE, (HAND_WIDTH - (maxi(n, 1) - 1) * HAND_GAP) / (maxi(n, 1) * CardView.SIZE.x))


func _hand_spacing(n: int) -> float:
	return CardView.SIZE.x * _hand_scale(n) + HAND_GAP


func _hand_x(i: int, n: int) -> float:
	var spacing := _hand_spacing(n)
	return 640.0 - (n - 1) * spacing / 2.0 + i * spacing - CardView.SIZE.x / 2


## Glisser-déposer d'une carte de la main : elle suit la souris.
## Relâchée sur le plateau, elle est jouée ; sur la zone « Défausser » (en bas à droite), défaussée ;
## dans la main, elle prend la place la plus proche (rangement manuel).
const HAND_ZONE_Y := 520.0   # au-dessus (coordonnées du plateau) : la carte est sur le plateau
var _drag_pos := Vector2.ZERO   # dernière position de la carte glissée (coordonnées du plateau)


func _on_hand_drag(cv: CardView, gpos: Vector2) -> void:
	if _dragging_card != cv:
		_dragging_card = cv
		_tips.hide_tips()
		_select_hand(null)
		_cancel_targeting()
		if cv.has_meta("tw"):
			var old: Tween = cv.get_meta("tw")
			if old and old.is_valid():
				old.kill()
		cv.scale = Vector2.ONE * _hand_scale(_hand_views.size())
		_discard_zone.visible = _can_act()
		_show_play_zone(cv)
	var local := gpos - _hand_root.global_position
	_drag_pos = local
	cv.z_index = 60
	# Au-dessus de la zone « Défausser », la carte rapetisse pour laisser voir la zone.
	var over_discard := _discard_zone.visible and DISCARD_RECT.has_point(local)
	var s := 0.4 if over_discard else _hand_scale(_hand_views.size())
	cv.scale = Vector2.ONE * s
	cv.modulate.a = 0.8 if over_discard else 1.0
	# Pivot en bas au centre : la carte est centrée sur la souris.
	cv.position = Vector2(local.x - CardView.SIZE.x / 2, local.y - CardView.SIZE.y + CardView.SIZE.y * s / 2)
	_style_discard_zone(over_discard)
	_style_play_zone(not over_discard and local.y < HAND_ZONE_Y and local.x < 1036.0)
	if local.y < HAND_ZONE_Y or DISCARD_RECT.has_point(local):
		return   # hors de la main : l'ordre des autres cartes ne change pas
	var n := _hand_views.size()
	var spacing := _hand_spacing(n)
	var first := 640.0 - (n - 1) * spacing / 2.0
	var idx := clampi(roundi((local.x - first) / spacing), 0, n - 1)
	if _hand_views.find(cv) != idx:
		if Settings.hand_sort != "manual":
			_set_hand_sort("manual")   # déplacer une carte passe en rangement manuel (ordre actuel conservé)
		_hand_views.erase(cv)
		_hand_views.insert(idx, cv)
		_layout_hand()


func _on_hand_drag_released(cv: CardView) -> void:
	if _dragging_card != cv:
		_layout_hand()
		return
	_dragging_card = null
	_discard_zone.visible = false
	_play_zone.visible = false
	cv.modulate.a = 1.0
	var local := _drag_pos
	if DISCARD_RECT.has_point(local) and _can_act():
		_submit({"type": "discard", "hand_uid": cv.hand_uid})
		return
	if local.y < HAND_ZONE_Y and local.x < 1036.0 and _can_act():
		_layout_hand()   # la carte revient dans la main (le jeu l'en retire s'il la joue)
		_play_from_hand(cv, cv.global_position + Vector2(64, 40))
		return
	Audio.play_sfx("card_draw", 0.1, -8.0)
	_layout_hand()


func _select_hand(cv: CardView) -> void:
	if _selected_hand and is_instance_valid(_selected_hand):
		_selected_hand.set_selected(false)
	_selected_hand = cv
	if cv:
		cv.set_selected(true)
	_layout_hand()


## Tour affiché : un tour comprend le jeu des deux joueurs (tours de jeu 1 et 2 -> tour 1, 3 et 4 -> tour 2...).
func _round(turn_number: int) -> int:
	return maxi(1, (turn_number + 1) / 2)


func _update_clock() -> void:
	if _clock == null or _start_msec == 0:
		return
	var end := _clock_stop_msec if _clock_stop_msec > 0 else Time.get_ticks_msec()
	var t := int((end - _start_msec) / 1000.0)
	if gs != null and _turn_label != null:
		_turn_label.text = Loc.t("Tour %d") % _round(int(gs.turn_number))
	_clock.text = (Loc.t("Durée %d:%02d:%02d") % [t / 3600, (t / 60) % 60, t % 60]) if t >= 3600 else (Loc.t("Durée %02d:%02d") % [t / 60, t % 60])


func _on_draw(ev: Dictionary, quick: bool) -> void:
	if ev.player == me:
		var cv := CardView.new().setup(ev.card_id, ev.uid)
		cv.draggable = true
		cv.drag_moved.connect(_on_hand_drag)
		cv.drag_released.connect(_on_hand_drag_released)
		cv.scale = Vector2.ONE * HAND_SCALE
		cv.pivot_offset = Vector2(CardView.SIZE.x / 2, CardView.SIZE.y)
		cv.position = Vector2(560, HAND_Y)
		cv.modulate.a = 0.0
		cv.pressed.connect(_on_hand_card_pressed)
		cv.hovered.connect(_on_hand_card_hovered)
		_hand_root.add_child(cv)
		_hand_views.append(cv)
		if not quick:
			Audio.play_sfx("card_draw")
			_log_line(Loc.t("Vous piochez [b]%s[/b].") % _cn(ev.card_id))
			await fx.draw_cards(_hero_views[me].center(), Vector2(640, 640), 1, _back_tex(me))
		cv.modulate.a = 1.0
		_layout_hand()
	else:
		var back := CardView.new().setup(ev.card_id, ev.uid, true)
		back.set_back_texture(_back_tex(opp))
		back.scale = Vector2.ONE * 0.55
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		back.position = Vector2(560, -200)
		_enemy_hand_root.add_child(back)
		_enemy_hand_views.append(back)
		if not quick:
			Audio.play_sfx("card_draw", 0.1, -6.0)
			_log_line(Loc.t("%s pioche une carte.") % _pname(opp))
			await fx.draw_cards(_hero_views[opp].center(), Vector2(640, 40), 1, _back_tex(opp))
		_layout_enemy_hand()
	_refresh_heroes()


func _on_play(ev: Dictionary) -> void:
	var card := CardDB.get_card(ev.card_id)
	Audio.play_sfx("card_play")
	var target_txt := ""
	if int(ev.get("target", -1)) != -1:
		target_txt = Loc.t(" sur %s") % _entity_name(ev.target)
	if ev.player == me:
		_log_line(Loc.t("Vous jouez [b]%s[/b]%s.") % [_cn(ev.card_id), target_txt])
		var cv := _find_hand_view(ev.hand_uid)
		if cv:
			_hand_views.erase(cv)
			if _hovered_hand == cv:
				_hovered_hand = null
			cv.z_index = 20
			cv.pivot_offset = CardView.SIZE / 2
			var tw := cv.create_tween().set_parallel(true)
			tw.tween_property(cv, "position", Vector2(560, 230), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(cv, "scale", Vector2.ONE, 0.22)
			tw.chain().tween_interval(0.25)
			tw.chain().tween_property(cv, "modulate:a", 0.0, 0.2)
			tw.chain().tween_callback(cv.queue_free)
			_layout_hand()
			await _wait(0.35)
	else:
		_log_line(Loc.t("%s joue [b]%s[/b]%s.") % [_pname(opp), _cn(ev.card_id), target_txt])
		for b in _enemy_hand_views:
			if b.hand_uid == ev.hand_uid:
				_enemy_hand_views.erase(b)
				b.queue_free()
				break
		_layout_enemy_hand()
		# Révèle la carte jouée par l'adversaire au centre de l'écran.
		var reveal := CardView.new().setup(ev.card_id)
		reveal.mouse_filter = Control.MOUSE_FILTER_IGNORE
		reveal.position = Vector2(560, 60)
		reveal.scale = Vector2.ONE * 0.5
		reveal.z_index = 30
		_board_root.add_child(reveal)
		var tw := reveal.create_tween()
		tw.tween_property(reveal, "scale", Vector2.ONE * 1.25, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.9)
		tw.tween_property(reveal, "modulate:a", 0.0, 0.2)
		tw.tween_callback(reveal.queue_free)
		await _wait(1.15)
	_refresh_heroes()


func _on_summon(ev: Dictionary) -> void:
	var e := gs.get_entity(ev.uid)
	if e == null:
		# Le serviteur est déjà mort dans l'état final : on l'affiche quand même brièvement.
		var c := CardDB.get_card(ev.card_id)
		e = GameState.Entity.new()
		e.uid = ev.uid
		e.card_id = ev.card_id
		e.attack = c.attack
		e.health = c.health
		e.max_health = c.health
	var mv := MinionView.new().setup(e)
	mv.pressed.connect(_on_minion_pressed)
	mv.hovered.connect(_on_minion_hovered)
	_board_root.add_child(mv)
	# Sous la main dans l'ordre de l'arbre : une carte survolée (agrandie) garde la souris, et son bouton « X »
	# reste cliquable même au-dessus d'un serviteur.
	_board_root.move_child(mv, _enemy_hand_root.get_index())
	_minion_views[ev.uid] = mv
	_layout_board(ev.player)
	mv.scale = Vector2.ONE * 0.2
	mv.modulate.a = 0.0
	var tw := mv.create_tween().set_parallel(true)
	tw.tween_property(mv, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(mv, "modulate:a", 1.0, 0.15)
	fx.impact(mv.center(), Color(1, 0.9, 0.7))


## Enchantement posé : il apparaît dans la zone de son propriétaire.
func _on_enchant(ev: Dictionary) -> void:
	var e := gs.get_entity(ev.uid)
	if e == null:
		# Déjà détruit dans l'état final : vue temporaire pour l'animation.
		e = GameState.Entity.new()
		e.uid = ev.uid
		e.card_id = ev.card_id
		e.is_enchant = true
		e.health = 1
		e.max_health = 1
	var v := EnchantView.new().setup(e)
	v.pressed.connect(_on_enchant_pressed)
	v.hovered.connect(_on_enchant_hovered)
	_board_root.add_child(v)
	_board_root.move_child(v, _enemy_hand_root.get_index())
	_enchant_views[ev.uid] = v
	_layout_enchants(ev.player)
	v.scale = Vector2.ONE * 0.2
	v.modulate.a = 0.0
	var tw := v.create_tween().set_parallel(true)
	tw.tween_property(v, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(v, "modulate:a", 1.0, 0.15)
	await fx.summon(v.center())


func _on_enchant_destroyed(ev: Dictionary) -> void:
	_log_line(Loc.t("L'enchantement [b]%s[/b] est détruit.") % _cn(ev.card_id))
	var v: EnchantView = _enchant_views.get(ev.uid)
	if v == null:
		return
	Audio.play_sfx("shield")
	fx.death(v.center())
	_enchant_views.erase(ev.uid)
	var tw := v.create_tween().set_parallel(true)
	tw.tween_property(v, "scale", Vector2(1.3, 0.1), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(v, "modulate", Color(0.6, 0.3, 1.0, 0.0), 0.3)
	tw.chain().tween_callback(v.queue_free)
	await _wait(0.32)
	_layout_enchants(ev.player)


func _on_discard(ev: Dictionary) -> void:
	var card := CardDB.get_card(ev.card_id)
	Audio.play_sfx("card_draw", 0.1, -4.0)
	if ev.player == me:
		_log_line(Loc.t("Vous défaussez [b]%s[/b].") % _cn(ev.card_id))
		var cv := _find_hand_view(ev.hand_uid)
		if cv:
			_hand_views.erase(cv)
			if _hovered_hand == cv:
				_hovered_hand = null
				_tips.hide_tips()
			cv.z_index = 20
			var tw := cv.create_tween().set_parallel(true)
			tw.tween_property(cv, "position", cv.position + Vector2(0, 140), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_property(cv, "rotation", 0.35, 0.3)
			tw.tween_property(cv, "modulate", Color(0.4, 0.3, 0.3, 0.0), 0.3)
			tw.chain().tween_callback(cv.queue_free)
			_layout_hand()
	else:
		_log_line(Loc.t("%s défausse [b]%s[/b].") % [_pname(opp), _cn(ev.card_id)])
		for b in _enemy_hand_views:
			if b.hand_uid == ev.hand_uid:
				_enemy_hand_views.erase(b)
				var tw := b.create_tween()
				tw.tween_property(b, "modulate:a", 0.0, 0.25)
				tw.tween_callback(b.queue_free)
				break
		_layout_enemy_hand()
	await _wait(0.25)


## Changement de main : la main part au cimetière (les nouvelles cartes arrivent par les événements « draw »).
func _on_mulligan(ev: Dictionary) -> void:
	Audio.play_sfx("card_draw", 0.1, -4.0)
	var n: int = ev.cards.size()
	if ev.player == me:
		_log_line(Loc.t("Vous changez de main : %d cartes au cimetière, nouvelle main de %d cartes.") % [n, n - 1])
		for uid in ev.hand_uids:
			var cv := _find_hand_view(int(uid))
			if cv == null:
				continue
			_hand_views.erase(cv)
			if _hovered_hand == cv:
				_hovered_hand = null
				_tips.hide_tips()
			if _selected_hand == cv:
				_select_hand(null)
			cv.z_index = 20
			var tw := cv.create_tween().set_parallel(true)
			tw.tween_property(cv, "position", cv.position + Vector2(0, 140), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_property(cv, "rotation", 0.35, 0.35)
			tw.tween_property(cv, "modulate", Color(0.4, 0.3, 0.3, 0.0), 0.35)
			tw.chain().tween_callback(cv.queue_free)
	else:
		_log_line(Loc.t("%s change de main : %d cartes au cimetière, nouvelle main de %d cartes.") % [_pname(ev.player), n, n - 1])
		for b in _enemy_hand_views.duplicate():
			if int(b.hand_uid) in ev.hand_uids:
				_enemy_hand_views.erase(b)
				var tw: Tween = b.create_tween()
				tw.tween_property(b, "modulate:a", 0.0, 0.25)
				tw.tween_callback(b.queue_free)
		_layout_enemy_hand()
	_float_text(_hero_views[ev.player].center() + Vector2(0, -60), Loc.t("Nouvelle main !"), Color("c9a0ff"), 24)
	_refresh_heroes()
	await _wait(0.45)


func _enchant_zone_y(player: int) -> float:
	return 230.0 if player == opp else 384.0


func _layout_enchants(player: int) -> void:
	_enchant_zone_labels[player].visible = gs.players[player].enchants.is_empty()
	var i := 0
	for e in gs.players[player].enchants:
		var v: EnchantView = _enchant_views.get(e.uid)
		if v == null:
			continue
		var target := Vector2(67 + i * 76, _enchant_zone_y(player))
		if v.position == Vector2.ZERO:
			v.position = target
		else:
			v.create_tween().tween_property(v, "position", target, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		i += 1


func _on_fx(ev: Dictionary) -> void:
	var fx_name: String = ev.fx
	if fx_name == "" or fx_name == "summon":
		return   # l'invocation est animée lors de l'événement "summon"
	if fx_name == "draw":
		# Pas d'animation ici : chaque carte réellement piochée est animée par son événement « draw »
		# (l'ancienne animation de 2 cartes s'ajoutait aux pioches : 4 cartes volaient pour 2 piochées).
		return
	var targets: Array = []
	for uid in ev.targets:
		targets.append(_entity_pos(uid))
	await fx.play_card_fx(fx_name, _entity_pos(ev.source), targets)


func _on_attack(ev: Dictionary) -> void:
	if int(ev.defender) == GameState.HERO_UIDS[me]:
		_log_line(Loc.t("[b]%s[/b] vous attaque.") % _entity_name(ev.attacker))
	else:
		_log_line(Loc.t("[b]%s[/b] attaque [b]%s[/b].") % [_entity_name(ev.attacker), _entity_name(ev.defender)])
	var av: MinionView = _minion_views.get(ev.attacker)
	if av == null:
		return
	var start := av.position
	var target := _entity_pos(ev.defender) - MinionView.SIZE / 2
	var dir := target - start
	av.z_index = 15
	var tw := av.create_tween()
	tw.tween_property(av, "position", start - dir.normalized() * 18, 0.12)
	tw.tween_property(av, "position", start + dir * 0.82, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	Audio.play_sfx("attack")
	fx.impact(_entity_pos(ev.defender))
	_shake(6.0)
	var back := av.create_tween()
	back.tween_property(av, "position", start, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	back.tween_callback(func(): av.z_index = 0)


func _on_damage(ev: Dictionary) -> void:
	_float_text(_entity_pos(ev.uid), "-%d" % ev.amount, UITheme.RED, 34)
	if ev.has("inferno"):
		_update_inferno_score(int(ev.inferno))
	else:
		_view_add_hp(ev.uid, -ev.amount)
	if int(ev.uid) == GameState.HERO_UIDS[me]:
		_log_line(Loc.t("Vous subissez [color=#ff6b6b]%d[/color] dégât(s).") % ev.amount)
	else:
		_log_line(Loc.t("%s subit [color=#ff6b6b]%d[/color] dégât(s).") % [_entity_name(ev.uid), ev.amount])
	if ev.get("hero", false):
		_hero_views[GameState.HERO_UIDS.find(ev.uid)].shake()
		Audio.play_sfx("hero_hit")
	elif _minion_views.has(ev.uid):
		var mv: MinionView = _minion_views[ev.uid]
		var tw := mv.create_tween()
		tw.tween_property(mv, "modulate", Color(1, 0.4, 0.4), 0.06)
		tw.tween_property(mv, "modulate", Color.WHITE, 0.2)


func _on_death(ev: Dictionary) -> void:
	_log_line(Loc.t("[b]%s[/b] meurt.") % _cn(ev.card_id))
	var mv: MinionView = _minion_views.get(ev.uid)
	if mv == null:
		return
	Audio.play_sfx("death")
	fx.death(mv.center())
	_minion_views.erase(ev.uid)
	var tw := mv.create_tween().set_parallel(true)
	tw.tween_property(mv, "scale", Vector2(1.2, 0.1), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(mv, "modulate", Color(0.3, 0.3, 0.3, 0.0), 0.3)
	tw.chain().tween_callback(mv.queue_free)
	await _wait(0.32)
	_layout_board(ev.player)


# ======================================================================== MISE EN PAGE

func _layout_board(player: int) -> void:
	var uids: Array[int] = []
	for m in gs.players[player].board:
		if _minion_views.has(m.uid):
			uids.append(m.uid)
	# Les serviteurs affichés mais déjà retirés de l'état (morts en cours d'animation) gardent leur place.
	var y := (PLAYER_BOARD_Y if player == me else ENEMY_BOARD_Y) - MinionView.SIZE.y / 2
	var n := uids.size()
	for i in n:
		var mv: MinionView = _minion_views[uids[i]]
		var target := Vector2(640.0 - (n - 1) * BOARD_SPACING / 2.0 + i * BOARD_SPACING - MinionView.SIZE.x / 2, y)
		if mv.position == Vector2.ZERO:
			mv.position = target
		else:
			mv.create_tween().tween_property(mv, "position", target, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _layout_hand() -> void:
	if _selected_hand and not _hand_views.has(_selected_hand):
		_selected_hand = null
	if _dragging_card and not _hand_views.has(_dragging_card):
		_dragging_card = null
	var n := _hand_views.size()
	if n == 0:
		return
	if Settings.hand_sort != "manual" and _dragging_card == null:
		_hand_views.sort_custom(_hand_less)
	for i in n:
		var cv := _hand_views[i]
		if cv == _dragging_card:
			continue   # suit la souris
		var x := _hand_x(i, n)
		cv.z_index = i
		var target := Vector2(x, HAND_Y + abs(i - (n - 1) / 2.0) * 4.0)
		var s := _hand_scale(n)
		if cv == _selected_hand:
			target.y = HAND_Y - 40
			cv.z_index = 49
			s = HAND_HOVER_SCALE
		if cv == _hovered_hand and _dragging_card == null:
			target.y = HAND_Y - 12
			cv.z_index = 50
			s = HAND_HOVER_SCALE
			if _targeting.is_empty():
				# Pivot en bas au centre : on calcule le rectangle final de la carte agrandie.
				var sz := CardView.SIZE * s
				var r := Rect2(target + Vector2(CardView.SIZE.x / 2 - sz.x / 2, CardView.SIZE.y - sz.y), sz)
				_tips.show_card(cv.card_id)
				_tips.place_beside(r)
		_tween_card(cv, target, s)


func _tween_card(cv: CardView, pos: Vector2, s: float) -> void:
	if cv.has_meta("tw"):
		var old: Tween = cv.get_meta("tw")
		if old and old.is_valid():
			old.kill()
	var tw := cv.create_tween().set_parallel(true)
	tw.tween_property(cv, "position", pos, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(cv, "scale", Vector2.ONE * s, 0.15)
	cv.set_meta("tw", tw)


func _layout_enemy_hand() -> void:
	var n := _enemy_hand_views.size()
	for i in n:
		var b := _enemy_hand_views[i]
		var x := 640.0 - (n - 1) * 26.0 + i * 52.0 - CardView.SIZE.x * 0.55 / 2
		b.create_tween().tween_property(b, "position", Vector2(x, -60), 0.2)


func _refresh_heroes() -> void:
	for i in 2:
		_hero_views[i].sync(gs.players[i])
	_update_deck_pile()


## Dos des bibliothèques : une pile de cartes (plus fine quand le deck s'épuise), avec le dos de cartes
## choisi par son propriétaire. Votre pile (en bas à droite) montre sa composition au clic, comme le
## bouton « Deck » ; celle de l'adversaire (en haut) seulement son nombre de cartes.
func _build_deck_pile(player: int, pos: Vector2) -> void:
	var pile := Control.new()
	pile.position = pos
	pile.size = Vector2(84, 150)
	pile.mouse_filter = Control.MOUSE_FILTER_STOP
	pile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pile.tooltip_text = Loc.t("Votre bibliothèque : cliquez pour voir les cartes qui restent (sans l'ordre de pioche)") if player == me \
		else Loc.t("Bibliothèque de l'adversaire")
	pile.visible = mode != "replay"
	pile.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and gs != null:
			_on_deck_pressed(_hero_views[player]))
	_board_root.add_child(pile)
	for i in 3:
		var back := TextureRect.new()
		back.name = "pile_back_%d" % i
		back.texture = _back_tex(player)
		back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		back.stretch_mode = TextureRect.STRETCH_SCALE
		back.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		back.size = Vector2(76, 106)
		back.position = Vector2(8 - i * 4, 8 - i * 4)
		back.modulate = Color(0.55, 0.5, 0.5) if i < 2 else Color.WHITE
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pile.add_child(back)
	var count := UITheme.label("", 14, Color("e8d6b0"), 3)
	count.position = Vector2(-10, 118)
	count.size = Vector2(104, 20)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pile.add_child(count)
	_deck_piles[player] = pile
	_deck_pile_counts[player] = count


func _update_deck_pile() -> void:
	if gs == null:
		return
	for player in _deck_piles:
		var n: int = gs.players[player].deck.size()
		_deck_pile_counts[player].text = _cards_text(n, false)
		# 3 épaisseurs de carte au-delà de 20 cartes, 2 au-delà de 5, 1 ensuite, aucune si le deck est vide.
		var layers := 3 if n > 20 else 2 if n > 5 else 1 if n > 0 else 0
		for i in 3:
			var back: TextureRect = _deck_piles[player].get_node("pile_back_%d" % i)
			back.texture = _back_tex(player)   # le dos de l'adversaire arrive avec son profil (en ligne)
			back.visible = i >= 3 - layers


## Zone où lâcher la carte glissée pour la jouer, en surbrillance pendant le glisser : votre rangée
## pour un serviteur, votre zone d'enchantements pour un enchantement, tout le plateau pour un sort.
func _build_play_zone() -> void:
	_play_zone = Panel.new()
	_play_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_play_zone.visible = false
	_play_zone.z_index = 30
	_board_root.add_child(_play_zone)
	_play_zone_label = UITheme.label(Loc.t("Déposez ici pour jouer"), 18, Color("fff2c0"), 4)
	# En haut à gauche de la zone : la carte glissée (au centre, sous la souris) ne le cache pas.
	_play_zone_label.position = Vector2(14, 8)
	_play_zone.add_child(_play_zone_label)


func _show_play_zone(cv: CardView) -> void:
	if not _can_act() or not gs.can_play(me, cv.hand_uid):
		_play_zone.visible = false
		return
	var c := CardDB.get_card(cv.card_id)
	var r := Rect2(270, 176, 740, 330)   # sort : tout le plateau
	if c.type == "minion":
		r = Rect2(270, PLAYER_BOARD_Y - 74, 740, 148)
	elif c.type == "enchantment":
		r = Rect2(59, _enchant_zone_y(me) - 4, 162, 96)
	_play_zone.position = r.position
	_play_zone.size = r.size
	_play_zone.visible = true
	_style_play_zone(false)


func _style_play_zone(hot: bool) -> void:
	if not _play_zone.visible:
		return
	var sb := UITheme.flat_style(Color(1.0, 0.85, 0.35, 0.10 if hot else 0.04), Color(1.0, 0.85, 0.35, 1.0 if hot else 0.6), 4 if hot else 3, 10)
	sb.shadow_color = Color(1.0, 0.8, 0.3, 0.5 if hot else 0.2)
	sb.shadow_size = 14 if hot else 6
	_play_zone.add_theme_stylebox_override("panel", sb)
	_play_zone_label.modulate.a = 1.0 if hot else 0.7


## Zone « Défausser » (en bas à droite) : n'apparaît que pendant le glisser d'une carte de votre main.
func _build_discard_zone() -> void:
	_discard_zone = PanelContainer.new()
	_discard_zone.position = DISCARD_RECT.position
	_discard_zone.size = DISCARD_RECT.size
	_discard_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_discard_zone.visible = false
	_discard_zone.z_index = 40
	# Libellé en haut : la carte déposée (centrée sur la souris) ne le cache pas.
	var l := UITheme.label(Loc.t("Défausser"), 16, Color("ffd9c9"), 3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_discard_zone.add_child(l)
	_board_root.add_child(_discard_zone)
	_style_discard_zone(false)


func _style_discard_zone(hot: bool) -> void:
	_discard_zone.add_theme_stylebox_override("panel", UITheme.flat_style(
		Color(0.55, 0.12, 0.08, 0.85) if hot else Color(0.25, 0.07, 0.05, 0.7),
		Color("ff7a5a") if hot else Color("a0483a"), 3, 6))


## Resynchronise tout l'affichage avec l'état de la partie.
func _refresh() -> void:
	_refresh_heroes()
	var my_turn := gs.current == me and not gs.is_over()
	var can := _can_act()
	for uid in _minion_views:
		var e := gs.get_entity(uid)
		if e:
			_minion_views[uid].sync(e, can and e.owner == me and e.can_attack())
	for uid in _enchant_views:
		var ench := gs.get_entity(uid)
		if ench:
			_enchant_views[uid].sync(ench)
	if _selected_hand and not can:
		_select_hand(null)
	var any_action := false
	for cv in _hand_views:
		var c := CardDB.get_card(cv.card_id)
		var playable := can and gs.can_play(me, cv.hand_uid)
		cv.set_playable(playable)
		cv.set_cost_color(c.cost <= gs.players[me].energy)
		any_action = any_action or playable
	for m in gs.players[me].board:
		if m.can_attack() and my_turn:
			any_action = true
	_any_action = can and any_action
	_end_confirm = false   # l'état a changé : la confirmation éventuelle est annulée
	_end_turn_btn.disabled = not can
	_style_end_turn_btn(my_turn)
	var can_mull := can and gs.can_mulligan(me)
	if not can_mull:
		_mulligan_confirm = false
	_mulligan_btn.visible = can_mull
	_mulligan_btn.text = Loc.t("Confirmer ?") if _mulligan_confirm else Loc.t("Changer de main")
	_maybe_auto_end_turn()
	_layout_hand()
	if _can_choose() and _choice_layer == null:
		_open_choice()
	if Settings.autoplay and (can or _can_choose()) and not _autoplay_pending:
		_autoplay_pending = true
		_autoplay_step()


# Mode test (--autoplay) : l'IA joue à la place du joueur local.
var _autoplay_pending := false
var _autoplay_ai: AIPlayer
var _autoplay_count := 0
var _autoplay_discard_turn := -1


func _autoplay_step() -> void:
	await _wait(0.5)
	_autoplay_pending = false
	if not _can_act() and not _can_choose():
		return
	if _autoplay_ai == null:
		_autoplay_ai = AIPlayer.new(me, 1)
	var act := _autoplay_ai.next_action(gs)
	# Test de la défausse : main chargée en début de tour -> on défausse la carte la plus chère.
	if act.type != "choose" and _autoplay_discard_turn != gs.turn_number and gs.players[me].hand.size() >= 4:
		_autoplay_discard_turn = gs.turn_number
		var worst: Dictionary = gs.players[me].hand[0]
		for hc in gs.players[me].hand:
			if CardDB.get_card(hc.card_id).cost > CardDB.get_card(worst.card_id).cost:
				worst = hc
		act = {"type": "discard", "hand_uid": worst.uid}
	_autoplay_count += 1
	if act.type == "end" or _autoplay_count > 40:
		act = {"type": "end_turn"}
		_autoplay_count = 0
	_submit(act)


# ======================================================================== INTERACTIONS JOUEUR

func _can_act() -> bool:
	return mode != "replay" and _started and not busy and not _awaiting_server and gs.current == me and not gs.is_over() \
		and gs.pending_choice.is_empty()


## Vrai quand le joueur local doit choisir sa carte de pioche.
func _can_choose() -> bool:
	return mode != "replay" and _started and not busy and not _awaiting_server and not gs.is_over() \
		and not gs.pending_choice.is_empty() and gs.pending_choice.player == me


# ======================================================================== PIOCHE AU CHOIX

func _open_choice() -> void:
	_cancel_targeting()
	_tips.hide_tips()
	_choice_layer = CanvasLayer.new()
	_choice_layer.layer = 70
	add_child(_choice_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.05, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_choice_layer.add_child(dim)
	var title := UITheme.title_label(Loc.t("Choisissez une carte"), 44)
	title.position = Vector2(0, 92)
	title.size = Vector2(1280, 60)
	_choice_layer.add_child(title)
	var sub := UITheme.label(Loc.t("Les autres retournent au fond de votre deck."), 20, Color("e8d9b8"))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.position = Vector2(0, 150)
	sub.size = Vector2(1280, 30)
	_choice_layer.add_child(sub)
	var choice_tips := KeywordTips.new()
	choice_tips.position = Vector2(1008, 214)
	var options: Array = gs.pending_choice.options
	var s := 1.25
	var w := CardView.SIZE.x * s
	var gap := 56.0
	var x0 := 640.0 - (options.size() * w + (options.size() - 1) * gap) / 2.0
	for i in options.size():
		var cv := CardView.new().setup(options[i])
		cv.pivot_offset = CardView.SIZE / 2
		cv.scale = Vector2.ONE * s
		# Avec un pivot centré, la position reste celle du coin non mis à l'échelle.
		cv.position = Vector2(x0 + i * (w + gap) + (w - CardView.SIZE.x) / 2.0, 360 - CardView.SIZE.y / 2.0 + 20)
		var c := CardDB.get_card(options[i])
		cv.set_playable(c.cost <= gs.players[me].max_energy)
		cv.modulate.a = 0.0
		cv.hovered.connect(func(v: CardView, on: bool):
			create_tween().tween_property(v, "scale", Vector2.ONE * (s * 1.08 if on else s), 0.1)
			if on:
				Audio.play_sfx("click", 0.2, -16.0)
				choice_tips.show_card(v.card_id)
				# Bulles à droite, sauf pour la dernière carte (à gauche) pour ne pas la masquer.
				choice_tips.position = Vector2(1008 if i < 2 else 22, 214)
			else:
				choice_tips.hide_tips())
		cv.pressed.connect(func(_v: CardView): _pick_choice(i))
		_choice_layer.add_child(cv)
		var tw := create_tween()
		tw.tween_interval(0.08 * i)
		tw.tween_property(cv, "modulate:a", 1.0, 0.2)
		var key := UITheme.label("[%d]" % (i + 1), 18, UITheme.GOLD)
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key.position = Vector2(x0 + i * (w + gap), 360 + CardView.SIZE.y * s / 2.0 + 34)
		key.size = Vector2(w, 24)
		_choice_layer.add_child(key)
	_choice_layer.add_child(choice_tips)
	# Consulter le plateau (main, serviteurs, héros) avant de choisir.
	var peek := UITheme.button(Loc.t("Voir le plateau (Tab)"), 240)
	peek.position = CHOICE_TOGGLE_POS
	peek.tooltip_text = Loc.t("Masque le choix pour consulter votre main et le plateau (touche Tab ou V).")
	peek.pressed.connect(_peek_board)
	_choice_layer.add_child(peek)
	Audio.play_sfx("card_draw")


const CHOICE_TOGGLE_POS := Vector2(22, 336)   # « Voir le plateau » / « Revenir au choix » : même place


## Masque temporairement le choix de pioche pour regarder la main et le plateau.
func _peek_board() -> void:
	if _choice_layer == null or not _choice_layer.visible:
		return
	Audio.play_sfx("click", 0.1)
	_choice_layer.visible = false
	_choice_return = CanvasLayer.new()
	_choice_return.layer = 70
	add_child(_choice_return)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.flat_style(Color(0.1, 0.07, 0.09, 0.92), UITheme.GOLD, 2, 6))
	panel.position = Vector2(640 - 210, 64)
	panel.custom_minimum_size = Vector2(420, 0)
	_choice_return.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var info := UITheme.label(Loc.t("Consultation du plateau : choisissez ensuite votre carte."), 15, Color("e8d9b8"))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(info)
	# Même emplacement que « Voir le plateau » : on alterne sans bouger la souris.
	var back := UITheme.button(Loc.t("Revenir au choix (Tab)"), 240)
	back.position = CHOICE_TOGGLE_POS
	back.pressed.connect(_back_to_choice)
	_choice_return.add_child(back)
	var tw := back.create_tween().set_loops()
	tw.tween_property(back, "modulate", Color(1.3, 1.2, 0.8), 0.6)
	tw.tween_property(back, "modulate", Color.WHITE, 0.6)


func _back_to_choice() -> void:
	if _choice_return:
		_choice_return.queue_free()
		_choice_return = null
	_tips.hide_tips()
	if _choice_layer:
		Audio.play_sfx("click", 0.1)
		_choice_layer.visible = true


## Vrai pendant une partie (utilisé par Lobby pour différer la proposition de mise à jour).
func is_game_running() -> bool:
	return gs != null and not gs.is_over()


func _pick_choice(index: int) -> void:
	if not _can_choose() or _choice_layer == null or _choice_layer.has_meta("picked"):
		return
	_choice_layer.set_meta("picked", true)
	Audio.play_sfx("card_play", 0.05, -4.0)
	_submit({"type": "choose", "index": index})


func _close_choice() -> void:
	if _choice_return:
		_choice_return.queue_free()
		_choice_return = null
	if _choice_layer:
		_choice_layer.queue_free()
		_choice_layer = null


func _on_hand_card_hovered(cv: CardView, on: bool) -> void:
	if on:
		# La souris « choisit » le nœud le plus haut dans l'arbre, pas celui au plus grand z_index :
		# la carte survolée (agrandie) passe devant ses voisines, sinon sa voisine lui vole le survol
		# dès que la souris approche du bouton « X » situé dans la zone où elles se chevauchent.
		cv.get_parent().move_child(cv, -1)
		_hovered_hand = cv
		Audio.play_sfx("click", 0.2, -18.0)
	elif _hovered_hand == cv:
		_hovered_hand = null
		_tips.hide_tips()
	if _dragging_card == null:
		_layout_hand()


func _on_hand_card_pressed(cv: CardView) -> void:
	if not _can_act():
		return
	if not _targeting.is_empty():
		_cancel_targeting()
		return
	if not _check_playable(cv, cv.global_position + Vector2(64, 40)):
		return
	# Premier clic : la carte est seulement sélectionnée (évite de jouer une carte par erreur).
	if _selected_hand != cv:
		Audio.play_sfx("click", 0.1)
		_select_hand(cv)
		_float_text(cv.global_position + Vector2(64, -30), Loc.t("Cliquez à nouveau pour jouer (ou glissez-la sur le plateau)"), UITheme.GOLD, 18)
		return
	_select_hand(null)
	_play_from_hand(cv, cv.global_position + Vector2(64, 40))


## Carte jouable ? Sinon, la raison s'affiche à msg_pos.
func _check_playable(cv: CardView, msg_pos: Vector2) -> bool:
	if gs.can_play(me, cv.hand_uid):
		return true
	var c := CardDB.get_card(cv.card_id)
	var msg := Loc.t("Pas assez d'énergie !")
	if c.cost <= gs.players[me].energy:
		msg = Loc.t("Plateau plein !") if c.type == "minion" else Loc.t("Aucune cible valide !")
		if c.type == "enchantment":
			msg = Loc.t("Zone d'enchantements pleine (%d max) !") % CardDB.MAX_ENCHANTS
	_float_text(msg_pos, msg, UITheme.RED, 22)
	return false


## Joue la carte (2e clic ou dépôt sur le plateau) ; une carte à cible passe en mode ciblage.
func _play_from_hand(cv: CardView, msg_pos: Vector2) -> void:
	if not _check_playable(cv, msg_pos):
		return
	if gs.needs_target(cv.card_id):
		_start_targeting({"kind": "spell", "hand_uid": cv.hand_uid, "card": cv,
			"valid": gs.valid_spell_targets(me, cv.card_id)})
	else:
		_submit({"type": "play", "hand_uid": cv.hand_uid, "target": -1})


func _on_minion_hovered(mv: MinionView, on: bool) -> void:
	_preview.visible = on
	_preview.position = PREVIEW_POS
	if on:
		_preview.setup(mv.card_id)
		_tips.show_card(mv.card_id)
		_tips.place_beside(Rect2(_preview.position, CardView.SIZE))
	else:
		_tips.hide_tips()


## Survol d'un nom de carte dans le journal : la carte s'affiche à gauche du journal.
func _on_log_card_hovered(meta: Variant, on: bool) -> void:
	var id := str(meta)
	if not on or not CardDB.CARDS.has(id):
		_preview.visible = false
		_preview.position = PREVIEW_POS
		_tips.hide_tips()
		return
	_preview.setup(id)
	_preview.position = Vector2(1036 - CardView.SIZE.x - 10, 8)
	_preview.visible = true
	_tips.show_card(id)
	_tips.place_beside(Rect2(_preview.position, CardView.SIZE))


func _on_enchant_hovered(v: EnchantView, on: bool) -> void:
	_preview.visible = on
	_preview.position = PREVIEW_POS
	if on:
		_preview.setup(v.card_id)
		_tips.show_card(v.card_id)
		_tips.place_beside(Rect2(_preview.position, CardView.SIZE))
	else:
		_tips.hide_tips()


func _on_enchant_pressed(v: EnchantView) -> void:
	if _can_act() and not _targeting.is_empty():
		_try_target(v.uid)


func _on_minion_pressed(mv: MinionView) -> void:
	if not _can_act():
		return
	if not _targeting.is_empty():
		_try_target(mv.uid)
		return
	var e := gs.get_entity(mv.uid)
	if e == null or e.owner != me:
		return
	if not e.can_attack():
		var msg := Loc.t("Ce serviteur a déjà attaqué.") if e.attacks_left <= 0 else Loc.t("Il vient d'arriver (Zzz).")
		if e.attack <= 0:
			msg = Loc.t("0 attaque : ne peut pas attaquer.")
		_float_text(mv.center(), msg, Color("c9b79a"), 18)
		return
	_start_targeting({"kind": "attack", "source": mv.uid, "valid": gs.valid_attack_targets(mv.uid)})


func _on_hero_pressed(hv: HeroView) -> void:
	if _can_act() and not _targeting.is_empty():
		_try_target(hv.uid)


## Bibliothèque : seul le joueur peut consulter la sienne (composition, pas l'ordre).
func _on_deck_pressed(hv: HeroView) -> void:
	Audio.play_sfx("click", 0.1)
	if hv.player_index != me:
		_float_text(hv.center() + Vector2(0, 90), Loc.t("%d cartes dans sa bibliothèque") % gs.players[opp].deck.size(), Color("c9b79a"), 18)
		return
	var deck: Array = gs.players[me].deck
	_overlay.add_child(PileViewer.new().setup(Loc.t("Votre bibliothèque"), Loc.t("%s, triées par coût (l'ordre de pioche reste secret)") % _cards_text(deck.size(), true), deck, true))


## « N carte(s) » (ou « N carte(s) restante(s) »), déjà traduit.
func _cards_text(n: int, remaining: bool) -> String:
	if remaining:
		return (Loc.t("%d cartes restantes") if n > 1 else Loc.t("%d carte restante")) % n
	return (Loc.t("%d cartes") if n > 1 else Loc.t("%d carte")) % n


## Cimetière (public) : cartes mortes, jouées, détruites ou défaussées.
func _on_grave_pressed(hv: HeroView) -> void:
	Audio.play_sfx("click", 0.1)
	var grave: Array = gs.players[hv.player_index].graveyard
	var title := Loc.t("Votre cimetière") if hv.player_index == me else Loc.t("Cimetière de %s") % _pname(hv.player_index)
	_overlay.add_child(PileViewer.new().setup(title, (Loc.t("%s, de la plus récente à la plus ancienne") % _cards_text(grave.size(), false)) if not grave.is_empty() else Loc.t("Aucune carte pour l'instant."), grave, false))


func _start_targeting(t: Dictionary) -> void:
	_targeting = t
	_tips.hide_tips()
	for uid in t.valid:
		_set_targetable(uid, true)
	var col := Color(1, 0.3, 0.2, 0.9) if t.kind == "attack" else Color(0.5, 0.7, 1.0, 0.9)
	_arrow.default_color = col
	_arrow_head.color = col
	_arrow.visible = true
	_arrow_head.visible = true
	_update_arrow()


func _cancel_targeting() -> void:
	if _targeting.is_empty():
		return
	for uid in _targeting.valid:
		_set_targetable(uid, false)
	_targeting = {}
	_arrow.visible = false
	_arrow_head.visible = false


func _try_target(uid: int) -> void:
	var t := _targeting
	_cancel_targeting()
	if not t.valid.has(uid):
		var e := gs.get_entity(uid)
		if t.kind == "attack" and e and e.owner == opp:
			if e.is_enchant:
				_float_text(_entity_pos(uid), Loc.t("Seule une carte de destruction peut le retirer"), Color("c9b79a"), 16)
			else:
				_float_text(_entity_pos(uid), Loc.t("Provocation !"), Color("c9b79a"), 20)
		return
	if t.kind == "attack":
		_submit({"type": "attack", "attacker": t.source, "defender": uid})
	else:
		_submit({"type": "play", "hand_uid": t.hand_uid, "target": uid})


func _set_targetable(uid: int, on: bool) -> void:
	var idx := GameState.HERO_UIDS.find(uid)
	if idx != -1:
		_hero_views[idx].set_targetable(on)
	elif _minion_views.has(uid):
		_minion_views[uid].set_targetable(on)
	elif _enchant_views.has(uid):
		_enchant_views[uid].set_targetable(on)


## Forum des suggestions par-dessus la partie (au-dessus du choix de pioche).
func _open_suggestions() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	var panel := SuggestionPanel.new()
	panel.tree_exited.connect(layer.queue_free)
	layer.add_child(panel)


## « Changer de main » : un premier appui demande confirmation (4 s), le second envoie l'action.
func _on_mulligan_pressed() -> void:
	if not _can_act() or not gs.can_mulligan(me):
		return
	_cancel_targeting()
	if not _mulligan_confirm:
		_mulligan_confirm = true
		_mulligan_btn.text = Loc.t("Confirmer ?")
		Audio.play_sfx("click", 0.1)
		var turn := gs.turn_number
		get_tree().create_timer(4.0).timeout.connect(func():
			if _mulligan_confirm and gs.turn_number == turn:
				_mulligan_confirm = false
				_mulligan_btn.text = Loc.t("Changer de main"))
		return
	_mulligan_confirm = false
	_mulligan_btn.visible = false
	_submit({"type": "mulligan"})


func _on_end_turn_pressed() -> void:
	if not _can_act():
		return
	_cancel_targeting()
	# Il reste des actions : le 1er appui transforme le bouton en « Confirmer », le 2e termine le tour
	# (sauf si la case « Confirmer la fin du tour » est décochée).
	if Settings.confirm_end_turn and _any_action and not _end_confirm:
		_end_confirm = true
		_style_end_turn_btn(true)
		Audio.play_sfx("click", 0.1)
		_float_text(_end_turn_btn.global_position + Vector2(-40, -34), Loc.t("Il vous reste des actions !"), Color("ffcf6b"), 18)
		get_tree().create_timer(4.0).timeout.connect(_end_confirm_expired.bind(gs.turn_number))
		return
	_end_confirm = false
	_submit({"type": "end_turn"})


## « Fin du tour automatique » : plus aucune carte jouable ni attaque possible -> le tour se termine seul,
## après un court délai (le temps de voir le dernier coup) et si rien n'a changé entre-temps.
func _maybe_auto_end_turn() -> void:
	if not Settings.auto_end_turn or mode == "replay" or _auto_end_pending or not _can_act() or _any_action:
		return
	if gs.can_mulligan(me):
		return   # premier tour : on laisse au joueur le temps de changer de main
	if Settings.autoplay or _dragging_card != null or not _targeting.is_empty():
		return
	_auto_end_pending = true
	var turn := gs.turn_number
	await _wait(0.9)
	_auto_end_pending = false
	if Settings.auto_end_turn and gs.turn_number == turn and _can_act() and not _any_action \
			and _dragging_card == null and _targeting.is_empty():
		_float_text(_end_turn_btn.global_position + Vector2(10, -34), Loc.t("Fin du tour automatique"), Color("c9b79a"), 16)
		_end_confirm = false
		_submit({"type": "end_turn"})


## Sans second appui dans les 4 s, le bouton redevient « Fin du tour ».
func _end_confirm_expired(turn: int) -> void:
	if _end_confirm and gs.turn_number == turn:
		_end_confirm = false
		_style_end_turn_btn(gs.current == me and not gs.is_over())


func _style_end_turn_btn(my_turn: bool) -> void:
	if _end_confirm:
		_end_turn_btn.text = Loc.t("Confirmer")
		_end_turn_btn.modulate = Color(1.45, 0.75, 0.6)
		return
	_end_turn_btn.text = Loc.t("Fin du tour") if my_turn else Loc.t("Tour adverse")
	_end_turn_btn.modulate = Color(1.25, 1.15, 0.6) if not _end_turn_btn.disabled and not _any_action else Color.WHITE


func _input(event: InputEvent) -> void:
	if _selected_hand and _targeting.is_empty() and ((event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT) or event.is_action_pressed("pause")):
		_select_hand(null)
		get_viewport().set_input_as_handled()
		return
	# Tab : bascule entre le choix de pioche et le plateau (avant la navigation au clavier de Godot).
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB \
			and _choice_layer and is_instance_valid(_choice_layer) \
			and not (get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_focus_owner() is TextEdit):
		if _choice_layer.visible:
			_peek_board()
		else:
			_back_to_choice()
		get_viewport().set_input_as_handled()
		return
	if _targeting.is_empty():
		return
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT) \
			or event.is_action_pressed("pause"):
		_cancel_targeting()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("open_chat"):
		_chat_tabs.current_tab = 1
		_chat_input.grab_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("end_turn"):
		_on_end_turn_pressed()
		get_viewport().set_input_as_handled()
	elif _choice_layer and event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_V and not _chat_input.has_focus():
		if _choice_layer.visible:
			_peek_board()
		else:
			_back_to_choice()
		get_viewport().set_input_as_handled()
	elif _choice_layer and _choice_layer.visible and event is InputEventKey and event.pressed and not event.echo \
			and event.keycode >= KEY_1 and event.keycode <= KEY_3:
		var i: int = event.keycode - KEY_1
		if i < gs.pending_choice.get("options", []).size():
			_pick_choice(i)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_cancel_targeting()
		if _selected_hand:
			_select_hand(null)
		if _chat_input.has_focus():
			_chat_input.release_focus()


func _process(_delta: float) -> void:
	_update_clock()
	if not _targeting.is_empty():
		_update_arrow()


func _update_arrow() -> void:
	var from: Vector2
	if _targeting.kind == "attack":
		from = _entity_pos(_targeting.source)
	else:
		var cv: CardView = _targeting.card
		from = cv.global_position + Vector2(CardView.SIZE.x * cv.scale.x / 2, 20)
	var to := get_global_mouse_position()
	var ctrl := (from + to) / 2 + Vector2(0, -80)
	var pts := PackedVector2Array()
	for i in 17:
		var t := i / 16.0
		pts.append(from.lerp(ctrl, t).lerp(ctrl.lerp(to, t), t))
	_arrow.points = pts
	_arrow_head.position = to
	_arrow_head.rotation = (to - pts[14]).angle()


# ======================================================================== OUTILS

func _entity_pos(uid: int) -> Vector2:
	var idx := GameState.HERO_UIDS.find(uid)
	if idx != -1:
		return _hero_views[idx].center()
	if _minion_views.has(uid):
		return _minion_views[uid].center()
	if _enchant_views.has(uid):
		return _enchant_views[uid].center()
	return Vector2(640, 360)


func _entity_name(uid: int) -> String:
	var idx := GameState.HERO_UIDS.find(uid)
	if idx != -1:
		return Loc.t("vous") if idx == me else _pname(idx)
	var e := gs.get_entity(uid)
	if e:
		return _cn(e.card_id)
	if _minion_views.has(uid):
		return _cn(_minion_views[uid].card_id)
	if _enchant_views.has(uid):
		return _cn(_enchant_views[uid].card_id)
	return "?"


## Nom de carte pour le journal : un lien qui affiche la carte au survol.
func _cn(card_id: String) -> String:
	return "[url=%s]%s[/url]" % [card_id, CardDB.get_card(card_id).name]


## Score Inferno affiché en haut à gauche (valeur de l'événement pendant l'animation, sinon celle de la partie).
func _update_inferno_score(value := -1) -> void:
	if gs.inferno < 0:
		return
	_inferno_label.visible = true
	_inferno_label.text = Loc.t("Score Inferno : %d") % (gs.inferno_damage if value < 0 else value)


func _view_add_hp(uid: int, delta: int) -> void:
	var idx := GameState.HERO_UIDS.find(uid)
	if idx != -1:
		_hero_views[idx].add_hp(delta)
	elif _minion_views.has(uid):
		_minion_views[uid].add_hp(delta)


func _find_hand_view(uid: int) -> CardView:
	for cv in _hand_views:
		if cv.hand_uid == uid:
			return cv
	return null


func _wait(t: float) -> void:
	await get_tree().create_timer(t, false).timeout


func _float_text(at: Vector2, text: String, color: Color, font_size := 30) -> void:
	var l := UITheme.label(text, font_size, color, 8)
	# Dégâts / soins / bonus (« -3 », « +2/+2 ») : police des chiffres ; le reste en police pixel grasse.
	var numeric := RegEx.create_from_string("^[-+0-9/ ]+$").search(text) != null
	if numeric:
		l.add_theme_font_override("font", UITheme.font_num)
	else:
		l.add_theme_font_override("font", UITheme.font_bold)
	if numeric:
		l.add_theme_font_size_override("font_size", 24 if font_size >= 28 else 16)
	l.position = at - Vector2(150, 20)
	l.size = Vector2(300, 40)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.pivot_offset = Vector2(150, 20)
	l.scale = Vector2.ONE * 0.5
	_overlay.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", l.position.y - 50, 0.8)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tw.tween_callback(l.queue_free)


func _show_banner(text: String, duration := 1.0) -> void:
	_banner.text = text
	_banner.scale = Vector2.ONE * 0.7
	_banner.pivot_offset = Vector2(640, 40)
	var tw := create_tween()
	tw.tween_property(_banner, "modulate:a", 1.0, 0.15)
	tw.parallel().tween_property(_banner, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(duration * 0.6)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.25)
	await _wait(duration * 0.6 + 0.3)


## Pile ou face : une pièce frappée des avatars des deux joueurs tourne en l'air
## et retombe sur celui qui commence (`first` est déjà fixé : hasard local ou tirage de l'hôte).
## Petit jeton doré « 1 » à droite du portrait du joueur qui a commencé (infobulle explicative).
func _add_first_token(first: int) -> void:
	if _first_token:
		_first_token.queue_free()
	_first_token = Panel.new()
	_first_token.size = Vector2(30, 30)
	_first_token.position = _hero_views[first].position + Vector2(166, 2)
	var sb := UITheme.flat_style(Color("b8862b"), Color("ffe08a"), 2, 15)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 3
	_first_token.add_theme_stylebox_override("panel", sb)
	_first_token.tooltip_text = (Loc.t("Vous avez commencé la partie (la pièce vous a désigné).") if first == me and mode != "replay"
		else Loc.t("%s a commencé la partie (la pièce l'a désigné).") % _pname(first))
	var l := UITheme.label("1", 17, Color("3a2408"), 0)
	l.add_theme_font_override("font", UITheme.font_bold)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_first_token.add_child(l)
	_board_root.add_child(_first_token)
	_first_token.pivot_offset = _first_token.size / 2
	_first_token.scale = Vector2.ZERO
	_first_token.create_tween().tween_property(_first_token, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _coin_toss(first: int) -> void:
	const SIDE := 180.0
	var fast := Settings.autoplay
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(dim)
	var title := UITheme.title_label(Loc.t("Pile ou face : qui commence ?"), 40)
	title.position = Vector2(0, 110)
	title.size = Vector2(1280, 60)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(title)

	# Les deux faces : le joueur 0 de la pièce est celui qui ne commence pas.
	var faces: Array[Texture2D] = []
	var owners := [1 - first, first]
	for i in owners:
		var tex := _portrait(i)
		if tex == null:
			tex = CardDB.texture("res://assets/art/%s.png" % CardDB.HEROES[i].portrait)
		faces.append(tex)
	# Rappel des deux faces, de chaque côté.
	for k in 2:
		var who: int = owners[k]
		var side_x := 250.0 if who == me else 1030.0
		var badge := AvatarBadge.new().setup(0, str(_look(who).get("border", "none")), 96, faces[k])
		badge.position = Vector2(side_x - 48, 300)
		layer.add_child(badge)
		var nm := UITheme.label(_pname(who), 20, UITheme.GOLD if who == me else Color("e8d6b0"), 4)
		nm.position = Vector2(side_x - 150, 404)
		nm.size = Vector2(300, 30)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		layer.add_child(nm)

	var shadow := Panel.new()
	shadow.add_theme_stylebox_override("panel", UITheme.flat_style(Color(0, 0, 0, 0.45), Color(0, 0, 0, 0), 0, 60))
	shadow.size = Vector2(150, 30)
	shadow.position = Vector2(640 - 75, 470)
	shadow.pivot_offset = shadow.size / 2
	layer.add_child(shadow)

	var coin := Control.new()
	coin.size = Vector2(SIDE, SIDE)
	coin.position = Vector2(640 - SIDE / 2, 360 - SIDE / 2)
	coin.pivot_offset = coin.size / 2
	layer.add_child(coin)
	var rim := Panel.new()
	rim.size = coin.size
	var rim_style := UITheme.flat_style(Color("b8862b"), Color("ffe08a"), 6, int(SIDE / 2))
	rim_style.shadow_color = Color(1, 0.8, 0.3, 0.45)
	rim_style.shadow_size = 14
	rim.add_theme_stylebox_override("panel", rim_style)
	coin.add_child(rim)
	var disc := Panel.new()
	disc.position = Vector2(12, 12)
	disc.size = coin.size - Vector2(24, 24)
	disc.add_theme_stylebox_override("panel", UITheme.flat_style(Color("3a2a12"), Color(0, 0, 0, 0), 0, int(SIDE / 2 - 12)))
	disc.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	coin.add_child(disc)
	var face := TextureRect.new()
	face.size = disc.size
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	face.texture = faces[0]
	disc.add_child(face)
	for c in [rim, disc, face]:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Nombre impair de demi-tours : la pièce part de la face 0 et retombe sur la face 1 (celui qui commence).
	var half_turns := 7 if fast else 13
	var dur := 0.9 if fast else 2.2
	var flip := func(angle: float) -> void:
		coin.scale.x = maxf(0.04, absf(cos(angle)))
		face.texture = faces[int(floor((angle + PI / 2) / PI)) % 2]
		coin.modulate = Color.WHITE.lerp(Color(0.55, 0.45, 0.3), 1.0 - absf(cos(angle)))
	Audio.play_sfx("card_draw", 0.0)
	var tw := layer.create_tween().set_parallel(true)
	tw.tween_method(flip, 0.0, PI * half_turns, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(coin, "position:y", 150.0, dur * 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(coin, "position:y", 360 - SIDE / 2, dur * 0.55).set_delay(dur * 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_property(shadow, "scale", Vector2(0.5, 0.5), dur * 0.45)
	tw.tween_property(shadow, "scale", Vector2.ONE, dur * 0.55).set_delay(dur * 0.45)
	await tw.finished
	flip.call(PI * half_turns)
	Audio.play_sfx("end_turn", 0.0)
	fx.impact(coin.global_position + coin.size / 2, Color(1, 0.85, 0.4))
	var caption := UITheme.title_label(Loc.t("Vous commencez !") if first == me and mode != "replay" else Loc.t("%s commence !") % _pname(first), 34)
	caption.position = Vector2(0, 560)
	caption.size = Vector2(1280, 50)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(caption)
	var pop := coin.create_tween()
	pop.tween_property(coin, "scale", Vector2.ONE * 1.15, 0.12).set_trans(Tween.TRANS_BACK)
	pop.tween_property(coin, "scale", Vector2.ONE, 0.15)
	await _wait(0.4 if fast else 1.1)
	var out := layer.create_tween()
	out.tween_property(layer, "modulate:a", 0.0, 0.3)
	await out.finished
	layer.queue_free()


# ======================================================================== REPLAY

## Replay envoyé au serveur : la graine et les actions suffisent à rejouer la partie à l'identique.
func _replay_data() -> Dictionary:
	var avatars := [0, 0]
	if Net.is_online():
		avatars[me] = Net.local_avatar
		avatars[opp] = Net.remote_avatar
	elif Settings.player_name != "":
		avatars[me] = Settings.avatar
	var names := [_pname(0), _pname(1)]
	if mode == "ai":
		names[opp] = "IA " + AI_NAMES[clampi(Settings.ai_difficulty, 0, 4)]
	return {"seed": _seed, "first": _first, "me": me, "difficulty": Settings.ai_difficulty, "game": Updater.current_version(),
		"names": names, "avatars": avatars, "actions": _record, "bonus": _bonus}


static func _encode_action(p: int, act: Dictionary) -> Array:
	return MatchCheck.encode(p, act)


static func _decode_action(a: Array) -> Dictionary:
	return MatchCheck.decode(a)


func _run_replay() -> void:
	_build_replay_bar()
	if Settings.autoplay:
		_set_replay_speed(8.0)   # tests automatiques
	for a in Net.replay.get("actions", []):
		if not is_inside_tree() or gs.is_over():
			return
		while _replay_paused and is_inside_tree():
			await get_tree().process_frame
		if _queue_running:
			await queue_idle
		if not (a is Array) or a.size() < 2 or int(a[0]) not in [0, 1]:
			continue
		var act := _decode_action(a)
		if act.is_empty():
			continue
		_enqueue(int(a[0]), act)
		if _queue_running:
			await queue_idle
		await _wait(0.3)
	if is_inside_tree() and not gs.is_over():
		_show_replay_end(-1)   # partie interrompue (déconnexion)


func _set_replay_speed(v: float) -> void:
	_replay_speed = v
	Engine.time_scale = Settings.anim_speed * v


func _build_replay_bar() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 65
	add_child(layer)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.flat_style(Color(0.1, 0.07, 0.09, 0.92), Color("9fd8ff"), 2, 6))
	panel.position = Vector2(250, 6)
	layer.add_child(panel)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	panel.add_child(hb)
	var title := UITheme.label(Loc.t("▶ REPLAY : %s contre %s") % [_pname(0), _pname(1)], 16, Color("9fd8ff"), 3)
	title.custom_minimum_size.x = 340
	title.clip_text = true
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(title)
	var pause := UITheme.button(Loc.t("Pause"), 110)
	pause.custom_minimum_size.y = 32
	pause.add_theme_font_size_override("font_size", 15)
	pause.pressed.connect(func():
		_replay_paused = not _replay_paused
		pause.text = Loc.t("Lecture") if _replay_paused else Loc.t("Pause"))
	hb.add_child(pause)
	var speed := UITheme.button(Loc.t("Vitesse ×%d") % 1, 130)
	speed.custom_minimum_size.y = 32
	speed.add_theme_font_size_override("font_size", 15)
	speed.pressed.connect(func():
		var next := {1.0: 2.0, 2.0: 4.0, 4.0: 1.0}.get(_replay_speed, 1.0) as float
		_set_replay_speed(next)
		speed.text = Loc.t("Vitesse ×%d") % int(next))
	hb.add_child(speed)
	var quit := UITheme.button(Loc.t("Quitter"), 110)
	quit.custom_minimum_size.y = 32
	quit.add_theme_font_size_override("font_size", 15)
	quit.pressed.connect(_leave_replay)
	hb.add_child(quit)


func _leave_replay() -> void:
	Engine.time_scale = Settings.anim_speed
	Net.close()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _show_replay_end(winner: int) -> void:
	busy = true
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 18)
	center.add_child(vb)
	vb.add_child(UITheme.title_label(Loc.t("FIN DU REPLAY"), 64))
	var text := Loc.t("Partie interrompue (déconnexion).")
	if winner == 2:
		text = Loc.t("Égalité.")
	elif winner in [0, 1]:
		text = Loc.t("%s remporte la partie en %d tours.") % [_pname(winner), gs.turn_number]
	var sub := UITheme.label(text, 24)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 20)
	vb.add_child(hb)
	var again := UITheme.button(Loc.t("Revoir"), 200)
	again.pressed.connect(func():
		Engine.time_scale = Settings.anim_speed
		get_tree().reload_current_scene())
	hb.add_child(again)
	var menu := UITheme.button(Loc.t("Menu principal"), 220)
	menu.pressed.connect(_leave_replay)
	hb.add_child(menu)
	root.modulate.a = 0.0
	create_tween().tween_property(root, "modulate:a", 1.0, 0.4)
	if Settings.quit_after_game:
		print("[replay] FIN DU REPLAY : vainqueur %d | tours %d | PV %d / %d" % [winner, gs.turn_number,
			gs.players[0].hero.health, gs.players[1].hero.health])
		await _wait(1.0)
		get_tree().quit()


func _exit_tree() -> void:
	if mode == "replay":
		Engine.time_scale = Settings.anim_speed


func _shake(strength: float) -> void:
	var tw := create_tween()
	for i in 5:
		tw.tween_property(_board_root, "position", Vector2(randf_range(-strength, strength), randf_range(-strength, strength)), 0.03)
		strength *= 0.7
	tw.tween_property(_board_root, "position", Vector2.ZERO, 0.03)


func _show_game_over(winner: int) -> void:
	busy = true
	_tips.hide_tips()
	_clock_stop_msec = Time.get_ticks_msec()
	_update_clock()
	_refresh()
	if mode == "replay":
		_show_replay_end(winner)
		return
	var won := winner == me
	var is_draw := winner == 2
	# Statistiques pour le classement et l'historique (conservés sur le serveur),
	# cartes jouées par camp (statistiques globales) et replay de la partie.
	var details := {"turns": gs.turn_number, "reason": _end_reason,
		"duration": int((_clock_stop_msec - _start_msec) / 1000.0),
		"cards": _card_plays, "first": _first, "me": me, "replay": _replay_data()}
	# Le serveur rejoue la partie pour la valider : récompenses, classement et statistiques en dépendent.
	if mode == "ai" and not is_draw:
		details["difficulty"] = Settings.ai_difficulty
		details["ticket"] = _ticket
		details["score"] = gs.inferno_damage
		if won:
			Settings.mark_ai_beaten(Settings.ai_difficulty)
		Lobby.report_ai_result(won, details)
	elif mode in ["host", "client"] and Net.transport == "relay":
		Lobby.report_pvp_result("draw" if is_draw else ("host" if winner == 0 else "guest"), details)
	_log_line(Loc.t("[color=#f2c14e]Fin de la partie : %s[/color]") % (Loc.t("égalité") if is_draw else (Loc.t("victoire !") if won else Loc.t("défaite."))))
	Audio.stop_music(0.4)
	Audio.play_music("victory" if won else "defeat", false, 0.1)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 18)
	center.add_child(vb)
	_game_over_vb = vb
	var title := UITheme.title_label(Loc.t("ÉGALITÉ") if is_draw else (Loc.t("VICTOIRE !") if won else Loc.t("DÉFAITE...")), 84)
	if not won and not is_draw:
		title.add_theme_color_override("font_color", UITheme.RED)
	var inferno := gs.inferno >= 0
	if inferno:
		title.text = Loc.t("FIN DE L'INFERNO")
		title.add_theme_color_override("font_color", Color("ff8a3a"))
	vb.add_child(title)
	if inferno:
		var best := maxi(Settings.inferno_best, gs.inferno_damage)
		var record := gs.inferno_damage > Settings.inferno_best and gs.inferno_damage > 0
		var sc := UITheme.label(Loc.t("Score : %d dégâts infligés") % gs.inferno_damage, 30, UITheme.GOLD, 4)
		sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(sc)
		var bl := UITheme.label(Loc.t("Nouveau record personnel !") if record else Loc.t("Record personnel : %d") % best, 20,
			Color("7dff8a") if record else Color("e8d6b0"), 3)
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(bl)
		if mode == "ai":
			Settings.set_inferno_best(gs.inferno_damage)
	elif not is_draw:
		var sub := UITheme.label(Loc.t("%s a été vaincu.") % (Loc.t("Vous avez") if not won else _pname(opp)), 24)
		if not won:
			sub.text = Loc.t("Vous avez été vaincu par %s.") % _pname(opp)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(sub)
	_game_over_box = HBoxContainer.new()
	_game_over_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_game_over_box.add_theme_constant_override("separation", 20)
	vb.add_child(_game_over_box)
	match mode:
		"ai":
			var again := UITheme.button(Loc.t("Rejouer"), 200)
			again.pressed.connect(func(): get_tree().reload_current_scene())
			_game_over_box.add_child(again)
		"host", "client":
			if mode == "client" or Net.remote_peer_id != 0:
				_rematch_btn = UITheme.button(Loc.t("Revanche"), 220)
				_rematch_btn.set_meta("rematch", true)
				_rematch_btn.pressed.connect(_on_rematch_pressed)
				_game_over_box.add_child(_rematch_btn)
				_rematch_row = HBoxContainer.new()
				_rematch_row.alignment = BoxContainer.ALIGNMENT_CENTER
				_rematch_row.add_theme_constant_override("separation", 14)
				_rematch_row.set_meta("rematch", true)
				vb.add_child(_rematch_row)
				if Net.rematch_remote:
					_on_rematch_changed("ask")
	var menu := UITheme.button(Loc.t("Menu principal"), 220)
	menu.pressed.connect(func():
		Net.close()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	_game_over_box.add_child(menu)
	root.modulate.a = 0.0
	create_tween().tween_property(root, "modulate:a", 1.0, 0.4)
	if won:
		fx.layer = 70   # le feu d'artifice passe devant l'écran de victoire
		fx.fireworks(8)
	if Lobby.pending_update != "":
		# Une nouvelle version a été publiée pendant la partie : on la propose maintenant.
		get_tree().create_timer(1.5).timeout.connect(Lobby.show_update_dialog)
	Net.games_played += 1
	if Settings.auto_rematch and Net.is_online() and Net.games_played == 1:
		print("[%s] FIN DE LA PARTIE 1 : demande de revanche" % _pname(me))
		await _wait(1.0)
		_on_rematch_pressed()
		return
	if Settings.quit_after_game:
		print("[%s] FIN DE PARTIE : %s | tours %d | PV %d / %d" % [_pname(me), "égalité" if is_draw else ("victoire" if won else "défaite"),
			gs.turn_number, gs.players[0].hero.health, gs.players[1].hero.health])
		await _wait(8.0)   # le serveur rejoue la partie avant d'envoyer la récompense
		get_tree().quit()
