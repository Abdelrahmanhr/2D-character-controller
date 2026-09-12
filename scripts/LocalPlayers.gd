extends Node

var selected_arena_path: String = "res://scenes/power_station2.tscn" 
var entering_arena_select_for_local: bool = false  
const MAX_PLAYERS: int = 4
const KEYBOARD_DEVICE_ID: int = -1

signal player_joined(device_id: int)
signal player_left(device_id: int)
signal device_remapped(old_device_id: int, new_device_id: int)

var joined_devices: Array[int] = []
var device_guids: Dictionary = {}


func is_joined(device_id: int) -> bool:
	return joined_devices.has(device_id)

func try_join(device_id: int) -> bool:
	if is_joined(device_id):
		return false
	if joined_devices.size() >= MAX_PLAYERS:
		return false
	joined_devices.append(device_id)
	if device_id != KEYBOARD_DEVICE_ID:
		device_guids[device_id] = Input.get_joy_guid(device_id)
	player_joined.emit(device_id)
	return true

func leave(device_id: int) -> void:
	if not is_joined(device_id):
		return
	joined_devices.erase(device_id)
	device_guids.erase(device_id)
	player_left.emit(device_id)

func reset() -> void:
	joined_devices.clear()
	device_guids.clear()

func get_slot_index(device_id: int) -> int:
	return joined_devices.find(device_id)


func resolve_device_drift() -> void:
	for old_device in joined_devices.duplicate():
		if old_device == KEYBOARD_DEVICE_ID:
			continue
		var guid: String = str(device_guids.get(old_device, ""))
		if guid.is_empty():
			continue
		if Input.get_connected_joypads().has(old_device) and Input.get_joy_guid(old_device) == guid:
			continue
		var new_device: int = PadState.find_device_by_guid(guid)
		if new_device < 0 or new_device == old_device or joined_devices.has(new_device):
			continue
		_remap(old_device, new_device, guid)


func _remap(old_device: int, new_device: int, guid: String) -> void:
	joined_devices[joined_devices.find(old_device)] = new_device
	device_guids.erase(old_device)
	device_guids[new_device] = guid
	PadState.clear_device(old_device)
	NetDebug.log_event("pad remapped %d -> %d" % [old_device, new_device])
	for node in get_tree().get_nodes_in_group("players"):
		if node.device_id != old_device:
			continue
		node.device_id = new_device
		var bomb: Node = node.get_node_or_null("BombController")
		if bomb:
			bomb.device_id = new_device
	device_remapped.emit(old_device, new_device)
