class_name MinionView
extends Control
## Serviteur posé sur le plateau (100x124).

signal hovered(view: MinionView, on: bool)
signal pressed(view: MinionView)

const SIZE := Vector2(100, 124)
const SHIELD_PAD := Vector2(20, 20)
const SHIELD_SHADER := preload("res://assets/shaders/divine_shield.gdshader")

var uid := -1
var card_id := ""

var _bg: Panel
var _bg_style: StyleBoxFlat
var _art: TextureRect
var _atk: Label
var _hp: Label
var _shield: ColorRect
var _shield_mat: ShaderMaterial
var _shield_sparks: CPUParticles2D
var _taunt_icon: TextureRect
var _zzz: SleepIcon
var _target_mark: Panel
var _shield_tween: Tween


func _init() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	pivot_offset = SIZE / 2
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build() -> void:
	_bg = Panel.new()
	_bg.size = SIZE
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_style = UITheme.flat_style(Color("2a1a12"), UITheme.GOLD, 3, 6)
	_bg_style.shadow_color = Color(0, 0, 0, 0.5)
	_bg_style.shadow_size = 6
	_bg_style.shadow_offset = Vector2(0, 4)
	_bg.add_theme_stylebox_override("panel", _bg_style)
	add_child(_bg)

	_art = TextureRect.new()
	_art.position = Vector2(5, 5)
	_art.size = Vector2(90, 102)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.clip_contents = true
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)

	# Bouclier divin : bulle dorée animée (shader) + étincelles qui montent le long du bord.
	_shield = ColorRect.new()
	_shield.position = -SHIELD_PAD
	_shield.size = SIZE + SHIELD_PAD * 2
	_shield.pivot_offset = _shield.size / 2
	_shield_mat = ShaderMaterial.new()
	_shield_mat.shader = SHIELD_SHADER
	_shield_mat.set_shader_parameter("rect_size", _shield.size)
	_shield_mat.set_shader_parameter("margin", SHIELD_PAD.x - 7)
	_shield.material = _shield_mat
	_shield.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shield.visible = false
	add_child(_shield)
	_shield_sparks = CPUParticles2D.new()
	_shield_sparks.amount = 14
	_shield_sparks.lifetime = 1.3
	_shield_sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	var pts := PackedVector2Array()
	for i in 40:
		var t := i / 40.0 * 2.0
		# Points répartis sur le contour de la bulle.
		var w := SIZE.x + 10
		var h := SIZE.y + 10
		var perim_pos := t * (w + h)
		var pt := Vector2.ZERO
		if perim_pos < w:
			pt = Vector2(perim_pos, 0)
		elif perim_pos < w + h:
			pt = Vector2(w, perim_pos - w)
		elif perim_pos < 2 * w + h:
			pt = Vector2(2 * w + h - perim_pos, h)
		else:
			pt = Vector2(0, 2 * (w + h) - perim_pos)
		pts.append(pt - Vector2(5, 5))
	_shield_sparks.emission_points = pts
	_shield_sparks.direction = Vector2.UP
	_shield_sparks.spread = 25.0
	_shield_sparks.gravity = Vector2(0, -18)
	_shield_sparks.initial_velocity_min = 6.0
	_shield_sparks.initial_velocity_max = 18.0
	_shield_sparks.scale_amount_min = 2.0
	_shield_sparks.scale_amount_max = 3.0
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 0.97, 0.8, 1))
	grad.set_color(1, Color(1, 0.75, 0.2, 0))
	_shield_sparks.color_ramp = grad
	_shield_sparks.emitting = false
	_shield_sparks.visible = false
	add_child(_shield_sparks)

	_taunt_icon = TextureRect.new()
	_taunt_icon.texture = CardDB.texture("res://assets/ui/icon_shield.png")
	_taunt_icon.position = Vector2(32, -20)
	_taunt_icon.size = Vector2(36, 36)
	_taunt_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_taunt_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_taunt_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_taunt_icon.visible = false
	add_child(_taunt_icon)

	var atk_icon := _icon("res://assets/ui/icon_attack.png", Vector2(-12, 88))
	_atk = _num(atk_icon.position)
	var hp_icon := _icon("res://assets/ui/icon_health.png", Vector2(72, 88))
	_hp = _num(hp_icon.position)

	_zzz = SleepIcon.new()
	_zzz.position = Vector2(58, 2)
	add_child(_zzz)

	_target_mark = Panel.new()
	_target_mark.position = Vector2(-4, -4)
	_target_mark.size = SIZE + Vector2(8, 8)
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color(1, 0.2, 0.2, 0.12)
	ts.border_color = UITheme.RED
	ts.set_border_width_all(3)
	ts.set_corner_radius_all(8)
	_target_mark.add_theme_stylebox_override("panel", ts)
	_target_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_target_mark.visible = false
	add_child(_target_mark)


func _icon(path: String, pos: Vector2) -> TextureRect:
	var t := TextureRect.new()
	t.texture = CardDB.texture(path)
	t.position = pos
	t.size = Vector2(40, 40)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(t)
	return t


func _num(pos: Vector2) -> Label:
	var l := UITheme.num_label("0", 16, Color.WHITE, 7)
	l.position = pos + Vector2(0, 3)
	l.size = Vector2(40, 40)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func setup(e: GameState.Entity) -> MinionView:
	uid = e.uid
	card_id = e.card_id
	_art.texture = CardDB.card_art(card_id)
	sync(e, false)
	return self


## Met à jour l'affichage d'après l'état. `ready_glow` : bordure verte si le serviteur peut attaquer.
func sync(e: GameState.Entity, ready_glow: bool) -> void:
	var base := CardDB.get_card(card_id)
	_atk.text = str(e.attack)
	_hp.text = str(e.health)
	_atk.add_theme_color_override("font_color", Color("7dff8a") if e.attack > base.attack else Color.WHITE)
	var hp_col := Color.WHITE
	if e.health < e.max_health:
		hp_col = Color("ff6b6b")
	elif e.max_health > base.health or e.health > e.max_health:
		hp_col = Color("7dff8a")   # au-dessus des PV de départ (pas de maximum)
	_hp.add_theme_color_override("font_color", hp_col)
	_taunt_icon.visible = e.taunt
	_zzz.visible = e.sleeping and not e.charge
	if e.shield and not _shield.visible:
		_show_shield()
	elif not e.shield and _shield.visible:
		hide_shield()
	if ready_glow:
		_bg_style.border_color = UITheme.GREEN
		_bg_style.set_border_width_all(4)
	elif e.taunt:
		_bg_style.border_color = Color("9aa3ad")
		_bg_style.set_border_width_all(6)
	else:
		_bg_style.border_color = UITheme.GOLD
		_bg_style.set_border_width_all(3)


## Effet « tant qu'il est en jeu » déclenché : le serviteur pulse.
func pulse() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE * 1.12, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "modulate", Color(1.4, 1.3, 1.1), 0.12)
	tw.tween_property(self, "scale", Vector2.ONE, 0.2)
	tw.parallel().tween_property(self, "modulate", Color.WHITE, 0.2)


## Ajuste les PV affichés pendant une animation (avant la resynchronisation finale).
func add_hp(delta: int) -> void:
	_hp.text = str(int(_hp.text) + delta)
	if delta < 0:
		_hp.add_theme_color_override("font_color", Color("ff6b6b"))


## Apparition : la bulle se referme sur le serviteur.
func _show_shield() -> void:
	if _shield_tween:
		_shield_tween.kill()
	_shield.visible = true
	_shield.scale = Vector2.ONE * 1.35
	_shield.modulate.a = 0.0
	_shield_mat.set_shader_parameter("intensity", 2.2)
	_shield_sparks.visible = true
	_shield_sparks.emitting = true
	_shield_tween = create_tween().set_parallel(true)
	_shield_tween.tween_property(_shield, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_shield_tween.tween_property(_shield, "modulate:a", 1.0, 0.2)
	_shield_tween.tween_method(func(v: float): _shield_mat.set_shader_parameter("intensity", v), 2.2, 1.0, 0.5)


func hide_shield() -> void:
	if _shield_tween:
		_shield_tween.kill()
	_shield.visible = false
	_shield_sparks.emitting = false
	_shield_sparks.visible = false


## Bris du bouclier : flash, la bulle éclate vers l'extérieur et le serviteur tremble.
func pop_shield() -> void:
	if not _shield.visible:
		return
	if _shield_tween:
		_shield_tween.kill()
	_shield_sparks.emitting = false
	_shield_tween = create_tween().set_parallel(true)
	_shield_tween.tween_method(func(v: float): _shield_mat.set_shader_parameter("intensity", v), 3.0, 0.0, 0.3)
	_shield_tween.tween_property(_shield, "scale", Vector2.ONE * 1.3, 0.3).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_shield_tween.chain().tween_callback(hide_shield)
	var base := position
	var shake := create_tween()
	for i in 4:
		shake.tween_property(self, "position", base + Vector2(randf_range(-4, 4), randf_range(-3, 3)), 0.035)
	shake.tween_property(self, "position", base, 0.04)


func set_targetable(on: bool) -> void:
	_target_mark.visible = on


func center() -> Vector2:
	return global_position + SIZE / 2 * scale


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pressed.emit(self)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		hovered.emit(self, true)
	elif what == NOTIFICATION_MOUSE_EXIT:
		hovered.emit(self, false)
