class_name LeaderboardPanel
extends Control
## Classement des joueurs (serveur communautaire) : onglet « Général » (victoires, défaites, % de victoires,
## contre l'IA, meilleur score Inferno) et onglet « Inferno » (meilleurs scores du mode Inferno).
## Un clic sur le titre d'une colonne trie le tableau (un 2e clic inverse l'ordre).
## Barre de recherche par pseudo ; un clic sur un joueur ouvre son profil (statistiques,
## cartes favorites, historique complet et replays des parties).

# [clé de tri, titre, largeur]
const GENERAL_COLS := [["rank", "#", 44], ["", "", 44], ["name", "Joueur", 178], ["wins", "V", 46], ["losses", "D", 46],
	["winrate", "% victoires", 104], ["ai_wins", "vs IA (V/D)", 104], ["ai_winrate", "% vs IA", 84], ["inferno", "Inferno", 90]]
const INFERNO_COLS := [["rank", "#", 44], ["", "", 44], ["name", "Joueur", 230], ["inferno", "Meilleur score", 150],
	["inferno_games", "Parties Inferno", 150], ["inferno_ts", "Date du record", 150]]

var _list: VBoxContainer
var _header: HBoxContainer
var _status: Label
var _search: LineEdit
var _query := ""
var _tab := "general"            # general | inferno
var _tab_btns := {}
var _rows: Array = []            # lignes reçues (ordre du serveur)
var _sort_key := "rank"
var _sort_desc := false


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
	panel.custom_minimum_size = Vector2(860, 660)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	vb.add_child(UITheme.title_label(Loc.t("Classement"), 38))

	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 10)
	vb.add_child(tabs)
	for t in [["general", "Général"], ["inferno", "Inferno"]]:
		var b := UITheme.button(Loc.t(t[1]), 180)
		b.toggle_mode = true
		b.custom_minimum_size.y = 36
		var key: String = t[0]
		b.pressed.connect(func(): _set_tab(key))
		tabs.add_child(b)
		_tab_btns[key] = b

	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 8)
	vb.add_child(search_row)
	_search = LineEdit.new()
	_search.placeholder_text = Loc.t("Rechercher un joueur (pseudo)")
	_search.max_length = 16
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_submitted.connect(func(_t): _do_search())
	_search.text_changed.connect(func(t: String):
		if t.strip_edges() == "" and _query != "":
			_request())
	search_row.add_child(_search)
	var go := UITheme.button(Loc.t("Rechercher"), 170)
	go.custom_minimum_size.y = 38
	go.pressed.connect(_do_search)
	search_row.add_child(go)

	_status = UITheme.label("", 15, Color("c9b79a"), 3)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(_status)

	_header = HBoxContainer.new()
	vb.add_child(_header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)

	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 12)
	vb.add_child(hb)
	var mine := UITheme.button(Loc.t("Mon profil"), 200)
	mine.pressed.connect(func(): _open_profile(Lobby.profile.get("name", "")))
	hb.add_child(mine)
	var refresh := UITheme.button(Loc.t("Actualiser"), 180)
	refresh.pressed.connect(func():
		if _query != "":
			_do_search()
		else:
			_request())
	hb.add_child(refresh)
	var close := UITheme.button(Loc.t("Fermer"), 180)
	close.pressed.connect(queue_free)
	hb.add_child(close)
	_set_tab("general", false)


func _ready() -> void:
	Lobby.leaderboard_received.connect(func(rows: Array):
		if _query == "":
			_set_rows(rows))
	Lobby.players_found.connect(func(q: String, rows: Array):
		if q == _query:
			_set_rows(rows)
			_status.text = (Loc.t("%d joueurs trouvés pour « %s ». Cliquez sur un joueur pour voir son profil.") if rows.size() > 1
				else Loc.t("%d joueur trouvé pour « %s ». Cliquez sur un joueur pour voir son profil.")) % [
				rows.size(), _search.text.strip_edges()])
	_request()


func _cols() -> Array:
	return INFERNO_COLS if _tab == "inferno" else GENERAL_COLS


func _set_tab(tab: String, refill := true) -> void:
	_tab = tab
	for k in _tab_btns:
		_tab_btns[k].set_pressed_no_signal(k == tab)
	# Onglet Inferno : meilleurs scores d'abord ; Général : ordre du classement du serveur.
	_sort_key = "inferno" if tab == "inferno" else "rank"
	_sort_desc = tab == "inferno"
	if refill:
		_fill()


func _build_header() -> void:
	for c in _header.get_children():
		c.queue_free()
	for c in _cols():
		if c[0] == "":
			var gap := Control.new()
			gap.custom_minimum_size.x = c[2]
			_header.add_child(gap)
			continue
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.x = c[2]
		b.clip_text = true
		for sn in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
			b.add_theme_stylebox_override(sn, StyleBoxEmpty.new())   # pas de marge : le titre tient dans la colonne
		var arrow := ""
		if c[0] == _sort_key:
			arrow = " v" if _sort_desc else " ^"
		b.text = Loc.t(c[1]) + arrow
		b.add_theme_font_size_override("font_size", 16)
		b.add_theme_color_override("font_color", UITheme.GOLD)
		b.add_theme_color_override("font_hover_color", Color("ffe0a0"))
		b.tooltip_text = Loc.t("Trier par cette colonne (cliquez à nouveau pour inverser)")
		var key: String = c[0]
		b.pressed.connect(func(): _sort_by(key))
		_header.add_child(b)


func _sort_by(key: String) -> void:
	if key == _sort_key:
		_sort_desc = not _sort_desc
	else:
		_sort_key = key
		_sort_desc = key not in ["rank", "name", "losses"]   # plus grand d'abord, sauf rang, pseudo et défaites
	_fill()


func _clear() -> void:
	for c in _list.get_children():
		c.queue_free()


func _request() -> void:
	_query = ""
	if Lobby.online:
		_status.text = Loc.t("Classement du serveur (parties en ligne). Cliquez sur un joueur pour voir son profil et ses parties.")
		Lobby.request_leaderboard()
	else:
		_status.text = Loc.t("Serveur hors ligne : seules vos statistiques locales sont affichées. (Options > Profil pour vous connecter)")
		var pname := Settings.player_name if Settings.player_name != "" else Loc.t("Vous")
		var w := Settings.local_ai_wins
		var l := Settings.local_ai_losses
		_set_rows([{"name": pname, "avatar": Settings.avatar, "wins": 0, "losses": 0, "winrate": 0.0,
			"ai_wins": w, "ai_losses": l, "ai_winrate": (100.0 * w / (w + l)) if w + l > 0 else 0.0, "me": true, "online": false,
			"inferno": Settings.inferno_best, "inferno_games": 0, "inferno_ts": 0}])


func _set_rows(rows: Array) -> void:
	_rows = rows
	for i in _rows.size():
		if not _rows[i].has("rank"):
			_rows[i]["rank"] = i + 1
	_fill()


func _do_search() -> void:
	var q := _search.text.strip_edges()
	if q == "":
		_request()
		return
	if not Lobby.online:
		_status.text = Loc.t("Connectez-vous au serveur pour rechercher un joueur.")
		return
	_query = q.to_lower()
	_status.text = Loc.t("Recherche...")
	Lobby.search_players(q)


func _open_profile(player_name: String) -> void:
	if not Lobby.online:
		_status.text = Loc.t("Connectez-vous au serveur pour consulter les profils.")
		return
	add_child(PlayerProfilePanel.new(player_name))


## Pseudo (cliquable en ligne : profil du joueur) avec son titre en dessous.
func _name_cell(r: Dictionary, text: String, col: Color, width: int) -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", -4)
	vb.custom_minimum_size.x = width
	var label := text + ("  ●" if r.get("online", false) else "")
	if Lobby.online:
		var b := Button.new()
		b.text = label
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_color_override("font_color", col)
		b.add_theme_font_size_override("font_size", 17)
		b.tooltip_text = Loc.t("Voir le profil et les parties de %s") % r.name
		var n: String = r.name
		b.pressed.connect(func(): _open_profile(n))
		vb.add_child(b)
	else:
		vb.add_child(UITheme.label(label, 17, col))
	var title := Cosmetics.title_name(r.get("title", ""))
	if title != "":
		vb.add_child(UITheme.label(title, 12, Color("c9a0ff"), 2))
	return vb


func _sort_value(r: Dictionary, key: String):
	if key == "name":
		return str(r.get("name", "")).to_lower()
	return float(r.get(key, 0))


func _cell_text(r: Dictionary, key: String, rank: int) -> String:
	match key:
		"rank":
			return str(rank)
		"name":
			return str(r.name)
		"winrate", "ai_winrate":
			return "%.1f %%" % float(r.get(key, 0.0))
		"ai_wins":
			return "%d / %d" % [int(r.get("ai_wins", 0)), int(r.get("ai_losses", 0))]
		"inferno":
			return str(int(r.get("inferno", 0))) if int(r.get("inferno", 0)) > 0 else "-"
		"inferno_ts":
			var ts := int(r.get("inferno_ts", 0))
			return Time.get_date_string_from_unix_time(ts) if ts > 0 else "-"
	return str(int(r.get(key, 0)))


func _fill() -> void:
	_clear()
	_build_header()
	var rows := _rows.duplicate()
	if _tab == "inferno":
		rows = rows.filter(func(r): return int(r.get("inferno", 0)) > 0)
		# Rang Inferno : ordre des meilleurs scores (à égalité, le record le plus ancien d'abord).
		rows.sort_custom(func(a, b):
			if int(a.get("inferno", 0)) != int(b.get("inferno", 0)):
				return int(a.get("inferno", 0)) > int(b.get("inferno", 0))
			return int(a.get("inferno_ts", 0)) < int(b.get("inferno_ts", 0)))
		for i in rows.size():
			rows[i] = rows[i].duplicate()
			rows[i]["inferno_rank"] = i + 1
	var rank_key := "inferno_rank" if _tab == "inferno" else "rank"
	var key := rank_key if _sort_key == "rank" else _sort_key
	var desc := _sort_desc
	rows.sort_custom(func(a, b):
		var va = _sort_value(a, key)
		var vb = _sort_value(b, key)
		if va == vb:
			return _sort_value(a, rank_key) < _sort_value(b, rank_key)
		return va > vb if desc else va < vb)
	var cols := _cols()
	for r in rows:
		var row := HBoxContainer.new()
		var col := UITheme.GOLD if r.get("me", false) else UITheme.LIGHT_TEXT
		var rank := int(r.get(rank_key, 0))
		for c in cols:
			if c[0] == "":
				# Avatar avec son contour (le n°1 du classement a le contour Champion).
				row.add_child(AvatarBadge.new().setup(int(r.avatar), str(r.get("border", "none")), 40))
				var gap := Control.new()
				gap.custom_minimum_size.x = maxf(0.0, c[2] - 44)
				row.add_child(gap)
				continue
			if c[0] == "name":
				row.add_child(_name_cell(r, str(r.name), col, c[2]))
				continue
			var l := UITheme.label(_cell_text(r, c[0], rank), 17, Color("ffa060") if c[0] == "inferno" and r.get("inferno", 0) > 0 else col)
			l.custom_minimum_size.x = c[2]
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			l.size_flags_vertical = Control.SIZE_FILL
			row.add_child(l)
		_list.add_child(row)
	if rows.is_empty():
		var empty := Loc.t("Aucun joueur trouvé.") if _query != "" else Loc.t("Aucun joueur classé pour le moment.")
		if _tab == "inferno" and _query == "":
			empty = Loc.t("Aucun score Inferno pour le moment : lancez-vous !")
		_list.add_child(UITheme.label(empty, 16, Color("c9b79a")))
