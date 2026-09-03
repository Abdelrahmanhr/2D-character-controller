extends Node2D

const PLAYER = preload("uid://dg4t5o3xnmwxn")

const LOSE_POPUP := preload("res://scenes/lose_popup.tscn")
const END_MENU := preload("res://scenes/end_menu.tscn")

var players: Array[CharacterBody2D]
var _spectate_overlay: CanvasLayer
var _end_menu: CanvasLayer
var _solo_test_mode := false
var _self_player: CharacterBody2D
var _dummy_players: Array[CharacterBody2D] = []

const DUMMY_NAMES: Array[String] = ["901", "902", "903"]
const DUMMY_DEVICE_IDS: Array[int] = [0, 1, 2]
@onready var multiplayer_spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var match_result: Label = $MatchResult
@onready var spawn_points: Array[Node2D] = [$SpawnPoint1, $SpawnPoint2, $SpawnPoint3, $SpawnPoint4]

func _ready() -> void:
	MusicManager.play(preload("res://resources/audio/ARENA SOUNDTRACK.ogg"), false, true, -25.0)  
	$PauseMenu.process_mode = Node.PROCESS_MODE_ALWAYS
	get_viewport().size_changed.connect(_layout_viewport_content)
	_layout_viewport_content()
	MinigameDirector.reset_match()
	MinigameDirector.match_finished.connect(_on_match_finished)
	multiplayer_spawner.spawn_function = _spawn_player
	var death_zone := $DeathBox
	death_zone.body_entered.connect(_on_death_zone_body_entered)
	var death_box := $DeathBox
	death_box.body_entered.connect(_on_death_zone_body_entered)
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		if LocalPlayers.joined_devices.size() > 0:
			_spawn_local_players()
		else:
			_spawn_local_player()
	elif multiplayer.is_server():
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		for peer_id in multiplayer.get_peers():
			_spawn_player_for_peer(peer_id)
		_spawn_player_for_peer(multiplayer.get_unique_id())
		MinigameDirector.force_start()
		if multiplayer.get_peers().is_empty():
			_solo_test_mode = true
			process_mode = Node.PROCESS_MODE_ALWAYS
			_self_player = get_node_or_null(str(multiplayer.get_unique_id())) as CharacterBody2D
			_spawn_dummy_players()
			MinigameDirector.match_finished.connect(_on_solo_match_finished)

func _layout_viewport_content() -> void:
	var viewport_size := get_viewport_rect().size
	match_result.position = (viewport_size - match_result.size) / 2.0

func _is_networked() -> bool: 
	return multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)

func _on_death_zone_body_entered(body: Node) -> void:
	if body is CharacterBody2D and (not _is_networked() or body.is_multiplayer_authority()) and not body.is_dead:
		body.get_node("BombController").eliminate_player()
		print("Player fell!")

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
		color = Color(1, 0.95, 0.15, 1)
	elif multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		var winner_slot: int = winner_peer_id - 1
		var winner_color: Color = BombController.PLAYER_COLORS[clampi(winner_slot, 0, 3)]
		title = "PLAYER %d WINS!" % winner_peer_id
		color = winner_color
	else:
		var local_peer_id := multiplayer.get_unique_id()
		if winner_peer_id == local_peer_id:
			title = "YOU WIN"
			color = Color(0.15, 1, 0.4, 1)
		else:
			title = "YOU LOSE"
			color = Color(1, 0.18, 0.22, 1)
	
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


func _spawn_player_for_peer(peer_id: int) -> void:
	multiplayer_spawner.spawn(peer_id)


func _spawn_player(peer_id: Variant) -> Node:
	var player := PLAYER.instantiate() as CharacterBody2D
	player.name = str(peer_id)
	player.position = spawn_points[players.size() % spawn_points.size()].position
	for other in players.duplicate():
		if not is_instance_valid(other) or not other is PhysicsBody2D:
			players.erase(other)
			continue
		player.add_collision_exception_with(other)
		other.add_collision_exception_with(player)
	players.append(player)
	return player


func _on_peer_connected(peer_id: int) -> void:
	_spawn_player_for_peer(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	MinigameDirector.player_disconnected(peer_id)
	var player := get_node_or_null(str(peer_id))
	if player:
		players.erase(player)
		player.queue_free()
		print("Removed disconnected player %s" % peer_id)


func _on_host_pressed() -> void:
	Networking.host_lobby()

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

func _spawn_dummy_players() -> void:
	var dummy_root := Node.new()
	dummy_root.name = "DummyPlayers"
	add_child(dummy_root)
	for i in DUMMY_NAMES.size():
		var dummy := PLAYER.instantiate() as CharacterBody2D
		dummy.name = DUMMY_NAMES[i]
		dummy.device_id = DUMMY_DEVICE_IDS[i]
		dummy.position = spawn_points[(i + 1) % spawn_points.size()].position
		for other in players:
			dummy.add_collision_exception_with(other)
			other.add_collision_exception_with(dummy)
		for other in _dummy_players:
			dummy.add_collision_exception_with(other)
			other.add_collision_exception_with(dummy)
		dummy_root.add_child(dummy)
		dummy.set_multiplayer_authority(multiplayer.get_unique_id())
		var bomb_controller: Node = dummy.get_node("BombController")
		bomb_controller.device_id = DUMMY_DEVICE_IDS[i]
		bomb_controller.stop_timer()
		MinigameDirector.unregister_player(bomb_controller)
		_dummy_players.append(dummy)

func _on_solo_match_finished(_winner_peer_id: int) -> void:
	call_deferred("_solo_post_match_respawn")

func _solo_post_match_respawn() -> void:
	get_tree().paused = false
	if _end_menu:
		_end_menu.queue_free()
		_end_menu = null
	_respawn_self()

func _unhandled_key_input(event: InputEvent) -> void:
	if not _solo_test_mode:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		get_tree().paused = false
		if _end_menu:
			_end_menu.queue_free()
			_end_menu = null
		_respawn_self()

func _respawn_self() -> void:
	if _self_player == null or not is_instance_valid(_self_player):
		return
	_self_player.velocity = Vector2.ZERO
	_self_player.global_position = spawn_points[0].global_position
	_self_player.is_dead = false
	_self_player.is_stunned = false
	_self_player.stun_time_left = 0.0
	_self_player.is_dashing = false
	_self_player.dash_time_left = 0.0
	_self_player.is_frozen = false
	_self_player.freeze_time_left = 0.0
	var bomb_controller: Node = _self_player.get_node("BombController")
	bomb_controller._expired = false
	bomb_controller._time_left = bomb_controller.bomb_time
	bomb_controller.set_process(true)
	MinigameDirector.reset_match()
	MinigameDirector.register_player(bomb_controller)
