extends Node

signal countdown_tick(seconds_left: int)
signal match_started
signal match_finished(winner_peer_id: int)
signal alive_count_changed(alive: int, total: int)

@export var expected_player_count: int = 1
@export var countdown_duration: float = 3.0

var _countdown_left: float = 0.0
var _counting_down: bool = false

@export var minigame_order: Array[PackedScene] = []  # index 0 = math, hardcoded order
@export var spawn_cooldown: float = 5.0

var _bomb_controllers: Array[BombController] = []
var _round_indices: Dictionary = {}
var _cooldowns: Dictionary = {}
var _alive_peer_ids: Dictionary = {}
var _total_players: int = 0
var _match_finished := false

func get_alive_count() -> int:
	return _alive_peer_ids.size()

func get_total_players() -> int:
	return _total_players

func _notify_alive_count() -> void:
	var alive := _alive_peer_ids.size()
	alive_count_changed.emit(alive, _total_players)
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer) and multiplayer.is_server():
		_sync_alive_count.rpc(alive, _total_players)

@rpc("authority", "reliable")
func _sync_alive_count(alive: int, total: int) -> void:
	_total_players = total
	alive_count_changed.emit(alive, total)

func reset_match() -> void:
	_bomb_controllers.clear()
	_round_indices.clear()
	_cooldowns.clear()
	_alive_peer_ids.clear()
	_total_players = 0
	_countdown_left = 0.0
	_counting_down = false
	_match_finished = false

func register_player(bomb_controller: BombController) -> void:
	if _bomb_controllers.has(bomb_controller):
		return
	_bomb_controllers.append(bomb_controller)
	_alive_peer_ids[bomb_controller.get_parent().name.to_int()] = bomb_controller
	_total_players = maxi(_total_players, _alive_peer_ids.size())
	_round_indices[bomb_controller] = -1
	_cooldowns[bomb_controller] = 0.0
	bomb_controller.player_finished_round.connect(_on_player_finished.bind(bomb_controller))
	_notify_alive_count()
	
	if _bomb_controllers.size() >= expected_player_count and not _counting_down:
		_begin_countdown()

func _begin_countdown() -> void:
	_counting_down = true
	_countdown_left = countdown_duration

func unregister_player(bomb_controller: BombController) -> void:
	if not _bomb_controllers.has(bomb_controller):
		return
	_bomb_controllers.erase(bomb_controller)
	_alive_peer_ids.erase(bomb_controller.get_parent().name.to_int())
	_round_indices.erase(bomb_controller)
	_cooldowns.erase(bomb_controller)
	var callback := _on_player_finished.bind(bomb_controller)
	if bomb_controller.player_finished_round.is_connected(callback):
		bomb_controller.player_finished_round.disconnect(callback)
	_notify_alive_count()
	if _bomb_controllers.is_empty():
		_counting_down = false
		_countdown_left = 0.0

func _start_rounds() -> void:
	for bomb_controller in _bomb_controllers.duplicate():
		_start_next_round_for_player(bomb_controller)

func _start_next_round_for_player(bomb_controller: BombController) -> void:
	if _match_finished or minigame_order.is_empty() or not is_instance_valid(bomb_controller) or not _bomb_controllers.has(bomb_controller):
		return
	var next_index: int = int(_round_indices[bomb_controller]) + 1
	if next_index >= minigame_order.size():
		next_index = 0
	_round_indices[bomb_controller] = next_index
	var scene: PackedScene = minigame_order[next_index]
	bomb_controller.play_minigame(scene, bomb_controller.get_slot_index())

func _on_player_finished(bomb_controller: BombController) -> void:
	if not _match_finished and _bomb_controllers.has(bomb_controller):
		_cooldowns[bomb_controller] = spawn_cooldown

func player_eliminated(peer_id: int) -> void:
	if _match_finished:
		return
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		_resolve_elimination(peer_id)
	elif multiplayer.is_server():
		_resolve_elimination(peer_id)
	else:
		_alive_peer_ids.erase(peer_id)
		alive_count_changed.emit(_alive_peer_ids.size(), _total_players)
		_report_elimination.rpc_id(1, peer_id)

@rpc("any_peer", "reliable")
func _report_elimination(peer_id: int) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == peer_id:
		_resolve_elimination(peer_id)

func player_disconnected(peer_id: int) -> void:
	if multiplayer.is_server():
		_resolve_elimination(peer_id)

func _resolve_elimination(peer_id: int) -> void:
	_alive_peer_ids.erase(peer_id)
	_notify_alive_count()
	if _alive_peer_ids.size() > 1:
		return
	var winner_peer_id := 0
	if _alive_peer_ids.size() == 1:
		winner_peer_id = int(_alive_peer_ids.keys()[0])
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		_finish_match(winner_peer_id)
	else:
		_finish_match.rpc(winner_peer_id)

@rpc("authority", "call_local", "reliable")
func _finish_match(winner_peer_id: int) -> void:
	if _match_finished:
		return
	_match_finished = true
	_counting_down = false
	_cooldowns.clear()
	for bomb_controller in _bomb_controllers.duplicate():
		if is_instance_valid(bomb_controller):
			bomb_controller.stop_minigame()
			bomb_controller.stop_timer()
	match_finished.emit(winner_peer_id)

func _process(delta: float) -> void:
	if _match_finished:
		return
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


func set_expected_player_count(count: int) -> void:  # NEW
	expected_player_count = maxi(count, 1)
