extends CanvasLayer

## Panel size per page. The options pages carry more than the pause menu does -
## three sliders, then a nine-row controls table - so the frame grows to fit
## rather than clipping. UICascade.slam_panel animates scale and position only,
## so moving the offsets here does not fight it.
const PAGE_SIZES := {
	"PAUSED": Vector2(340.0, 320.0),
	"OPTIONS": Vector2(380.0, 360.0),
	"CONTROLS": Vector2(480.0, 440.0),
}

@onready var dim: ColorRect = $Dim
@onready var panel: Panel = $Panel
@onready var menu: VBoxContainer = $Panel/Menu
@onready var options: Control = $Panel/Options
@onready var title_bar: Label = $Panel/TitleBar

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	dim.hide()
	panel.hide()
	options.hide()
	# The frame's title bar names the page, so the options headings are redundant.
	options.set_titles_visible(false)
	options.back_pressed.connect(_hide_options)
	options.page_changed.connect(_on_options_page_changed)
	$Panel/Menu/ResumeButton.pressed.connect(_resume)
	$Panel/CloseButton.pressed.connect(_resume)
	$Panel/Menu/RestartButton.pressed.connect(_restart)
	$Panel/Menu/OptionsButton.pressed.connect(_show_options)
	$Panel/Menu/ExitButton.pressed.connect(_exit_game)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# The options scene owns its own page stack, so give it first refusal -
		# otherwise cancelling on the controls page would close the whole screen.
		if options.visible:
			if not options.handle_cancel():
				_hide_options()
		else:
			_toggle_pause()
		get_viewport().set_input_as_handled()

func _toggle_pause() -> void:
	if panel.visible:
		_resume()
	else:
		dim.show()
		panel.show()
		if not Networking.is_connected_online():
			# Soft pause: bomb timers freeze and input is ignored, but the arena,
			# music and particles keep running. Online we deliberately do neither -
			# bomb time is wall-clock derived and would silently drain, and one
			# player must never be able to freeze the match for everyone else.
			MinigameDirector.lock_input(MinigameDirector.LOCK_MENU)
			MinigameDirector.set_timers_frozen(true)
		_show_page("PAUSED")
		_cascade_page(menu)

func _resume() -> void:
	options.hide()
	menu.show()
	_show_page("PAUSED")
	panel.hide()
	dim.hide()
	_release_soft_pause()

func _restart() -> void:
	_release_soft_pause()
	Networking.restart_game()

func _show_options() -> void:
	menu.hide()
	options.open()

func _hide_options() -> void:
	options.hide()
	menu.show()
	_show_page("PAUSED")
	_cascade_page(menu)

func _on_options_page_changed(title: String) -> void:
	_show_page(title)

func _show_page(title: String) -> void:
	title_bar.text = title
	var size: Vector2 = PAGE_SIZES.get(title, PAGE_SIZES["PAUSED"])
	panel.offset_left = -size.x * 0.5
	panel.offset_right = size.x * 0.5
	panel.offset_top = -size.y * 0.5
	panel.offset_bottom = size.y * 0.5

func _exit_game() -> void:
	Networking.leave_lobby()
	_release_soft_pause()
	SceneTransition.circle_to("res://scenes/main_menu.tscn")

func _release_soft_pause() -> void:
	MinigameDirector.unlock_input(MinigameDirector.LOCK_MENU)
	MinigameDirector.set_timers_frozen(false)
	get_tree().paused = false


func _cascade_page(page: Control) -> void:
	var elements: Array[Control] = []
	for child in page.get_children():
		if child is Control and child.visible:
			elements.append(child)
	UICascade.reset(elements)
	UICascade.slam_panel(panel, 0.20)
	await get_tree().process_frame
	if is_inside_tree():
		UICascade.play(elements, 0.0, 0.055)
