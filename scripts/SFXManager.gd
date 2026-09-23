extends Node
# Autoload as "SFXManager"

@export var pool_size: int = 8

var _players: Array[AudioStreamPlayer] = []
var _next_player_index: int = 0

func _ready() -> void:
	for i in pool_size:
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		_players.append(player)

func play(stream: AudioStream, volume_db: float = 0.0, pitch_variance: float = 0.0, pitch_shift: float = 1.0) -> void:
	if stream == null:
		return
	var player := _players[_next_player_index]
	_next_player_index = (_next_player_index + 1) % _players.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_shift + randf_range(-pitch_variance, pitch_variance)
	player.play()
