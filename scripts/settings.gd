extends Node
## Autoload as "Settings". Per-bus volume and keyboard bindings, persisted to
## user://settings.cfg.
##
## Each bus keeps whatever it was mixed at in default_bus_layout.tres as its
## 100% reference (Master +0.565 dB, SFX +6.02 dB). A slider at full therefore
## reproduces the designer's mix, rather than flattening every bus to 0 dB the
## way a bare set_bus_volume_db(idx, linear_to_db(value)) would - that call was
## quietly cutting SFX by 6 dB the first time anyone touched the old slider.
##
## Keyboard bindings live here rather than in the project's InputMap because
## gameplay never goes through InputMap: player.gd polls physical keys per
## device so local multiplayer can tell two keyboards-worth of players apart,
## and the minigames match raw keycodes. InputMap actions are global and cannot
## express that, so this is the one place a key literal belongs.

const PATH := "user://settings.cfg"
const SECTION := "audio"
const BUSES: Array[String] = ["Master", "Music", "SFX"]
const MIN_DB := -80.0
const SAVE_DELAY := 0.4

const KEY_SECTION := "keys"

## Every rebindable action -> the key it ships with. The *_alt entries are the
## second cap on a row, not a fallback; both are bound and both are editable.
const DEFAULT_KEYS := {
	&"move_left": KEY_A,
	&"move_right": KEY_D,
	&"move_up": KEY_W,
	&"move_down": KEY_S,
	&"jump": KEY_SPACE,
	&"dash": KEY_SHIFT,
	&"dash_alt": KEY_F,
	&"mg_up": KEY_UP,
	&"mg_down": KEY_DOWN,
	&"mg_left": KEY_LEFT,
	&"mg_right": KEY_RIGHT,
	&"mash": KEY_Y,
	&"confirm": KEY_SPACE,
	&"confirm_alt": KEY_ENTER,
}

signal keys_changed

var _base_db: Dictionary = {}
var _volumes: Dictionary = {}
var _keys: Dictionary = {}
var _save_pending := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Captured before _load() so the layout mix is what 1.0 means.
	for bus_name in BUSES:
		_base_db[bus_name] = AudioServer.get_bus_volume_db(_index(bus_name))
		_volumes[bus_name] = 1.0
	for action in DEFAULT_KEYS:
		_keys[action] = DEFAULT_KEYS[action]
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


# --- keyboard bindings ------------------------------------------------------

func get_key(action: StringName) -> Key:
	return _keys.get(action, KEY_NONE)


## The key this action ships with, regardless of what it is bound to now. Used
## as the canonical code on the wire - see bomb_controller._try_replicate_input.
func default_key(action: StringName) -> Key:
	return DEFAULT_KEYS.get(action, KEY_NONE)


## Bindings only, never defaults: once MOVE LEFT is rebound off A, pressing A
## must do nothing rather than quietly still work.
func action_for_key(key: int) -> StringName:
	for action in _keys:
		if _keys[action] == key:
			return action
	return &""


## The mirror of action_for_key for codes that arrived over the network, which
## are always canonical. Kept separate for the same reason: a remote peer's
## canonical code must not shadow this peer's own bindings.
func action_for_default_key(key: int) -> StringName:
	for action in DEFAULT_KEYS:
		if DEFAULT_KEYS[action] == key:
			return action
	return &""


## Binding a key that is already taken swaps the two actions rather than
## blanking the other one - a half-unbound controls page is worse than a
## surprising one, and the player can see both rows change at once.
func set_key(action: StringName, key: Key) -> void:
	if not _keys.has(action) or key == KEY_NONE:
		return
	var previous: Key = _keys[action]
	var holder := action_for_key(key)
	if holder == action:
		return
	if holder != &"":
		_keys[holder] = previous
	_keys[action] = key
	keys_changed.emit()
	_queue_save()


func reset_keys() -> void:
	for action in DEFAULT_KEYS:
		_keys[action] = DEFAULT_KEYS[action]
	keys_changed.emit()
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
	for action in DEFAULT_KEYS:
		var stored: int = int(config.get_value(KEY_SECTION, String(action), DEFAULT_KEYS[action]))
		_keys[action] = stored as Key if stored != KEY_NONE else DEFAULT_KEYS[action]


## Dragging a slider emits value_changed every frame - coalesce into one write.
func _queue_save() -> void:
	if _save_pending:
		return
	_save_pending = true
	await get_tree().create_timer(SAVE_DELAY).timeout
	_save_pending = false
	_save()


## Rebuilds the file from scratch, so it has to write *everything* we own -
## otherwise nudging a volume slider would drop the bindings on the floor.
func _save() -> void:
	var config := ConfigFile.new()
	for bus_name in BUSES:
		config.set_value(SECTION, bus_name, _volumes[bus_name])
	for action in DEFAULT_KEYS:
		config.set_value(KEY_SECTION, String(action), int(_keys[action]))
	config.save(PATH)
