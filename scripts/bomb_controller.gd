extends Node
class_name BombController

signal player_finished_round

@export var bomb_time: float = 40.0
@export var device_id: int = 0  

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

func _process(delta: float) -> void:
	if _player.is_multiplayer_authority() and not _expired:
		_time_left -= delta
		if _time_left <= 0.0:
			_on_bomb_expired()
	if _minigame_layer:
		_minigame_layer.global_position = _player.global_position + Vector2(-100, -150)

func _input(event: InputEvent) -> void:
	if _active_minigame == null or not _player.is_multiplayer_authority():
		return
	if event is InputEventJoypadButton and event.device == device_id:
		_active_minigame._handle_input(event)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		_active_minigame._handle_input(event)
		get_viewport().set_input_as_handled()

func _on_bomb_expired() -> void:
	eliminate_player()
	print("Player exploded!")

func eliminate_player() -> void:
	if _expired:
		return
	_expired = true
	set_process(false)
	stop_minigame()
	_player.play_death_animation()
	MinigameDirector.player_eliminated(_player.name.to_int())

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
	if _expired or not _player.is_multiplayer_authority():
		return
	var scene_index: int = MinigameDirector.minigame_order.find(scene)
	if scene_index < 0:
		return
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		_show_minigame(slot_index, scene_index)
	else:
		_show_minigame.rpc(slot_index, scene_index)

func stop_minigame() -> void:
	if _player.is_multiplayer_authority() and multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		_clear_minigame.rpc()
	else:
		_clear_minigame()

@rpc("any_peer", "call_local", "reliable")
func _show_minigame(slot_index: int, scene_index: int) -> void:
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
	_active_minigame.setup(_player)
	if _player.is_multiplayer_authority():
		_active_minigame.bomb_time_delta.connect(_on_bomb_time_delta)
		_active_minigame.round_finished.connect(_on_minigame_finished)

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
	stop_minigame()
	player_finished_round.emit()

func _on_bomb_time_delta(seconds: float) -> void:
	_time_left += seconds
