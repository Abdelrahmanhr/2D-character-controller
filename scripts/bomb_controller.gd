extends Node
class_name BombController

signal player_finished_round

@export var bomb_time: float = 40.0
@export var device_id: int = 0  
@export var bonus_sounds: Array[AudioStream] = [] 
@export var bonus_pitch_variance: float = 0.15  
@export var input_sound: AudioStream
@export var penalty_sound: AudioStream  
@export var minigame_complete_sound: AudioStream

@export var max_bomb_time: float = 60.0  # 

var _time_left: float
var _active_minigame: Control = null
var _active_minigame_slot: Control = null
var _player: Node
var _expired := false

var time_left: float:
	get:
		return _time_left

@onready var _minigame_layer: Control = $Minigamelayer

func _ready() -> void:
	_player = get_parent()
	_time_left = bomb_time
	MinigameDirector.register_player(self)

func _exit_tree() -> void:
	MinigameDirector.unregister_player(self)

func _is_networked() -> bool:  # NEW
	return multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)

func _has_authority() -> bool:  # NEW
	return not _is_networked() or _player.is_multiplayer_authority()

func _process(delta: float) -> void:
	if _has_authority() and not _expired:  # CHANGED: was "_player.is_multiplayer_authority()"
		_time_left -= delta
		if _time_left <= 0.0:
			_on_bomb_expired()
	if _minigame_layer:
		_minigame_layer.global_position = _player.global_position + Vector2(-100, -150)

func _input(event: InputEvent) -> void:
	if _active_minigame == null or not _has_authority() or _player.is_stunned:  # CHANGED
		return
	if event is InputEventJoypadButton and event.device == device_id:
		var handled: bool = _active_minigame._handle_input(event)
		get_viewport().set_input_as_handled()
		if event.pressed:
			if handled:
				SfxManager.play(input_sound,-13.0,0.1)
			_try_replicate_input(false, event.button_index)
	elif event is InputEventKey and _player.device_id == LocalPlayers.KEYBOARD_DEVICE_ID:  # CHANGED: added device_id check
		var handled: bool = _active_minigame._handle_input(event)
		get_viewport().set_input_as_handled()
		if event.pressed and not event.echo:
			if handled:
				SfxManager.play(input_sound,-13.0,0.1)
			var key: int = event.keycode if event.keycode != KEY_NONE else event.physical_keycode
			_try_replicate_input(true, key)

func _on_bomb_expired() -> void:
	eliminate_player()
	print("Player exploded!")

func stop_timer() -> void:
	set_process(false)

func eliminate_player() -> void:
	if _expired:
		return
	_expired = true
	set_process(false)
	stop_minigame()
	await _player.play_death_animation()
	MinigameDirector.player_eliminated(_player.name.to_int())
	if _has_authority():  # CHANGED: was "_player.is_multiplayer_authority()"
		var scene := get_tree().current_scene
		if scene.has_method("show_lose_popup"):
			scene.show_lose_popup()

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
	if _expired or not _has_authority():  # CHANGED
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
	if _has_authority() and _is_networked():  # CHANGED: was "_player.is_multiplayer_authority() and multiplayer.multiplayer_peer != null and not (...)"
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
	if _has_authority():  # CHANGED: was "_player.is_multiplayer_authority()"
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
	if _active_minigame == null or _has_authority() or _player.is_stunned:  # CHANGED: was "_player.is_multiplayer_authority()"
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
	_time_left = minf(_time_left + seconds, max_bomb_time)

func _play_bonus_sound() -> void:
	if bonus_sounds.is_empty():
		return
	var sound: AudioStream = bonus_sounds[randi() % bonus_sounds.size()]
	SfxManager.play(sound, -10.0, bonus_pitch_variance)
