class_name CheckMark
extends Control
## Coche verte dessinée (niveau d'IA déjà battu), avec un contour sombre pour rester lisible sur tous les fonds.

const FILL := Color("4ee06a")
const OUTLINE := Color("0c2412")


func _init(side := 26.0) -> void:
	custom_minimum_size = Vector2(side, side)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s := size.x
	var pts := PackedVector2Array([Vector2(0.16, 0.55) * s, Vector2(0.42, 0.8) * s, Vector2(0.86, 0.22) * s])
	draw_circle(Vector2(s, s) / 2, s / 2, Color(0, 0, 0, 0.45))
	draw_polyline(pts, OUTLINE, s * 0.26, false)
	draw_polyline(pts, FILL, s * 0.15, false)
