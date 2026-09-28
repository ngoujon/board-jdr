class_name IconButton
extends Button
## Bouton rond avec une icône dessinée : "gear" (paramètres) ou "logout" (quitter le jeu).

var icon_kind := "gear"


func _init(kind := "gear", tip := "") -> void:
	icon_kind = kind
	tooltip_text = tip
	custom_minimum_size = Vector2(56, 56)
	size = custom_minimum_size
	focus_mode = Control.FOCUS_NONE
	flat = true
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func _draw() -> void:
	var c := size / 2
	var hover := is_hovered()
	draw_circle(c + Vector2(0, 2), 27, Color(0, 0, 0, 0.45))
	draw_circle(c, 27, Color("2a1d14") if not hover else Color("3d2a1c"))
	draw_arc(c, 26, 0, TAU, 40, UITheme.GOLD if hover else Color("8a6a3c"), 3.0)
	var col := Color("ffe6a8") if hover else Color("e8d6b0")
	match icon_kind:
		"gear":
			var pts := PackedVector2Array()
			var teeth := 8
			for i in teeth * 4:
				var a := TAU * i / (teeth * 4.0)
				var r := 15.0 if (i % 4) < 2 else 11.0
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(pts, col)
			draw_circle(c, 5.5, Color("2a1d14") if not hover else Color("3d2a1c"))
		"logout":
			# Porte ouverte + flèche vers la sortie.
			var door := Rect2(c + Vector2(-14, -14), Vector2(15, 28))
			draw_rect(door, col, false, 3.0)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-14, -14), c + Vector2(-4, -10), c + Vector2(-4, 18), c + Vector2(-14, 14)]), col)
			draw_line(c + Vector2(2, 0), c + Vector2(16, 0), col, 3.0)
			draw_colored_polygon(PackedVector2Array([c + Vector2(18, 0), c + Vector2(11, -7), c + Vector2(11, 7)]), col)
