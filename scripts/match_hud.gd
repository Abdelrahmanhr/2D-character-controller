extends CanvasLayer

@onready var bomb_bar: ProgressBar = $Header/TimerBlock/BombBar
@onready var bomb_time_label: Label = $Header/TimerBlock/BombTime
@onready var alive_label: Label = $Header/AliveBlock/AliveRow/AliveCount

var _local_bomb: BombController

func _ready() -> void:
	MinigameDirector.alive_count_changed.connect(_on_alive_count_changed)
	_on_alive_count_changed(MinigameDirector.get_alive_count(), MinigameDirector.get_total_players())

func _process(_delta: float) -> void:
	if _local_bomb == null or not is_instance_valid(_local_bomb):
		_local_bomb = _find_local_bomb()
	if _local_bomb == null:
		return
	var max_time: float = maxf(_local_bomb.bomb_time, 0.001)
	var time_left: float = clampf(_local_bomb.time_left, 0.0, max_time)
	bomb_bar.max_value = max_time
	bomb_bar.value = time_left
	bomb_time_label.text = "%.1f" % time_left
	var urgency := clampf(time_left / max_time, 0.0, 1.0)
	if urgency < 0.25:
		bomb_bar.modulate = Color(1.0, 0.35, 0.1, 1.0)
	elif urgency < 0.5:
		bomb_bar.modulate = Color(1.0, 0.7, 0.15, 1.0)
	else:
		bomb_bar.modulate = Color(1.0, 0.95, 0.2, 1.0)

func _find_local_bomb() -> BombController:
	for node in get_tree().get_nodes_in_group("players"):
		if node is CharacterBody2D and node.is_multiplayer_authority():
			return node.get_node_or_null("BombController") as BombController
	return null

func _on_alive_count_changed(alive: int, total: int) -> void:
	var shown_total: int = maxi(total, alive)
	alive_label.text = "%d / %d" % [alive, shown_total]
