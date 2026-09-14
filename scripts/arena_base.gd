extends Node2D
class_name ArenaBase

const PLAYER = preload("uid://dg4t5o3xnmwxn")

const LOSE_POPUP := preload("res://scenes/lose_popup.tscn")
const END_MENU := preload("res://scenes/end_menu.tscn")

var players: Array[CharacterBody2D]
var _spectate_overlay: CanvasLayer
var _end_menu: CanvasLayer

@export var safe_zone_event_interval_min: float = 5.0  # NEW
@export var safe_zone_event_interval_max: float = 10.0  # NEW
@export var safe_zone_active_duration: float = 20.0  # NEW
@export var safe_zone_start_radius: float = 1200.0  # NEW
@export var safe_zone_end_radius: float = 220.0  # NEW
@export var safe_zone_gravity_multiplier: float = 0.6  # NEW
@export var safe_zone_outside_death_time: float = 3.0  # NEW
@export var safe_zone_hold_duration: float = 10.0  # NEW

var _active_zone: SafeZone = null  # NEW
var _active_zone_spawn_index: int = -1  # NEW
var _next_zone_event_ms: int = -1  # NEW

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
	MinigameDirector.match_started.connect(_on_match_started_for_zone)  # NEW
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


func _process(delta: float) -> void:  # NEW
	_update_safe_zone_schedule()


func _is_zone_authority() -> bool:  # NEW
	return not _is_networked() or multiplayer.is_server()


func _get_timestamp() -> int:  # NEW
	if _is_networked():
		return Networking.get_sync_time()
	return Time.get_ticks_msec()


func _on_match_started_for_zone() -> void:  # NEW
	if _is_zone_authority():
		_schedule_next_zone_event()


func _schedule_next_zone_event() -> void:  # NEW
	var wait: float = randf_range(safe_zone_event_interval_min, safe_zone_event_interval_max)
	_next_zone_event_ms = _get_timestamp() + int(wait * 1000.0)


func _update_safe_zone_schedule() -> void:  # NEW
	if not _is_zone_authority():
		return
	if _active_zone != null or _next_zone_event_ms < 0:
		return
	if _get_timestamp() >= _next_zone_event_ms:
		var index: int = randi() % spawn_points.size()
		if _is_networked():
			_start_safe_zone_event.rpc(index)
		else:
			_start_safe_zone_event(index)


@rpc("authority", "call_local", "reliable")
func _start_safe_zone_event(spawn_index: int) -> void:
	if spawn_index < 0 or spawn_index >= spawn_points.size():
		return
	var zone := SafeZone.new()
	zone.name = "SafeZoneEvent"
	zone.z_index = 10
	zone.global_position = spawn_points[spawn_index].global_position
	zone.start_radius = safe_zone_start_radius
	zone.end_radius = safe_zone_end_radius
	zone.shrink_duration = safe_zone_active_duration
	zone.hold_duration = safe_zone_hold_duration  
	zone.outer_gravity_multiplier = safe_zone_gravity_multiplier
	zone.outside_death_time = safe_zone_outside_death_time
	add_child(zone)
	zone.expired.connect(_on_safe_zone_expired)
	zone.activate()
	_active_zone = zone
	_active_zone_spawn_index = spawn_index


func _on_safe_zone_expired() -> void:  # NEW
	_active_zone = null
	_active_zone_spawn_index = -1
	if _is_zone_authority():
		_schedule_next_zone_event()


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
	var target_index: int  # NEW
	if _active_zone != null and _active_zone_spawn_index >= 0:  # NEW: respawn at the event's location while it's active
		target_index = _active_zone_spawn_index  # NEW
	else:  # NEW
		target_index = player.get_node("BombController").get_slot_index()  # CHANGED: was inlined directly below
	player.global_position = spawn_points[target_index % spawn_points.size()].global_position
