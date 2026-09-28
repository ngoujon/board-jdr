class_name GoldCoin
extends Control
## Petite pièce d'or dessinée (icône de la monnaie « PO »).

var radius := 14.0


func _init(r := 14.0) -> void:
	radius = r
	custom_minimum_size = Vector2(r * 2 + 2, r * 2 + 2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _draw() -> void:
	var c := size / 2
	draw_circle(c + Vector2(1, 2), radius, Color(0, 0, 0, 0.45))
	draw_circle(c, radius, Color("b07a10"))
	draw_circle(c, radius - 2.0, Color("ffd24a"))
	draw_arc(c, radius - 5.0, 0, TAU, 32, Color("d79a1c"), 2.0)
	draw_string(UITheme.font_bold, c + Vector2(-radius * 0.62, radius * 0.38), Loc.t("PO"), HORIZONTAL_ALIGNMENT_LEFT, -1,
		int(radius * 0.85), Color("8a5a08"))
	draw_circle(c + Vector2(-radius * 0.45, -radius * 0.45), radius * 0.16, Color(1, 1, 1, 0.7))
