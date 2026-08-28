extends Node

signal countdown_tick(seconds_left: int)
signal match_started

@export var expected_player_count: int = 1
@export var countdown_duration: float = 3.0

var _countdown_left: float = 0.0
var _counting_down: bool = false

@export var minigame_order: Array[PackedScene] = []  # index 0 = math, hardcoded order
@export var spawn_cooldown: float = 5.0

var _bomb_controllers: Array[BombController] = []
var _current_index: int = -1
var _finished_count: int = 0
var _cooldown_left: float = 0.0
var _waiting_for_cooldown: bool = false

func register_player(bomb_controller: BombController) -> void:
	_bomb_controllers.append(bomb_controller)
	bomb_controller.player_finished_round.connect(_on_player_finished)
	
	if _bomb_controllers.size() >= expected_player_count and not _counting_down:
		_begin_countdown()

func _begin_countdown() -> void:
	_counting_down = true
	_countdown_left = countdown_duration

func start_next_round() -> void:
	_current_index += 1
	if _current_index >= minigame_order.size():
		_current_index = 0  
	
	_finished_count = 0
	var scene: PackedScene = minigame_order[_current_index]
	for bc in _bomb_controllers:
		bc.play_minigame(scene)

func _on_player_finished() -> void:
	_finished_count += 1
	if _finished_count >= _bomb_controllers.size():
		_waiting_for_cooldown = true
		_cooldown_left = spawn_cooldown

func _process(delta: float) -> void:
	if _counting_down:
		var prev_second := ceili(_countdown_left)
		_countdown_left -= delta
		var new_second := ceili(_countdown_left)
		if new_second != prev_second and new_second >= 0:
			countdown_tick.emit(new_second)
		if _countdown_left <= 0.0:
			_counting_down = false
			match_started.emit()
			start_next_round()
		return
	
	if not _waiting_for_cooldown:
		return
	_cooldown_left -= delta
	if _cooldown_left <= 0.0:
		_waiting_for_cooldown = false
		start_next_round()
