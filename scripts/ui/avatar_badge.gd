class_name AvatarBadge
extends Control
## Avatar d'un joueur avec son contour (bronze, or, arcane... ou Champion pour le n°1 du classement).

const BORDER_SHADER := preload("res://assets/shaders/avatar_border.gdshader")

var _avatar: TextureRect
var _ring: ColorRect
var _mat: ShaderMaterial
var _crown: Control
var _border := ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_avatar = TextureRect.new()
	_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_avatar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_avatar)
	_ring = ColorRect.new()
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = BORDER_SHADER
	_ring.material = _mat
	add_child(_ring)


## `avatar_id` <= 0 : pas d'image (seulement le contour). `texture` remplace l'avatar si fourni.
func setup(avatar_id: int, border_id: String, side: float, texture: Texture2D = null) -> AvatarBadge:
	custom_minimum_size = Vector2(side, side)
	size = custom_minimum_size
	var thick := clampf(side * 0.09, 3.0, 10.0)
	_avatar.position = Vector2.ONE * thick * 0.6
	_avatar.size = Vector2.ONE * (side - thick * 1.2)
	_avatar.texture = texture if texture else (CardDB.avatar(avatar_id) if avatar_id > 0 else null)
	_ring.position = Vector2.ZERO
	_ring.size = Vector2(side, side)
	_mat.set_shader_parameter("rect_size", _ring.size)
	_mat.set_shader_parameter("thickness", thick)
	_mat.set_shader_parameter("corner", side * 0.12)
	_mat.set_shader_parameter("pixel", 2.0 if side >= 60 else 1.0)
	set_border(border_id)
	return self


func set_border(border_id: String) -> void:
	_border = border_id if border_id != "" else "none"
	var st := Cosmetics.border_style(_border)
	_mat.set_shader_parameter("color_a", st[0])
	_mat.set_shader_parameter("color_b", st[1])
	_mat.set_shader_parameter("speed", st[2])
	_mat.set_shader_parameter("sparkle", st[3])
	_mat.set_shader_parameter("rainbow", 1.0 if _border == "champion" else 0.0)
	if _crown:
		_crown.queue_free()
		_crown = null
	if _border == "champion":
		_crown = _make_crown(size.x)
		add_child(_crown)


func set_texture(tex: Texture2D) -> void:
	_avatar.texture = tex


## Petite couronne dorée posée sur le contour (réservée au n°1 du classement).
func _make_crown(side: float) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var w := clampf(side * 0.42, 14.0, 44.0)
	var h := w * 0.62
	holder.position = Vector2(side / 2 - w / 2, -h * 0.72)
	var outline := Polygon2D.new()
	var pts := PackedVector2Array([
		Vector2(0, h), Vector2(0, h * 0.25), Vector2(w * 0.25, h * 0.6), Vector2(w * 0.5, 0),
		Vector2(w * 0.75, h * 0.6), Vector2(w, h * 0.25), Vector2(w, h)])
	var big := PackedVector2Array()
	for pt in pts:
		big.append((pt - Vector2(w / 2, h / 2)) * 1.18 + Vector2(w / 2, h / 2))
	outline.polygon = big
	outline.color = Color("5a3000")
	holder.add_child(outline)
	var crown := Polygon2D.new()
	crown.polygon = pts
	crown.color = Color("ffd24a")
	holder.add_child(crown)
	for i in 3:
		var gem := ColorRect.new()
		gem.size = Vector2.ONE * maxf(2.0, w * 0.1)
		gem.position = Vector2(w * (0.2 + 0.3 * i) - gem.size.x / 2, h * 0.72)
		gem.color = [Color("e0303a"), Color("30a0ff"), Color("e0303a")][i]
		holder.add_child(gem)
	var tw := holder.create_tween().set_loops()
	tw.tween_property(holder, "modulate", Color(1.35, 1.25, 1.0), 0.8).set_trans(Tween.TRANS_SINE)
	tw.tween_property(holder, "modulate", Color.WHITE, 0.8).set_trans(Tween.TRANS_SINE)
	return holder
