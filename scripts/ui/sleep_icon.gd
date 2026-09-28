class_name SleepIcon
extends Control
## Icône « endormi » d'un serviteur qui vient d'être posé : trois Z en pixel art (du plus petit au plus grand),
## avec un contour sombre, qui montent et descendent doucement.

const PX := 2                                   # taille d'un « pixel » de lettre
const FILL := Color("cfe6ff")
const SHADE := Color("7fa8e0")                  # bas des lettres (léger dégradé)
const OUTLINE := Color("141a33")
# [taille de la lettre en pixels, position du coin haut gauche, déphasage de l'animation]
const LETTERS := [[4, Vector2(2, 20), 0.0], [5, Vector2(14, 10), 0.7], [6, Vector2(28, 0), 1.4]]

var _t := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(44, 34)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_t += delta
		queue_redraw()


func _draw() -> void:
	for l in LETTERS:
		var n: int = l[0]
		var off: Vector2 = l[1] + Vector2(0, roundf(sin(_t * 2.2 - float(l[2])) * 1.5))
		var cells := _z_cells(n)
		for c in cells:   # contour : chaque case débordée d'un pixel
			draw_rect(Rect2(off + c * PX - Vector2.ONE, Vector2.ONE * (PX + 2)), OUTLINE)
		for c in cells:
			draw_rect(Rect2(off + c * PX, Vector2.ONE * PX), SHADE if c.y == n - 1 else FILL)


static func _z_cells(n: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for x in n:
		out.append(Vector2(x, 0))
		out.append(Vector2(x, n - 1))
	for y in range(1, n - 1):
		out.append(Vector2(n - 1 - y, y))
	return out
