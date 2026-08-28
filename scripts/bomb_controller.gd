extends Node
class_name BombController

signal player_finished_round

@export var bomb_time: float = 60.0
@export var device_id: int = 0  

var _time_left: float
var _active_minigame: Control = null
var _player: Node
var _expired := false

@onready var _minigame_layer: Control = $Minigamelayer
@onready var _bomb_timer_ui: Label = $BombTimerUI

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
	_bomb_timer_ui.text = "BOMB: %.1f" % max(_time_left, 0.0)
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
	if _expired:
		return
	_expired = true
	set_process(false)
	if _active_minigame:
		_active_minigame.queue_free()
		_active_minigame = null
	_player.play_death_animation()
	MinigameDirector.unregister_player(self)
	print("Player exploded!")

func play_minigame(scene: PackedScene) -> void:
	if _expired or not _player.is_multiplayer_authority():
		return
	_active_minigame = scene.instantiate()
	_minigame_layer.add_child(_active_minigame)
	_active_minigame.setup(_player)
	_active_minigame.correct_answer.connect(_on_correct_answer)
	_active_minigame.round_finished.connect(_on_minigame_finished)

func _on_correct_answer(bonus_time: float) -> void:
	_time_left += bonus_time

func _on_minigame_finished() -> void:
	if _active_minigame == null:
		return
	_active_minigame.queue_free()
	_active_minigame = null
	player_finished_round.emit()
