extends Node

signal device_remapped(old_device: int, new_device: int)

var _axes: Dictionary = {}
var _buttons: Dictionary = {}
var _guids: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	for device in Input.get_connected_joypads():
		_guids[device] = Input.get_joy_guid(device)


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		if not _axes.has(event.device):
			_axes[event.device] = {}
		_axes[event.device][event.axis] = event.axis_value
	elif event is InputEventJoypadButton:
		if not _buttons.has(event.device):
			_buttons[event.device] = {}
		_buttons[event.device][event.button_index] = event.pressed


func get_axis(device: int, axis: int) -> float:
	if device < 0 or not _axes.has(device):
		return 0.0
	return _axes[device].get(axis, 0.0)


func is_pressed(device: int, button: int) -> bool:
	if device < 0 or not _buttons.has(device):
		return false
	return _buttons[device].get(button, false)


func get_guid(device: int) -> String:
	return str(_guids.get(device, ""))


func find_device_by_guid(guid: String) -> int:
	if guid.is_empty():
		return -1
	for device in Input.get_connected_joypads():
		if Input.get_joy_guid(device) == guid:
			return device
	return -1


func clear_device(device: int) -> void:
	_axes.erase(device)
	_buttons.erase(device)


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		_guids[device] = Input.get_joy_guid(device)
		NetDebug.log_event("pad %d connected: %s" % [device, Input.get_joy_name(device)])
	else:
		clear_device(device)
		_guids.erase(device)
		NetDebug.log_event("pad %d disconnected" % device)
	LocalPlayers.resolve_device_drift()
