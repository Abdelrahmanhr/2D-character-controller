extends Node

signal device_remapped(old_device: int, new_device: int)

var _axes: Dictionary = {}
var _buttons: Dictionary = {}
var _guids: Dictionary = {}

## The most recent joypad to actually send input (a button press, or a stick
## push past this deadzone). Player/BombController/TutorialOverlay's
## singleplayer/online input paths poll a single "the pad" device rather than
## reading events per-device the way couch play's locked-in device_id does -
## without tracking which one last spoke, they always polled
## Input.get_connected_joypads()[0], so with two pads connected at once
## (e.g. switching from a PS4 to an Xbox controller mid-session without
## unplugging the first) only whichever one enumerated first ever worked.
const ACTIVE_DEVICE_DEADZONE := 0.3
var _last_active_device: int = -1


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
		if absf(event.axis_value) > ACTIVE_DEVICE_DEADZONE:
			_last_active_device = event.device
	elif event is InputEventJoypadButton:
		if not _buttons.has(event.device):
			_buttons[event.device] = {}
		_buttons[event.device][event.button_index] = event.pressed
		if event.pressed:
			_last_active_device = event.device


## Whichever connected pad most recently sent real input, falling back to the
## first enumerated one if none has yet. Staleness on disconnect is handled by
## _on_joy_connection_changed clearing this below, rather than re-checking
## Input.get_connected_joypads() here on every call. For contexts with a
## single local player where any connected pad should work interchangeably -
## callers with their own per-player device_id (couch play) should keep using
## that instead of this.
func active_device() -> int:
	if _last_active_device >= 0:
		return _last_active_device
	var pads := Input.get_connected_joypads()
	return pads[0] if not pads.is_empty() else -1


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
		if _last_active_device == device:
			_last_active_device = -1
		NetDebug.log_event("pad %d disconnected" % device)
	LocalPlayers.resolve_device_drift()
