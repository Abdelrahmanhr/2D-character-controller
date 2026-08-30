extends Control
class_name InputSequenceMinigame

signal bomb_time_delta(seconds: float)
signal round_finished

@export var bonus_per_correct: float = 0.5
@export var penalty_per_wrong: float = 1.0
@export var target_correct: int = 30
@export var visible_arrow_count: int = 4
@export var arrow_spacing: float = 22.0
@export var slide_duration: float = 0.15

const ARROW_SIZE := Vector2(48.0, 22.0)
const INACTIVE_COLOR := Color(1.0, 1.0, 1.0, 0.55)




const DIRECTIONS := ["up", "down", "left", "right"]
const ARROW_SYMBOLS := {"up": "^", "down": "v", "left": "<", "right": ">"}

var _player: Node
var _rng: RandomNumberGenerator
var _accent: Color = Color(1, 0.95, 0.2, 1)
var _correct_count: int = 0
var _round_finished: bool = false
var _arrow_queue: Array[Label] = []
var _active_tweens: Dictionary = {}

@onready var arrow_container: Control = $ArrowContainer
@onready var time_bar: ProgressBar = $TimeBar



func setup(player: Node, rng_seed: int = 0) -> void:
	_player = player
	_rng = MinigameUI.make_rng(rng_seed)
	_accent = MinigameUI.player_color_for(player)
	_correct_count = 0
	_round_finished = false
	MinigameUI.style_time_bar(time_bar, _accent)
	time_bar.max_value = 100.0
	time_bar.value = 0.0
	for i in visible_arrow_count:
		_push_new_arrow(false)
	_reposition_queue(false)

func _push_new_arrow(animate: bool) -> void:
	var direction: String = DIRECTIONS[_rng.randi() % DIRECTIONS.size()]
	var arrow_label := Label.new()
	arrow_label.text = ARROW_SYMBOLS[direction]
	arrow_label.set_meta("direction", direction)
	arrow_label.size = ARROW_SIZE
	arrow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	arrow_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow_label.add_theme_font_override("font", MinigameUI.game_font())
	arrow_container.add_child(arrow_label)
	arrow_label.position = Vector2(_arrow_x(), -arrow_spacing if animate else 0.0)
	_arrow_queue.push_front(arrow_label)

func _arrow_x() -> float:
	return (arrow_container.size.x - ARROW_SIZE.x) * 0.5

func _reposition_queue(animate: bool) -> void:
	var x := _arrow_x()
	for i in _arrow_queue.size():
		var arrow := _arrow_queue[i]
		var target_y := float(i) * arrow_spacing
		arrow.position.x = x

		if _active_tweens.has(arrow):
			var old_tween: Tween = _active_tweens[arrow]
			if old_tween.is_valid():
				old_tween.kill()

		if animate:
			var tween := create_tween()
			_active_tweens[arrow] = tween
			tween.tween_property(arrow, "position:y", target_y, slide_duration)
		else:
			arrow.position.y = target_y
	_refresh_active_style()

func _refresh_active_style() -> void:
	var last_index := _arrow_queue.size() - 1
	for i in _arrow_queue.size():
		var arrow := _arrow_queue[i]
		var is_active := i == last_index
		arrow.add_theme_color_override("font_color", _accent if is_active else INACTIVE_COLOR)
		arrow.add_theme_font_size_override("font_size", 28 if is_active else 18)
		arrow.add_theme_color_override("font_outline_color", Color(_accent.r, _accent.g, _accent.b, 0.7 if is_active else 0.25))
		arrow.add_theme_constant_override("outline_size", 4 if is_active else 2)

func _consume_active_arrow() -> void:
	var arrow: Label = _arrow_queue.pop_back()
	_active_tweens.erase(arrow)
	arrow.queue_free()
	_push_new_arrow(true)
	_reposition_queue(true)
	time_bar.value = (float(_correct_count) / float(target_correct)) * 100.0

func _handle_input(event: InputEvent) -> bool:  
	if _round_finished:
		return false  
	var pressed_direction := ""
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_DPAD_UP: pressed_direction = "up"
			JOY_BUTTON_DPAD_DOWN: pressed_direction = "down"
			JOY_BUTTON_DPAD_LEFT: pressed_direction = "left"
			JOY_BUTTON_DPAD_RIGHT: pressed_direction = "right"
			_: return false  
	elif event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.keycode if event.keycode != KEY_NONE else event.physical_keycode
		match key:
			KEY_UP: pressed_direction = "up"
			KEY_DOWN: pressed_direction = "down"
			KEY_LEFT: pressed_direction = "left"
			KEY_RIGHT: pressed_direction = "right"
			_: return false
	else:
		return false  

	_submit_direction(pressed_direction)
	return true 

func _submit_direction(direction: String) -> void:
	if _arrow_queue.is_empty():
		return
	var next_arrow: Label = _arrow_queue[_arrow_queue.size() - 1]

	MinigameUI.shake_widget(time_bar)  # NEW

	if direction == next_arrow.get_meta("direction"):
		_correct_count += 1
		bomb_time_delta.emit(bonus_per_correct)
		_spawn_sequence_popup(next_arrow, bonus_per_correct)
		await MinigameUI.highlight_correct(next_arrow)
		_consume_active_arrow()
		if _correct_count >= target_correct:
			_finish_round()
	else:
		bomb_time_delta.emit(-penalty_per_wrong)
		_spawn_sequence_popup(next_arrow, -penalty_per_wrong)
		await MinigameUI.highlight_wrong(next_arrow)

func _spawn_sequence_popup(arrow: Label, amount: float) -> void:
	var popup := Label.new()
	popup.text = "%+.1f" % amount
	popup.add_theme_font_override("font", MinigameUI.game_font())
	popup.add_theme_font_size_override("font_size", 18)
	popup.add_theme_color_override("font_color", Color(0.35, 1.0, 0.35) if amount > 0.0 else Color(1.0, 0.3, 0.3))
	popup.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	popup.add_theme_constant_override("outline_size", 3)
	popup.z_index = 10
	arrow_container.add_child(popup)
	
	var start_position: Vector2 = arrow.position + Vector2(ARROW_SIZE.x + 12.0, 0.0)
	popup.position = start_position
	
	var tween := popup.create_tween()
	tween.set_parallel(true)
	tween.tween_property(popup, "position:y", start_position.y - 20.0, 1.2)
	tween.tween_property(popup, "modulate:a", 0.0, 1.2).set_delay(0.5)
	tween.chain().tween_callback(popup.queue_free)

func _finalize_arrow_position(arrow: Label) -> void:  # NEW
	if _active_tweens.has(arrow):
		var tween: Tween = _active_tweens[arrow]
		if tween.is_valid():
			tween.kill()
		_active_tweens.erase(arrow)
	var index: int = _arrow_queue.find(arrow)
	if index != -1:
		arrow.position.y = float(index) * arrow_spacing


func _finish_round() -> void:
	if _round_finished:
		return
	_round_finished = true
	round_finished.emit()
