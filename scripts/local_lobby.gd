extends Control
class_name LocalLobby

const CONFIRM_JOYPAD_BUTTONS: Array[JoyButton] = [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y]
@export var min_players_to_start: int = 2
@export var slot_scene: PackedScene  # a small UI scene showing "P1 - Ready", empty slot, etc.

@onready var slot_container: Control = $SlotContainer
@onready var start_hint_label: Label = $StartHintLabel
@onready var start_button: Button = $StartButton
@onready var back_button: Button = $BackButton

const START_JOYPAD_BUTTON: JoyButton = JOY_BUTTON_START  # NEW

var _slot_nodes: Dictionary = {}  # device_id -> slot UI instance

## CHANGED: was const CONFIRM_KEYS = [KEY_SPACE, KEY_ENTER]; read live so a
## rebind on the options page takes effect here too.
func _confirm_keys() -> Array[Key]:
	return [Settings.get_key(&"confirm"), Settings.get_key(&"confirm_alt")]


func _ready() -> void:
	MusicManager.play_id(&"menu")
	# This screen's first job is "press a button to join", so it opts out of
	# UINav's focus-on-arrival: a highlight parked on BACK while four people are
	# still pressing A to join is a way to lose the lobby, not a help. A direction
	# press still acquires focus normally, so Start and Back stay pad-reachable.
	add_to_group(UINav.NO_AUTO_FOCUS_GROUP)
	LocalPlayers.reset()
	LocalPlayers.player_joined.connect(_on_player_joined)
	LocalPlayers.player_left.connect(_on_player_left)
	start_button.pressed.connect(_try_start_match)
	back_button.pressed.connect(_on_back_pressed)
	_refresh_start_hint()


## CHANGED: was _unhandled_input, and had no "already joined?" gate.
##
## ui_accept now carries JOY_BUTTON_A alongside Space/Enter so that menus are
## controller-navigable at all, which means a focused Button consumes exactly the
## press this screen listens for, in gui_input, BEFORE unhandled input ever runs.
## Left in _unhandled_input, a second player pressing A to join would instead
## press whatever the first player had highlighted and never get a slot.
## _input runs ahead of the GUI, so the join wins while a device is still
## unjoined.
##
## The "not joined yet" gate is what stops this being a blanket steal: once a
## device has a slot its presses fall straight through to the menu, so that same
## pad can still drive Start and Back. Per-device assignment is untouched - this
## keys off event.device exactly as it did before, and nothing here is shared
## with the singleplayer/online path's PadState.active_device().
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		# This screen's own hint says "Press Start to begin" and the options
		# CONTROLS table lists START MATCH as START/OPTIONS, but nothing was
		# actually wired to it -- START_JOYPAD_BUTTON and _try_start_from_device
		# were both left unreferenced, so the only way in was clicking the button
		# with a mouse. Honour what the UI already promises.
		if event.button_index == START_JOYPAD_BUTTON:
			_try_start_from_device(event.device)
			get_viewport().set_input_as_handled()
			return
		if event.button_index in CONFIRM_JOYPAD_BUTTONS and not LocalPlayers.is_joined(event.device):
			LocalPlayers.try_join(event.device)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if LocalPlayers.is_joined(LocalPlayers.KEYBOARD_DEVICE_ID):
			return
		# A focused NameEdit already consumes its own key events before they'd
		# reach here, but belt-and-suspenders: typing a space or hitting enter to
		# confirm a name must never also register as the keyboard trying to join.
		# Scoped to the keyboard branch only -- a controller press must still be
		# able to join a new player while someone else is mid-edit on a name.
		if get_viewport().gui_get_focus_owner() is LineEdit:
			return
		var key: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		if key in _confirm_keys():  # CHANGED: removed the START_KEY special-case above this
			LocalPlayers.try_join(LocalPlayers.KEYBOARD_DEVICE_ID)
			get_viewport().set_input_as_handled()

func _try_start_from_device(device_id: int) -> void:  # NEW
	if not LocalPlayers.is_joined(device_id):
		return
	_try_start_match()

func _on_player_joined(device_id: int) -> void:
	var slot_index: int = LocalPlayers.get_slot_index(device_id)
	var slot := slot_scene.instantiate()
	slot_container.add_child(slot)
	slot.setup(slot_index, _device_label(device_id), device_id)
	_slot_nodes[device_id] = slot
	_refresh_start_hint()

func _on_player_left(device_id: int) -> void:
	if _slot_nodes.has(device_id):
		_slot_nodes[device_id].queue_free()
		_slot_nodes.erase(device_id)
	_refresh_start_hint()

func _device_label(device_id: int) -> String:
	if device_id == LocalPlayers.KEYBOARD_DEVICE_ID:
		return "Keyboard"
	return "Controller %d" % (device_id + 1)

func _refresh_start_hint() -> void:
	var count := LocalPlayers.joined_devices.size()
	start_button.disabled = count < min_players_to_start  # NEW
	if count >= min_players_to_start:
		start_hint_label.text = "Press Start to begin (%d players)" % count
	else:
		start_hint_label.text = "Listening for input... (%d/%d minimum players)" % [count, min_players_to_start]


func _on_back_pressed() -> void:  
	LocalPlayers.reset()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	

func _try_start_match() -> void:
	if LocalPlayers.joined_devices.size() < min_players_to_start:
		return
	# Matches the online path: networking.gd's _load_arena RPC hands its arena_path
	# to SceneTransition.circle_to instead of calling change_scene_to_file directly.
	SceneTransition.circle_to(LocalPlayers.selected_arena_path)
