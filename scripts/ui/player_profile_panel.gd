class_name PlayerProfilePanel
extends Control
## Profil public d'un joueur (ouvert depuis le classement) : avatar, titre, rang, statistiques,
## cartes favorites et historique complet de ses parties, avec « Revoir » pour les replays.

const HIST_COLS := [["Date", 165], ["Mode", 75], ["Adversaire", 170], ["Résultat", 100], ["Tours", 55], ["Durée", 90], ["", 110]]
const REASONS := {"concede": " (abandon)", "disconnect": " (déconnexion)", "normal": ""}

var _name := ""
var _head: HBoxContainer
var _info: RichTextLabel
var _actions: HBoxContainer
var _list: VBoxContainer
var _status: Label


func _init(player_name := "") -> void:
	_name = player_name
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("modal")   # Échap la ferme (voir PauseMenu)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(880, 680)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)

	_head = HBoxContainer.new()
	_head.add_theme_constant_override("separation", 16)
	vb.add_child(_head)
	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.fit_content = true
	_info.scroll_active = false
	_info.add_theme_font_size_override("normal_font_size", 15)
	_info.add_theme_font_size_override("bold_font_size", 15)
	vb.add_child(_info)
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 10)
	vb.add_child(_actions)

	vb.add_child(UITheme.label(Loc.t("Historique des parties"), 20, UITheme.GOLD))
	var header := HBoxContainer.new()
	vb.add_child(header)
	for c in HIST_COLS:
		var l := UITheme.label(Loc.t(c[0]), 15, UITheme.GOLD)
		l.custom_minimum_size.x = c[1]
		header.add_child(l)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 3)
	scroll.add_child(_list)
	_status = UITheme.label("", 14, Color("c9b79a"), 3)
	vb.add_child(_status)
	var close_btn := UITheme.button(Loc.t("Fermer"), 200)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(queue_free)
	vb.add_child(close_btn)


func _ready() -> void:
	Lobby.player_profile_received.connect(_on_profile)
	Lobby.history_received.connect(_on_history)
	if not Lobby.online:
		_info.text = Loc.t("Connectez-vous au serveur pour consulter les profils.")
		return
	_info.text = Loc.t("Chargement du profil...")
	Lobby.request_player_profile(_name)
	Lobby.request_history(_name, 200)


func _is_me(n: String) -> bool:
	return n == Lobby.profile.get("name", "")


func _on_profile(d: Dictionary) -> void:
	if _name != "" and d.get("name", "") != _name:
		return
	_name = str(d.get("name", ""))
	for c in _head.get_children():
		c.queue_free()
	_head.add_child(AvatarBadge.new().setup(int(d.get("avatar", 1)), str(d.get("border", "none")), 96))
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	_head.add_child(names)
	names.add_child(UITheme.title_label(_name, 34))
	var title := Cosmetics.title_name(d.get("title", ""))
	if title != "":
		names.add_child(UITheme.label(title, 16, Color("c9a0ff"), 3))
	var online := bool(d.get("online", false))
	var sub := Loc.t("Rang n°%d") % int(d.get("rank", 0)) if d.has("rank") else Loc.t("Non classé")
	if bool(d.get("champion", false)):
		sub += Loc.t("  ·  Champion")
	sub += "  ·  " + (Loc.t("● En ligne") if online else Loc.t("○ Hors ligne"))
	names.add_child(UITheme.label(sub, 15, Color("5fd068") if online else Color("c9b79a"), 3))

	var w := int(d.get("wins", 0))
	var l := int(d.get("losses", 0))
	var aw := int(d.get("ai_wins", 0))
	var al := int(d.get("ai_losses", 0))
	var st: Dictionary = d.get("stats", {})
	var txt := Loc.t("En ligne : [b]%d[/b] V / [b]%d[/b] D (%s)  ·  contre l'IA : [b]%d[/b] V / [b]%d[/b] D (%s)  ·  égalités : %d\n") % [
		w, l, _pct(w, w + l), aw, al, _pct(aw, aw + al), int(d.get("draws", 0))]
	txt += Loc.t("Parties : [b]%d[/b]  ·  série en cours : [b]%d[/b]  ·  meilleure série : [b]%d[/b]\n") % [
		int(d.get("games", 0)), int(d.get("streak", 0)), int(d.get("best_streak", 0))]
	txt += Loc.t("Serviteurs joués : %d  ·  sorts : %d  ·  enchantements : %d  ·  enchantements détruits : %d  ·  dégâts au héros adverse : %d") % [
		int(st.get("minions_played", 0)), int(st.get("spells_played", 0)), int(st.get("enchants_played", 0)),
		int(st.get("enchants_destroyed", 0)), int(st.get("hero_damage", 0))]
	var fav: Array[String] = []
	for f in d.get("favorites", []):
		var c := CardDB.get_card(str(f.card))
		if not c.is_empty():
			fav.append("%s (%d)" % [c.name, int(f.plays)])
	if not fav.is_empty():
		txt += Loc.t("\nCartes favorites : [color=#f2c14e]") + ", ".join(fav) + "[/color]"
	_info.text = txt

	for c in _actions.get_children():
		c.queue_free()
	if not _is_me(_name):
		if bool(d.get("friend", false)):
			var write := _small_btn(Loc.t("Écrire"))
			write.pressed.connect(func():
				queue_free()
				Lobby.open_messages(_name))
			_actions.add_child(write)
		else:
			var add := _small_btn(Loc.t("Ajouter en ami"))
			add.pressed.connect(func():
				Lobby.add_friend(_name)
				add.disabled = true)
			_actions.add_child(add)


func _pct(a: int, n: int) -> String:
	return "%.0f %%" % (100.0 * a / n) if n > 0 else "—"


func _small_btn(text: String) -> Button:
	var b := UITheme.button(text, 180)
	b.custom_minimum_size.y = 34
	b.add_theme_font_size_override("font_size", 15)
	return b


func _on_history(player_name: String, total: int, rows: Array) -> void:
	if _name != "" and player_name != _name:
		return
	for c in _list.get_children():
		c.queue_free()
	_status.text = (Loc.t("%d parties au total%s. « Revoir » rejoue la partie à l'identique (parties jouées depuis la version 1.6).") if total > 1
		else Loc.t("%d partie au total%s. « Revoir » rejoue la partie à l'identique (parties jouées depuis la version 1.6).")) % [
		total, Loc.t(" (200 plus récentes)") if total > rows.size() else ""]
	var tz: int = Time.get_time_zone_from_system().get("bias", 0) * 60
	for r in rows:
		var row := HBoxContainer.new()
		var d := Time.get_datetime_dict_from_unix_time(int(r.ts) + tz)
		var result: String = r.result
		var res_col: Color = {"win": UITheme.GREEN, "loss": UITheme.RED}.get(result, UITheme.LIGHT_TEXT)
		var dur := int(r.duration)
		var values := [
			"%02d/%02d/%d %02d:%02d" % [d.day, d.month, d.year, d.hour, d.minute],
			Loc.t("En ligne") if r.mode == "pvp" else Loc.t("vs IA"),
			str(r.opponent),
			Loc.t({"win": "Victoire", "loss": "Défaite", "draw": "Égalité"}.get(result, "?")) + Loc.t(REASONS.get(r.reason, "")),
			str(int(r.turns)),
			(Loc.t("%d min %02d s") % [floori(dur / 60.0), dur % 60]) if dur > 0 else "—",
		]
		for i in values.size():
			var l := UITheme.label(values[i], 15, res_col if i == 3 else UITheme.LIGHT_TEXT, 3)
			l.custom_minimum_size.x = HIST_COLS[i][1]
			l.clip_text = true
			l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(l)
		if bool(r.get("replay", false)):
			var b := UITheme.button(Loc.t("Revoir"), 100)
			b.custom_minimum_size.y = 30
			b.add_theme_font_size_override("font_size", 14)
			var mid := int(r.id)
			b.pressed.connect(func():
				b.disabled = true
				b.text = "..."
				Lobby.request_replay(mid))
			row.add_child(b)
		_list.add_child(row)
	if rows.is_empty():
		_list.add_child(UITheme.label(Loc.t("Aucune partie enregistrée pour le moment."), 15, Color("c9b79a")))
