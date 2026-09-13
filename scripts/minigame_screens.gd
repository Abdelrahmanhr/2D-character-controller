extends Node
class_name MinigameScreens

const SCREEN_TEXTURE := preload("res://resources/ui/led_screen.png")
const SCREEN_SHADER := preload("res://resources/led_screen.gdshader")

const ART_REGION := Rect2(12, 19, 64, 48)
const ART_SIZE := Vector2(64.0, 48.0)
const DISPLAY_ORIGIN := Vector2(2.0, 18.0)
const DISPLAY_SIZE := Vector2(60.0, 28.0)

const SLOT_COUNT := 4

@export var auto_layout: bool = true
@export var screen_scale: float = 0.82
@export var top_margin: float = 56.0
@export var side_margin: float = 16.0
@export var gap: float = 12.0
@export var content_design_size: Vector2 = Vector2(280.0, 160.0)
@export var content_fill: float = 1.0
@export var frame_offset: Vector2 = Vector2.ZERO
@export var frame_scale: float = 1.0
@export var frame_offset_per_slot: Array[Vector2] = []

@export var entrance_duration: float = 0.45
@export var entrance_stagger: float = 0.08
@export var power_on_duration: float = 0.22
@export var power_off_duration: float = 0.14
@export var flash_color: Color = Color(3.0, 3.0, 3.0, 1.0)
@export var boost_on: float = 1.4
@export var boost_off: float = 0.25
@export var boost_flash: float = 2.6
@export var collapsed_height: float = 0.03
@export var dot_width: float = 0.10
@export var line_duration: float = 0.08
@export var line_hold: float = 0.05

@export var shadow_enabled: bool = true
@export var shadow_offset: Vector2 = Vector2(2.0, 3.0)
@export var shadow_color: Color = Color(0.0, 0.0, 0.0, 0.18)
@export var shadow_grow: float = 1.0

var _slots: Array[Control] = []
var _frames: Array[TextureRect] = []
var _base_scale: Array[Vector2] = []
var _rest_y: Array[float] = []
var _content_rect: Array[Rect2] = []
var _materials: Array[ShaderMaterial] = []
var _shadows: Array[TextureRect] = []
var _tweens: Array[Tween] = []
var _entered := false
var _layout: Control


func build(layout: Control) -> void:
	_slots.clear()
	_frames.clear()
	_base_scale.clear()
	_rest_y.clear()
	_content_rect.clear()
	_materials.clear()
	_shadows.clear()
	_tweens.clear()
	_layout = layout
	if auto_layout:
		_layout_slots(layout)
	for i in SLOT_COUNT:
		var slot := layout.get_node_or_null("Slot%d" % i) as Control
		if slot == null:
			push_warning("MinigameScreens: no Slot%d under %s" % [i, layout.name])
			return
		_slots.append(slot)
		_base_scale.append(slot.scale)
		_tweens.append(null)
		slot.pivot_offset = slot.size * 0.5
		slot.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		slot.visible = false
		_build_frame(layout, slot, i)
	add_to_group("minigame_screens")
	get_viewport().size_changed.connect(_relayout)


func _layout_slots(layout: Control) -> void:
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var view: Vector2 = layout.get_viewport_rect().size
	var total_gap: float = gap * float(SLOT_COUNT - 1)
	var slot_w: float = ((view.x - side_margin * 2.0 - total_gap) / float(SLOT_COUNT)) * screen_scale
	var slot_h: float = slot_w * (ART_SIZE.y / ART_SIZE.x)
	var row_w: float = slot_w * float(SLOT_COUNT) + total_gap
	var start_x: float = (view.x - row_w) * 0.5
	for i in SLOT_COUNT:
		var slot := layout.get_node_or_null("Slot%d" % i) as Control
		if slot == null:
			continue
		slot.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		slot.scale = Vector2.ONE
		slot.size = Vector2(slot_w, slot_h)
		slot.position = Vector2(start_x + (slot_w + gap) * float(i), top_margin)


func _build_frame(layout: Control, slot: Control, index: int) -> void:
	var atlas := AtlasTexture.new()
	atlas.atlas = SCREEN_TEXTURE
	atlas.region = ART_REGION

	var shadow: TextureRect = null
	if shadow_enabled:
		shadow = TextureRect.new()
		shadow.name = "ScreenShadow%d" % index
		shadow.texture = atlas
		shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		shadow.stretch_mode = TextureRect.STRETCH_SCALE
		shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shadow.modulate = shadow_color
		layout.add_child(shadow)
		layout.move_child(shadow, slot.get_index())
	_shadows.append(shadow)

	var frame := TextureRect.new()
	frame.name = "Screen%d" % index
	frame.texture = atlas
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var mat := ShaderMaterial.new()
	mat.shader = SCREEN_SHADER
	mat.set_shader_parameter("screen_color", BombController.PLAYER_COLORS[index])
	mat.set_shader_parameter("screen_boost", boost_off)
	frame.material = mat
	_materials.append(mat)

	layout.add_child(frame)
	layout.move_child(frame, slot.get_index())
	_frames.append(frame)
	_rest_y.append(0.0)
	_content_rect.append(Rect2())
	_place_frame(index)
	frame_off_screen(index)


func _place_frame(index: int) -> void:
	var slot: Control = _slots[index]
	var frame: TextureRect = _frames[index] if index < _frames.size() else null
	if frame == null:
		return
	var visual_size: Vector2 = slot.size * slot.scale
	var visual_pos: Vector2 = slot.position + slot.pivot_offset * (Vector2.ONE - slot.scale)
	var s: float = minf(visual_size.x / ART_SIZE.x, visual_size.y / ART_SIZE.y) * frame_scale
	var nudge: Vector2 = frame_offset
	if index < frame_offset_per_slot.size():
		nudge += frame_offset_per_slot[index]
	frame.size = ART_SIZE * s
	frame.position = visual_pos + (visual_size - frame.size) * 0.5 + nudge
	_rest_y[index] = frame.position.y
	_place_shadow(index)
	var s_local: float = s / slot.scale.x
	var frame_tl_local: Vector2 = (frame.position - visual_pos) / slot.scale
	_content_rect[index] = Rect2(
		frame_tl_local + DISPLAY_ORIGIN * s_local,
		DISPLAY_SIZE * s_local,
	)


func frame_off_screen(index: int) -> void:
	if index < 0 or index >= _frames.size():
		return
	_frames[index].position.y = -_frames[index].size.y - 40.0
	_sync_shadow_y(index)


func get_reserved_height() -> float:
	var view: Vector2 = get_viewport().get_visible_rect().size
	var total_gap: float = gap * float(SLOT_COUNT - 1)
	var slot_w: float = ((view.x - side_margin * 2.0 - total_gap) / float(SLOT_COUNT)) * screen_scale
	return top_margin + slot_w * (ART_SIZE.y / ART_SIZE.x)


func _relayout() -> void:
	if _frames.is_empty() or _layout == null:
		return
	if auto_layout:
		_layout_slots(_layout)
	for i in _frames.size():
		_slots[i].pivot_offset = _slots[i].size * 0.5
		_place_frame(i)
		if not _entered:
			frame_off_screen(i)
	for i in _slots.size():
		for child in _slots[i].get_children():
			if child is Control:
				fit_content(i, child)


func play_entrance() -> void:
	if _entered or _frames.is_empty():
		return
	_entered = true
	for i in _frames.size():
		var tw := create_tween()
		tw.tween_interval(entrance_stagger * float(i))
		tw.tween_method(_slide_screen.bind(i), _frames[i].position.y, _rest_y[i], entrance_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _slide_screen(y: float, index: int) -> void:
	_frames[index].position.y = y
	_sync_shadow_y(index)


func _place_shadow(index: int) -> void:
	var shadow: TextureRect = _shadows[index] if index < _shadows.size() else null
	if shadow == null:
		return
	var frame: TextureRect = _frames[index]
	shadow.size = frame.size * shadow_grow
	shadow.position = frame.position + shadow_offset - (shadow.size - frame.size) * 0.5


func _sync_shadow_y(index: int) -> void:
	var shadow: TextureRect = _shadows[index] if index < _shadows.size() else null
	if shadow == null:
		return
	shadow.position.y = _frames[index].position.y + shadow_offset.y


func fit_content(slot_index: int, instance: Control) -> void:
	if slot_index < 0 or slot_index >= _content_rect.size():
		instance.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return
	var r: Rect2 = _content_rect[slot_index]
	var design := content_design_size
	var k: float = minf(r.size.x / design.x, r.size.y / design.y) * content_fill
	if k <= 0.0:
		return
	instance.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	instance.pivot_offset = Vector2.ZERO
	instance.size = design
	instance.scale = Vector2(k, k)
	instance.position = r.position + (r.size - design * k) * 0.5


func power_on(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _slots.size():
		return
	var slot := _slots[slot_index]
	var base: Vector2 = _base_scale[slot_index]
	_kill(slot_index)
	slot.visible = true
	slot.scale = Vector2(base.x * dot_width, base.y * collapsed_height)
	slot.modulate = flash_color
	_set_boost(boost_flash, slot_index)
	var tw := create_tween()
	tw.tween_property(slot, "scale:x", base.x, line_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(line_hold)
	tw.tween_property(slot, "scale:y", base.y, power_on_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(slot, "modulate", Color.WHITE, power_on_duration)
	tw.parallel().tween_method(_set_boost.bind(slot_index), boost_flash, boost_on, power_on_duration)
	_tweens[slot_index] = tw


func power_off(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _slots.size():
		return
	var slot := _slots[slot_index]
	if not slot.visible:
		return
	var base: Vector2 = _base_scale[slot_index]
	_kill(slot_index)
	var tw := create_tween()
	tw.tween_property(slot, "modulate", flash_color, power_off_duration * 0.45)
	tw.parallel().tween_property(slot, "scale:y", base.y * collapsed_height, power_off_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_method(_set_boost.bind(slot_index), boost_on, boost_flash, power_off_duration * 0.45)
	tw.tween_interval(line_hold)
	tw.tween_property(slot, "scale:x", base.x * dot_width, line_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_method(_set_boost.bind(slot_index), boost_flash, boost_off, line_duration)
	tw.tween_callback(_reset_slot.bind(slot_index))
	_tweens[slot_index] = tw
	await tw.finished


func snap_off(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _slots.size():
		return
	_kill(slot_index)
	_reset_slot(slot_index)


func _set_boost(value: float, slot_index: int) -> void:
	if slot_index >= 0 and slot_index < _materials.size():
		_materials[slot_index].set_shader_parameter("screen_boost", value)


func _reset_slot(slot_index: int) -> void:
	var slot := _slots[slot_index]
	slot.visible = false
	slot.scale = _base_scale[slot_index]
	slot.modulate = Color.WHITE
	_set_boost(boost_off, slot_index)


func _kill(slot_index: int) -> void:
	var tw: Tween = _tweens[slot_index]
	if tw and tw.is_valid():
		tw.kill()
	_tweens[slot_index] = null
