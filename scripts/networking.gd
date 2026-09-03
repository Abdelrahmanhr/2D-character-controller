extends Node

signal lobby_ready(is_host: bool)
signal lobby_failed(message: String)
signal client_joined()
signal arena_updated(display_name: String)

const LOBBY_TYPE := Steam.LobbyType.LOBBY_TYPE_FRIENDS_ONLY
const MAX_MEMBERS := 4
const DEFAULT_ARENA_SCENE := "res://scenes/power_station.tscn"
const DEFAULT_ARENA_NAME := "Power Station"

var peer: SteamMultiplayerPeer
var selected_arena_path: String = DEFAULT_ARENA_SCENE
var selected_arena_name: String = DEFAULT_ARENA_NAME

func _ready() -> void:
	Steam.lobby_created.connect(on_lobby_created)
	Steam.lobby_joined.connect(on_lobby_joined)
	Steam.join_requested.connect(on_join_requested)
	if SteamManager.is_initialized:
		Steam.initRelayNetworkAccess()
	else:
		SteamManager.initialized.connect(_on_steam_initialized)


func _on_steam_initialized(success: bool, _message: String) -> void:
	if success:
		Steam.initRelayNetworkAccess()


func set_arena(path: String, display_name: String) -> void:
	selected_arena_path = path
	selected_arena_name = display_name

func host_lobby() -> void:
	if not SteamManager.is_initialized:
		lobby_failed.emit("Steam is not initialized. Restart Steam, then reopen the editor.")
		return
	Steam.createLobby(LOBBY_TYPE, MAX_MEMBERS)

func on_lobby_created(connect: int, lobby_id: int) -> void:
	if connect == Steam.RESULT_OK:
		peer = SteamMultiplayerPeer.new()
		peer.server_relay = true
		peer.create_host()
		multiplayer.multiplayer_peer = peer
		multiplayer.peer_connected.connect(_on_host_peer_connected)
		lobby_ready.emit(true)
	else:
		lobby_failed.emit("Could not create lobby.")

func _on_host_peer_connected(id: int) -> void:
	_receive_arena.rpc_id(id, selected_arena_path, selected_arena_name)

@rpc("authority", "reliable")
func _receive_arena(path: String, display_name: String) -> void:
	selected_arena_path = path
	selected_arena_name = display_name
	arena_updated.emit(display_name)

func on_lobby_joined(lobby_id: int, permissions: int, locked: bool, response: int) -> void:
	if response == Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		if Steam.getLobbyOwner(lobby_id) == Steam.getSteamID():
			return
		peer = SteamMultiplayerPeer.new()
		peer.server_relay = true
		peer.create_client(Steam.getLobbyOwner(lobby_id))
		multiplayer.multiplayer_peer = peer
		lobby_ready.emit(false)
		client_joined.emit()
	else:
		lobby_failed.emit("Could not join lobby.")

func on_join_requested(lobby_id: int, steam_id: int) -> void:
	Steam.joinLobby(lobby_id)


func start_game() -> void:
	if multiplayer.is_server():
		_start_game.rpc(selected_arena_path)

func restart_game() -> void:
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		_restart_game()
	elif multiplayer.is_server():
		_restart_game.rpc()
	else:
		_request_restart.rpc_id(1)

@rpc("any_peer", "reliable")
func _request_restart() -> void:
	if multiplayer.is_server():
		_restart_game.rpc()

@rpc("authority", "call_local", "reliable")
func _restart_game() -> void:
	get_tree().reload_current_scene()


@rpc("authority", "call_local", "reliable")
func _start_game(arena_path: String) -> void:
	SceneTransition.circle_to(arena_path)
