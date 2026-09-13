extends Node2D
class_name ArenaBase

const PLAYER = preload("uid://dg4t5o3xnmwxn")

const LOSE_POPUP := preload("res://scenes/lose_popup.tscn")
const END_MENU := preload("res://scenes/end_menu.tscn")

var players: Array[CharacterBody2D]
var _spectate_overlay: CanvasLayer
var _end_menu: CanvasLayer

@onready var multiplayer_spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var match_result: Label = $MatchResult
@onready var spawn_points: Array[Node2D] = [$SpawnPoint1, $SpawnPoint2, $SpawnPoint3, $SpawnPoint4]


func _ready() -> void:
	_set_global_parallax_active(false)
	MusicManager.play(preload("res://resources/audio/ARENA SOUNDTRACK.ogg"), false, true, -25.0)
	$PauseMenu.process_mode = Node.PROCESS_MODE_ALWAYS
	get_viewport().size_changed.connect(_layout_viewport_content)
	_layout_viewport_content()
	MinigameDirector.reset_match()
	MinigameDirector.match_finished.connect(_on_match_finished)
	_setup_minigame_screens()
	multiplayer_spawner.spawn_function = _spawn_player
	$DeathBox.body_entered.connect(_on_death_zone_body_entered)

	if not _is_networked():
		if LocalPlayers.joined_devices.size() > 0:
			_spawn_local_players()
		else:
			_spawn_local_player()
		return

	Networking.arena_spawn_requested.connect(_on_arena_spawn_requested)
	Networking.disconnected.connect(_on_disconnected)
	if multiplayer.is_server():
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	Networking.notify_arena_ready()


func _exit_tree() -> void:
	_set_global_parallax_active(true)


# Every arena draws its own LocalParallax, so the GlobalParallax autoload sitting at
# layer -10 underneath it is 15 full-screen quads of pure overdraw, repositioned
# every frame. Park it for the duration of the match.
func _set_global_parallax_active(active: bool) -> void:
	var global_parallax := get_node_or_null("/root/GlobalParallax") as CanvasLayer
	if global_parallax == null:
		return
	global_parallax.visible = active
	global_parallax.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED


func _on_arena_spawn_requested(slots: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	for peer_id in slots.keys():
		multiplayer_spawner.spawn({"peer": int(peer_id), "slot": int(slots[peer_id])})


func _setup_minigame_screens() -> void:
	var layout := get_node_or_null("MinigameLayout/Layout")
	if layout == null:
		return
	var screens := MinigameScreens.new()
	screens.name = "MinigameScreens"
	add_child(screens)
	screens.build(layout)
	MinigameDirector.match_started.connect(screens.play_entrance)


func _on_disconnected(message: String) -> void:
	NetDebug.log_event("returned to menu: %s" % message)
	get_tree().paused = false
	MinigameDirector.reset_match()
	get_tree().call_deferred("change_scene_to_file", "res://scenes/main_menu.tscn")


func _layout_viewport_content() -> void:
	var viewport_size := get_viewport_rect().size
	match_result.position = (viewport_size - match_result.size) / 2.0


func _is_networked() -> bool:
	return multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)


func _on_death_zone_body_entered(body: Node) -> void:
	if body is CharacterBody2D and not body.is_dead:
		_play_death_zone_zap(body.global_position)
	if body is CharacterBody2D and (not _is_networked() or body.is_multiplayer_authority()) and not body.is_dead:
		body.get_node("BombController").player_died() 


@export var death_zap_sound: AudioStream
@export var death_zap_volume_db: float = -6.0


func _play_death_zone_zap(at: Vector2) -> void:
	if death_zap_sound:
		SfxManager.play(death_zap_sound, death_zap_volume_db, 0.12)
	var rail := get_tree().get_first_node_in_group("lightning_emitters")
	if rail and rail.has_method("strike_global"):
		rail.strike_global(Vector2(at.x, rail.global_position.y), at)
	var cam := get_viewport().get_camera_2d()
	if cam and cam.has_method("shake"):
		cam.shake(14.0)


func show_lose_popup() -> void:
	if _spectate_overlay or _end_menu:
		return
	_spectate_overlay = LOSE_POPUP.instantiate()
	add_child(_spectate_overlay)


func _on_match_finished(winner_peer_id: int) -> void:
	if _spectate_overlay:
		_spectate_overlay.queue_free()
		_spectate_overlay = null
	var title: String
	var color: Color

	if winner_peer_id == 0:
		title = "DRAW"
		color = Color(1, 0.8784, 0.5686, 1)
	elif not _is_networked():
		var winner_slot: int = winner_peer_id - 1
		var winner_color: Color = BombController.PLAYER_COLORS[clampi(winner_slot, 0, 3)]
		title = "PLAYER %d WINS!" % winner_peer_id
		color = winner_color
	else:
		if winner_peer_id == multiplayer.get_unique_id():
			title = "YOU WIN"
			color = Color(0.549, 1, 0.6078, 1)
		else:
			title = "YOU LOSE"
			color = Color(1, 0.4118, 0.3529, 1)

	get_tree().paused = true
	_end_menu = END_MENU.instantiate()
	add_child(_end_menu)
	_end_menu.set_result(title, color)


func _spawn_local_player() -> void:
	var player := PLAYER.instantiate() as CharacterBody2D
	player.name = "1"
	player.position = spawn_points[0].position
	add_child(player)
	players.append(player)


func _spawn_player(data: Variant) -> Node:
	var peer_id: int = int(data["peer"])
	var slot: int = int(data["slot"])
	var player := PLAYER.instantiate() as CharacterBody2D
	player.name = str(peer_id)
	player.position = spawn_points[slot % spawn_points.size()].position
	for other in players.duplicate():
		if not is_instance_valid(other) or not other is PhysicsBody2D:
			players.erase(other)
			continue
		player.add_collision_exception_with(other)
		other.add_collision_exception_with(player)
	players.append(player)
	return player


func _on_peer_disconnected(peer_id: int) -> void:
	MinigameDirector.player_disconnected(peer_id)
	var player := get_node_or_null(str(peer_id))
	if player:
		players.erase(player)
		player.queue_free()


func _spawn_local_players() -> void:
	var devices := LocalPlayers.joined_devices
	for i in devices.size():
		var device_id: int = devices[i]
		var player := PLAYER.instantiate() as CharacterBody2D
		player.name = str(i + 1)
		player.device_id = device_id
		player.position = spawn_points[i % spawn_points.size()].position

		for other in players.duplicate():
			if not is_instance_valid(other) or not other is PhysicsBody2D:
				players.erase(other)
				continue
			player.add_collision_exception_with(other)
			other.add_collision_exception_with(player)

		add_child(player)
		var bomb_controller: Node = player.get_node("BombController")
		bomb_controller.device_id = device_id
		players.append(player)


func respawn_player(player: CharacterBody2D) -> void:  
	var slot_index: int = player.get_node("BombController").get_slot_index()
	player.global_position = spawn_points[slot_index % spawn_points.size()].global_position
