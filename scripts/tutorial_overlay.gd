extends CanvasLayer
class_name TutorialOverlay

signal continue_pressed
signal skip_requested
signal practice_requested
signal replay_requested
signal quit_requested

const LAYER := 9
const MAX_HOLES := 4
const SPOTLIGHT_SHADER := preload("res://resources/tutorial_spotlight.gdshader")

const SKIP_HOLD_TIME: float = 1.0
const MINIGAME_DESIGN := Vector2(280.0, 160.0)
const MINIGAME_TEACH_SCALE: float = 1.5

const TITLE_COLOR := Color(1.0, 0.8784, 0.5686)
const BODY_COLOR := Color(0.8824, 0.9176, 0.9608)
const DONE_COLOR := Color(0.549, 1.0, 0.6078)
const PENDING_COLOR := Color(0.6196, 0.6588, 0.7294)
const PANEL_BG := Color(0.0353, 0.0392, 0.0627, 0.94)
const PANEL_BORDER := Color(0.3216, 0.6392, 1.0, 0.75)

var _dim: ColorRect
var _material: ShaderMaterial
var _card: PanelContainer
var _column: VBoxContainer
var _title: Label
var _body: Label
var _caps_slot: MarginContainer
var _objectives_box: VBoxContainer
var _objective_labels: Array[Label] = []
var _continue: Label
var _banner: PanelContainer
var _banner_label: Label
var _skip_root: VBoxContainer
var _skip_bar: ProgressBar
var _teach_panel: PanelContainer
var _complete: PanelContainer

var _targets: Array = []
var _skip_timer: float = 0.0
var _skip_active: bool = false
var _awaiting_continue: bool = false
var _pumped_minigame: Control = null
var banner_only: bool = false


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_dim()
	_build_card()
	_build_teach_panel()
	_build_banner()
	_build_skip()
	hide_card()
	clear_spotlight()
	_skip_root.visible = not banner_only
	get_viewport().size_changed.connect(_layout)


func _build_dim() -> void:
	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.color = Color(1.0, 1.0, 1.0, 1.0)
	_material = ShaderMaterial.new()
	_material.shader = SPOTLIGHT_SHADER
	_dim.material = _material
	add_child(_dim)


func _build_card() -> void:
	_card = PanelContainer.new()
	_card.name = "Card"
	_card.add_theme_stylebox_override("panel", _panel_style())
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card)

	_column = VBoxContainer.new()
	_column.alignment = BoxContainer.ALIGNMENT_CENTER
	_column.add_theme_constant_override("separation", 10)
	_card.add_child(_column)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MinigameUI.style_label(_title, TITLE_COLOR, 20)
	_column.add_child(_title)

	_body = Label.new()
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(520.0, 0.0)
	MinigameUI.style_label(_body, BODY_COLOR, 15)
	_column.add_child(_body)

	_caps_slot = MarginContainer.new()
	_column.add_child(_caps_slot)

	_objectives_box = VBoxContainer.new()
	_objectives_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_objectives_box.add_theme_constant_override("separation", 3)
	_column.add_child(_objectives_box)

	_continue = Label.new()
	_continue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MinigameUI.style_label(_continue, PENDING_COLOR, 13)
	_column.add_child(_continue)


func _build_teach_panel() -> void:
	_teach_panel = PanelContainer.new()
	_teach_panel.name = "TeachPanel"
	_teach_panel.add_theme_stylebox_override("panel", _panel_style())
	_teach_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_teach_panel.visible = false
	add_child(_teach_panel)


func _build_banner() -> void:
	_banner = PanelContainer.new()
	_banner.name = "Banner"
	_banner.add_theme_stylebox_override("panel", _panel_style())
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	add_child(_banner)

	_banner_label = Label.new()
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MinigameUI.style_label(_banner_label, TITLE_COLOR, 16)
	_banner.add_child(_banner_label)


func _build_skip() -> void:
	_skip_root = VBoxContainer.new()
	_skip_root.name = "Skip"
	_skip_root.alignment = BoxContainer.ALIGNMENT_CENTER
	_skip_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_skip_root)

	var hint := Label.new()
	hint.text = "HOLD ESC TO SKIP"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MinigameUI.style_label(hint, PENDING_COLOR, 11)
	_skip_root.add_child(hint)

	_skip_bar = ProgressBar.new()
	_skip_bar.custom_minimum_size = Vector2(150.0, 6.0)
	_skip_bar.show_percentage = false
	_skip_bar.max_value = SKIP_HOLD_TIME
	_skip_bar.value = 0.0
	_skip_bar.visible = false
	MinigameUI.style_time_bar(_skip_bar, TITLE_COLOR)
	_skip_root.add_child(_skip_bar)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = PANEL_BORDER
	style.set_border_width_all(2)
	style.set_content_margin_all(18.0)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style


func show_card(title: String, body: String, caps: Array = [], continue_hint: String = "") -> void:
	_title.text = title
	_title.visible = not title.is_empty()
	_body.text = body
	_body.visible = not body.is_empty()
	_set_caps(caps)
	_continue.text = continue_hint
	_continue.visible = not continue_hint.is_empty()
	_card.visible = true
	_layout()


func hide_card() -> void:
	_card.visible = false
	_awaiting_continue = false


func await_continue() -> void:
	_awaiting_continue = true
	await continue_pressed
	_awaiting_continue = false


func continue_hint_text() -> String:
	return "PRESS [ %s ] TO CONTINUE" % TutorialKeycap.key_text(&"confirm")


func set_objectives(items: Array) -> void:
	for label in _objective_labels:
		label.queue_free()
	_objective_labels.clear()
	for item in items:
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		MinigameUI.style_label(label, PENDING_COLOR, 13)
		label.text = "[  ]  %s" % String(item)
		_objectives_box.add_child(label)
		_objective_labels.append(label)
	_objectives_box.visible = not items.is_empty()
	_layout()


func mark_objective(index: int, done: bool) -> void:
	if index < 0 or index >= _objective_labels.size():
		return
	var label: Label = _objective_labels[index]
	var text: String = label.text.substr(6)
	label.text = ("[ x ]  %s" if done else "[  ]  %s") % text
	MinigameUI.style_label(label, DONE_COLOR if done else PENDING_COLOR, 13)


func set_spotlight(targets: Array) -> void:
	_targets = targets.duplicate()
	_dim.visible = true
	_update_holes()


func dim_all() -> void:
	set_spotlight([])


func clear_spotlight() -> void:
	_targets.clear()
	_dim.visible = false


func show_banner(text: String, duration: float = 3.5) -> void:
	_banner_label.text = text
	_banner.visible = true
	_banner.modulate.a = 1.0
	_layout()
	var tween := create_tween()
	tween.tween_interval(duration)
	tween.tween_property(_banner, "modulate:a", 0.0, 0.4)
	tween.tween_callback(_hide_banner)


func _hide_banner() -> void:
	_banner.visible = false
	_banner.modulate.a = 1.0


func host_minigame(minigame: Control, scale_factor: float = MINIGAME_TEACH_SCALE) -> void:
	release_minigame()
	_pumped_minigame = minigame

	var design := MINIGAME_DESIGN
	var screens := get_tree().get_first_node_in_group("minigame_screens")
	if screens != null and "content_design_size" in screens:
		design = screens.content_design_size

	var holder := Control.new()
	holder.name = "TeachHolder"
	holder.custom_minimum_size = design * scale_factor
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_teach_panel.add_child(holder)

	minigame.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	minigame.pivot_offset = Vector2.ZERO
	minigame.size = design
	minigame.scale = Vector2(scale_factor, scale_factor)
	minigame.position = Vector2.ZERO
	holder.add_child(minigame)

	_teach_panel.visible = true
	_layout()


func pump_minigame(minigame: Control) -> void:
	_pumped_minigame = minigame


func release_minigame() -> void:
	var pumped := _pumped_minigame
	_pumped_minigame = null
	if pumped != null and is_instance_valid(pumped) and pumped.get_parent() != null:
		pumped.get_parent().remove_child(pumped)
	for child in _teach_panel.get_children():
		_teach_panel.remove_child(child)
		child.queue_free()
	_teach_panel.visible = false


func show_completion() -> void:
	if _complete != null:
		return
	hide_card()
	release_minigame()
	_skip_root.visible = false
	dim_all()

	_complete = PanelContainer.new()
	_complete.name = "Complete"
	_complete.add_theme_stylebox_override("panel", _panel_style())
	add_child(_complete)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 12)
	_complete.add_child(column)

	var title := Label.new()
	title.text = "TUTORIAL COMPLETE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MinigameUI.style_label(title, TITLE_COLOR, 22)
	column.add_child(title)

	var buttons: Array[Control] = []
	for entry in [
		["PRACTICE VS BOTS", practice_requested],
		["REPLAY TUTORIAL", replay_requested],
		["MAIN MENU", quit_requested],
	]:
		var button := Button.new()
		button.text = String(entry[0])
		button.custom_minimum_size = Vector2(240.0, 0.0)
		var signal_to_fire: Signal = entry[1]
		button.pressed.connect(func() -> void: signal_to_fire.emit())
		column.add_child(button)
		buttons.append(button)

	_layout()
	UICascade.reset(buttons)
	UICascade.slam_panel(_complete, 0.20)
	await get_tree().process_frame
	if is_inside_tree():
		UICascade.play(buttons, 0.0, 0.055)
		buttons[0].grab_focus()


func _input(event: InputEvent) -> void:
	if banner_only:
		return

	if _pumped_minigame != null and is_instance_valid(_pumped_minigame):
		if _pumped_minigame._handle_input(event):
			get_viewport().set_input_as_handled()
			return

	if _awaiting_continue and _is_confirm(event):
		get_viewport().set_input_as_handled()
		continue_pressed.emit()
		return

	if not _skip_root.visible or not event.is_action("ui_cancel"):
		return
	if _pause_menu_open():
		return

	get_viewport().set_input_as_handled()
	if event.is_pressed() and not event.is_echo():
		_skip_active = true
		_skip_timer = 0.0
		_skip_bar.visible = true
	elif not event.is_pressed() and _skip_active:
		_end_skip_hold()
		if _skip_timer < SKIP_HOLD_TIME:
			_toggle_pause_menu()


func _is_confirm(event: InputEvent) -> bool:
	if event is InputEventJoypadButton and event.pressed:
		return true
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return false
	var raw_key: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	return raw_key == Settings.get_key(&"confirm") or raw_key == Settings.get_key(&"confirm_alt")


func _end_skip_hold() -> void:
	_skip_active = false
	_skip_bar.visible = false
	_skip_bar.value = 0.0


func _pause_menu_open() -> bool:
	var pause := get_tree().current_scene.get_node_or_null("PauseMenu")
	if pause == null:
		return false
	var panel := pause.get_node_or_null("Panel") as Control
	return panel != null and panel.visible


func _toggle_pause_menu() -> void:
	var pause := get_tree().current_scene.get_node_or_null("PauseMenu")
	if pause and pause.has_method("toggle"):
		pause.toggle()


func _process(delta: float) -> void:
	if _skip_active:
		_skip_timer += delta
		_skip_bar.value = minf(_skip_timer, SKIP_HOLD_TIME)
		if _skip_timer >= SKIP_HOLD_TIME:
			_end_skip_hold()
			skip_requested.emit()
	if _dim.visible:
		_update_holes()


func _update_holes() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var canvas: Transform2D = get_viewport().get_canvas_transform()
	var zoom: float = canvas.get_scale().x

	var holes := PackedVector4Array()
	var radii := PackedFloat32Array()
	var feathers := PackedFloat32Array()

	for target in _targets:
		if holes.size() >= MAX_HOLES:
			break
		if not (target is Dictionary):
			continue

		var centre := Vector2.ZERO
		var half := Vector2.ZERO
		var corner: float = 0.0

		if target.has("node"):
			if not is_instance_valid(target["node"]):
				continue
			var node := target["node"] as Node2D
			if node == null:
				continue
			var radius: float = float(target.get("radius", 90.0)) * zoom
			centre = canvas * node.global_position
			half = Vector2(radius, radius)
			corner = radius
		elif target.has("control"):
			if not is_instance_valid(target["control"]):
				continue
			var control := target["control"] as Control
			if control == null or not control.is_visible_in_tree():
				continue
			var rect: Rect2 = control.get_global_rect()
			var pad: float = float(target.get("pad", 12.0))
			centre = rect.get_center()
			half = rect.size * 0.5 + Vector2(pad, pad)
			corner = float(target.get("radius", 8.0))
		else:
			continue

		holes.append(Vector4(centre.x, centre.y, half.x, half.y))
		radii.append(corner)
		feathers.append(float(target.get("feather", 24.0)))

	_material.set_shader_parameter("holes", holes)
	_material.set_shader_parameter("radii", radii)
	_material.set_shader_parameter("feathers", feathers)
	_material.set_shader_parameter("hole_count", holes.size())
	_material.set_shader_parameter("viewport_size", viewport_size)


func _set_caps(caps: Array) -> void:
	for child in _caps_slot.get_children():
		_caps_slot.remove_child(child)
		child.queue_free()
	if caps.is_empty():
		_caps_slot.visible = false
		return
	_caps_slot.add_child(TutorialKeycap.row(caps))
	_caps_slot.visible = true


func _layout() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size

	_card.reset_size()
	var card_size: Vector2 = _card.size
	_card.position = Vector2(
		(viewport_size.x - card_size.x) * 0.5,
		viewport_size.y - card_size.y - 46.0,
	)

	_teach_panel.reset_size()
	var teach_size: Vector2 = _teach_panel.size
	_teach_panel.position = Vector2(
		(viewport_size.x - teach_size.x) * 0.5,
		viewport_size.y * 0.34 - teach_size.y * 0.5,
	)

	_banner.reset_size()
	_banner.position = Vector2((viewport_size.x - _banner.size.x) * 0.5, 92.0)

	if _complete != null:
		_complete.reset_size()
		_complete.position = (viewport_size - _complete.size) * 0.5

	_skip_root.reset_size()
	_skip_root.position = Vector2(viewport_size.x - _skip_root.size.x - 24.0, viewport_size.y - 52.0)
