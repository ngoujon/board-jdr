class_name StatsPanel
extends Control
## Statistiques globales du jeu, calculées par le serveur à partir de toutes les parties enregistrées :
## cartes les plus jouées, taux de victoire quand une carte est jouée, durée des parties, avantage du
## premier joueur, résultats contre chaque IA. (Pas de statistiques personnelles ici.)

const MODES := [["all", "Toutes les parties"], ["pvp", "En ligne (JcJ)"], ["ai", "Contre l'IA"]]
const SORTS := [["plays", "Plus jouées"], ["winrate", "Meilleur % de victoire"], ["rate", "Présence dans les decks"]]
const COLS := [["#", 40], ["Carte", 230], ["Coût", 60], ["Jouée", 90], ["Parties", 90], ["Présence", 100], ["% victoires", 120]]
const AI_NAMES := ["Apprenti", "Chevalier", "Seigneur de guerre", "Challenger", "Inferno"]

var _mode := "all"
var _sort := "plays"
var _data := {}
var _summary: RichTextLabel
var _list: VBoxContainer
var _status: Label
var _mode_btns: Array[Button] = []
var _sort_btns: Array[Button] = []
var _preview: CardView
var _tips: KeywordTips


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("modal")   # Échap la ferme (voir PauseMenu)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 680)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	vb.add_child(UITheme.title_label(Loc.t("Statistiques du jeu"), 36))

	var modes := HBoxContainer.new()
	modes.alignment = BoxContainer.ALIGNMENT_CENTER
	modes.add_theme_constant_override("separation", 8)
	vb.add_child(modes)
	for m in MODES:
		var b := _tab_btn(Loc.t(m[1]), 210)
		var key: String = m[0]
		b.pressed.connect(func(): _set_mode(key))
		modes.add_child(b)
		_mode_btns.append(b)

	_summary = RichTextLabel.new()
	_summary.bbcode_enabled = true
	_summary.fit_content = true
	_summary.scroll_active = false
	_summary.add_theme_font_size_override("normal_font_size", 15)
	_summary.add_theme_font_size_override("bold_font_size", 15)
	vb.add_child(_summary)

	var sorts := HBoxContainer.new()
	sorts.add_theme_constant_override("separation", 8)
	vb.add_child(sorts)
	sorts.add_child(UITheme.label(Loc.t("Cartes :"), 16, UITheme.GOLD))
	for so in SORTS:
		var b := _tab_btn(Loc.t(so[1]), 230)
		var key: String = so[0]
		b.pressed.connect(func():
			_sort = key
			_fill_cards())
		sorts.add_child(b)
		_sort_btns.append(b)

	var header := HBoxContainer.new()
	vb.add_child(header)
	for c in COLS:
		var l := UITheme.label(Loc.t(c[0]), 15, UITheme.GOLD)
		l.custom_minimum_size.x = c[1]
		header.add_child(l)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_list)

	_status = UITheme.label("", 14, Color("c9b79a"), 3)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(_status)
	var close_btn := UITheme.button(Loc.t("Fermer"), 200)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(queue_free)
	vb.add_child(close_btn)

	# Survol d'une ligne : la carte et ses infobulles (comme en partie), au-dessus du panneau.
	_preview = CardView.new()
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.visible = false
	_preview.z_index = 10
	add_child(_preview)
	_tips = KeywordTips.new()
	_tips.z_index = 10
	add_child(_tips)


func _ready() -> void:
	Lobby.global_stats_received.connect(_on_stats)
	_set_mode("all")


## Ligne survolée : surlignée, avec la carte à droite du panneau et ses infobulles.
func _show_card(row: Control, id: String) -> void:
	row.modulate = Color(1.3, 1.25, 1.0)
	_preview.setup(id)
	var r := row.get_global_rect()
	# À droite du nom de la carte, centrée sur la ligne, sans sortir de l'écran.
	var pos := Vector2(r.position.x + 290, clampf(r.get_center().y - CardView.SIZE.y / 2, 6, 720 - CardView.SIZE.y - 6))
	_preview.position = pos
	_preview.visible = true
	_tips.show_card(id)
	_tips.place_beside(Rect2(pos, CardView.SIZE))


func _hide_card(row: Control) -> void:
	if is_instance_valid(row):
		row.modulate = Color.WHITE
	_preview.visible = false
	_tips.hide_tips()


func _tab_btn(text: String, width: int) -> Button:
	var b := UITheme.button(text, width)
	b.custom_minimum_size.y = 34
	b.add_theme_font_size_override("font_size", 15)
	return b


func _highlight(btns: Array[Button], index: int) -> void:
	for i in btns.size():
		btns[i].add_theme_color_override("font_color", UITheme.GOLD if i == index else UITheme.LIGHT_TEXT)


func _set_mode(mode: String) -> void:
	_mode = mode
	_highlight(_mode_btns, MODES.map(func(m): return m[0]).find(mode))
	for c in _list.get_children():
		c.queue_free()
	if not Lobby.online:
		_summary.text = ""
		_status.text = Loc.t("Connectez-vous au serveur pour consulter les statistiques (Paramètres > Profil).")
		return
	_status.text = Loc.t("Chargement...")
	Lobby.request_global_stats(mode)


func _on_stats(data: Dictionary) -> void:
	if data.get("mode", "") != _mode:
		return
	_data = data
	var games := int(data.get("games", 0))
	var by_mode: Dictionary = data.get("by_mode", {})
	var dur := int(data.get("avg_duration", 0))
	var txt := (Loc.t("[b]%d[/b] parties enregistrées  ·  en ligne : [b]%d[/b]  ·  contre l'IA : [b]%d[/b]\n") if games > 1
		else Loc.t("[b]%d[/b] partie enregistrée  ·  en ligne : [b]%d[/b]  ·  contre l'IA : [b]%d[/b]\n")) % [
		games, int(by_mode.get("pvp", 0)), int(by_mode.get("ai", 0))]
	txt += Loc.t("Durée moyenne : [b]%s[/b]  ·  tours moyens : [b]%.1f[/b]") % [
		(Loc.t("%d min %02d s") % [dur / 60, dur % 60]) if dur > 0 else "—", float(data.get("avg_turns", 0))]
	var fg := int(data.get("first_games", 0))
	if fg > 0:
		txt += Loc.t("  ·  le joueur qui commence gagne [b]%.0f %%[/b] des parties") % (100.0 * int(data.get("first_wins", 0)) / fg)
	var ai_parts: Array[String] = []
	for a in data.get("ai", []):
		var n := int(a.games)
		if n > 0:
			ai_parts.append(Loc.t("%s : [b]%.0f %%[/b] de victoires des joueurs (%d)") % [
				Loc.t(AI_NAMES[clampi(int(a.difficulty), 0, 4)]), 100.0 * int(a.player_wins) / n, n])
	if not ai_parts.is_empty() and _mode != "pvp":
		txt += Loc.t("\nContre l'IA — ") + "  ·  ".join(ai_parts)
	_summary.text = txt
	_fill_cards()


func _fill_cards() -> void:
	_highlight(_sort_btns, SORTS.map(func(so): return so[0]).find(_sort))
	for c in _list.get_children():
		c.queue_free()
	var cards: Array = _data.get("cards", []).duplicate()
	var sides := maxi(1, int(_data.get("sides", 0)))
	for c in cards:
		c["winrate"] = 100.0 * int(c.wins) / maxi(1, int(c.games))
		c["rate"] = 100.0 * int(c.games) / sides
	match _sort:
		"plays":
			cards.sort_custom(func(a, b): return int(a.plays) > int(b.plays))
		"winrate":
			# Au moins 5 parties pour que le pourcentage ait du sens.
			cards.sort_custom(func(a, b):
				var ka := int(a.games) >= 5
				var kb := int(b.games) >= 5
				return a.winrate > b.winrate if ka == kb else ka)
		"rate":
			cards.sort_custom(func(a, b): return a.rate > b.rate)
	var rank := 0
	for c in cards:
		var card := CardDB.get_card(c.card)
		if card.is_empty():
			continue
		rank += 1
		var row := HBoxContainer.new()
		var type_col: Color = {"spell": Color("9fd8ff"), "enchantment": Color("c9a0ff")}.get(card.type, UITheme.LIGHT_TEXT)
		var values := [str(rank), card.name, str(card.cost), str(int(c.plays)), str(int(c.games)),
			"%.0f %%" % c.rate, ("%.0f %%" % c.winrate) if int(c.games) >= 5 else "—"]
		for i in COLS.size():
			var col := type_col if i == 1 else UITheme.LIGHT_TEXT
			if i == 6 and int(c.games) >= 5:
				col = UITheme.GREEN if c.winrate >= 55.0 else (UITheme.RED if c.winrate <= 45.0 else UITheme.LIGHT_TEXT)
			var l := UITheme.label(values[i], 15, col, 3)
			l.custom_minimum_size.x = COLS[i][1]
			l.clip_text = true
			row.add_child(l)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		var id: String = c.card
		row.mouse_entered.connect(_show_card.bind(row, id))
		row.mouse_exited.connect(_hide_card.bind(row))
		_list.add_child(row)
	if rank == 0:
		_list.add_child(UITheme.label(Loc.t("Aucune carte enregistrée pour ce mode pour le moment."), 15, Color("c9b79a")))
	_status.text = Loc.t("Calculé sur toutes les parties enregistrées par le serveur (cartes : depuis la version 1.6). « Présence » : part des decks qui ont joué la carte au moins une fois ; % de victoires affiché à partir de 5 parties.")
