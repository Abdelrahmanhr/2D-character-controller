extends Control

@onready var host_button: Button = $Panel/HostButton
@onready var start_button: Button = $Panel/StartButton
@onready var status_label: Label = $Panel/Status
@onready var back_button: Button = $BackButton

var _players_label: Label


func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	start_button.pressed.connect(_on_start_pressed)
	back_button.pressed.connect(_exit_game)
	start_button.disabled = true

	_players_label = Label.new()
	_players_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_players_label.add_theme_color_override("font_color", Color(0.545098, 0.670588, 0.74902, 1))
	$Panel.add_child(_players_label)
	$Panel.move_child(_players_label, status_label.get_index())

	Networking.lobby_ready.connect(_on_lobby_ready)
	Networking.lobby_failed.connect(_on_lobby_failed)
	Networking.client_joined.connect(_on_client_joined)
	Networking.arena_updated.connect(_on_arena_updated)
	Networking.peers_changed.connect(_on_peers_changed)
	Networking.disconnected.connect(_on_disconnected)

	# Only trust is_host when a live peer actually backs it. A stale flag with no
	# peer used to render a "Lobby created" screen stuck at 0/4 with Host disabled.
	if Networking.is_host and Networking.is_connected_online():
		_on_lobby_ready(true)
	else:
		host_button.disabled = false
	_refresh_players()


func _on_host_pressed() -> void:
	host_button.disabled = true
	status_label.text = "Creating lobby..."
	Networking.host_lobby()


func _on_start_pressed() -> void:
	start_button.disabled = true
	status_label.text = "Loading arena, waiting for players..."
	Networking.start_game()


func _exit_game() -> void:
	get_tree().paused = false
	Networking.leave_lobby()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_lobby_ready(is_host: bool) -> void:
	if is_host:
		if not Networking.is_connected_online():
			_on_lobby_failed("Lobby created but the host connection did not open. Try hosting again.")
			return
		host_button.disabled = true
		status_label.text = "Lobby created. Invite a friend via the Steam overlay. Arena: %s" % Networking.selected_arena_name
	else:
		host_button.disabled = true
		status_label.text = "Joined lobby. Waiting for host..."
	_refresh_players()


func _on_client_joined() -> void:
	status_label.text = "Joined lobby. Waiting for host..."
	_refresh_players()


func _on_arena_updated(display_name: String) -> void:
	status_label.text = "Joined lobby. Arena: %s. Waiting for host..." % display_name


func _on_peers_changed(_peer_count: int) -> void:
	_refresh_players()


func _on_disconnected(message: String) -> void:
	status_label.text = message
	start_button.disabled = true
	host_button.disabled = false
	_refresh_players()


func _refresh_players() -> void:
	var total: int = 0
	if Networking.is_connected_online():
		total = Networking.get_peer_count() + 1
	_players_label.text = "Players: %d/%d" % [total, Networking.MAX_MEMBERS]
	if not Networking.is_host:
		start_button.disabled = true
		return
	var can_start: bool = Networking.get_peer_count() >= 1 or NetDebug.allow_solo_start
	start_button.disabled = not can_start
	if not can_start:
		start_button.text = "Waiting for players..."
	else:
		start_button.text = "Start"


func _on_lobby_failed(message: String) -> void:
	host_button.disabled = false
	start_button.disabled = true
	status_label.text = message
	_refresh_players()
