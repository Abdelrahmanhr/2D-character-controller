extends Node

signal lobby_ready(is_host: bool)
signal lobby_failed(message: String)
signal client_joined()

const LOBBY_TYPE := Steam.LobbyType.LOBBY_TYPE_FRIENDS_ONLY
const MAX_MEMBERS := 4

var peer: SteamMultiplayerPeer

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


func host_lobby() -> void:
	if not SteamManager.is_initialized:
		lobby_failed.emit("Steam is not initialized. Restart Steam, then reopen the editor.")
		return
	# Will cause the "lobby_created" and "lobby_joined" signals to emit
	Steam.createLobby(LOBBY_TYPE, MAX_MEMBERS)


# Called after creating a lobby locally
func on_lobby_created(connect: int, lobby_id: int) -> void:
	# We created the lobby, so we act as server host
	if connect == Steam.RESULT_OK:
		peer = SteamMultiplayerPeer.new()
		peer.server_relay = true
		peer.create_host()
		multiplayer.multiplayer_peer = peer
		lobby_ready.emit(true)
	else:
		lobby_failed.emit("Could not create lobby.")


# Called when joining a lobby (after creating the lobby or joining a friend)
func on_lobby_joined(lobby_id: int, permissions: int, locked: bool, response: int) -> void:
	if response == Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		# If we created the lobby, we are already hosting, so we should not create a new client peer
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


# Called when attempting to join from the Steam interface
func on_join_requested(lobby_id: int, steam_id: int) -> void:
	# Will cause the "lobby_joined" signal to emit
	Steam.joinLobby(lobby_id)


func start_game() -> void:
	if multiplayer.is_server():
		_start_game.rpc()

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
func _start_game() -> void:
	get_tree().change_scene_to_file("res://scenes/empty_level.tscn")
