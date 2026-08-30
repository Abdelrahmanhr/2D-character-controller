extends Node


const MAX_PLAYERS: int = 4
const KEYBOARD_DEVICE_ID: int = -1  # sentinel value, no real joypad uses -1

signal player_joined(device_id: int)
signal player_left(device_id: int)

var joined_devices: Array[int] = []  # device_id per joined player, in join order


func is_joined(device_id: int) -> bool:
	return joined_devices.has(device_id)

func try_join(device_id: int) -> bool:
	if is_joined(device_id):
		return false
	if joined_devices.size() >= MAX_PLAYERS:
		return false
	joined_devices.append(device_id)
	player_joined.emit(device_id)
	return true

func leave(device_id: int) -> void:
	if not is_joined(device_id):
		return
	joined_devices.erase(device_id)
	player_left.emit(device_id)

func reset() -> void:
	joined_devices.clear()

func get_slot_index(device_id: int) -> int:
	return joined_devices.find(device_id)
