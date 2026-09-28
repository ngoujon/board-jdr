extends Node
## Construit le thème global (police pixel, panneaux en pierre, boutons en bois)
## et l'applique à la fenêtre racine. Les textures viennent de assets/ui (générées via ComfyUI).

const GOLD := Color("f2c14e")
const PARCHMENT_TEXT := Color("3b2412")
const LIGHT_TEXT := Color("f5e9d0")
const DARK := Color("1a1220")
const RED := Color("d9434b")
const GREEN := Color("5fd068")
const BLUE := Color("5ab4f0")

var font: FontFile
var font_bold: FontVariation
var font_num: FontFile   # chiffres : Press Start 2P, bien plus lisible que Pixelify pour 1/7, 5/6, 0/8...
var theme: Theme


func _ready() -> void:
	font = load("res://assets/fonts/ArcanesPixel.ttf")  # Pixelify Sans + chiffres de Press Start 2P (tools/merge_digits.py)
	font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	font.hinting = TextServer.HINTING_NONE
	# La ligature « fi » de la police pixel s'affiche mal : on désactive les ligatures.
	var ts := TextServerManager.get_primary_interface()
	font.opentype_feature_overrides = {ts.name_to_tag("liga"): 0, ts.name_to_tag("clig"): 0}
	font_bold = FontVariation.new()
	font_bold.base_font = font
	font_bold.variation_opentype = {ts.name_to_tag("wght"): 700}
	font_bold.opentype_features = {ts.name_to_tag("liga"): 0, ts.name_to_tag("clig"): 0}
	font_num = load("res://assets/fonts/PressStart2P.ttf")
	font_num.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font_num.hinting = TextServer.HINTING_NONE
	theme = _build_theme()
	get_tree().root.theme = theme
	# Les contrôles placés sous un CanvasLayer n'héritent pas du thème de la fenêtre :
	# on fusionne donc aussi le thème dans le thème par défaut du moteur.
	var default_theme := ThemeDB.get_default_theme()
	default_theme.merge_with(theme)
	default_theme.default_font = font
	default_theme.default_font_size = 18
	ThemeDB.fallback_font = font
	ThemeDB.fallback_font_size = 18


func _tex_box(path: String, margin: int, content := 8, fallback_color := Color(0.15, 0.1, 0.12)) -> StyleBox:
	if ResourceLoader.exists(path):
		var sb := StyleBoxTexture.new()
		sb.texture = load(path)
		sb.set_texture_margin_all(margin)
		sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		sb.set_content_margin_all(content)
		return sb
	var flat := StyleBoxFlat.new()
	flat.bg_color = fallback_color
	flat.border_color = GOLD
	flat.set_border_width_all(2)
	flat.set_content_margin_all(content)
	return flat


func panel_style() -> StyleBox:
	return _tex_box("res://assets/ui/panel.png", 10, 14, Color(0.16, 0.14, 0.18))


func parchment_style() -> StyleBox:
	return _tex_box("res://assets/ui/parchment_panel.png", 10, 14, Color(0.85, 0.75, 0.55))


func flat_style(bg: Color, border: Color = GOLD, width := 2, radius := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(6)
	return sb


func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 18

	var normal := _tex_box("res://assets/ui/button.png", 8, 10, Color(0.35, 0.22, 0.12))
	var hover := _tex_box("res://assets/ui/button_hover.png", 8, 10, Color(0.5, 0.32, 0.16))
	var pressed := _tex_box("res://assets/ui/button_pressed.png", 8, 10, Color(0.25, 0.15, 0.08))
	for sb in [normal, hover, pressed]:
		sb.content_margin_left = 16
		sb.content_margin_right = 16
	var disabled: StyleBox = normal.duplicate()
	if disabled is StyleBoxTexture:
		disabled.modulate_color = Color(0.5, 0.5, 0.5)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", flat_style(Color(0, 0, 0, 0), GOLD, 2))
	t.set_color("font_color", "Button", LIGHT_TEXT)
	t.set_color("font_hover_color", "Button", GOLD)
	t.set_color("font_pressed_color", "Button", Color("ffe9a8"))
	t.set_color("font_focus_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", Color(0.6, 0.55, 0.5))
	t.set_color("font_outline_color", "Button", DARK)
	t.set_constant("outline_size", "Button", 4)
	t.set_font_size("font_size", "Button", 20)

	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "Panel", panel_style())

	t.set_color("font_color", "Label", LIGHT_TEXT)
	t.set_color("font_outline_color", "Label", DARK)
	t.set_constant("outline_size", "Label", 4)

	t.set_color("default_color", "RichTextLabel", LIGHT_TEXT)
	t.set_color("font_outline_color", "RichTextLabel", DARK)
	t.set_constant("outline_size", "RichTextLabel", 3)
	t.set_font("bold_font", "RichTextLabel", font_bold)
	t.set_font_size("normal_font_size", "RichTextLabel", 17)
	t.set_font_size("bold_font_size", "RichTextLabel", 17)

	# Onglets
	t.set_stylebox("panel", "TabContainer", flat_style(Color(0.1, 0.08, 0.12, 0.85), Color("6b5a3c"), 2))
	t.set_stylebox("tab_selected", "TabContainer", flat_style(Color("5a3a1e"), GOLD, 2))
	t.set_stylebox("tab_unselected", "TabContainer", flat_style(Color("2b1d14"), Color("6b5a3c"), 2))
	t.set_stylebox("tab_hovered", "TabContainer", flat_style(Color("3f2a18"), GOLD, 2))
	t.set_color("font_selected_color", "TabContainer", GOLD)
	t.set_color("font_unselected_color", "TabContainer", LIGHT_TEXT)
	t.set_color("font_hovered_color", "TabContainer", GOLD)

	# Curseurs de volume
	var slider_bg := flat_style(Color("2b1d14"), Color("6b5a3c"), 2)
	slider_bg.content_margin_top = 4
	slider_bg.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", slider_bg)
	var fill := flat_style(Color("c98a2b"), Color("6b5a3c"), 2)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var grab := _make_grabber()
	t.set_icon("grabber", "HSlider", grab)
	t.set_icon("grabber_highlight", "HSlider", grab)

	# Cases à cocher / options
	t.set_color("font_color", "CheckButton", LIGHT_TEXT)
	t.set_color("font_hover_color", "CheckButton", GOLD)
	t.set_color("font_color", "OptionButton", LIGHT_TEXT)

	t.set_stylebox("panel", "PopupMenu", flat_style(Color(0.12, 0.09, 0.1), GOLD, 2))

	var sb_scroll := flat_style(Color("2b1d14"), Color("2b1d14"), 0)
	t.set_stylebox("scroll", "VScrollBar", sb_scroll)
	var sb_grab := flat_style(Color("8a6a3a"), Color("8a6a3a"), 0)
	t.set_stylebox("grabber", "VScrollBar", sb_grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", flat_style(Color("c98a2b"), Color("c98a2b"), 0))
	t.set_stylebox("grabber_pressed", "VScrollBar", flat_style(Color("f2c14e"), Color("f2c14e"), 0))

	t.set_stylebox("panel", "TooltipPanel", flat_style(Color(0.1, 0.07, 0.08, 0.95), GOLD, 2))
	t.set_color("font_color", "TooltipLabel", LIGHT_TEXT)
	return t


func _make_grabber() -> Texture2D:
	var img := Image.create(12, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color("1a1220"))
	img.fill_rect(Rect2i(2, 2, 8, 16), Color("f2c14e"))
	img.fill_rect(Rect2i(2, 2, 8, 3), Color("fff0b0"))
	return ImageTexture.create_from_image(img)


## Crée un Label stylé rapidement.
func label(text: String, size := 18, color := LIGHT_TEXT, outline := 4) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", outline)
	return l


## Label numérique (coût, attaque, PV, énergie, dégâts) avec la police des chiffres.
func num_label(text: String, size := 16, color := Color.WHITE, outline := 6) -> Label:
	var l := label(text, size, color, outline)
	l.add_theme_font_override("font", font_num)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func title_label(text: String, size := 48) -> Label:
	var l := label(text, size, GOLD, 10)
	l.add_theme_font_override("font", font_bold)
	l.add_theme_color_override("font_outline_color", Color("2a0f08"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func button(text: String, min_width := 260) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 46)
	b.mouse_entered.connect(func(): Audio.play_sfx("click", 0.15, -14.0))
	b.pressed.connect(func(): Audio.play_sfx("click", 0.05, -4.0))
	return b
