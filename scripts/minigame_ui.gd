class_name MinigameUI

static var _font: Font

const SHAKE_STRENGTH: float = 6.0
const SHAKE_DURATION: float = 0.15
const WRONG_COLOR: Color = Color(1.0, 0.3, 0.3)  
const DEFAULT_FONT_COLOR: Color = Color(1, 1, 1, 0.96) 
const CORRECT_COLOR: Color = Color(0.35, 1.0, 0.35)
const HIGHLIGHT_DURATION: float = 0.12
const ANSWER_SHAKE_STRENGTH: float = 10.0 

const FLOAT_TEXT_DURATION: float = 1.0  
const FLOAT_TEXT_RISE: float = 40.0  
const FLOAT_TEXT_SPREAD: float = 25.0

const FLOAT_TEXT_VERTICAL_OFFSET: float = 12.0  

static func game_font() -> Font:  
	if _font == null:
		_font = load("res://resources/boldpixels.ttf")  
	return _font

static func spawn_floating_bonus(label: Label, amount: float, forced_side: float = 0.0, vertical_offset: float = FLOAT_TEXT_VERTICAL_OFFSET, rise_distance: float = FLOAT_TEXT_RISE) -> void:
	var parent: Node = label.get_parent()
	if parent == null:
		return
	
	var popup := Label.new()
	popup.text = "%+.1f" % amount
	popup.add_theme_font_override("font", game_font())
	popup.add_theme_font_size_override("font_size", 18)
	popup.add_theme_color_override("font_color", CORRECT_COLOR if amount > 0.0 else WRONG_COLOR)
	popup.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	popup.add_theme_constant_override("outline_size", 3)
	popup.z_index = 10
	parent.add_child(popup)
	
	var side: float = forced_side if forced_side != 0.0 else (1.0 if randf() < 0.5 else -1.0)
	var min_offset: float = 8.0
	var max_offset: float = min_offset + FLOAT_TEXT_SPREAD
	var horizontal_offset: float = randf_range(min_offset, max_offset) * side
	var start_position: Vector2 = label.position + Vector2(label.size.x * 0.5 + horizontal_offset, -vertical_offset)
	popup.position = start_position
	popup.pivot_offset = popup.size * 0.5
	
	var tween := popup.create_tween()
	tween.set_parallel(true)
	tween.tween_property(popup, "position:y", start_position.y - rise_distance, FLOAT_TEXT_DURATION)
	tween.tween_property(popup, "modulate:a", 0.0, FLOAT_TEXT_DURATION).set_delay(FLOAT_TEXT_DURATION * 0.3)
	tween.chain().tween_callback(popup.queue_free)

static func highlight_correct(label: Label) -> void: 
	await _flash_label(label, CORRECT_COLOR)

static func highlight_wrong(label: Label) -> void:  
	await _flash_label(label, WRONG_COLOR)

static func _flash_label(label: Label, color: Color) -> void:  
	var original_position: Vector2 = label.position
	label.add_theme_color_override("font_color", color)
	var tween := label.create_tween()
	var steps := 4
	for i in steps:
		var offset := Vector2(randf_range(-ANSWER_SHAKE_STRENGTH, ANSWER_SHAKE_STRENGTH), randf_range(-ANSWER_SHAKE_STRENGTH, ANSWER_SHAKE_STRENGTH))
		tween.tween_property(label, "position", original_position + offset, HIGHLIGHT_DURATION / steps)
	tween.tween_property(label, "position", original_position, HIGHLIGHT_DURATION / steps)
	await tween.finished
	label.add_theme_color_override("font_color", DEFAULT_FONT_COLOR) 

static func shake_widget(node: Control) -> void:
	if not node.has_meta("_shake_home_position"):
		node.set_meta("_shake_home_position", node.position)
	if node.has_meta("_shake_tween"):
		var old_tween: Tween = node.get_meta("_shake_tween")
		if old_tween.is_valid():
			old_tween.kill()
	
	var home_position: Vector2 = node.get_meta("_shake_home_position")
	var tween := node.create_tween()
	node.set_meta("_shake_tween", tween)
	var steps := 4
	for i in steps:
		var offset := Vector2(randf_range(-SHAKE_STRENGTH, SHAKE_STRENGTH), randf_range(-SHAKE_STRENGTH, SHAKE_STRENGTH))
		tween.tween_property(node, "position", home_position + offset, SHAKE_DURATION / steps)
	tween.tween_property(node, "position", home_position, SHAKE_DURATION / steps)


static func player_color_for(player: Node) -> Color:
	var bomb := player.get_node_or_null("BombController") as BombController
	if bomb:
		return bomb.get_player_color()
	return Color(1, 0.95, 0.15, 1)

# CHANGED: removed the second, duplicate game_font() that was here (the SystemFont version) — game_font() now only exists once, near the top of the file

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

static func make_rng(rng_seed: int = 0) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	if rng_seed == 0:
		rng.randomize()
	else:
		rng.seed = rng_seed
	return rng

static func shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for i in range(values.size() - 1, 0, -1):
		var j: int = rng.randi() % (i + 1)
		var temp: Variant = values[i]
		values[i] = values[j]
		values[j] = temp

static func style_label(label: Label, color: Color, font_size: int = 20) -> void:
	label.add_theme_font_override("font", game_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.96))
	label.add_theme_color_override("font_outline_color", Color(color.r, color.g, color.b, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
