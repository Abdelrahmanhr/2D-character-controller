extends CanvasLayer

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const END_SCENE := "res://scenes/end.tscn"

@onready var panel: Panel = $Panel
@onready var options_panel: Panel = $Panel/OptionsPanel

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel.hide()
	$Panel/Menu/ResumeButton.pressed.connect(_resume)
	$Panel/Menu/RestartButton.pressed.connect(_restart)
	$Panel/Menu/OptionsButton.pressed.connect(_show_options)
	$Panel/Menu/MainMenuButton.pressed.connect(_go_to_main_menu)
	$Panel/Menu/EndButton.pressed.connect(_go_to_end)
	$Panel/Menu/ExitButton.pressed.connect(_exit_game)
	$Panel/OptionsPanel/BackButton.pressed.connect(_hide_options)
	$Panel/OptionsPanel/FullscreenCheck.toggled.connect(_set_fullscreen)
	$Panel/OptionsPanel/VsyncCheck.toggled.connect(_set_vsync)
	$Panel/OptionsPanel/VolumeSlider.value_changed.connect(_set_volume)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if options_panel.visible:
			_hide_options()
		else:
			_toggle_pause()
		get_viewport().set_input_as_handled()

func _toggle_pause() -> void:
	if panel.visible:
		_resume()
	else:
		panel.show()
		get_tree().paused = true

func _resume() -> void:
	options_panel.hide()
	panel.hide()
	get_tree().paused = false

func _restart() -> void:
	get_tree().paused = false
	Networking.restart_game()

func _show_options() -> void:
	$Panel/Menu.hide()
	options_panel.show()

func _hide_options() -> void:
	options_panel.hide()
	$Panel/Menu.show()

func _go_to_main_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)

func _go_to_end() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(END_SCENE)

func _exit_game() -> void:
	get_tree().quit()

func _set_fullscreen(enabled: bool) -> void:
	if enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _set_vsync(enabled: bool) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if enabled else DisplayServer.VSYNC_DISABLED)

func _set_volume(value: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(value))