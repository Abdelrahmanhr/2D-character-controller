extends Label

@export var base_alpha: float = 1.0
@export var min_flicker_chance: float = 0.02
@export var flicker_min_duration: float = 0.03
@export var flicker_max_duration: float = 0.12
@export var flicker_dim_min: float = 0.15
@export var flicker_dim_max: float = 0.55
@export var double_flicker_chance: float = 0.35 
@export var flicker_sound: AudioStream
@export var flicker_sound_volume: float = -15.0
@export var flicker_sound_pitch_variance: float = 0.1

var _flicker_time_left: float = 0.0
var _flicker_target_alpha: float = 1.0
var _queued_flicker: bool = false

func _process(delta: float) -> void:
	if _flicker_time_left > 0.0:
		_flicker_time_left -= delta
		modulate.a = _flicker_target_alpha
		if _flicker_time_left <= 0.0:
			if _queued_flicker:
				_queued_flicker = false
				_start_flicker()
			else:
				modulate.a = base_alpha
	else:
		modulate.a = base_alpha
		if randf() < min_flicker_chance:
			_start_flicker()

func _start_flicker() -> void:
	_flicker_time_left = randf_range(flicker_min_duration, flicker_max_duration)
	_flicker_target_alpha = randf_range(flicker_dim_min, flicker_dim_max)
	if randf() < double_flicker_chance:
		_queued_flicker = true
	SfxManager.play(flicker_sound, flicker_sound_volume, flicker_sound_pitch_variance)
