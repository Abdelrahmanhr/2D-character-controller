extends Node
class_name BombController

signal player_finished_round

@export var bomb_time: float = 40.0
@export var device_id: int = 0  
@export var respawn_delay: float = 2.0  
@export var bonus_sounds: Array[AudioStream] = [] 
@export var bonus_pitch_variance: float = 0.15  
@export var max_lives: int = 5  
@export var respawn_invulnerability_duration: float = 1.5 
var _lives_remaining: int = 5 
@export var input_sound: AudioStream
@export var penalty_sound: AudioStream  
@export var minigame_complete_sound: AudioStream

@export var max_bomb_time: float = 60.0

var _time_left: float
var _active_minigame: Control = null
var _active_minigame_slot: Control = null
var _player: Node
var _expired := false

var _start_time_ms: int = 0
var _adjust_total: float = 0.0
var _running: bool = false
var _frozen_value: float = 0.0

const STICK_THRESHOLD: float = 0.5  

var _prev_stick_direction: String = ""

var time_left: float:
	get:
		return _compute_time_left()

@onready var _minigame_layer: Control = $Minigamelayer

func _ready() -> void:
	_player = get_parent()
	_time_left = bomb_time
	_frozen_value = bomb_time
	_lives_remaining = max_lives
	if _is_networked():
		Networking.bombs_start.connect(start_at)
	MinigameDirector.register_player(self)


func start_at(start_time_ms: int) -> void:
	_start_time_ms = start_time_ms
	_adjust_total = 0.0
	_expired = false
	_running = true
	_frozen_value = bomb_time
	set_process(true)


func _compute_time_left() -> float:
	if not _is_networked():
		return _time_left
	if not _running:
		return _frozen_value
	var elapsed: float = float(Networking.get_sync_time() - _start_time_ms) / 1000.0
	if elapsed < 0.0:
		elapsed = 0.0
	return clampf(bomb_time + _adjust_total - elapsed, 0.0, max_bomb_time)


func clamp_time_delta(seconds: float) -> float:
	var current: float = _compute_time_left()
	var target: float = minf(current + seconds, max_bomb_time)
	return target - current


func commit_time_delta(seconds: float) -> void:
	if _is_networked():
		_adjust_total += seconds
	else:
		_time_left = minf(_time_left + seconds, max_bomb_time)

func _exit_tree() -> void:
	MinigameDirector.unregister_player(self)

func _is_networked() -> bool:
	return multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)

func _has_authority() -> bool:
	return not _is_networked() or _player.is_multiplayer_authority()

func _process(delta: float) -> void:
	if _is_networked():
		if multiplayer.is_server() and _running and not _expired and _compute_time_left() <= 0.0:
			_running = false
			_frozen_value = 0.0
			_explode.rpc()
	elif not _expired:
		_time_left -= delta
		if _time_left <= 0.0:
			player_died("explode")  
	if _minigame_layer:
		_minigame_layer.global_position = _player.global_position + Vector2(-100, -150)
	_poll_right_stick()

func _input(event: InputEvent) -> void:
	if _active_minigame == null or not _has_authority() or _player.is_stunned:
		return
	if event is InputEventJoypadButton and (_is_networked() or event.device == device_id):
		var handled: bool = _active_minigame._handle_input(event)
		if handled:
			get_viewport().set_input_as_handled()
			SfxManager.play(input_sound,-13.0,0.1)
		_try_replicate_input(false, event.button_index)
	elif event is InputEventKey and (_is_networked() or _player.device_id == LocalPlayers.KEYBOARD_DEVICE_ID):
		var handled: bool = _active_minigame._handle_input(event)
		if event.pressed and not event.echo:
			if handled:
				get_viewport().set_input_as_handled()
				SfxManager.play(input_sound,-13.0,0.1)
			var key: int = event.keycode if event.keycode != KEY_NONE else event.physical_keycode
			_try_replicate_input(true, key)


func _poll_right_stick() -> void:
	if _active_minigame == null or not _has_authority() or _player.is_stunned:
		return
	
	var poll_device: int = device_id
	if _is_networked():
		var pads := Input.get_connected_joypads()
		if pads.is_empty():
			_prev_stick_direction = ""
			return
		poll_device = pads[0]
	elif device_id < 0:
		_prev_stick_direction = ""
		return
	
	var stick_x: float = PadState.get_axis(poll_device, JOY_AXIS_RIGHT_X)
	var stick_y: float = PadState.get_axis(poll_device, JOY_AXIS_RIGHT_Y)
	
	var current_direction: String = ""
	if abs(stick_x) > abs(stick_y):
		if stick_x > STICK_THRESHOLD:
			current_direction = "right"
		elif stick_x < -STICK_THRESHOLD:
			current_direction = "left"
	else:
		if stick_y > STICK_THRESHOLD:
			current_direction = "down"
		elif stick_y < -STICK_THRESHOLD:
			current_direction = "up"
	
	if current_direction != "" and current_direction != _prev_stick_direction:
		_submit_stick_direction(current_direction, poll_device)
	
	if current_direction == "":
		_prev_stick_direction = ""
	else:
		_prev_stick_direction = current_direction


func _submit_stick_direction(direction: String, source_device: int) -> void:
	var button: JoyButton
	match direction:
		"up": button = JOY_BUTTON_DPAD_UP
		"down": button = JOY_BUTTON_DPAD_DOWN
		"left": button = JOY_BUTTON_DPAD_LEFT
		"right": button = JOY_BUTTON_DPAD_RIGHT
		_: return
	
	var synthetic_event := InputEventJoypadButton.new()
	synthetic_event.device = source_device
	synthetic_event.button_index = button
	synthetic_event.pressed = true
	
	var handled: bool = _active_minigame._handle_input(synthetic_event)
	if handled:
		SfxManager.play(input_sound, -13.0, 0.1)
	_try_replicate_input(false, button)
@rpc("any_peer", "call_local", "reliable")
func _explode() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	_running = false
	_frozen_value = 0.0
	_do_player_died("explode")  


func detach_from_match() -> void:
	_running = false
	_frozen_value = _compute_time_left()
	if _is_networked() and Networking.bombs_start.is_connected(start_at):
		Networking.bombs_start.disconnect(start_at)


func reset_for_respawn() -> void:
	_expired = false
	_running = false
	_adjust_total = 0.0
	_time_left = bomb_time
	_frozen_value = bomb_time
	set_process(true)

func stop_timer() -> void:
	_frozen_value = _compute_time_left()
	_running = false
	set_process(false)



const PLAYER_COLORS: Array[Color] = [
	Color(1, 0.18, 0.22, 1),
	Color(1, 0.95, 0.15, 1),
	Color(0.2, 0.55, 1, 1),
	Color(0.15, 1, 0.4, 1),
]

func get_slot_index() -> int:
	var ids: Array[int] = []
	for node in get_tree().get_nodes_in_group("players"):
		ids.append(node.name.to_int())
	ids.sort()
	return clampi(ids.find(_player.name.to_int()), 0, 3)

func get_player_color() -> Color:
	return PLAYER_COLORS[get_slot_index()]

func play_minigame(scene: PackedScene, slot_index: int) -> void:
	if _expired or not _has_authority():
		return
	var scene_index: int = MinigameDirector.minigame_order.find(scene)
	if scene_index < 0:
		return
	var rng_seed: int = randi()
	if rng_seed == 0:
		rng_seed = 1
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		_show_minigame(slot_index, scene_index, rng_seed)
	else:
		_show_minigame.rpc(slot_index, scene_index, rng_seed)

func stop_minigame() -> void:
	if _has_authority() and _is_networked():
		_clear_minigame.rpc()
	else:
		_clear_minigame()

@rpc("any_peer", "call_local", "reliable")
func _show_minigame(slot_index: int, scene_index: int, rng_seed: int = 0) -> void:
	_clear_minigame()
	if _expired or scene_index < 0 or scene_index >= MinigameDirector.minigame_order.size():
		return
	var slot := get_tree().current_scene.get_node_or_null("MinigameLayout/Layout/Slot%d" % slot_index)
	if slot == null:
		return
	var scene: PackedScene = MinigameDirector.minigame_order[scene_index]
	_active_minigame = scene.instantiate()
	_active_minigame_slot = slot
	_active_minigame_slot.visible = true
	slot.add_child(_active_minigame)
	_active_minigame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_active_minigame.setup(_player, rng_seed)
	if _has_authority():
		_active_minigame.bomb_time_delta.connect(_on_bomb_time_delta)
		_active_minigame.round_finished.connect(_on_minigame_finished)

func _try_replicate_input(is_key: bool, code: int) -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return
	_replicate_minigame_input.rpc(is_key, code)

@rpc("any_peer", "reliable")
func _replicate_minigame_input(is_key: bool, code: int) -> void:
	if multiplayer.get_remote_sender_id() != _player.name.to_int():
		return
	if _active_minigame == null or _has_authority() or _player.is_stunned:
		return
	if is_key:
		var key_event := InputEventKey.new()
		key_event.pressed = true
		key_event.keycode = code as Key
		_active_minigame._handle_input(key_event)
	else:
		var pad_event := InputEventJoypadButton.new()
		pad_event.pressed = true
		pad_event.button_index = code as JoyButton
		_active_minigame._handle_input(pad_event)

@rpc("any_peer", "call_local", "reliable")
func _clear_minigame() -> void:
	if _active_minigame:
		_active_minigame.queue_free()
		_active_minigame = null
	if _active_minigame_slot:
		_active_minigame_slot.visible = false
		_active_minigame_slot = null


func _on_minigame_finished() -> void:
	if _active_minigame == null:
		return
	SfxManager.play(minigame_complete_sound,-10.0,0.2)
	stop_minigame()
	player_finished_round.emit()

func _on_bomb_time_delta(seconds: float) -> void:
	if seconds > 0.0:
		_play_bonus_sound()
	elif seconds < 0.0:
		SfxManager.play(penalty_sound,-15.0,0.2)
	if not _is_networked():
		commit_time_delta(seconds)
	elif multiplayer.is_server():
		Networking.apply_time_delta(_player.name.to_int(), seconds)
	else:
		Networking.report_time_delta(_player.name.to_int(), seconds)

func _play_bonus_sound() -> void:
	if bonus_sounds.is_empty():
		return
	var sound: AudioStream = bonus_sounds[randi() % bonus_sounds.size()]
	SfxManager.play(sound, -10.0, bonus_pitch_variance)


func player_died(cause: String = "fall") -> void:  # CHANGED: added cause param
	if _expired:
		return
	if not _is_networked():
		_do_player_died(cause)
	else:
		_do_player_died.rpc(cause)

@rpc("any_peer", "call_local", "reliable")
func _do_player_died(cause: String = "fall") -> void:  # CHANGED: added cause param
	if _expired:
		return
	_lives_remaining -= 1
	if _lives_remaining <= 0:
		eliminate_player(cause)  # CHANGED: pass cause through
	else:
		_respawn(cause)  # CHANGED: pass cause through

func eliminate_player(cause: String = "fall") -> void:  # CHANGED: added cause param
	if _expired:
		return
	_expired = true
	_running = false
	_frozen_value = 0.0
	set_process(false)
	stop_minigame()
	await _player.play_death_animation(cause)  # CHANGED: pass cause through
	MinigameDirector.player_eliminated(_player.name.to_int())
	if _has_authority():
		var scene := get_tree().current_scene
		if scene.has_method("show_lose_popup"):
			scene.show_lose_popup()

func _respawn(cause: String = "fall") -> void:  # CHANGED: added cause param
	set_process(false)
	_player.play_death_animation(cause)  # CHANGED: pass cause through
	stop_minigame()
	MinigameDirector.schedule_next_round(self)
	await get_tree().create_timer(respawn_delay).timeout
	if _expired:
		return
	if _is_networked():
		_start_time_ms = Networking.get_sync_time()
		_adjust_total = 0.0
		_running = true
		_frozen_value = bomb_time
	else:
		_time_left = bomb_time
	set_process(true)
	var scene := get_tree().current_scene
	if scene.has_method("respawn_player"):
		scene.respawn_player(_player)
	_player.respawn(respawn_invulnerability_duration)
	


func get_lives_remaining() -> int:  
	return _lives_remaining
