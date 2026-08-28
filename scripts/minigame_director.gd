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
var _round_indices: Dictionary = {}
var _cooldowns: Dictionary = {}

func register_player(bomb_controller: BombController) -> void:
	if _bomb_controllers.has(bomb_controller):
		return
	_bomb_controllers.append(bomb_controller)
	_round_indices[bomb_controller] = -1
	_cooldowns[bomb_controller] = 0.0
	bomb_controller.player_finished_round.connect(_on_player_finished.bind(bomb_controller))
	
	if _bomb_controllers.size() >= expected_player_count and not _counting_down:
		_begin_countdown()

func _begin_countdown() -> void:
	_counting_down = true
	_countdown_left = countdown_duration

func unregister_player(bomb_controller: BombController) -> void:
	if not _bomb_controllers.has(bomb_controller):
		return
	_bomb_controllers.erase(bomb_controller)
	_round_indices.erase(bomb_controller)
	_cooldowns.erase(bomb_controller)
	var callback := _on_player_finished.bind(bomb_controller)
	if bomb_controller.player_finished_round.is_connected(callback):
		bomb_controller.player_finished_round.disconnect(callback)
	if _bomb_controllers.is_empty():
		_counting_down = false
		_countdown_left = 0.0

func _start_rounds() -> void:
	for bomb_controller in _bomb_controllers.duplicate():
		_start_next_round_for_player(bomb_controller)

func _start_next_round_for_player(bomb_controller: BombController) -> void:
	if minigame_order.is_empty() or not is_instance_valid(bomb_controller) or not _bomb_controllers.has(bomb_controller):
		return
	var next_index: int = int(_round_indices[bomb_controller]) + 1
	if next_index >= minigame_order.size():
		next_index = 0
	_round_indices[bomb_controller] = next_index
	var scene: PackedScene = minigame_order[next_index]
	bomb_controller.play_minigame(scene)

func _on_player_finished(bomb_controller: BombController) -> void:
	if _bomb_controllers.has(bomb_controller):
		_cooldowns[bomb_controller] = spawn_cooldown

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
			_start_rounds()
		return

	for bomb_controller in _cooldowns.keys():
		if not is_instance_valid(bomb_controller):
			unregister_player(bomb_controller)
			continue
		var cooldown: float = _cooldowns[bomb_controller]
		if cooldown <= 0.0:
			continue
		cooldown -= delta
		_cooldowns[bomb_controller] = cooldown
		if cooldown <= 0.0:
			_start_next_round_for_player(bomb_controller)
