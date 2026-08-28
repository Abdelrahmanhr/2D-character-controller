extends Node2D

const PLAYER = preload("uid://dg4t5o3xnmwxn")

var players: Array[CharacterBody2D]
@onready var multiplayer_spawner: MultiplayerSpawner = $MultiplayerSpawner

func _ready() -> void:
	$PauseMenu.process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer_spawner.spawn_function = _spawn_player
	var death_zone := $DeathZone
	death_zone.body_entered.connect(_on_death_zone_body_entered)
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		_spawn_local_player()
	elif multiplayer.is_server():
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		for peer_id in multiplayer.get_peers():
			_spawn_player_for_peer(peer_id)
		_spawn_player_for_peer(multiplayer.get_unique_id())

func _on_death_zone_body_entered(body: Node) -> void:
	if body is CharacterBody2D and not body.is_dead:
		body.play_death_animation()
		print("Player fell!")

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
	for other in players:
		player.add_collision_exception_with(other)
		other.add_collision_exception_with(player)
	players.append(player)
	return player


func _on_peer_connected(peer_id: int) -> void:
	_spawn_player_for_peer(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	var player := get_node_or_null(str(peer_id))
	if player:
		players.erase(player)
		player.queue_free()
		print("Removed disconnected player %s" % peer_id)


func _on_host_pressed() -> void:
	Networking.host_lobby()
