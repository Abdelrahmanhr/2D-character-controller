extends Control
class_name InputSequenceMinigame

signal bomb_time_delta(seconds: float) 
signal round_finished

@export var round_duration: float = 10.0
@export var bonus_per_correct: float = 0.5
@export var penalty_per_wrong: float = 1.0
@export var target_correct: int = 30
@export var visible_arrow_count: int = 5
@export var arrow_spacing: float = 50.0
@export var slide_duration: float = 0.15

const DIRECTIONS := ["up", "down", "left", "right"]
const ARROW_SYMBOLS := {"up": "↑", "down": "↓", "left": "←", "right": "→"}

var _player: Node
var _time_left: float
var _correct_count: int = 0
var _round_finished: bool = false
var _arrow_queue: Array[Label] = []
var _active_tweens: Dictionary = {} 

@onready var arrow_container: Control = $ArrowContainer
@onready var time_bar: ProgressBar = $TimeBar

func setup(player: Node) -> void:
	_player = player
	_time_left = round_duration
	_correct_count = 0
	_round_finished = false
	time_bar.max_value = 100.0
	time_bar.value = 100.0
	for i in visible_arrow_count:
		_push_new_arrow(false)
	_reposition_queue(false)
	print("INITIAL QUEUE (top to bottom): ", _arrow_queue.map(func(a): return a.get_meta("direction")))
	print("ACTIVE (bottom) ARROW: ", _arrow_queue[_arrow_queue.size() - 1].get_meta("direction"))

func _push_new_arrow(animate: bool) -> void:
	var direction: String = DIRECTIONS[randi() % DIRECTIONS.size()]
	var arrow_label := Label.new()
	arrow_label.text = ARROW_SYMBOLS[direction]
	arrow_label.set_meta("direction", direction)
	arrow_label.custom_minimum_size = Vector2(40.0, 24.0)
	arrow_label.position.x = 80.0
	arrow_label.add_theme_font_size_override("font_size", 20)
	arrow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow_container.add_child(arrow_label)
	arrow_label.position.y = -arrow_spacing if animate else 0.0
	_arrow_queue.push_front(arrow_label)

func _reposition_queue(animate: bool) -> void:
	for i in _arrow_queue.size():
		var arrow := _arrow_queue[i]
		var target_y := float(i) * arrow_spacing
		
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

func _consume_active_arrow() -> void:
	var arrow: Label = _arrow_queue.pop_back()
	_active_tweens.erase(arrow)
	arrow.queue_free()
	_push_new_arrow(true)
	_reposition_queue(true)

func _handle_input(event: InputEvent) -> void:
	if _round_finished:
		return

	var pressed_direction := ""
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_DPAD_UP: pressed_direction = "up"
			JOY_BUTTON_DPAD_DOWN: pressed_direction = "down"
			JOY_BUTTON_DPAD_LEFT: pressed_direction = "left"
			JOY_BUTTON_DPAD_RIGHT: pressed_direction = "right"
			_: return
	elif event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.keycode if event.keycode != KEY_NONE else event.physical_keycode
		match key:
			KEY_UP: pressed_direction = "up"
			KEY_DOWN: pressed_direction = "down"
			KEY_LEFT: pressed_direction = "left"
			KEY_RIGHT: pressed_direction = "right"
			_: return
	else:
		return
	
	_submit_direction(pressed_direction)

func _submit_direction(direction: String) -> void:
	if _arrow_queue.is_empty():
		return
	var next_arrow: Label = _arrow_queue[_arrow_queue.size() - 1]
	
	if direction == next_arrow.get_meta("direction"):
		_correct_count += 1
		bomb_time_delta.emit(bonus_per_correct)
		_consume_active_arrow()
		if _correct_count >= target_correct:
			_finish_round()
	else:
		bomb_time_delta.emit(-penalty_per_wrong)

func _process(delta: float) -> void:
	if _round_finished:
		return
	_time_left -= delta
	time_bar.value = (_time_left / round_duration) * 100.0
	if _time_left <= 0.0:
		_finish_round()

func _finish_round() -> void:
	if _round_finished:
		return
	_round_finished = true
	set_process(false)
	round_finished.emit()
