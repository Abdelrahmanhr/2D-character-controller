extends Node

signal countdown_tick(seconds_left: int)
signal match_started
signal match_finished(winner_peer_id: int)
signal alive_count_changed(alive: int, total: int)
signal input_locked_changed(locked: bool)

## Soft pause. A bitmask rather than a bool so that closing the pause menu can
## never unlock the input that the end of the match locked.
## Purely local presentation state - never RPC lock_input/unlock_input. The match
## end stays in sync for free because _finish_match is already "call_local".
const LOCK_MATCH_OVER := 1
const LOCK_MENU := 2
const LOCK_TUTORIAL := 4

@export var expected_player_count: int = 1
@export var countdown_duration: float = 3.0

var _countdown_left: float = 0.0
var _counting_down: bool = false

@export var minigame_order: Array[PackedScene] = []
@export var spawn_cooldown: float = 5.0

var auto_serve: bool = true

var _bomb_controllers: Array[BombController] = []
var _round_indices: Dictionary = {}
var _cooldowns: Dictionary = {}
var _alive_peer_ids: Dictionary = {}
var _total_players: int = 0
var _match_finished := false
var _pending_start_ms: int = 0
var _lock_mask: int = 0
var _lock_started_ms: int = -1
var _paused_accum_ms: int = 0

## End-of-match stats. Keyed by the same player.name.to_int() identifier
## _alive_peer_ids/winner_peer_id already use (peer_id online, slot+1 couch).
## Populated by record_match_stats, called from BombController._report_kill - the
## same already-networked call site the kill feed reads from - so this can never
## drift out of sync with what the kill feed showed during the match.
var _match_start_ms: int = -1
var _match_end_ms: int = -1
var _kill_counts: Dictionary = {}
var _survival_end_ms: Dictionary = {}
## Time a player spent dead, so survival time can measure time actually spent
## alive in the arena rather than raw match-start-to-elimination wall time.
## _dead_ms banks finished death->respawn windows; _death_started_ms holds the
## one currently open, if any.
var _dead_ms: Dictionary = {}
var _death_started_ms: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Networking.match_begin.connect(_on_match_begin)
	Networking.bombs_start.connect(_on_bombs_start)


func _on_match_begin(expected_count: int) -> void:
	set_expected_player_count(expected_count)
	_match_finished = false
	_pending_start_ms = 0
	if multiplayer.is_server():
		_begin_countdown()


func _on_bombs_start(start_time_ms: int) -> void:
	_counting_down = false
	_countdown_left = 0.0
	_pending_start_ms = start_time_ms


func get_registered_count() -> int:
	return _bomb_controllers.size()


func is_counting_down() -> bool:
	return _counting_down


func is_match_finished() -> bool:
	return _match_finished

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
	_pending_start_ms = 0
	_lock_mask = 0
	_lock_started_ms = -1
	_paused_accum_ms = 0
	auto_serve = true
	_match_start_ms = -1
	_match_end_ms = -1
	_kill_counts.clear()
	_survival_end_ms.clear()
	_dead_ms.clear()
	_death_started_ms.clear()

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

	if _is_offline() and _bomb_controllers.size() >= expected_player_count and not _counting_down and not _match_finished:
		_begin_countdown()


func _is_offline() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer

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
	if not auto_serve:
		return
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
	if Networking.is_leaving:
		return
	if multiplayer.is_server():
		# Stamped here too since a disconnect never goes through
		# BombController.eliminate_player - without this the departed player's row
		# would wrongly read as "survived to the end". A disconnect is inherently
		# final, same as running out of lives, so this uses record_elimination
		# rather than the per-life-lost record_match_stats.
		record_elimination(peer_id)
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
	# Captured before lock_input below freezes get_hazard_time_ms(), so this is the
	# live moment the match actually ended - every surviving player's stats row
	# uses this as their end time (see get_survival_seconds).
	_match_end_ms = get_hazard_time_ms()
	_match_finished = true
	_counting_down = false
	_cooldowns.clear()
	for bomb_controller in _bomb_controllers.duplicate():
		if is_instance_valid(bomb_controller):
			bomb_controller.stop_minigame()
			bomb_controller.stop_timer()
	lock_input(LOCK_MATCH_OVER)
	match_finished.emit(winner_peer_id)


func is_input_locked() -> bool:
	return _lock_mask != 0


## Used by the pause menu for the offline soft pause. Never resumes a bomb once
## the match is over - those are frozen for good.
func set_timers_frozen(frozen: bool) -> void:
	if not frozen and _match_finished:
		return
	for bomb_controller in _bomb_controllers:
		if not is_instance_valid(bomb_controller):
			continue
		if frozen:
			bomb_controller.stop_timer()
		else:
			bomb_controller.resume_timer()


func lock_input(reason: int) -> void:
	var was_locked := _lock_mask != 0
	_lock_mask |= reason
	if not was_locked:
		_lock_started_ms = _raw_time_ms()
		input_locked_changed.emit(true)


func unlock_input(reason: int) -> void:
	var was_locked := _lock_mask != 0
	_lock_mask &= ~reason
	if was_locked and _lock_mask == 0:
		if _lock_started_ms >= 0:
			_paused_accum_ms += _raw_time_ms() - _lock_started_ms
			_lock_started_ms = -1
		input_locked_changed.emit(false)


func _raw_time_ms() -> int:
	# Called every frame from several arena systems now (see get_hazard_time_ms),
	# including during app-quit teardown when this autoload's own get_multiplayer()
	# can transiently go null -- guard the same way arena_base.gd's _is_networked
	# does rather than crashing mid-shutdown.
	if is_inside_tree() and multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		return Networking.get_sync_time()
	return Time.get_ticks_msec()


## Wall-clock timestamp that freezes for the duration of any active input lock
## (couch pause, match over) instead of counting through it. Arena hazards that
## key their scheduling/movement off this (safe zone shrink, lightning strike
## timing, electrify hazard windows, pickup lifetime) stop advancing while
## input is locked rather than silently resolving behind a paused menu, and
## pick up exactly where they left off once unlocked. LOCK_MENU is only ever
## set for the offline soft pause (see pause_menu.gd), so online play never
## triggers this freeze.
func get_hazard_time_ms() -> int:
	if _lock_mask != 0 and _lock_started_ms >= 0:
		return _lock_started_ms - _paused_accum_ms
	return _raw_time_ms() - _paused_accum_ms

func _process(delta: float) -> void:
	if _match_finished:
		return

	if _pending_start_ms != 0:
		if Networking.get_sync_time() >= _pending_start_ms:
			_pending_start_ms = 0
			_match_start_ms = get_hazard_time_ms()
			match_started.emit()
			_start_rounds()
		return

	if _counting_down:
		var prev_second := ceili(_countdown_left)
		_countdown_left -= delta
		var new_second := ceili(_countdown_left)
		if new_second != prev_second and new_second >= 0:
			countdown_tick.emit(new_second)
		if _countdown_left <= 0.0:
			_counting_down = false
			if _is_offline():
				_match_start_ms = get_hazard_time_ms()
				match_started.emit()
				_start_rounds()
			else:
				Networking.broadcast_bomb_start()
		return

	if not auto_serve:
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


func set_expected_player_count(count: int) -> void:
	expected_player_count = maxi(count, 1)

func force_start() -> void:
	if not _is_offline() and not multiplayer.is_server():
		return
	if not _counting_down and not _match_finished:
		_begin_countdown()

func schedule_next_round(bomb_controller: BombController) -> void:
	if _cooldowns.has(bomb_controller):
		_cooldowns[bomb_controller] = spawn_cooldown


## Records a kill for the kill count, if credited. Called from the same
## already-networked BombController._report_kill the kill feed reads from, on
## every life lost (not just a final elimination) - so it runs identically on
## every peer for free, no RPC of its own. victim_key/killer_key are
## player.name.to_int() identifiers; killer_key defaults to -1 for an
## uncredited/environmental death.
func record_match_stats(victim_key: int, killer_key: int = -1) -> void:
	if killer_key >= 0 and killer_key != victim_key:
		_kill_counts[killer_key] = int(_kill_counts.get(killer_key, 0)) + 1


## Stamps survival time. Called only once a player is actually eliminated (out
## of lives) or disconnects - NOT on every respawn-causing death - so "survival
## time" measures match-start to when they were fully out, not to their first
## lost life.
func record_elimination(player_key: int) -> void:
	if player_key >= 0 and not _survival_end_ms.has(player_key):
		_survival_end_ms[player_key] = get_hazard_time_ms()


## Opens a dead window. Called the instant a player dies, for the last life as
## well as a respawning one, so the death animation and the respawn delay both
## fall outside time-alive. Idempotent: a second death cannot reopen a window
## that is already open and lose the original start.
func record_death_start(player_key: int) -> void:
	if player_key < 0 or _death_started_ms.has(player_key):
		return
	_death_started_ms[player_key] = get_hazard_time_ms()


## Closes the window record_death_start opened and banks how long it ran.
func record_respawn(player_key: int) -> void:
	if player_key < 0 or not _death_started_ms.has(player_key):
		return
	var started: int = int(_death_started_ms[player_key])
	_death_started_ms.erase(player_key)
	_dead_ms[player_key] = int(_dead_ms.get(player_key, 0)) + maxi(get_hazard_time_ms() - started, 0)


func get_kill_count(player_key: int) -> int:
	return int(_kill_counts.get(player_key, 0))


## Time actually spent alive in the arena: match start to elimination (or to
## match end for a survivor), minus every death->respawn window in between.
func get_survival_seconds(player_key: int) -> float:
	if _match_start_ms < 0:
		return 0.0
	var fallback_end: int = _match_end_ms if _match_end_ms >= 0 else get_hazard_time_ms()
	var end_ms: int = int(_survival_end_ms.get(player_key, fallback_end))
	var dead_ms: int = int(_dead_ms.get(player_key, 0))
	# A window still open at end_ms was never banked by record_respawn. For an
	# eliminated player that window opened at their death, which is end_ms, so
	# this adds nothing; it only matters for someone still mid-respawn when the
	# match ended, whose wait would otherwise count as time alive.
	if _death_started_ms.has(player_key):
		dead_ms += maxi(end_ms - int(_death_started_ms[player_key]), 0)
	return maxf(float(end_ms - _match_start_ms - dead_ms) / 1000.0, 0.0)


## Every player.name.to_int() worth showing a stats row for: currently registered
## players plus anyone who's already recorded a kill or a death (covers a player
## who was unregistered - e.g. freed on disconnect - after their stats landed).
func get_tracked_player_keys() -> Array:
	var keys: Dictionary = {}
	for bomb_controller in _bomb_controllers:
		if is_instance_valid(bomb_controller):
			keys[bomb_controller.get_parent().name.to_int()] = true
	for k in _kill_counts.keys():
		keys[k] = true
	for k in _survival_end_ms.keys():
		keys[k] = true
	return keys.keys()
