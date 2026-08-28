extends Control
class_name MathMinigame

signal bomb_time_delta(seconds: float)
 
signal round_finished                       

var _round_finished: bool = false

@export var round_duration: float = 20.0
@export var bonus_per_correct: float = 4.0
@export var equation_count: int = 5

var _player: Node
var _time_left: float
var _equations_solved: int = 0
var _current_answer: int  # 0 = left is correct, 1 = right is correct

@onready var equation_label: Label = $EquationLabel
@onready var option_left: Label = $OptionLeft
@onready var option_right: Label = $OptionRight
@onready var time_bar: ProgressBar = $TimeBar

const EQUATIONS := [
	{"text": "51 - 32", "correct": 19, "wrong": 21},
	{"text": "12 - 7",  "correct": 5,  "wrong": 4},
	{"text": "8 + 8",   "correct": 16, "wrong": 14},
	{"text": "19 + 26", "correct": 45, "wrong": 47},
	{"text": "9 * 8",   "correct": 72, "wrong": 74},
	{"text": "5 * 9",   "correct": 45, "wrong": 40},
	{"text": "42 / 6",  "correct": 7,  "wrong": 8},
	{"text": "27 / 9",  "correct": 3,  "wrong": 4},
]

var _round_equations: Array = []
var _equation_index: int = 0
var _answered: bool = false

func setup(player: Node) -> void:
	_player = player
	_time_left = round_duration
	
	var pool := EQUATIONS.duplicate()
	pool.shuffle()
	_round_equations = pool.slice(0, equation_count)
	
	_equation_index = 0
	_load_equation(_equation_index)


func _load_equation(index: int) -> void:
	_answered = false
	var eq: Dictionary = _round_equations[index]
	equation_label.text = eq["text"] + " ="
	
	# Randomize which side the correct answer lands on
	if randi() % 2 == 0:
		_current_answer = 0  # left
		option_left.text = str(eq["correct"])
		option_right.text = str(eq["wrong"])
	else:
		_current_answer = 1  # right
		option_left.text = str(eq["wrong"])
		option_right.text = str(eq["correct"])

func _handle_input(event: InputEvent) -> void:
	if _answered:
		return

	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_DPAD_LEFT:
			_submit_answer(0)
		elif event.button_index == JOY_BUTTON_DPAD_RIGHT:
			_submit_answer(1)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_LEFT:
			_submit_answer(0)
		elif event.keycode == KEY_RIGHT:
			_submit_answer(1)

func _submit_answer(side: int) -> void:
	_answered = true
	if side == _current_answer:
		_equations_solved += 1
		bomb_time_delta.emit(bonus_per_correct)
	_advance_to_next_equation()

func _advance_to_next_equation() -> void:
	_equation_index += 1
	if _equation_index >= _round_equations.size():
		_finish_round()
	else:
		_load_equation(_equation_index)

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
