extends Control

const LOBBY_SCENE := "res://scenes/lobby.tscn"
const ARENA_SELECT_SCENE := "res://scenes/arena_select.tscn"
const LOCAL_LOBBY_SCENE := "res://scenes/local_lobby.tscn"
const CREDITS_SCENE := "res://scenes/credits.tscn"
const PAUSE_MENU := preload("res://scenes/pause_menu.tscn")
const OPTIONS_RISE := 40.0

var _joining := false
var _options: Panel


func _ready() -> void:
	get_tree().paused = false
	SceneTransition.boot_reveal()
	MusicManager.play(preload("res://resources/audio/MAINMENUSOUNDTRACK.ogg"), false, false)
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
	var source := PAUSE_MENU.instantiate()
	_options = source.get_node("Panel/OptionsPanel")
	_options.get_parent().remove_child(_options)
	source.free()

	add_child(_options)
	_options.hide()
	_options.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var menu: Control = $Menu
	_options.anchor_left = menu.anchor_left
	_options.anchor_top = menu.anchor_top
	_options.anchor_right = menu.anchor_right
	_options.anchor_bottom = menu.anchor_bottom
	_options.offset_left = menu.offset_left
	_options.offset_top = menu.offset_top - OPTIONS_RISE
	_options.offset_right = menu.offset_right
	_options.offset_bottom = menu.offset_bottom - OPTIONS_RISE
	_options.grow_horizontal = menu.grow_horizontal
	_options.grow_vertical = menu.grow_vertical
	_options.get_node("OptionsLayout/BackButton").pressed.connect(_close_options)
	_options.get_node("OptionsLayout/VolumeRow/VolumeSlider").value_changed.connect(_set_volume)

	var button: Button = $Menu/CreditsButton.duplicate(Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS)
	button.name = "OptionsButton"
	button.text = "OPTIONS"
	button.visible = true
	$Menu.add_child(button)
	$Menu.move_child(button, $Menu/CreditsButton.get_index() + 1)
	button.pressed.connect(_open_options)


func _open_options() -> void:
	$Menu.hide()
	_options.show()
	_cascade(_options.get_node("OptionsLayout"))


func _close_options() -> void:
	_options.hide()
	$Menu.show()
	_cascade($Menu)


## OptionsPanel is reparented out of a throwaway pause_menu instance above, so
## pause_menu.gd never runs for it - the cascade has to be driven from here.
func _cascade(page: Control) -> void:
	var elements: Array[Control] = []
	for child in page.get_children():
		if child is Control and child.visible:
			elements.append(child)
	UICascade.reset(elements)
	await get_tree().process_frame
	if is_inside_tree():
		UICascade.play(elements, 0.0, 0.055)


func _set_volume(value: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(value))


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
