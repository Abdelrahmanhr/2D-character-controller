extends Node2D
class_name LightningWarning

const COLOR := Color(1, 0.1608, 0.1608)
const OUTLINE_COLOR := Color(0, 0, 0, 0.9)
const FONT_SIZE := 34
const FLASH_INTERVAL := 0.12
const MIN_ALPHA := 0.15

var _label: Label
var _tween: Tween
var _expire_time_ms: int = -1


static func spawn(parent: Node, at: Vector2, duration: float) -> LightningWarning:
	var warning := LightningWarning.new()
	parent.add_child(warning)
	warning.global_position = at
	warning.play(duration)
	return warning


func _ready() -> void:
	z_index = 15
	_label = Label.new()
	_label.text = "!"
	_label.add_theme_font_override("font", MinigameUI.game_font())
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.add_theme_color_override("font_color", COLOR)
	_label.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	_label.add_theme_constant_override("outline_size", 5)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	# Centered on this node's origin, which spawn() places above the target platform.
	_label.position = Vector2(-FONT_SIZE * 0.5, -FONT_SIZE)
	_label.size = Vector2(FONT_SIZE, FONT_SIZE)
	MinigameDirector.input_locked_changed.connect(_on_input_locked_changed)


func play(duration: float) -> void:
	_tween = create_tween()
	_tween.set_loops()
	_tween.tween_property(_label, "modulate:a", MIN_ALPHA, FLASH_INTERVAL)
	_tween.tween_property(_label, "modulate:a", 1.0, FLASH_INTERVAL)
	_expire_time_ms = _get_timestamp() + int(duration * 1000.0)


## Polled off the pause-aware clock instead of a get_tree().create_timer(duration),
## so the "!" keeps flashing and stays up for its full warning window rather than
## silently expiring in real time behind a couch pause.
func _process(_delta: float) -> void:
	if _expire_time_ms < 0:
		return
	if _get_timestamp() >= _expire_time_ms:
		_finish()


func _on_input_locked_changed(locked: bool) -> void:
	if not _tween or not _tween.is_valid():
		return
	if locked:
		_tween.pause()
	else:
		_tween.play()


func _get_timestamp() -> int:
	return MinigameDirector.get_hazard_time_ms()


func _finish() -> void:
	_expire_time_ms = -1
	if _tween and _tween.is_valid():
		_tween.kill()
	queue_free()
