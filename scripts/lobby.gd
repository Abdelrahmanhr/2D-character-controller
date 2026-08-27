extends Control

@onready var host_button: Button = $Panel/HostButton
@onready var start_button: Button = $Panel/StartButton
@onready var status_label: Label = $Panel/Status


func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	start_button.pressed.connect(_on_start_pressed)
	start_button.disabled = true
	Networking.lobby_ready.connect(_on_lobby_ready)
	Networking.lobby_failed.connect(_on_lobby_failed)
	Networking.client_joined.connect(_on_client_joined)


func _on_host_pressed() -> void:
	host_button.disabled = true
	status_label.text = "Creating lobby..."
	Networking.host_lobby()


func _on_start_pressed() -> void:
	Networking.start_game()


func _on_lobby_ready(is_host: bool) -> void:
	if is_host:
		status_label.text = "Lobby created. Invite a friend, then start."
		start_button.disabled = false
	else:
		status_label.text = "Joined lobby. Waiting for host..."


func _on_client_joined() -> void:
	status_label.text = "Joined lobby. Waiting for host..."


func _on_lobby_failed(message: String) -> void:
	host_button.disabled = false
	status_label.text = message
