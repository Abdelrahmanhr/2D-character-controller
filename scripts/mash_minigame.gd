extends Control
class_name MashMinigame

signal bomb_time_delta(seconds: float)
signal round_finished

@export var max_presses: int = 40
@export var bonus_per_threshold: float = 1.0
@export var presses_per_bonus: int = 10

var _player: Node
var _press_count: int = 0
var _round_finished: bool = false

@onready var press_count_label: Label = $PressCountLabel
@onready var time_bar: ProgressBar = $TimeBar



func setup(player: Node, _rng_seed: int = 0) -> void:
	_player = player
	var color := MinigameUI.player_color_for(player)
	MinigameUI.style_time_bar(time_bar, color)
	MinigameUI.style_label($MashLabel, color, 34)
	MinigameUI.style_label(press_count_label, color, 24)
	time_bar.value = 0.0
	_update_label()

## What a bot should press right now, as a Settings action name, or &"" if there
## is nothing to answer. BombController.bot_submit turns it into a real key event,
## so a bot travels exactly the same path a human does.
func bot_action() -> StringName:
	return &"" if _round_finished else &"mash"


func _handle_input(event: InputEvent) -> bool:  
	if _round_finished:
		return false  
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_Y:
		_register_press()
		return true 
	elif event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		if Settings.action_for_key(key) == &"mash":
			_register_press()
			return true  
	return false 

func _register_press() -> void:
	if _press_count >= max_presses:
		return
	_press_count += 1
	_update_label()
	time_bar.value = (float(_press_count) / float(max_presses)) * 100.0
	MinigameUI.shake_widget(self)  # NEW
	if _press_count % presses_per_bonus == 0:
		bomb_time_delta.emit(bonus_per_threshold)
		MinigameUI.spawn_floating_bonus(press_count_label, bonus_per_threshold)  # NEW
	if _press_count >= max_presses:
		_finish_round()

func _finish_round() -> void:
	if _round_finished:
		return
	_round_finished = true
	round_finished.emit()

func _update_label() -> void:
	press_count_label.text = "%d/%d" % [_press_count, max_presses]
