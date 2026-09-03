extends Node2D

@export var ghost_color: Color = Color(0.4, 0.8, 1.0, 0.9) 
@export var fade_time: float = 0.45                
@export var interval: float = 0.02                     

var _sprite: AnimatedSprite2D
var _timer: float = 0.0
var _active: bool = false

func _ready() -> void:
	_sprite = get_parent().get_node("AnimatedSprite2D")

func start() -> void:
	_active = true
	_timer = 0.0

func stop() -> void:
	_active = false

func _process(delta: float) -> void:
	if not _active:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = interval
		_spawn_ghost()

func _spawn_ghost() -> void:
	var ghost := Sprite2D.new()
	ghost.texture = _sprite.sprite_frames.get_frame_texture(_sprite.animation, _sprite.frame)
	ghost.global_position = _sprite.global_position
	ghost.flip_h = _sprite.flip_h
	ghost.scale = _sprite.scale
	ghost.modulate = ghost_color
	ghost.z_index = -1 
	get_tree().current_scene.add_child(ghost)
	var tween := ghost.create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, fade_time)

	tween.tween_callback(ghost.queue_free)
