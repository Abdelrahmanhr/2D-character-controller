extends Node
class_name BombController

signal player_finished_round

@export var bomb_time: float = 60.0
@export var device_id: int = 0  

var _time_left: float
var _active_minigame: Control = null
var _active_minigame_slot: Control = null
var _player: Node
var _expired := false

@onready var _minigame_layer: Control = $Minigamelayer
@onready var _bomb_timer_ui: ProgressBar = $BombTimerLayer/BombTimerUI

func _ready() -> void:
	_player = get_parent()
	_time_left = bomb_time
	_bomb_timer_ui.max_value = bomb_time
	_bomb_timer_ui.value = bomb_time
	_setup_bomb_timer_position()
	MinigameDirector.register_player(self)

func _setup_bomb_timer_position() -> void:
	if _player.name == "1":
		_bomb_timer_ui.anchor_left = 0.0
		_bomb_timer_ui.anchor_right = 0.0
		_bomb_timer_ui.offset_left = 24.0
		_bomb_timer_ui.offset_right = 204.0
		_bomb_timer_ui.offset_top = 24.0
		_bomb_timer_ui.offset_bottom = 47.0
	else:
		_bomb_timer_ui.anchor_left = 1.0
		_bomb_timer_ui.anchor_right = 1.0
		_bomb_timer_ui.offset_left = -204.0
		_bomb_timer_ui.offset_right = -24.0
		_bomb_timer_ui.offset_top = 24.0
		_bomb_timer_ui.offset_bottom = 47.0

func _exit_tree() -> void:
	MinigameDirector.unregister_player(self)

func _process(delta: float) -> void:
	if _player.is_multiplayer_authority() and not _expired:
		_time_left -= delta
		if _time_left <= 0.0:
			_on_bomb_expired()
	_bomb_timer_ui.value = clampf(_time_left, 0.0, bomb_time)
	if _minigame_layer:
		_minigame_layer.global_position = _player.global_position + Vector2(-100, -150)

func _unhandled_input(event: InputEvent) -> void:
	if _active_minigame == null or not _player.is_multiplayer_authority():
		return
	if event is InputEventJoypadButton and event.device == device_id:
		_active_minigame._handle_input(event)
	elif event is InputEventKey:
		_active_minigame._handle_input(event)

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

func play_minigame(scene: PackedScene, slot_index: int) -> void:
	if _expired or not _player.is_multiplayer_authority():
		return
	var slot := get_tree().current_scene.get_node_or_null("MinigameLayout/Layout/Slot%d" % slot_index)
	if slot == null:
		return
	_active_minigame = scene.instantiate()
	_active_minigame_slot = slot
	_active_minigame_slot.visible = true
	slot.add_child(_active_minigame)
	_active_minigame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_active_minigame.setup(_player)
	_active_minigame.correct_answer.connect(_on_correct_answer)
	_active_minigame.round_finished.connect(_on_minigame_finished)

func stop_minigame() -> void:
	if _active_minigame:
		_active_minigame.queue_free()
		_active_minigame = null
	if _active_minigame_slot:
		_active_minigame_slot.visible = false
		_active_minigame_slot = null

func _on_correct_answer(bonus_time: float) -> void:
	_time_left += bonus_time

func _on_minigame_finished() -> void:
	if _active_minigame == null:
		return
	stop_minigame()
	player_finished_round.emit()
