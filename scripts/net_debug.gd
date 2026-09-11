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


func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	ready_delay = _read_delay_arg()
	allow_solo_start = OS.has_feature("editor") or OS.get_cmdline_args().has("--solo-start")
	_build_overlay()
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
	if event.physical_keycode == KEY_F3:
		_visible_overlay = not _visible_overlay
		_panel.visible = _visible_overlay
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_F4:
		var index := DELAY_STEPS.find(ready_delay)
		ready_delay = DELAY_STEPS[(index + 1) % DELAY_STEPS.size()] if index >= 0 else 0.0
		log_event("ready delay -> %.1fs" % ready_delay)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
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


func _player_names() -> Array[String]:
	var names: Array[String] = []
	for node in get_tree().get_nodes_in_group("players"):
		names.append(str(node.name))
	names.sort()
	return names
