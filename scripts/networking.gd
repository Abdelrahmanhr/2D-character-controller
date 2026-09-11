extends Node

signal lobby_ready(is_host: bool)
signal lobby_failed(message: String)
signal client_joined()
signal arena_updated(display_name: String)
signal peers_changed(peer_count: int)
signal disconnected(message: String)
signal join_pending()
signal arena_spawn_requested(slots: Dictionary)
signal match_begin(expected_count: int)
signal bombs_start(start_time_ms: int)

const LOBBY_TYPE := Steam.LobbyType.LOBBY_TYPE_FRIENDS_ONLY
const MAX_MEMBERS := 4
const DEFAULT_ARENA_SCENE := "res://scenes/power_station.tscn"
const DEFAULT_ARENA_NAME := "Power Station"
const ARENA_READY_TIMEOUT := 8.0
const CLOCK_SAMPLE_COUNT := 5
const CLOCK_PING_INTERVAL := 5.0
const CLOCK_WARMUP_INTERVAL := 0.25
const BOMB_START_LEAD_MS := 250
const LOBBY_CREATE_TIMEOUT := 10.0
const MAX_VIRTUAL_PORT := 64
const LOBBY_VPORT_KEY := "vport"

var peer: SteamMultiplayerPeer
var selected_arena_path: String = DEFAULT_ARENA_SCENE
var selected_arena_name: String = DEFAULT_ARENA_NAME
var current_lobby_id: int = 0
var is_host: bool = false
var is_leaving: bool = false
var pending_lobby_id: int = 0
var _create_pending: bool = false
var _abandon_create: bool = false
var _create_timeout_left: float = 0.0
var _next_vport: int = 0
var _active_vport: int = 0

var _ready_acks: Dictionary = {}
var _expected_acks: Array[int] = []
var _awaiting_acks: bool = false
var _ack_timeout_left: float = 0.0
var _assigned_slots: Dictionary = {}

var _clock_offset: int = 0
var _clock_samples: Array[int] = []
var _last_rtt: int = 0
var _ping_timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Steam.lobby_created.connect(on_lobby_created)
	Steam.lobby_joined.connect(on_lobby_joined)
	Steam.join_requested.connect(on_join_requested)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	if SteamManager.is_initialized:
		_on_steam_initialized(true, "")
	else:
		SteamManager.initialized.connect(_on_steam_initialized)


func _on_steam_initialized(success: bool, _message: String) -> void:
	if not success:
		return
	Steam.initRelayNetworkAccess()
	var launch_lobby := _read_launch_lobby_id()
	if launch_lobby != 0:
		pending_lobby_id = launch_lobby
		NetDebug.log_event("launch invite lobby %d" % launch_lobby)
		call_deferred("_consume_pending_join")


func _read_launch_lobby_id() -> int:
	for i in OS.get_cmdline_args().size():
		var arg: String = OS.get_cmdline_args()[i]
		if arg == "+connect_lobby" and i + 1 < OS.get_cmdline_args().size():
			return OS.get_cmdline_args()[i + 1].to_int()
		if arg.begins_with("+connect_lobby="):
			return arg.split("=", true, 1)[1].to_int()
	var launch_line: String = str(Steam.getLaunchCommandLine())
	var parts := launch_line.split(" ", false)
	for i in parts.size():
		if parts[i] == "+connect_lobby" and i + 1 < parts.size():
			return parts[i + 1].to_int()
	return 0


func _consume_pending_join() -> void:
	if pending_lobby_id == 0:
		return
	var lobby_id := pending_lobby_id
	pending_lobby_id = 0
	join_pending.emit()
	join_lobby(lobby_id)


func has_pending_join() -> bool:
	return pending_lobby_id != 0


func set_arena(path: String, display_name: String) -> void:
	selected_arena_path = path
	selected_arena_name = display_name


func leave_lobby() -> void:
	is_leaving = true
	if _create_pending:
		_abandon_create = true
	_reset_peer()
	if current_lobby_id != 0 and SteamManager.is_initialized:
		Steam.leaveLobby(current_lobby_id)
	current_lobby_id = 0
	is_host = false
	MinigameDirector.reset_match()
	NetDebug.set_ack_target(0)
	peers_changed.emit(0)
	is_leaving = false


func _reset_peer() -> void:
	_awaiting_acks = false
	_ready_acks.clear()
	_expected_acks.clear()
	_assigned_slots.clear()
	_reset_clock()
	if peer != null:

		if multiplayer.multiplayer_peer == peer and multiplayer.is_server():
			for id in multiplayer.get_peers():
				peer.disconnect_peer(id, true)
		NetDebug.log_event("closing peer, status %d" % peer.get_connection_status())
		peer.close()
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	peer = null


func host_lobby() -> void:
	if not SteamManager.is_initialized:
		lobby_failed.emit("Steam is not initialized. Restart Steam, then reopen the editor.")
		return
	if _create_pending:
		# Steam has not answered the previous createLobby yet. Bail out and let the
		# UI re-enable Host rather than stacking a second request.
		NetDebug.log_event("host_lobby ignored, create already pending")
		lobby_failed.emit("Still finishing the previous lobby request. Try again in a moment.")
		return
	leave_lobby()
	if not await _settle_steam():
		lobby_failed.emit("Steam is not initialized.")
		return
	_create_pending = true
	_abandon_create = false
	_create_timeout_left = LOBBY_CREATE_TIMEOUT
	NetDebug.log_event("creating lobby")
	Steam.createLobby(LOBBY_TYPE, MAX_MEMBERS)


func join_lobby(lobby_id: int) -> void:
	if not SteamManager.is_initialized:
		lobby_failed.emit("Steam is not initialized.")
		return
	leave_lobby()
	if not await _settle_steam():
		lobby_failed.emit("Steam is not initialized.")
		return
	NetDebug.log_event("requesting join %d" % lobby_id)
	Steam.joinLobby(lobby_id)

func _settle_steam() -> bool:
	await get_tree().create_timer(0.3).timeout
	return SteamManager.is_initialized

func _open_host_peer() -> SteamMultiplayerPeer:
	for _attempt in MAX_VIRTUAL_PORT:
		var vport := _next_vport
		_next_vport = (_next_vport + 1) % MAX_VIRTUAL_PORT
		var candidate := SteamMultiplayerPeer.new()
		candidate.server_relay = true
		var err: int = candidate.create_host(vport)
		if err == OK and candidate.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
			_active_vport = vport
			NetDebug.log_event("host listening on vport %d" % vport)
			return candidate
		NetDebug.log_event("create_host vport %d failed, err %d" % [vport, err])

		candidate.close()
	return null


func on_lobby_created(connect_result: int, lobby_id: int) -> void:
	_create_pending = false
	_create_timeout_left = 0.0
	if connect_result != Steam.RESULT_OK:
		_abandon_create = false
		NetDebug.log_event("createLobby failed, result %d" % connect_result)
		lobby_failed.emit("Could not create lobby.")
		return
	if _abandon_create:
		# The player backed out while the create was in flight. Drop the lobby
		# instead of leaking it, and leave the offline peer in place.
		_abandon_create = false
		NetDebug.log_event("abandoning lobby %d, host cancelled" % lobby_id)
		Steam.leaveLobby(lobby_id)
		return
	var host_peer := _open_host_peer()
	if host_peer == null:
		NetDebug.log_event("no virtual port could be opened for hosting")
		Steam.leaveLobby(lobby_id)
		current_lobby_id = 0
		is_host = false
		lobby_failed.emit("Could not open the host connection. Restart the game and try again.")
		return
	peer = host_peer
	multiplayer.multiplayer_peer = peer
	current_lobby_id = lobby_id
	is_host = true

	Steam.setLobbyData(lobby_id, LOBBY_VPORT_KEY, str(_active_vport))
	NetDebug.log_event("lobby created %d on vport %d" % [lobby_id, _active_vport])
	lobby_ready.emit(true)
	peers_changed.emit(0)


func on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		NetDebug.log_event("lobby_joined failed, response %d" % response)
		lobby_failed.emit("Could not join lobby.")
		return
	var owner_id: int = Steam.getLobbyOwner(lobby_id)
	if _create_pending or is_host or owner_id == Steam.getSteamID():
		# Our own lobby echoing back. on_lobby_created owns the host peer.
		current_lobby_id = lobby_id
		return

	var vport_text: String = str(Steam.getLobbyData(lobby_id, LOBBY_VPORT_KEY))
	var vport: int = vport_text.to_int() if not vport_text.is_empty() else 0
	var client_peer := SteamMultiplayerPeer.new()
	client_peer.server_relay = true
	var err: int = client_peer.create_client(owner_id, vport)
	if err != OK or client_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		NetDebug.log_event("create_client vport %d failed, err %d" % [vport, err])
		client_peer.close()
		Steam.leaveLobby(lobby_id)
		current_lobby_id = 0
		lobby_failed.emit("Could not connect to the host.")
		return
	peer = client_peer
	multiplayer.multiplayer_peer = peer
	current_lobby_id = lobby_id
	is_host = false
	NetDebug.log_event("joining lobby %d owner %d vport %d" % [lobby_id, owner_id, vport])


func on_join_requested(lobby_id: int, _steam_id: int) -> void:
	NetDebug.log_event("join_requested %d" % lobby_id)
	join_lobby(lobby_id)


func _on_connected_to_server() -> void:
	NetDebug.log_event("connected to server as %d" % multiplayer.get_unique_id())
	_reset_clock()
	_send_ping()
	lobby_ready.emit(false)
	client_joined.emit()
	peers_changed.emit(multiplayer.get_peers().size())


func _on_connection_failed() -> void:
	NetDebug.log_event("connection failed")
	leave_lobby()
	lobby_failed.emit("Could not connect to the host.")


func _on_server_disconnected() -> void:
	NetDebug.log_event("server disconnected")
	leave_lobby()
	disconnected.emit("The host left the game.")


func _on_peer_connected(id: int) -> void:
	NetDebug.log_event("peer connected %d" % id)
	if multiplayer.is_server():
		_receive_arena.rpc_id(id, selected_arena_path, selected_arena_name)
	peers_changed.emit(multiplayer.get_peers().size())


func _on_peer_disconnected(id: int) -> void:
	NetDebug.log_event("peer disconnected %d" % id)
	_ready_acks.erase(id)
	_expected_acks.erase(id)
	peers_changed.emit(multiplayer.get_peers().size())
	if _awaiting_acks:
		_check_acks_complete()


@rpc("authority", "reliable")
func _receive_arena(path: String, display_name: String) -> void:
	selected_arena_path = path
	selected_arena_name = display_name
	arena_updated.emit(display_name)


func get_sync_time() -> int:
	return Time.get_ticks_msec() + _clock_offset


func get_clock_offset() -> int:
	return _clock_offset


func get_last_rtt() -> int:
	return _last_rtt


func is_clock_ready() -> bool:
	return multiplayer.is_server() or not _clock_samples.is_empty()


func _reset_clock() -> void:
	_clock_offset = 0
	_clock_samples.clear()
	_last_rtt = 0
	_ping_timer = 0.0


func _send_ping() -> void:
	if not is_connected_online() or multiplayer.is_server():
		return
	_ping.rpc_id(1, Time.get_ticks_msec())


@rpc("any_peer", "reliable")
func _ping(client_ms: int) -> void:
	if not multiplayer.is_server():
		return
	_pong.rpc_id(multiplayer.get_remote_sender_id(), client_ms, Time.get_ticks_msec())


@rpc("authority", "reliable")
func _pong(client_ms: int, host_ms: int) -> void:
	var now := Time.get_ticks_msec()
	_last_rtt = now - client_ms
	var sample: int = host_ms - (client_ms + _last_rtt / 2)
	_clock_samples.append(sample)
	if _clock_samples.size() > CLOCK_SAMPLE_COUNT:
		_clock_samples.remove_at(0)
	var sorted := _clock_samples.duplicate()
	sorted.sort()
	_clock_offset = sorted[sorted.size() / 2]


func is_connected_online() -> bool:
	return multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)


func get_peer_count() -> int:
	if not is_connected_online():
		return 0
	return multiplayer.get_peers().size()


func start_game() -> void:
	if not multiplayer.is_server():
		return
	_expected_acks.clear()
	_ready_acks.clear()
	_assigned_slots.clear()
	var slot := 0
	_assigned_slots[multiplayer.get_unique_id()] = slot
	_expected_acks.append(multiplayer.get_unique_id())
	for peer_id in multiplayer.get_peers():
		slot += 1
		_assigned_slots[peer_id] = slot
		_expected_acks.append(peer_id)
	_awaiting_acks = true
	_ack_timeout_left = ARENA_READY_TIMEOUT
	NetDebug.set_ack_target(_expected_acks.size())
	NetDebug.log_event("start_game, awaiting %d acks" % _expected_acks.size())
	_load_arena.rpc(selected_arena_path)


@rpc("authority", "call_local", "reliable")
func _load_arena(arena_path: String) -> void:
	SceneTransition.circle_to(arena_path)


func notify_arena_ready() -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return
	var delay := NetDebug.get_ready_delay()
	if delay > 0.0:
		NetDebug.log_event("delaying arena ack by %.1fs" % delay)
		await get_tree().create_timer(delay).timeout
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return
	NetDebug.log_event("arena ready ack -> host")
	_arena_ready.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _arena_ready() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	_ready_acks[sender] = true
	NetDebug.set_ack_count(_ready_acks.size())
	NetDebug.log_event("ack from %d (%d/%d)" % [sender, _ready_acks.size(), _expected_acks.size()])
	_check_acks_complete()


func _check_acks_complete() -> void:
	if not _awaiting_acks:
		return
	for peer_id in _expected_acks:
		if not _ready_acks.has(peer_id):
			return
	_dispatch_spawns()


func _dispatch_spawns() -> void:
	if not _awaiting_acks:
		return
	_awaiting_acks = false
	var slots: Dictionary = {}
	for peer_id in _expected_acks:
		if _ready_acks.has(peer_id):
			slots[peer_id] = _assigned_slots.get(peer_id, slots.size())
	NetDebug.log_event("dispatching spawns for %s" % str(slots.keys()))
	arena_spawn_requested.emit(slots)
	_begin_match.rpc(slots.size())


func broadcast_bomb_start() -> void:
	if not multiplayer.is_server():
		return
	var start_time_ms: int = get_sync_time() + BOMB_START_LEAD_MS
	NetDebug.log_event("bomb start at host t=%d" % start_time_ms)
	_start_bombs.rpc(start_time_ms)


@rpc("authority", "call_local", "reliable")
func _start_bombs(start_time_ms: int) -> void:
	bombs_start.emit(start_time_ms)


func report_time_delta(peer_id: int, seconds: float) -> void:
	_request_time_delta.rpc_id(1, peer_id, seconds)


@rpc("any_peer", "reliable")
func _request_time_delta(peer_id: int, seconds: float) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	apply_time_delta(peer_id, seconds)


func apply_time_delta(peer_id: int, seconds: float) -> void:
	if not multiplayer.is_server():
		return
	var bomb := _find_bomb(peer_id)
	if bomb == null:
		return
	var effective: float = bomb.clamp_time_delta(seconds)
	if is_equal_approx(effective, 0.0):
		return
	_commit_time_delta.rpc(peer_id, effective)


@rpc("authority", "call_local", "reliable")
func _commit_time_delta(peer_id: int, seconds: float) -> void:
	var bomb := _find_bomb(peer_id)
	if bomb:
		bomb.commit_time_delta(seconds)


func _find_bomb(peer_id: int) -> BombController:
	for node in get_tree().get_nodes_in_group("players"):
		if node.name.to_int() == peer_id:
			return node.get_node_or_null("BombController") as BombController
	return null


@rpc("authority", "call_local", "reliable")
func _begin_match(expected_count: int) -> void:
	NetDebug.log_event("match begin, expected %d" % expected_count)
	MinigameDirector.set_expected_player_count(expected_count)
	match_begin.emit(expected_count)


func _process(delta: float) -> void:
	if _create_pending:
		_create_timeout_left -= delta
		if _create_timeout_left <= 0.0:
			_create_pending = false
			_abandon_create = false
			NetDebug.log_event("createLobby timed out, no callback from Steam")
			lobby_failed.emit("Steam never answered the lobby request. Try again.")
	if is_connected_online() and not multiplayer.is_server():
		_ping_timer -= delta
		if _ping_timer <= 0.0:
			_ping_timer = CLOCK_WARMUP_INTERVAL if _clock_samples.size() < CLOCK_SAMPLE_COUNT else CLOCK_PING_INTERVAL
			_send_ping()
	if not _awaiting_acks:
		return
	_ack_timeout_left -= delta
	if _ack_timeout_left <= 0.0:
		NetDebug.log_event("ack timeout, proceeding with %d/%d" % [_ready_acks.size(), _expected_acks.size()])
		_dispatch_spawns()


func restart_game() -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		get_tree().paused = false
		get_tree().reload_current_scene()
	elif multiplayer.is_server():
		get_tree().paused = false
		_unpause.rpc()
		start_game()
	else:
		_request_restart.rpc_id(1)


@rpc("authority", "reliable")
func _unpause() -> void:
	get_tree().paused = false


@rpc("any_peer", "reliable")
func _request_restart() -> void:
	if multiplayer.is_server():
		restart_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		leave_lobby()
