extends Control
class_name LocalLobby

const CONFIRM_JOYPAD_BUTTONS: Array[JoyButton] = [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y]
const CONFIRM_KEYS: Array[Key] = [KEY_SPACE, KEY_ENTER]

@export var min_players_to_start: int = 2
@export var slot_scene: PackedScene  # a small UI scene showing "P1 - Ready", empty slot, etc.

@onready var slot_container: Control = $SlotContainer
@onready var start_hint_label: Label = $StartHintLabel
@onready var start_button: Button = $StartButton
@onready var back_button: Button = $BackButton

const START_JOYPAD_BUTTON: JoyButton = JOY_BUTTON_START  # NEW
const START_KEY: Key = KEY_ENTER


var _slot_nodes: Dictionary = {}  # device_id -> slot UI instance

func _ready() -> void:
	LocalPlayers.reset()
	LocalPlayers.player_joined.connect(_on_player_joined)
	LocalPlayers.player_left.connect(_on_player_left)
	start_button.pressed.connect(_try_start_match)
	back_button.pressed.connect(_on_back_pressed)
	_refresh_start_hint()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index in CONFIRM_JOYPAD_BUTTONS:  # CHANGED: removed the START_JOYPAD_BUTTON check above this
			LocalPlayers.try_join(event.device)
	elif event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.keycode if event.keycode != KEY_NONE else event.physical_keycode
		if key in CONFIRM_KEYS:  # CHANGED: removed the START_KEY special-case above this
			LocalPlayers.try_join(LocalPlayers.KEYBOARD_DEVICE_ID)
	elif event is InputEventJoypadMotion:
		return

func _try_start_from_device(device_id: int) -> void:  # NEW
	if not LocalPlayers.is_joined(device_id):
		return
	_try_start_match()

func _on_player_joined(device_id: int) -> void:
	var slot_index: int = LocalPlayers.get_slot_index(device_id)
	var slot := slot_scene.instantiate()
	slot_container.add_child(slot)
	slot.setup(slot_index, _device_label(device_id))
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

func _try_start_match() -> void:
	if LocalPlayers.joined_devices.size() < min_players_to_start:
		return
	SceneTransition.circle_to("res://scenes/power_station.tscn")

func _on_back_pressed() -> void:  
	LocalPlayers.reset()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
