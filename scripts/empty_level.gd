extends Node2D

const PLAYER = preload("uid://dg4t5o3xnmwxn")

const LOSE_POPUP := preload("res://scenes/lose_popup.tscn")
const END_MENU := preload("res://scenes/end_menu.tscn")

var players: Array[CharacterBody2D]
var _spectate_overlay: CanvasLayer
var _end_menu: CanvasLayer
@onready var multiplayer_spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var match_result: Label = $MatchResult
@onready var background_sprite: Sprite2D = $background/Sprite2D

func _ready() -> void:
	$PauseMenu.process_mode = Node.PROCESS_MODE_ALWAYS
	get_viewport().size_changed.connect(_layout_viewport_content)
	_layout_viewport_content()
	MinigameDirector.reset_match()
	MinigameDirector.match_finished.connect(_on_match_finished)
	multiplayer_spawner.spawn_function = _spawn_player
	var death_zone := $DeathZone
	death_zone.body_entered.connect(_on_death_zone_body_entered)
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		if LocalPlayers.joined_devices.size() > 0:  # NEW
			_spawn_local_players()  # NEW: multiple local players from the lobby
		else:  # NEW
			_spawn_local_player()  # unchanged: fallback for solo testing without going through the lobby
	elif multiplayer.is_server():
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		for peer_id in multiplayer.get_peers():
			_spawn_player_for_peer(peer_id)
		_spawn_player_for_peer(multiplayer.get_unique_id())

func _layout_viewport_content() -> void:
	var viewport_size := get_viewport_rect().size
	var texture_size := background_sprite.texture.get_size()
	background_sprite.position = viewport_size / 2.0
	background_sprite.scale = Vector2.ONE * max(viewport_size.x / texture_size.x, viewport_size.y / texture_size.y)
	match_result.position = (viewport_size - match_result.size) / 2.0

func _is_networked() -> bool: 
	return multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)

func _on_death_zone_body_entered(body: Node) -> void:
	if body is CharacterBody2D and (not _is_networked() or body.is_multiplayer_authority()) and not body.is_dead:  # CHANGED
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
	elif multiplayer.multiplayer_peer is OfflineMultiplayerPeer:  # NEW: local multiplayer branch
		var winner_slot: int = winner_peer_id - 1  # NEW: player names are "1".."4" matching slot index+1
		var winner_color: Color = BombController.PLAYER_COLORS[clampi(winner_slot, 0, 3)]  # NEW
		title = "PLAYER %d WINS!" % winner_peer_id  # NEW
		color = winner_color  # NEW
	else:
		var local_peer_id := multiplayer.get_unique_id()  # CHANGED: moved inside this branch, only relevant for online
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
	player.position = $"spawn point".position
	add_child(player)
	players.append(player)


func _spawn_player_for_peer(peer_id: int) -> void:
	multiplayer_spawner.spawn(peer_id)


func _spawn_player(peer_id: Variant) -> Node:
	var player := PLAYER.instantiate() as CharacterBody2D
	player.name = str(peer_id)
	player.position = $"spawn point".position + Vector2(players.size() * 80.0, 0.0)
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

func _spawn_local_players() -> void:  # NEW
	var devices := LocalPlayers.joined_devices
	for i in devices.size():
		var device_id: int = devices[i]
		var player := PLAYER.instantiate() as CharacterBody2D
		player.name = str(i + 1)
		player.device_id = device_id
		player.position = $"spawn point".position + Vector2(i * 80.0, 0.0)

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
