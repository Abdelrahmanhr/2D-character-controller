extends Node
## Autoload as "Settings". Per-bus volume, persisted to user://settings.cfg.
##
## Each bus keeps whatever it was mixed at in default_bus_layout.tres as its
## 100% reference (Master +0.565 dB, SFX +6.02 dB). A slider at full therefore
## reproduces the designer's mix, rather than flattening every bus to 0 dB the
## way a bare set_bus_volume_db(idx, linear_to_db(value)) would - that call was
## quietly cutting SFX by 6 dB the first time anyone touched the old slider.

const PATH := "user://settings.cfg"
const SECTION := "audio"
const BUSES: Array[String] = ["Master", "Music", "SFX"]
const MIN_DB := -80.0
const SAVE_DELAY := 0.4

var _base_db: Dictionary = {}
var _volumes: Dictionary = {}
var _save_pending := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Captured before _load() so the layout mix is what 1.0 means.
	for bus_name in BUSES:
		_base_db[bus_name] = AudioServer.get_bus_volume_db(_index(bus_name))
		_volumes[bus_name] = 1.0
	_load()
	for bus_name in BUSES:
		_apply(bus_name)


func get_volume(bus_name: String) -> float:
	return _volumes.get(bus_name, 1.0)


func set_volume(bus_name: String, value: float) -> void:
	if not _volumes.has(bus_name):
		return
	_volumes[bus_name] = clampf(value, 0.0, 1.0)
	_apply(bus_name)
	_queue_save()


## By name, never a hardcoded index - the old code wrote to bus 0 by number.
func _index(bus_name: String) -> int:
	return AudioServer.get_bus_index(bus_name)


func _apply(bus_name: String) -> void:
	var index := _index(bus_name)
	if index < 0:
		return
	var value: float = _volumes[bus_name]
	# linear_to_db(0.0) is -inf; use a silent but finite floor instead.
	var db: float = MIN_DB if value <= 0.001 else float(_base_db[bus_name]) + linear_to_db(value)
	AudioServer.set_bus_volume_db(index, db)


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	for bus_name in BUSES:
		_volumes[bus_name] = clampf(float(config.get_value(SECTION, bus_name, 1.0)), 0.0, 1.0)


## Dragging a slider emits value_changed every frame - coalesce into one write.
func _queue_save() -> void:
	if _save_pending:
		return
	_save_pending = true
	await get_tree().create_timer(SAVE_DELAY).timeout
	_save_pending = false
	_save()


func _save() -> void:
	var config := ConfigFile.new()
	for bus_name in BUSES:
		config.set_value(SECTION, bus_name, _volumes[bus_name])
	config.save(PATH)
