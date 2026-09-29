class_name SuggestionPanel
extends Control
## Forum des suggestions (menu d'accueil et bouton du plateau en partie) : chaque suggestion est un sujet
## public (buff / nerf de cartes, bug, autre idée) où les joueurs discutent dans un fil de réponses.
## Trois pages : liste des sujets (recherche + filtres, pour vérifier qu'un sujet n'existe pas déjà),
## fil de discussion d'un sujet, création d'un sujet. Le serveur enregistre l'auteur de chaque message
## (tables « suggestions » et « suggestion_replies », lues avec tools/suggestions.py).

const MAX_CARDS := 5
const MAX_LEN := 600
const KINDS := [["buff", "Buff (renforcer)"], ["nerf", "Nerf (affaiblir)"], ["bug", "Bug"], ["autre", "Autre idée"]]
const FILTERS := [["", "Tous"], ["buff", "Buffs"], ["nerf", "Nerfs"], ["bug", "Bugs"], ["autre", "Autres"]]
const KIND_COLORS := {"buff": "#7fd67f", "nerf": "#ff7a6a", "bug": "#ffb347", "autre": "#c9a0ff"}
const KIND_TAGS := {"buff": "BUFF", "nerf": "NERF", "bug": "BUG", "autre": "IDÉE"}

var _pages: Array[Control] = []
var _status: Label

# Liste des sujets
var _search: LineEdit
var _filter := ""
var _filter_btns: Array[Button] = []
var _topic_list: VBoxContainer
var _search_timer: Timer

# Fil de discussion
var _topic := {}
var _thread_head: RichTextLabel
var _thread_msgs: RichTextLabel
var _reply: LineEdit
var _reply_btn: Button

# Nouveau sujet
var _selected: Array[String] = []
var _kind := "buff"
var _rows := {}                 # card_id -> CheckBox de la liste
var _card_search: LineEdit
var _chosen_label: RichTextLabel
var _kind_btns: Array[Button] = []
var _text: TextEdit
var _counter: Label
var _send_btn: Button
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
	panel.custom_minimum_size = Vector2(1040, 690)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	vb.add_child(UITheme.title_label(Loc.t("Suggestions et bugs"), 34))
	var pages := Control.new()
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pages.custom_minimum_size = Vector2(1000, 540)
	vb.add_child(pages)
	for build in [_build_list_page, _build_thread_page, _build_new_page]:
		var page: Control = build.call()
		page.set_anchors_preset(Control.PRESET_FULL_RECT)
		pages.add_child(page)
		_pages.append(page)
	_status = UITheme.label("", 15, Color("c9b79a"), 3)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.custom_minimum_size.x = 1000
	vb.add_child(_status)
	var close_btn := UITheme.button(Loc.t("Fermer"), 200)
	close_btn.custom_minimum_size.y = 40
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(queue_free)
	vb.add_child(close_btn)

	_preview = CardView.new()
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.visible = false
	_preview.z_index = 10
	add_child(_preview)
	_tips = KeywordTips.new()
	_tips.z_index = 10
	add_child(_tips)
	_search_timer = Timer.new()
	_search_timer.one_shot = true
	_search_timer.wait_time = 0.35
	_search_timer.timeout.connect(_request_list)
	add_child(_search_timer)


func _ready() -> void:
	Lobby.sugg_list_received.connect(_on_list)
	Lobby.sugg_thread_received.connect(_on_thread)
	Lobby.server_error.connect(_on_error)
	_show_page(0)
	_update_form()
	_request_list()


func _exit_tree() -> void:
	if Lobby.online:
		Lobby.close_sugg()


func _show_page(i: int) -> void:
	for p in _pages.size():
		_pages[p].visible = p == i
	_hide_card()


# ======================================================================== liste des sujets

func _build_list_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	page.add_child(top)
	_search = LineEdit.new()
	_search.placeholder_text = Loc.t("Rechercher (carte, mot, joueur)...")
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): _search_timer.start())
	top.add_child(_search)
	var new_btn := UITheme.button(Loc.t("Nouveau sujet"), 220)
	new_btn.custom_minimum_size.y = 38
	new_btn.pressed.connect(_open_new)
	top.add_child(new_btn)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 6)
	page.add_child(filters)
	for fl in FILTERS:
		var b := UITheme.button(Loc.t(fl[1]), 120)
		b.custom_minimum_size.y = 32
		b.add_theme_font_size_override("font_size", 15)
		var key: String = fl[0]
		b.pressed.connect(func():
			_filter = key
			_request_list())
		filters.add_child(b)
		_filter_btns.append(b)
	var hint := UITheme.label(Loc.t("Avant de créer un sujet, cherchez s'il existe déjà : vous pourrez y répondre."), 14, Color("9a8aa8"), 3)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.custom_minimum_size.x = 300
	filters.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	_topic_list = VBoxContainer.new()
	_topic_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_topic_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_topic_list)
	return page


func _request_list() -> void:
	for i in _filter_btns.size():
		_filter_btns[i].modulate = Color(1.3, 1.2, 0.6) if FILTERS[i][0] == _filter else Color(0.75, 0.75, 0.75)
	if not Lobby.online:
		_status.text = Loc.t("Connectez-vous au serveur pour lire et envoyer des suggestions (Paramètres > Profil).")
		return
	var q := _search.text.strip_edges()
	var ids: Array = []
	if q.length() >= 2:
		for id in CardDB.COLLECTION_ORDER:
			if str(CardDB.get_card(id).get("name", "")).to_lower().contains(q.to_lower()):
				ids.append(id)
	_status.text = Loc.t("Chargement...")
	Lobby.request_sugg_list(_filter, q, ids)


func _on_list(topics: Array) -> void:
	_status.text = ""
	for c in _topic_list.get_children():
		c.queue_free()
	if topics.is_empty():
		var l := UITheme.label(Loc.t("Aucun sujet trouvé.") if _search.text.strip_edges() != "" or _filter != ""
			else Loc.t("Aucun sujet pour l'instant : lancez la discussion !"), 16, Color("9a8aa8"), 3)
		_topic_list.add_child(l)
		return
	for t in topics:
		_topic_list.add_child(_topic_row(t))


func _topic_row(t: Dictionary) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 58)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", UITheme.flat_style(Color(0.13, 0.09, 0.11, 0.9), Color("5a4636"), 1, 4))
	b.add_theme_stylebox_override("hover", UITheme.flat_style(Color(0.22, 0.15, 0.12, 0.95), UITheme.GOLD, 2, 4))
	b.add_theme_stylebox_override("pressed", UITheme.flat_style(Color(0.22, 0.15, 0.12, 0.95), UITheme.GOLD, 2, 4))
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.scroll_active = false
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rt.set_anchors_preset(Control.PRESET_FULL_RECT)
	rt.offset_left = 10
	rt.offset_top = 6
	rt.offset_right = -10
	rt.add_theme_font_size_override("normal_font_size", 15)
	rt.add_theme_font_size_override("bold_font_size", 15)
	var excerpt := str(t.get("text", "")).replace("\n", " ")
	if excerpt.length() > 110:
		excerpt = excerpt.left(107) + "..."
	var n := int(t.get("replies", 0))
	var replies := (Loc.t("%d réponses") if n > 1 else Loc.t("%d réponse")) % n
	rt.text = "%s %s%s\n[color=#9a8aa8]%s[/color]" % [_tag(str(t.get("kind", "autre"))), _cards_txt(t), _esc(excerpt),
		Loc.t("par %s · %s · %s") % [_esc(str(t.get("name", "?"))), _date(int(t.get("last_ts", t.get("ts", 0)))), replies]]
	b.add_child(rt)
	var id := int(t.get("id", 0))
	b.pressed.connect(func():
		_status.text = Loc.t("Chargement...")
		Lobby.request_sugg_thread(id))
	return b


# ======================================================================== fil de discussion

func _build_thread_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	var back := UITheme.button(Loc.t("Retour à la liste"), 240)
	back.custom_minimum_size.y = 34
	back.add_theme_font_size_override("font_size", 15)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(func():
		_topic = {}
		_show_page(0)
		_request_list())
	page.add_child(back)
	_thread_head = RichTextLabel.new()
	_thread_head.bbcode_enabled = true
	_thread_head.fit_content = true
	_thread_head.scroll_active = false
	_thread_head.add_theme_font_size_override("normal_font_size", 16)
	_thread_head.add_theme_font_size_override("bold_font_size", 16)
	var head_panel := PanelContainer.new()
	head_panel.add_theme_stylebox_override("panel", UITheme.flat_style(Color(0.13, 0.09, 0.11, 0.9), UITheme.GOLD, 2, 4))
	head_panel.add_child(_thread_head)
	page.add_child(head_panel)
	_thread_msgs = RichTextLabel.new()
	_thread_msgs.bbcode_enabled = true
	_thread_msgs.scroll_following = true
	_thread_msgs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_thread_msgs.add_theme_font_size_override("normal_font_size", 15)
	_thread_msgs.add_theme_font_size_override("bold_font_size", 15)
	page.add_child(_thread_msgs)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	page.add_child(row)
	_reply = LineEdit.new()
	_reply.placeholder_text = Loc.t("Votre réponse...")
	_reply.max_length = 400
	_reply.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reply.text_submitted.connect(func(_t): _send_reply())
	row.add_child(_reply)
	_reply_btn = UITheme.button(Loc.t("Répondre"), 180)
	_reply_btn.custom_minimum_size.y = 38
	_reply_btn.pressed.connect(_send_reply)
	row.add_child(_reply_btn)
	return page


func _on_thread(topic: Dictionary, created: bool) -> void:
	if topic.is_empty():
		return
	# Mise à jour en direct d'un autre sujet que celui affiché : ignorée.
	if not created and not _topic.is_empty() and int(_topic.get("id", 0)) != int(topic.get("id", 0)) and _pages[1].visible:
		return
	_topic = topic
	_status.text = Loc.t("Merci ! Votre sujet est publié : les autres joueurs peuvent y répondre.") if created else ""
	if created:
		_reset_form()
	_thread_head.text = "%s %s[color=#9a8aa8]%s[/color]\n%s" % [_tag(str(topic.get("kind", "autre"))), _cards_txt(topic),
		Loc.t("par %s · %s") % [_esc(str(topic.get("name", "?"))), _date(int(topic.get("ts", 0)))], _esc(str(topic.get("text", "")))]
	var lines: Array[String] = []
	for m in topic.get("messages", []):
		lines.append("[color=#f2c14e][b]%s[/b][/color] [color=#9a8aa8]%s[/color]\n%s" % [
			_esc(str(m.get("name", "?"))), _date(int(m.get("ts", 0))), _esc(str(m.get("text", "")))])
	_thread_msgs.text = "\n\n".join(lines) if not lines.is_empty() \
		else "[color=#9a8aa8]%s[/color]" % Loc.t("Aucune réponse pour l'instant : donnez votre avis !")
	_reply_btn.disabled = not Lobby.online
	_show_page(1)


func _send_reply() -> void:
	var txt := _reply.text.strip_edges()
	if txt == "" or _topic.is_empty() or not Lobby.online:
		return
	Lobby.reply_sugg(int(_topic.get("id", 0)), txt)
	_reply.text = ""


# ======================================================================== nouveau sujet

func _build_new_page() -> Control:
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	# Colonne gauche : recherche et liste des cartes (cases à cocher).
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 330
	left.add_theme_constant_override("separation", 6)
	cols.add_child(left)
	_card_search = LineEdit.new()
	_card_search.placeholder_text = Loc.t("Rechercher une carte...")
	_card_search.text_changed.connect(func(_t): _filter_cards())
	left.add_child(_card_search)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	for id in CardDB.COLLECTION_ORDER:
		var c := CardDB.get_card(id)
		if c.is_empty():
			continue
		var b := CheckBox.new()
		b.text = "%d · %s" % [int(c.cost), c.name]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_color_override("font_color", Color("e8d6b0"))
		b.toggled.connect(_on_card_toggled.bind(id))
		b.mouse_entered.connect(_show_card.bind(b, id))
		b.mouse_exited.connect(_hide_card)
		list.add_child(b)
		_rows[id] = b

	# Colonne droite : type de sujet, cartes choisies, texte, envoi.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	cols.add_child(right)
	var kinds := HBoxContainer.new()
	kinds.add_theme_constant_override("separation", 6)
	right.add_child(kinds)
	for k in KINDS:
		var b := UITheme.button(Loc.t(k[1]), 150)
		b.custom_minimum_size.y = 36
		b.add_theme_font_size_override("font_size", 14)
		var key: String = k[0]
		b.pressed.connect(func():
			_kind = key
			_update_form())
		kinds.add_child(b)
		_kind_btns.append(b)
	_chosen_label = RichTextLabel.new()
	_chosen_label.bbcode_enabled = true
	_chosen_label.fit_content = true
	_chosen_label.scroll_active = false
	_chosen_label.add_theme_font_size_override("normal_font_size", 16)
	_chosen_label.add_theme_font_size_override("bold_font_size", 16)
	right.add_child(_chosen_label)
	_text = TextEdit.new()
	_text.custom_minimum_size = Vector2(0, 200)
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text.add_theme_font_size_override("font_size", 15)
	_text.text_changed.connect(_on_text_changed)
	right.add_child(_text)
	var send_row := HBoxContainer.new()
	send_row.add_theme_constant_override("separation", 12)
	right.add_child(send_row)
	_send_btn = UITheme.button(Loc.t("Publier le sujet"), 240)
	_send_btn.custom_minimum_size.y = 40
	_send_btn.pressed.connect(_on_send)
	send_row.add_child(_send_btn)
	var cancel := UITheme.button(Loc.t("Annuler"), 160)
	cancel.custom_minimum_size.y = 40
	cancel.pressed.connect(func():
		_show_page(0)
		_status.text = "")
	send_row.add_child(cancel)
	_counter = UITheme.label("", 14, Color("c9b79a"), 3)
	send_row.add_child(_counter)
	return cols


func _open_new() -> void:
	_status.text = "" if Lobby.online else Loc.t("Connectez-vous au serveur pour lire et envoyer des suggestions (Paramètres > Profil).")
	_update_form()
	_show_page(2)


func _on_card_toggled(on: bool, id: String) -> void:
	if on and not _selected.has(id):
		if _selected.size() >= MAX_CARDS:
			_rows[id].set_pressed_no_signal(false)
			_status.text = Loc.t("5 cartes au plus par suggestion.")
			return
		_selected.append(id)
	elif not on:
		_selected.erase(id)
	_update_form()


func _on_text_changed() -> void:
	if _text.text.length() > MAX_LEN:
		_text.text = _text.text.left(MAX_LEN)
		_text.set_caret_line(_text.get_line_count() - 1)
		_text.set_caret_column(_text.get_line(_text.get_line_count() - 1).length())
	_update_form()


func _needs_cards() -> bool:
	return _kind in ["buff", "nerf"]


func _update_form() -> void:
	if _selected.is_empty():
		_chosen_label.text = Loc.t("Cartes choisies : [color=#9a8aa8]aucune (cochez-les dans la liste)[/color]") if _needs_cards() \
			else Loc.t("Cartes concernées : [color=#9a8aa8]facultatif[/color]")
	else:
		var names: Array[String] = []
		for id in _selected:
			names.append("[b]%s[/b]" % CardDB.get_card(id).name)
		_chosen_label.text = Loc.t("Cartes choisies : %s") % ", ".join(names)
	for i in _kind_btns.size():
		_kind_btns[i].modulate = Color(1.3, 1.2, 0.6) if KINDS[i][0] == _kind else Color(0.75, 0.75, 0.75)
	_text.placeholder_text = Loc.t("Décrivez le bug : ce que vous faisiez, ce qui s'est passé, ce que vous attendiez...") if _kind == "bug" \
		else Loc.t("Votre proposition, par exemple : coûter 1 de moins, passer à 3/4, changer son effet...")
	_counter.text = "%d / %d" % [_text.text.length(), MAX_LEN]
	_send_btn.disabled = not Lobby.online or (_needs_cards() and _selected.is_empty()) or _text.text.strip_edges() == ""


func _filter_cards() -> void:
	var q := _card_search.text.strip_edges().to_lower()
	for id in _rows:
		_rows[id].visible = q == "" or str(CardDB.get_card(id).name).to_lower().contains(q)


func _on_send() -> void:
	if _send_btn.disabled:
		return
	_send_btn.disabled = true
	_status.text = Loc.t("Envoi...")
	Lobby.send_suggestion(_selected.duplicate(), _kind, _text.text)


func _reset_form() -> void:
	_text.text = ""
	for id in _selected.duplicate():
		_rows[id].button_pressed = false
	_update_form()


func _on_error(code: String, msg: String) -> void:
	if code in ["suggest_invalid", "rate", "sugg_missing"]:
		_status.text = msg
		_update_form()


# ======================================================================== outils

func _tag(kind: String) -> String:
	return "[color=%s][b]%s[/b][/color]" % [KIND_COLORS.get(kind, "#c9a0ff"), Loc.t(KIND_TAGS.get(kind, "IDÉE"))]


func _cards_txt(t: Dictionary) -> String:
	var names: Array[String] = []
	for id in t.get("cards", []):
		names.append(str(CardDB.get_card(str(id)).get("name", id)))
	return "[b]%s[/b] — " % ", ".join(names) if not names.is_empty() else ""


## Texte d'un joueur affiché tel quel (pas de BBCode).
static func _esc(s: String) -> String:
	return s.replace("[", "[lb]")


static func _date(ts: int) -> String:
	var local := ts + int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(local)
	return "%02d/%02d/%d %02d:%02d" % [d.day, d.month, d.year, d.hour, d.minute]


func _show_card(row: Control, id: String) -> void:
	_preview.setup(id)
	var r := row.get_global_rect()
	var pos := Vector2(r.position.x + 300, clampf(r.get_center().y - CardView.SIZE.y / 2, 6, 720 - CardView.SIZE.y - 6))
	_preview.position = pos
	_preview.visible = true
	_tips.show_card(id)
	_tips.place_beside(Rect2(pos, CardView.SIZE))


func _hide_card() -> void:
	if _preview:
		_preview.visible = false
		_tips.hide_tips()
