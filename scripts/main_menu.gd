extends Control

const LOBBY_SCENE := "res://scenes/lobby.tscn"
const ARENA_SELECT_SCENE := "res://scenes/arena_select.tscn"
const LOCAL_LOBBY_SCENE := "res://scenes/local_lobby.tscn"
const CREDITS_SCENE := "res://scenes/credits.tscn"
const OPTIONS_MENU := preload("res://scenes/options_menu.tscn")

var _joining := false
var _options: Control


func _ready() -> void:
	get_tree().paused = false
	SceneTransition.boot_reveal()
	MusicManager.play_id(&"menu")
	$Menu/MultiplayerButton.pressed.connect(_on_multiplayer_pressed)
	$Menu/LocalMultiplayerButton.pressed.connect(_on_local_multiplayer_pressed)
	$Menu/CreditsButton.pressed.connect(_on_credits_pressed)
	$Menu/ExitButton.pressed.connect(_on_exit_pressed)
	Networking.client_joined.connect(_on_client_joined)
	Networking.join_pending.connect(_on_join_pending)
	Networking.lobby_failed.connect(_on_lobby_failed)
	_setup_options()
	if Networking.has_pending_join():
		_on_join_pending()


func _setup_options() -> void:
	_options = OPTIONS_MENU.instantiate()
	add_child(_options)
	_options.hide()
	_options.back_pressed.connect(_close_options)
	# There is no frame here the way there is in the pause menu, so the options
	# draw their own and centre themselves per page.
	_options.set_framed(true)

	var button: Button = $Menu/CreditsButton.duplicate(Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS)
	button.name = "OptionsButton"
	button.text = "OPTIONS"
	button.visible = true
	$Menu.add_child(button)
	$Menu.move_child(button, $Menu/CreditsButton.get_index() + 1)
	button.pressed.connect(_open_options)


func _unhandled_input(event: InputEvent) -> void:
	if not _options.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		# The options scene owns its own page stack; only close once it says it
		# has nothing left to back out of.
		if not _options.handle_cancel():
			_close_options()
		get_viewport().set_input_as_handled()


func _open_options() -> void:
	$Menu.hide()
	# The title sting occupies the upper half of the screen; the controls page is
	# tall enough to run into it.
	$Title.hide()
	_options.open()


func _close_options() -> void:
	_options.hide()
	$Title.show()
	$Menu.show()
	_cascade($Menu)


## The options scene animates its own pages; this is only for the menu list
## coming back after the options close.
func _cascade(page: Control) -> void:
	var elements: Array[Control] = []
	for child in page.get_children():
		if child is Control and child.visible:
			elements.append(child)
	UICascade.reset(elements)
	await get_tree().process_frame
	if is_inside_tree():
		UICascade.play(elements, 0.0, 0.055)


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


func _on_credits_pressed() -> void:
	get_tree().change_scene_to_file(CREDITS_SCENE)


func _on_exit_pressed() -> void:
	Networking.leave_lobby()
	get_tree().quit()

func _on_local_multiplayer_pressed() -> void:
	LocalPlayers.entering_arena_select_for_local = true  # NEW
	get_tree().change_scene_to_file(ARENA_SELECT_SCENE)

func _on_multiplayer_pressed() -> void:
	if _joining:
		return
	LocalPlayers.entering_arena_select_for_local = false  # NEW
	get_tree().change_scene_to_file(ARENA_SELECT_SCENE)
