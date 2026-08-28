class_name MinigameUI

static var _font: Font

static func player_color_for(player: Node) -> Color:
	var bomb := player.get_node_or_null("BombController") as BombController
	if bomb:
		return bomb.get_player_color()
	return Color(1, 0.95, 0.15, 1)

static func game_font() -> Font:
	if _font == null:
		var sys := SystemFont.new()
		sys.font_names = PackedStringArray(["Segoe UI", "Noto Sans", "Arial"])
		sys.font_weight = 700
		_font = sys
	return _font

static func style_time_bar(bar: ProgressBar, color: Color) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.9)
	bg.set_border_width_all(1)
	bg.border_color = Color(color, 0.45)
	bg.set_corner_radius_all(2)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(2)
	fill.shadow_color = Color(color, 0.4)
	fill.shadow_size = 3
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	bar.show_percentage = false

static func style_label(label: Label, color: Color, font_size: int = 20) -> void:
	label.add_theme_font_override("font", game_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.96))
	label.add_theme_color_override("font_outline_color", Color(color.r, color.g, color.b, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
