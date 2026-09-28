class_name WelcomePanel
extends Control
## Accueil des nouveaux joueurs (premier lancement, pas encore de pseudo) : présentation du jeu en
## 3 diapositives, puis choix du pseudo et de l'avatar (réservés sur le serveur).
## « Passer » ferme l'accueil à tout moment ; il ne revient pas (Settings.welcome_done).

const SLIDES := [
	{"title": "Bienvenue dans Arcanes & Lames",
	 "text": "Un duel de cartes au cœur du Royaume : réduisez les points de vie du héros adverse de [b]25[/b] à [b]0[/b] avec vos serviteurs, vos sorts et vos enchantements.",
	 "image": "castle"},
	{"title": "Un tour de jeu",
	 "text": "À chaque tour, gardez [b]1 carte parmi 3[/b] et gagnez [b]1 énergie[/b] de plus (jusqu'à 10). Glissez vos cartes sur le plateau pour les jouer, puis attaquez avec vos serviteurs.",
	 "image": "cards"},
	{"title": "Jouez et progressez",
	 "text": "Affrontez l'IA, de l'Apprenti au Challenger puis le mode Inferno, ou défiez d'autres joueurs en ligne. Montez au classement et débloquez titres, avatars, dos de cartes et plateaux.",
	 "image": "arena"},
]

var _page := 0
var _body: Control
var _dots: HBoxContainer
var _prev: Button
var _next: Button
var _name_edit: LineEdit
var _status: Label
var _avatar := 1
var _avatar_buttons: Array[Button] = []
var _waiting_name := ""


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("modal")   # Échap la ferme (voir PauseMenu), comme « Passer »
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 580)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	var top := HBoxContainer.new()
	vb.add_child(top)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var skip := UITheme.button(Loc.t("Passer"), 130)
	skip.custom_minimum_size.y = 34
	skip.tooltip_text = Loc.t("Fermer l'accueil : vous pourrez choisir votre pseudo plus tard dans Paramètres > Profil.")
	skip.pressed.connect(queue_free)
	top.add_child(skip)

	_body = Control.new()
	_body.custom_minimum_size = Vector2(880, 440)
	vb.add_child(_body)

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 16)
	vb.add_child(nav)
	_prev = UITheme.button(Loc.t("Précédent"), 180)
	_prev.pressed.connect(func(): _show(_page - 1))
	nav.add_child(_prev)
	var mid := CenterContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(mid)
	_dots = HBoxContainer.new()
	_dots.add_theme_constant_override("separation", 10)
	mid.add_child(_dots)
	_next = UITheme.button(Loc.t("Suivant"), 180)
	_next.pressed.connect(func(): _show(_page + 1))
	nav.add_child(_next)

	_avatar = Settings.avatar if Settings.avatar in CardDB.BASE_AVATARS else 1
	tree_exiting.connect(func():
		Settings.welcome_done = true
		Settings.save_settings())


func _ready() -> void:
	Lobby.profile_changed.connect(_on_profile)
	Lobby.server_error.connect(_on_server_error)
	_show(0)


## Pages 0 à 2 : présentation ; page 3 : pseudo et avatar.
func _show(page: int) -> void:
	_page = clampi(page, 0, SLIDES.size())
	for c in _body.get_children():
		c.queue_free()
	for c in _dots.get_children():
		c.queue_free()
	for i in SLIDES.size() + 1:
		var d := Panel.new()
		d.custom_minimum_size = Vector2(14, 14)
		d.add_theme_stylebox_override("panel", UITheme.flat_style(UITheme.GOLD if i == _page else Color(0.3, 0.25, 0.2), Color(0, 0, 0, 0), 0, 7))
		_dots.add_child(d)
	_prev.visible = _page > 0
	_next.visible = _page < SLIDES.size()
	if _page < SLIDES.size():
		_build_slide(SLIDES[_page])
	else:
		_build_register()


func _build_slide(s: Dictionary) -> void:
	var title := UITheme.title_label(Loc.t(s.title), 38)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(880, 52)
	_body.add_child(title)
	var art := _slide_art(str(s.image))
	art.position = Vector2(440 - art.size.x / 2, 64)
	_body.add_child(art)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.position = Vector2(60, 330)
	text.size = Vector2(760, 110)
	text.add_theme_font_size_override("normal_font_size", 19)
	text.add_theme_font_size_override("bold_font_size", 19)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.text = Loc.t(s.text)
	_body.add_child(text)


## Illustration d'une diapositive (250 px de haut au plus).
func _slide_art(kind: String) -> Control:
	if kind == "cards":
		# Pioche au choix : trois cartes côte à côte, celle du milieu mise en avant.
		var row := Control.new()
		row.size = Vector2(520, 250)
		var ids := ["boule_feu", "chevalier", "golem"]
		for i in 3:
			var cv := CardView.new().setup(ids[i])
			cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cv.pivot_offset = Vector2.ZERO
			var k := 1.1 if i == 1 else 0.95
			cv.scale = Vector2.ONE * k
			cv.position = Vector2(i * 180 + (0 if i == 1 else 8), 0 if i == 1 else 16)
			if i != 1:
				cv.modulate = Color(0.7, 0.7, 0.75)
			row.add_child(cv)
		return row
	if kind == "arena":
		# Progression : avatars avec des contours de plus en plus prestigieux (IA battues, champion).
		var badges := Control.new()
		badges.size = Vector2(560, 250)
		var looks := [[3, "ia_chevalier"], [15, "champion"], [7, "ia_challenger"]]
		for i in 3:
			var big := i == 1
			var side := 170 if big else 130
			var b := AvatarBadge.new().setup(int(looks[i][0]), str(looks[i][1]), side)
			b.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.position = Vector2([20, 195, 410][i], 30 if big else 60)
			badges.add_child(b)
		return badges
	var tex := TextureRect.new()
	tex.texture = CardDB.texture("res://assets/bg/menu.png")
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex.size = Vector2(437, 250)
	return tex


func _build_register() -> void:
	var title := UITheme.title_label(Loc.t("Choisissez votre pseudo"), 38)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(880, 52)
	_body.add_child(title)
	var intro := UITheme.label(Loc.t("Il vous identifie en ligne : classement, parties contre d'autres joueurs, amis. Il est réservé sur le serveur, sans mot de passe ni adresse e-mail."), 17, Color("e8d6b0"), 3)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.position = Vector2(60, 60)
	intro.size = Vector2(760, 60)
	_body.add_child(intro)

	_name_edit = LineEdit.new()
	_name_edit.max_length = 16
	_name_edit.placeholder_text = Loc.t("3 à 16 caractères")
	_name_edit.text = Settings.player_name
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.add_theme_font_size_override("font_size", 22)
	_name_edit.position = Vector2(240, 130)
	_name_edit.size = Vector2(400, 46)
	_name_edit.text_submitted.connect(func(_t): _register())
	_body.add_child(_name_edit)
	_name_edit.call_deferred("grab_focus")

	var al := UITheme.label(Loc.t("Avatar"), 17, UITheme.GOLD, 3)
	al.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	al.position = Vector2(0, 196)
	al.size = Vector2(880, 24)
	_body.add_child(al)
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 8)
	_avatar_buttons.clear()
	for i in CardDB.BASE_AVATARS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(70, 70)
		b.icon = CardDB.avatar(i)
		b.expand_icon = true
		b.tooltip_text = Loc.t(CardDB.AVATAR_NAMES[i])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.set_meta("avatar", i)
		var off := UITheme.flat_style(Color("1a1220"), Color("6b5a3c"), 2, 4)
		var on := UITheme.flat_style(Color("3a2a10"), UITheme.GOLD, 4, 4)
		for sb in [off, on]:
			sb.set_content_margin_all(3)
		b.add_theme_stylebox_override("normal", off)
		b.add_theme_stylebox_override("hover", on)
		b.add_theme_stylebox_override("pressed", on)
		b.add_theme_stylebox_override("hover_pressed", on)
		b.pressed.connect(_select_avatar.bind(i))
		grid.add_child(b)
		_avatar_buttons.append(b)
	var gc := CenterContainer.new()
	gc.position = Vector2(0, 226)
	gc.size = Vector2(880, 80)
	gc.add_child(grid)
	_body.add_child(gc)
	_select_avatar(_avatar)

	var go := UITheme.button(Loc.t("Commencer l'aventure"), 300)
	go.custom_minimum_size.y = 48
	go.add_theme_color_override("font_color", UITheme.GOLD)
	go.position = Vector2(290, 320)
	go.pressed.connect(_register)
	_body.add_child(go)
	_status = UITheme.label("", 16, Color("c9b79a"), 3)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.position = Vector2(60, 380)
	_status.size = Vector2(760, 50)
	_body.add_child(_status)


func _select_avatar(i: int) -> void:
	_avatar = i
	for b in _avatar_buttons:
		var sel: bool = b.get_meta("avatar") == i
		b.set_pressed_no_signal(sel)
		b.modulate = Color.WHITE if sel else Color(0.6, 0.6, 0.6)


## Enregistre le pseudo et l'avatar, puis attend la réponse du serveur (pseudo libre ou déjà pris).
func _register() -> void:
	var n := _name_edit.text.strip_edges()
	if n.length() < 3:
		_status.text = Loc.t("Le pseudo doit contenir au moins 3 caractères.")
		_status.add_theme_color_override("font_color", UITheme.RED)
		return
	_status.remove_theme_color_override("font_color")
	_status.text = Loc.t("Vérification du pseudo auprès du serveur...")
	_waiting_name = n
	Settings.set_profile(n, _avatar)
	Lobby.update_profile()
	# Serveur injoignable : le profil est gardé sur ce PC et sera réservé à la prochaine connexion.
	get_tree().create_timer(8.0).timeout.connect(func():
		if is_instance_valid(self) and _waiting_name == n and not Lobby.online:
			Lobby.toast(Loc.t("Serveur injoignable : votre pseudo sera réservé à la prochaine connexion."), UITheme.GOLD, 6.0)
			queue_free())


func _on_profile() -> void:
	if _waiting_name != "" and Lobby.online and str(Lobby.profile.get("name", "")) == _waiting_name:
		Lobby.toast(Loc.t("Bienvenue, %s ! Bonne partie.") % _waiting_name, UITheme.GOLD, 5.0)
		_waiting_name = ""
		queue_free()


func _on_server_error(code: String, msg: String) -> void:
	if _waiting_name == "" or not is_instance_valid(_status):
		return
	if code in ["name_taken", "name_invalid"]:
		_waiting_name = ""
		_status.text = msg
		_status.add_theme_color_override("font_color", UITheme.RED)
