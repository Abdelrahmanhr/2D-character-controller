extends CanvasLayer

const MAX_EVENTS := 12
const DELAY_STEPS: Array[float] = [0.0, 2.0, 5.0, 10.0]

var ready_delay: float = 0.0
var allow_solo_start: bool = false
var ack_count: int = 0
var ack_target: int = 0

var _events: Array[String] = []
var _label: Label
var _panel: PanelContainer
var _visible_overlay: bool = false

var _pad_label: Label
var _pad_panel: PanelContainer
var _pad_overlay: bool = false
var _pad_events: Array[String] = []

const MAX_PAD_EVENTS := 10
const WATCH_BUTTONS: Array[int] = [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_START]
const BUTTON_NAMES: Array[String] = ["A", "B", "X", "Y", "Start"]


func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	ready_delay = _read_delay_arg()
	allow_solo_start = OS.has_feature("editor") or OS.get_cmdline_args().has("--solo-start")
	_build_overlay()
	_build_pad_overlay()
	if ready_delay > 0.0:
		_visible_overlay = true
		_panel.visible = true
		log_event("net-debug-delay = %.1fs" % ready_delay)


func _read_delay_arg() -> float:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--net-debug-delay="):
			return maxf(0.0, arg.split("=", true, 1)[1].to_float())
	return 0.0


func _build_overlay() -> void:
	_panel = PanelContainer.new()
	_panel.position = Vector2(12, 12)
	_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.72)
	style.border_color = Color(0.2, 0.95, 1, 0.6)
	style.set_border_width_all(1)
	style.set_content_margin_all(8)
	_panel.add_theme_stylebox_override("panel", style)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", Color(0.75, 1, 1, 1))
	_panel.add_child(_label)
	add_child(_panel)


func _build_pad_overlay() -> void:
	_pad_panel = PanelContainer.new()
	_pad_panel.position = Vector2(12, 12)
	_pad_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.78)
	style.border_color = Color(1, 0.8, 0.2, 0.7)
	style.set_border_width_all(1)
	style.set_content_margin_all(8)
	_pad_panel.add_theme_stylebox_override("panel", style)
	_pad_label = Label.new()
	_pad_label.add_theme_font_size_override("font_size", 12)
	_pad_label.add_theme_color_override("font_color", Color(1, 0.95, 0.8, 1))
	_pad_panel.add_child(_pad_label)
	add_child(_pad_panel)


func _input(event: InputEvent) -> void:
	if not _pad_overlay:
		return
	if event is InputEventJoypadButton:
		_log_pad("dev %d  button %d  %s" % [event.device, event.button_index, "down" if event.pressed else "up"])
	elif event is InputEventJoypadMotion:
		if absf(event.axis_value) > 0.35:
			_log_pad("dev %d  axis %d  %+.2f" % [event.device, event.axis, event.axis_value])


func _log_pad(text: String) -> void:
	_pad_events.append(text)
	if _pad_events.size() > MAX_PAD_EVENTS:
		_pad_events.remove_at(0)


func _compose_pad_text() -> String:
	var lines: Array[String] = []
	lines.append("CONTROLLER DEBUG   F2 hide")
	lines.append("joined devices: %s" % str(LocalPlayers.joined_devices))
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		lines.append("no joypads connected")
	for device in pads:
		lines.append("")
		lines.append("[%d] %s" % [device, Input.get_joy_name(device)])
		lines.append("    guid %s" % Input.get_joy_guid(device))
		lines.append("    info %s" % str(Input.get_joy_info(device)))
		lines.append("    LX/LY polled %+.2f %+.2f   event %+.2f %+.2f" % [
			Input.get_joy_axis(device, JOY_AXIS_LEFT_X),
			Input.get_joy_axis(device, JOY_AXIS_LEFT_Y),
			PadState.get_axis(device, JOY_AXIS_LEFT_X),
			PadState.get_axis(device, JOY_AXIS_LEFT_Y),
		])
		lines.append("    RX/RY polled %+.2f %+.2f   event %+.2f %+.2f" % [
			Input.get_joy_axis(device, JOY_AXIS_RIGHT_X),
			Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y),
			PadState.get_axis(device, JOY_AXIS_RIGHT_X),
			PadState.get_axis(device, JOY_AXIS_RIGHT_Y),
		])
		var polled: Array[String] = []
		var evented: Array[String] = []
		for i in WATCH_BUTTONS.size():
			if Input.is_joy_button_pressed(device, WATCH_BUTTONS[i]):
				polled.append(BUTTON_NAMES[i])
			if PadState.is_pressed(device, WATCH_BUTTONS[i]):
				evented.append(BUTTON_NAMES[i])
		lines.append("    buttons polled %s   event %s" % [str(polled), str(evented)])
	lines.append("")
	lines.append("--- raw events ---")
	for line in _pad_events:
		lines.append(line)
	return "\n".join(lines)


func get_ready_delay() -> float:
	return ready_delay


func set_ack_count(value: int) -> void:
	ack_count = value


func set_ack_target(value: int) -> void:
	ack_target = value
	ack_count = 0


func log_event(text: String) -> void:
	_events.append("%6.1f  %s" % [Time.get_ticks_msec() / 1000.0, text])
	if _events.size() > MAX_EVENTS:
		_events.remove_at(0)
	print("[net] %s" % text)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.physical_keycode == KEY_F2:
		_pad_overlay = not _pad_overlay
		_pad_panel.visible = _pad_overlay
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_F3:
		_visible_overlay = not _visible_overlay
		_panel.visible = _visible_overlay
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_F4:
		var index := DELAY_STEPS.find(ready_delay)
		ready_delay = DELAY_STEPS[(index + 1) % DELAY_STEPS.size()] if index >= 0 else 0.0
		log_event("ready delay -> %.1fs" % ready_delay)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _pad_overlay:
		_pad_label.text = _compose_pad_text()
		_panel.position = Vector2(12, 12 + _pad_panel.size.y + 8)
	else:
		_panel.position = Vector2(12, 12)
	if not _visible_overlay:
		return
	_label.text = _compose_text()


func _compose_text() -> String:
	var lines: Array[String] = []
	var mp := multiplayer
	var is_online: bool = mp.multiplayer_peer != null and not (mp.multiplayer_peer is OfflineMultiplayerPeer)
	lines.append("NET DEBUG   F3 hide   F4 delay=%.1fs   solo=%s" % [ready_delay, str(allow_solo_start)])
	if not is_online:
		lines.append("mode: offline")
	else:
		lines.append("mode: %s   id: %d" % ["HOST" if mp.is_server() else "CLIENT", mp.get_unique_id()])
		lines.append("peers: %s" % str(mp.get_peers()))
		lines.append("lobby: %d" % Networking.current_lobby_id)
		lines.append("arena acks: %d/%d" % [ack_count, ack_target])
		lines.append("clock offset: %d ms   rtt: %d ms   sync: %d" % [
			Networking.get_clock_offset(),
			Networking.get_last_rtt(),
			Networking.get_sync_time(),
		])
		lines.append("bomb starts: %s" % str(_bomb_starts()))
	lines.append("arena: %s" % Networking.selected_arena_name)
	lines.append("players in tree: %s" % str(_player_names()))
	lines.append("director: registered %d / expected %d  alive %d" % [
		MinigameDirector.get_registered_count(),
		MinigameDirector.expected_player_count,
		MinigameDirector.get_alive_count(),
	])
	lines.append("counting down: %s   finished: %s" % [
		str(MinigameDirector.is_counting_down()),
		str(MinigameDirector.is_match_finished()),
	])
	lines.append("--- events ---")
	for line in _events:
		lines.append(line)
	return "\n".join(lines)


func _bomb_starts() -> Array[String]:
	var out: Array[String] = []
	for node in get_tree().get_nodes_in_group("players"):
		var bomb := node.get_node_or_null("BombController")
		if bomb:
			out.append("%s:t=%d %.2fs" % [node.name, bomb._start_time_ms, bomb.time_left])
	out.sort()
	return out


func _player_names() -> Array[String]:
	var names: Array[String] = []
	for node in get_tree().get_nodes_in_group("players"):
		names.append(str(node.name))
	names.sort()
	return names
