extends Node
# Autoload as "MusicManager"
@export var default_volume_db: float = -20.0
@export var fade_in_duration: float = 0.5
@onready var player: AudioStreamPlayer = AudioStreamPlayer.new()
func _ready() -> void:
	player.bus = "Music"
	add_child(player)
func play(stream: AudioStream, restart_if_same: bool = false, fade_in: bool = true, target_volume_db: float = INF) -> void:  # CHANGED: added target_volume_db param — pass a specific dB value per call, or leave it unset to use default_volume_db
	var volume: float = default_volume_db if target_volume_db == INF else target_volume_db  # NEW: this line is what lets each call site pick its own volume
	if player.stream == stream and player.playing and not restart_if_same:
		return
	player.stream = stream
	if fade_in:
		player.volume_db = -80.0
		player.play()
		var tween := create_tween()
		tween.tween_property(player, "volume_db", volume, fade_in_duration)  # CHANGED: was "default_volume_db", now uses the resolved per-call "volume"
	else:
		player.volume_db = volume  # CHANGED: was "default_volume_db", now uses the resolved per-call "volume"
		player.play()
func stop() -> void:
	player.stop()
