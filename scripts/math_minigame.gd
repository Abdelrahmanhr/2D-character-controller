extends Control
class_name MathMinigame

signal bomb_time_delta(seconds: float)
signal round_finished

@export var bonus_per_correct: float = 4.0
@export var penalty_per_wrong: float = 1.0
@export var target_correct: int = 8

var _player: Node
var _rng: RandomNumberGenerator
var _correct_count: int = 0
var _current_answer: int  # 0 = left is correct, 1 = right is correct
var _round_finished: bool = false
var _answered: bool = false

@onready var equation_label: Label = $EquationLabel
@onready var option_left: Label = $OptionLeft
@onready var option_right: Label = $OptionRight
@onready var time_bar: ProgressBar = $TimeBar

func setup(player: Node, rng_seed: int = 0) -> void:
	_player = player
	_rng = MinigameUI.make_rng(rng_seed)
	var color := MinigameUI.player_color_for(player)
	MinigameUI.style_time_bar(time_bar, color)
	MinigameUI.style_label(equation_label, color, 22)
	MinigameUI.style_label(option_left, color, 20)
	MinigameUI.style_label(option_right, color, 20)
	_load_new_equation()

func _generate_equation() -> Dictionary:
	var operators := ["+", "-", "*", "/"]
	var op: String = operators[_rng.randi() % operators.size()]
	var a: int
	var b: int
	var correct: int
	
	match op:
		"+":
			a = _rng.randi_range(1, 50)
			b = _rng.randi_range(1, 50)
			correct = a + b
		"-":
			a = _rng.randi_range(10, 60)
			b = _rng.randi_range(1, a)
			correct = a - b
		"*":
			a = _rng.randi_range(2, 12)
			b = _rng.randi_range(2, 12)
			correct = a * b
		"/":
			b = _rng.randi_range(2, 12)
			correct = _rng.randi_range(2, 12)
			a = b * correct
	
	var text: String = "%d %s %d" % [a, op, b]
	var wrong: int = _generate_wrong_answer(correct)
	return {"text": text, "correct": correct, "wrong": wrong}

func _generate_wrong_answer(correct: int) -> int:
	var offsets := [-3, -2, -1, 1, 2, 3]
	MinigameUI.shuffle(offsets, _rng)
	for offset in offsets:
		var candidate: int = correct + offset
		if candidate >= 0 and candidate != correct:
			return candidate
	return correct + 1

func _load_new_equation() -> void:
	_answered = false
	var eq: Dictionary = _generate_equation()
	equation_label.text = eq["text"] + " ="
	
	if _rng.randi() % 2 == 0:
		_current_answer = 0
		option_left.text = str(eq["correct"])
		option_right.text = str(eq["wrong"])
	else:
		_current_answer = 1
		option_left.text = str(eq["wrong"])
		option_right.text = str(eq["correct"])
	
	time_bar.value = (float(_correct_count) / float(target_correct)) * 100.0

func _handle_input(event: InputEvent) -> bool: 
	if _answered:
		return false  
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_DPAD_LEFT:
			_submit_answer(0)
			return true  
		elif event.button_index == JOY_BUTTON_DPAD_RIGHT:
			_submit_answer(1)
			return true  
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_LEFT:
			_submit_answer(0)
			return true  
		elif event.keycode == KEY_RIGHT:
			_submit_answer(1)
			return true  
	return false  

func _submit_answer(side: int) -> void:
	_answered = true
	if side == _current_answer:
		_correct_count += 1
		bomb_time_delta.emit(bonus_per_correct)
		if _correct_count >= target_correct:
			_finish_round()
			return
	else:
		bomb_time_delta.emit(-penalty_per_wrong)
	_load_new_equation()

func _finish_round() -> void:
	if _round_finished:
		return
	_round_finished = true
	round_finished.emit()
