extends Control
const EMPTY_LEVEL_SCENE := "res://scenes/empty_level.tscn"
const LOBBY_SCENE := "res://scenes/lobby.tscn"
const LOCAL_LOBBY_SCENE := "res://scenes/local_lobby.tscn"
const CREDITS_SCENE := "res://scenes/credits.tscn"

func _ready() -> void:
	MusicManager.play(preload("res://resources/audio/MAINMENUSOUNDTRACK.ogg"), false, false)
	$Menu/StartButton.pressed.connect(_on_start_pressed)
	$Menu/MultiplayerButton.pressed.connect(_on_multiplayer_pressed)
	$Menu/LocalMultiplayerButton.pressed.connect(_on_local_multiplayer_pressed) 
	$Menu/CreditsButton.pressed.connect(_on_credits_pressed)
	$Menu/ExitButton.pressed.connect(_on_exit_pressed)
	Networking.client_joined.connect(_on_client_joined)


func _on_client_joined() -> void:
	get_tree().change_scene_to_file(LOBBY_SCENE)

func _on_start_pressed() -> void:
	SceneTransition.circle_to(EMPTY_LEVEL_SCENE)

func _on_multiplayer_pressed() -> void:
	get_tree().change_scene_to_file(LOBBY_SCENE)

func _on_local_multiplayer_pressed() -> void: 
	get_tree().change_scene_to_file(LOCAL_LOBBY_SCENE)

func _on_credits_pressed() -> void:
	get_tree().change_scene_to_file(CREDITS_SCENE)

func _on_exit_pressed() -> void:
	get_tree().quit()
