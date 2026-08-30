extends Control
class_name ColorMatchMinigame

signal bomb_time_delta(seconds: float)
signal round_finished

@export var bonus_per_correct: float = 1.0
@export var penalty_per_wrong: float = 1.0
@export var target_correct: int = 15

const POSITIONS := ["left", "up", "right", "down"]
const COLOR_NAMES := ["RED", "GREEN", "BLUE", "YELLOW"]
const COLOR_VALUES := {
	"RED": Color.RED,
	"GREEN": Color.GREEN,
	"BLUE": Color.BLUE,
	"YELLOW": Color.YELLOW,
}

var _player: Node
var _rng: RandomNumberGenerator
var _correct_count: int = 0
var _round_finished: bool = false
var _position_color_name: Dictionary = {}
var _target_color_name: String = ""

@onready var label_left: Label = $LabelLeft
@onready var label_up: Label = $LabelUp
@onready var label_right: Label = $LabelRight
@onready var label_down: Label = $LabelDown
@onready var center_square: ColorRect = $CenterSquare
@onready var time_bar: ProgressBar = $TimeBar

func setup(player: Node, rng_seed: int = 0) -> void:
	_player = player
	_rng = MinigameUI.make_rng(rng_seed)
	var accent := MinigameUI.player_color_for(player)
	MinigameUI.style_time_bar(time_bar, accent)
	time_bar.value = 0.0
	for label in [label_left, label_up, label_right, label_down]:
		MinigameUI.style_label(label, accent, 14)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))  
	_next_round()

func _get_label(position: String) -> Label:
	match position:
		"left": return label_left
		"up": return label_up
		"right": return label_right
		"down": return label_down
	return null

func _next_round() -> void:
	var shuffled_names := COLOR_NAMES.duplicate()
	MinigameUI.shuffle(shuffled_names, _rng)
	
	for i in POSITIONS.size():
		var position: String = POSITIONS[i]
		var color_name: String = shuffled_names[i]
		_position_color_name[position] = color_name
		
		var label := _get_label(position)
		label.text = color_name
		var ink_color: String = COLOR_NAMES[_rng.randi() % COLOR_NAMES.size()]
		label.add_theme_color_override("font_color", COLOR_VALUES[ink_color])
	
	_target_color_name = COLOR_NAMES[_rng.randi() % COLOR_NAMES.size()]
	center_square.color = COLOR_VALUES[_target_color_name]

func _handle_input(event: InputEvent) -> bool: 
	if _round_finished:
		return false  
	var pressed_position := ""
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_DPAD_LEFT: pressed_position = "left"
			JOY_BUTTON_DPAD_UP: pressed_position = "up"
			JOY_BUTTON_DPAD_RIGHT: pressed_position = "right"
			JOY_BUTTON_DPAD_DOWN: pressed_position = "down"
			_: return false  
	elif event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.keycode if event.keycode != KEY_NONE else event.physical_keycode
		match key:
			KEY_LEFT: pressed_position = "left"
			KEY_UP: pressed_position = "up"
			KEY_RIGHT: pressed_position = "right"
			KEY_DOWN: pressed_position = "down"
			_: return false  
	else:
		return false  
	_submit_position(pressed_position)
	return true 

func _submit_position(position: String) -> void:
	var color_name_at_position: String = _position_color_name[position]
	var label := _get_label(position)
	var forced_side: float = _get_popup_side(position)  # NEW
	
	MinigameUI.shake_widget(self)

	if color_name_at_position == _target_color_name:
		_correct_count += 1
		bomb_time_delta.emit(bonus_per_correct)
		MinigameUI.spawn_floating_bonus(label, bonus_per_correct, forced_side)  # CHANGED: added forced_side
		time_bar.value = (float(_correct_count) / float(target_correct)) * 100.0
		await MinigameUI.highlight_correct(label)
		if _correct_count >= target_correct:
			_finish_round()
			return
	else:
		bomb_time_delta.emit(-penalty_per_wrong)
		MinigameUI.spawn_floating_bonus(label, -penalty_per_wrong, forced_side)  # CHANGED: added forced_side
		await MinigameUI.highlight_wrong(label)
	
	_next_round()

func _get_popup_side(position: String) -> float:  # NEW
	match position:
		"left": return -1.0
		"right": return 1.0
		_: return 1.0 if randf() < 0.5 else -1.0  # up/down: no strong left/right bias needed, random is fine
	
	_next_round()

func _finish_round() -> void:
	if _round_finished:
		return
	_round_finished = true
	round_finished.emit()
