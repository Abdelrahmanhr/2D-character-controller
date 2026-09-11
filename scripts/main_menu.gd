extends Control

const LOBBY_SCENE := "res://scenes/lobby.tscn"
const ARENA_SELECT_SCENE := "res://scenes/arena_select.tscn"
const LOCAL_LOBBY_SCENE := "res://scenes/local_lobby.tscn"
const CREDITS_SCENE := "res://scenes/credits.tscn"

var _joining := false


func _ready() -> void:
	MusicManager.play(preload("res://resources/audio/MAINMENUSOUNDTRACK.ogg"), false, false)
	$Menu/MultiplayerButton.pressed.connect(_on_multiplayer_pressed)
	$Menu/LocalMultiplayerButton.pressed.connect(_on_local_multiplayer_pressed)
	$Menu/CreditsButton.pressed.connect(_on_credits_pressed)
	$Menu/ExitButton.pressed.connect(_on_exit_pressed)
	Networking.client_joined.connect(_on_client_joined)
	Networking.join_pending.connect(_on_join_pending)
	Networking.lobby_failed.connect(_on_lobby_failed)
	if Networking.has_pending_join():
		_on_join_pending()


func _on_join_pending() -> void:
	_joining = true
	$Menu/MultiplayerButton.text = "Joining friend..."
	$Menu/MultiplayerButton.disabled = true


func _on_lobby_failed(_message: String) -> void:
	_joining = false
	$Menu/MultiplayerButton.text = "Multiplayer"
	$Menu/MultiplayerButton.disabled = false


func _on_client_joined() -> void:
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_multiplayer_pressed() -> void:
	if _joining:
		return
	get_tree().change_scene_to_file(ARENA_SELECT_SCENE)


func _on_local_multiplayer_pressed() -> void:
	get_tree().change_scene_to_file(LOCAL_LOBBY_SCENE)


func _on_credits_pressed() -> void:
	get_tree().change_scene_to_file(CREDITS_SCENE)


func _on_exit_pressed() -> void:
	Networking.leave_lobby()
	get_tree().quit()
