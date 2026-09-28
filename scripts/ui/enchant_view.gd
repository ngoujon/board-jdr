class_name EnchantView
extends Control
## Enchantement en jeu (petite plaque violette à côté du héros) : illustration (pas de PV).

signal hovered(view: EnchantView, on: bool)
signal pressed(view: EnchantView)

const SIZE := Vector2(70, 88)
const PURPLE := Color("b27cff")

var uid := -1
var card_id := ""

var _art: TextureRect
var _target_mark: Panel
var _glow: Panel


func _init() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	pivot_offset = SIZE / 2
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build() -> void:
	_glow = Panel.new()
	_glow.position = Vector2(-5, -5)
	_glow.size = SIZE + Vector2(10, 10)
	var gs := StyleBoxFlat.new()
	gs.bg_color = Color(0.7, 0.45, 1.0, 0.0)
	gs.shadow_color = Color(0.7, 0.45, 1.0, 0.55)
	gs.shadow_size = 10
	gs.set_corner_radius_all(10)
	_glow.add_theme_stylebox_override("panel", gs)
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_glow)

	var bg := Panel.new()
	bg.size = SIZE
	var st := UITheme.flat_style(Color("1e1030"), PURPLE, 3, 8)
	st.shadow_color = Color(0, 0, 0, 0.5)
	st.shadow_size = 5
	st.shadow_offset = Vector2(0, 3)
	bg.add_theme_stylebox_override("panel", st)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_art = TextureRect.new()
	_art.position = Vector2(5, 5)
	_art.size = Vector2(60, 78)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.clip_contents = true
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)

	# Petite gemme violette : repère visuel « enchantement ».
	var gem := Panel.new()
	gem.position = Vector2(SIZE.x / 2 - 7, -7)
	gem.size = Vector2(14, 14)
	gem.rotation_degrees = 45
	gem.pivot_offset = Vector2(7, 7)
	gem.add_theme_stylebox_override("panel", UITheme.flat_style(PURPLE, Color("f0e0ff"), 2, 2))
	gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(gem)

	_target_mark = Panel.new()
	_target_mark.position = Vector2(-4, -4)
	_target_mark.size = SIZE + Vector2(8, 8)
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color(1, 0.2, 0.2, 0.15)
	ts.border_color = UITheme.RED
	ts.set_border_width_all(3)
	ts.set_corner_radius_all(10)
	_target_mark.add_theme_stylebox_override("panel", ts)
	_target_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_target_mark.visible = false
	add_child(_target_mark)

	var tw := _glow.create_tween().set_loops()
	tw.tween_property(_glow, "modulate:a", 0.35, 1.1).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_glow, "modulate:a", 1.0, 1.1).set_trans(Tween.TRANS_SINE)


func setup(e: GameState.Entity) -> EnchantView:
	uid = e.uid
	card_id = e.card_id
	_art.texture = CardDB.card_art(card_id)
	return self


func sync(_e: GameState.Entity) -> void:
	pass


## Effet déclenché (début / fin de tour) : l'enchantement pulse.
func pulse() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE * 1.18, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "modulate", Color(1.5, 1.3, 1.8), 0.12)
	tw.tween_property(self, "scale", Vector2.ONE, 0.2)
	tw.parallel().tween_property(self, "modulate", Color.WHITE, 0.2)


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
