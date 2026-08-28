extends Control
class_name MashMinigame

signal bomb_time_delta(seconds: float)
signal round_finished

@export var max_presses: int = 40
@export var round_duration: float = 10.0
@export var bonus_per_threshold: float = 1.0
@export var presses_per_bonus: int = 10

var _player: Node
var _time_left: float
var _press_count: int = 0
var _round_finished: bool = false

@onready var press_count_label: Label = $PressCountLabel
@onready var time_bar: ProgressBar = $TimeBar

func setup(player: Node, _rng_seed: int = 0) -> void:
	_player = player
	_time_left = round_duration
	var color := MinigameUI.player_color_for(player)
	MinigameUI.style_time_bar(time_bar, color)
	MinigameUI.style_label($MashLabel, color, 28)
	MinigameUI.style_label(press_count_label, color, 20)
	_update_label()

func _handle_input(event: InputEvent) -> void:
	if _round_finished:
		return
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_Y:
		_register_press()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Y or event.physical_keycode == KEY_Y:
			_register_press()

func _register_press() -> void:
	if _press_count >= max_presses:
		return
	_press_count += 1
	_update_label()
	if _press_count % presses_per_bonus == 0:
		bomb_time_delta.emit(bonus_per_threshold)
	if _press_count >= max_presses:
		_finish_round()

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

func _update_label() -> void:
	press_count_label.text = "%d/%d" % [_press_count, max_presses]
