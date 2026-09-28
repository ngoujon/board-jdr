class_name RewardFx
extends CanvasLayer
## Animations de récompense, au-dessus de tout le jeu :
## - pluie de pièces d'or qui jaillissent puis filent vers le compteur de PO (+N PO) ;
## - révélation « épique » d'une personnalisation débloquée : rayons de lumière, éclair, gerbe d'étincelles,
##   objet qui surgit et flotte, fanfare. Plusieurs objets s'enchaînent ; pendant une partie, la révélation
##   attend la fin de la partie pour ne pas gêner le joueur.

const KIND_COLORS := {"title": Color("c58bff"), "avatar": Color("7ac8ff"), "border": Color("7dfff0"),
	"card_back": Color("ffd24a"), "board": Color("8aff9a")}

var _queue: Array = []        # objets à révéler : {kind, id}
var _showing := false


func _init() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	if not _showing and not _queue.is_empty() and not _game_running():
		_reveal_next()


func _game_running() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.has_method("is_game_running") and scene.is_game_running()


# ------------------------------------------------------------------ pièces d'or

## Pluie de pièces : elles jaillissent de `from`, puis filent vers `to` (le compteur de PO).
func coins(amount: int, from: Vector2, to: Vector2) -> void:
	if amount <= 0:
		return
	Audio.play_sfx("coins", 0.05, -2.0)
	var n := clampi(amount / 4, 8, 28)
	for i in n:
		var c := GoldCoin.new(randf_range(9.0, 14.0))
		c.pivot_offset = c.custom_minimum_size / 2
		c.position = from - c.custom_minimum_size / 2
		c.scale = Vector2.ONE * 0.2
		add_child(c)
		var burst := from + Vector2.from_angle(randf() * TAU) * randf_range(50, 140) - c.custom_minimum_size / 2
		var tw := c.create_tween()
		tw.set_parallel(true)
		tw.tween_property(c, "position", burst, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "scale", Vector2.ONE * randf_range(0.9, 1.3), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "rotation", randf_range(-1.5, 1.5), 0.35)
		tw.chain().tween_interval(0.08 + i * 0.025)
		tw.chain().set_parallel(true)
		tw.tween_property(c, "position", to - c.custom_minimum_size / 2, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(c, "scale", Vector2.ONE * 0.5, 0.45)
		tw.chain().tween_callback(c.queue_free)
	# « +N PO » qui grossit puis s'envole
	var l := UITheme.label(Loc.t("+%d PO") % amount, 40, UITheme.GOLD, 8)
	l.add_theme_font_override("font", UITheme.font_bold)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(300, 56)
	l.pivot_offset = l.size / 2
	l.position = from - l.size / 2 + Vector2(0, -30)
	l.scale = Vector2.ONE * 0.3
	add_child(l)
	var lt := l.create_tween()
	lt.tween_property(l, "scale", Vector2.ONE * 1.15, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	lt.tween_property(l, "scale", Vector2.ONE, 0.12)
	lt.tween_interval(0.6)
	lt.set_parallel(true)
	lt.tween_property(l, "position:y", l.position.y - 70, 0.6)
	lt.tween_property(l, "modulate:a", 0.0, 0.6)
	lt.chain().tween_callback(l.queue_free)


# ------------------------------------------------------------------ révélation des personnalisations

func reveal(items: Array) -> void:
	for it in items:
		_queue.append(it)


func _reveal_next() -> void:
	var it: Dictionary = _queue.pop_front()
	_showing = true
	var kind := str(it.get("kind", ""))
	var col: Color = KIND_COLORS.get(kind, UITheme.GOLD)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var center := Vector2(640, 330)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.01, 0.04, 0.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	create_tween().tween_property(bg, "color:a", 0.88, 0.35)

	var rays := _Rays.new(col)
	rays.position = center
	rays.scale = Vector2.ZERO
	root.add_child(rays)
	var rt := rays.create_tween()
	rt.tween_property(rays, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Objet débloqué, en grand
	var pv := ShopPanel.preview(kind, it.get("id"), true)
	pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sz := pv.custom_minimum_size
	var k := minf(3.2, minf(230.0 / maxf(1.0, sz.y), 460.0 / maxf(1.0, sz.x)))
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.position = center
	holder.scale = Vector2.ZERO
	root.add_child(holder)
	pv.position = -sz / 2
	holder.add_child(pv)

	var head := UITheme.title_label(Loc.t("NOUVELLE PERSONNALISATION !"), 46)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.size = Vector2(1280, 64)
	head.position = Vector2(0, 40)
	head.pivot_offset = Vector2(640, 32)
	head.scale = Vector2.ONE * 0.2
	head.modulate.a = 0.0
	root.add_child(head)
	var kind_l := UITheme.label(Loc.t(Lobby.KIND_SINGULAR.get(kind, kind)).to_upper(), 22, col, 6)
	kind_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kind_l.size = Vector2(1280, 30)
	kind_l.position = Vector2(0, 520)
	kind_l.modulate.a = 0.0
	root.add_child(kind_l)
	var name_l := UITheme.title_label(Cosmetics.item_name(kind, it.get("id")), 38)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.size = Vector2(1280, 56)
	name_l.position = Vector2(0, 552)
	name_l.modulate.a = 0.0
	root.add_child(name_l)
	# Pourquoi cet objet est obtenu : sa condition de déblocage (ex. « Battre l'IA Challenger. »).
	var why := UITheme.label(Loc.t("Obtenu : %s") % Cosmetics.rule_text(Cosmetics.item(kind, it.get("id")).get("rule")), 19, Color("e8d6b0"), 4)
	why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	why.size = Vector2(1080, 50)
	why.position = Vector2(100, 610)
	why.modulate.a = 0.0
	root.add_child(why)
	var hint := UITheme.label(Loc.t("Cliquez pour continuer") + (Loc.t("  (%d de plus)") % _queue.size() if not _queue.is_empty() else ""), 16, Color("e8d6b0"), 3)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.size = Vector2(1280, 24)
	hint.position = Vector2(0, 660)
	hint.modulate.a = 0.0
	root.add_child(hint)

	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0.0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash)

	Audio.play_sfx("fanfare", 0.0, -1.0)
	var tw := root.create_tween()
	tw.tween_interval(0.45)
	tw.tween_callback(func():
		flash.color.a = 0.85
		root.create_tween().tween_property(flash, "color:a", 0.0, 0.5)
		_burst(root, center, col)
		Audio.play_sfx("shield", 0.0, -4.0))
	tw.tween_property(holder, "scale", Vector2.ONE * k * 1.25, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(holder, "scale", Vector2.ONE * k, 0.18)
	tw.set_parallel(true)
	tw.tween_property(head, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(head, "modulate:a", 1.0, 0.2)
	tw.tween_property(kind_l, "modulate:a", 1.0, 0.3)
	tw.tween_property(name_l, "modulate:a", 1.0, 0.4)
	tw.tween_property(why, "modulate:a", 1.0, 0.5)
	tw.chain().tween_property(hint, "modulate:a", 1.0, 0.3)
	# L'objet flotte doucement, les étincelles continuent.
	var bob := holder.create_tween().set_loops()
	bob.tween_property(holder, "position:y", center.y - 8, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(holder, "position:y", center.y + 8, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var sparkles := _sparkles(col)
	sparkles.position = center
	root.add_child(sparkles)
	root.move_child(sparkles, 2)

	var ready_at := Time.get_ticks_msec() + 900
	root.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and Time.get_ticks_msec() >= ready_at:
			_close(root))


func _close(root: Control) -> void:
	if root.has_meta("closing"):
		return
	root.set_meta("closing", true)
	var tw := root.create_tween()
	tw.tween_property(root, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func():
		root.queue_free()
		_showing = false)


func _burst(root: Control, at: Vector2, col: Color) -> void:
	var p := CPUParticles2D.new()
	p.position = at
	p.amount = 90
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 1.4
	p.spread = 180.0
	p.initial_velocity_min = 220.0
	p.initial_velocity_max = 520.0
	p.gravity = Vector2(0, 260)
	p.damping_min = 40.0
	p.damping_max = 90.0
	p.scale_amount_min = 3.0
	p.scale_amount_max = 7.0
	p.color_ramp = _ramp(col)
	root.add_child(p)
	p.emitting = true


func _sparkles(col: Color) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = 40
	p.lifetime = 2.2
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 170.0
	p.direction = Vector2(0, -1)
	p.spread = 30.0
	p.gravity = Vector2(0, -30)
	p.initial_velocity_min = 10.0
	p.initial_velocity_max = 40.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	p.color_ramp = _ramp(col)
	return p


static func _ramp(col: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 0.9, 1))
	g.set_color(1, Color(col.r, col.g, col.b, 0))
	g.add_point(0.35, col)
	return g


## Rayons de lumière qui tournent derrière l'objet.
class _Rays extends Control:
	var col: Color

	func _init(c: Color) -> void:
		col = c
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		rotation += delta * 0.35
		queue_redraw()

	func _draw() -> void:
		var n := 18
		for i in n:
			var a := TAU * i / n
			var w := 0.09
			var r := 760.0
			var pts := PackedVector2Array([Vector2.ZERO, Vector2.from_angle(a - w) * r, Vector2.from_angle(a + w) * r])
			draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.16 if i % 2 == 0 else 0.08))
		for i in 6:
			draw_circle(Vector2.ZERO, 200.0 - i * 30.0, Color(col.r, col.g, col.b, 0.05 + i * 0.03))
		draw_circle(Vector2.ZERO, 40.0, Color(1, 1, 0.95, 0.25))
