extends Line2D
class_name LightningBolt


signal fade_finished(bolt: LightningBolt)

const TEAL := Color(0.1529, 0.8275, 0.7961)
const WIDTH_CURVE_VARIANTS := 8

@export var divider: float = 40.0
@export var sway_divider: float = 40.0
@export var max_sway: float = 10.0
@export var life: float = 0.5
@export var flicker_steps: int = 3
@export var light_energy: float = 1.7
@export var light_radius_scale: float = 1.0

# Emitters spawn ~20 bolts a second, and these are identical for every bolt, so
# they are built once for the whole process instead of per instance. Previously
# each bolt uploaded its own 128x128 gradient texture and created its own
# material, which also broke draw-call batching.
static var _shared_gradient: Gradient = null
static var _shared_light_texture: GradientTexture2D = null
static var _shared_material: CanvasItemMaterial = null
static var _shared_width_curves: Array[Curve] = []

var _sway_amount: float = 0.0
var _point_offsets: Array[float] = []
var _light: PointLight2D
var _tween: Tween


func _ready() -> void:
	joint_mode = Line2D.LINE_JOINT_ROUND
	begin_cap_mode = Line2D.LINE_CAP_ROUND
	end_cap_mode = Line2D.LINE_CAP_ROUND
	_build_shared()
	gradient = _shared_gradient
	material = _shared_material
	_build_light()


static func _build_shared() -> void:
	if _shared_gradient != null:
		return

	_shared_gradient = Gradient.new()
	_shared_gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	_shared_gradient.colors = PackedColorArray([
		Color(1, 1, 1, 1),
		Color(0.7569, 0.851, 0.949, 1),
		Color(TEAL.r, TEAL.g, TEAL.b, 1),
	])

	var glow := Gradient.new()
	glow.offsets = PackedFloat32Array([0.0, 1.0])
	glow.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	_shared_light_texture = GradientTexture2D.new()
	_shared_light_texture.gradient = glow
	_shared_light_texture.width = 128
	_shared_light_texture.height = 128
	_shared_light_texture.fill = GradientTexture2D.FILL_RADIAL
	_shared_light_texture.fill_from = Vector2(0.5, 0.5)
	_shared_light_texture.fill_to = Vector2(0.5, 0.0)

	_shared_material = CanvasItemMaterial.new()
	_shared_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_shared_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED

	# A handful of pregenerated silhouettes reads as randomly as a fresh curve per
	# bolt, at a fraction of the cost.
	_shared_width_curves.clear()
	for _v in WIDTH_CURVE_VARIANTS:
		var curve := Curve.new()
		curve.min_value = 0.0
		curve.max_value = 1.0
		for i in 6:
			curve.add_point(Vector2(float(i) / 5.0, randf_range(0.35, 1.0)))
		_shared_width_curves.append(curve)


func _build_light() -> void:
	_light = PointLight2D.new()
	_light.texture = _shared_light_texture
	_light.color = Color(0.549, 0.8549, 1)
	_light.energy = 0.0
	add_child(_light)


# Returns the bolt to a clean state so an emitter can reuse it from a pool.
func reset() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null
	clear_points()
	self_modulate = Color.WHITE
	if _light:
		_light.energy = 0.0
	width_curve = _shared_width_curves[randi() % _shared_width_curves.size()]


func _place_light() -> void:
	if _light == null or get_point_count() < 2:
		return
	var a: Vector2 = get_point_position(0)
	var b: Vector2 = get_point_position(get_point_count() - 1)
	_light.position = (a + b) / 2.0
	_light.texture_scale = maxf(a.distance_to(b) / 96.0, 1.0) * light_radius_scale


func set_start(pos: Vector2) -> void:
	add_point(pos)


func set_end(pos: Vector2) -> void:
	add_point(pos)


func segmentize(from_to: Vector2, start_position: Vector2) -> void:
	_point_offsets.clear()
	var distance: float = from_to.length()
	_sway_amount = minf(distance / sway_divider, max_sway)
	var segment_count: int = int(distance / divider)
	for i in segment_count:
		_point_offsets.append(randf())
	_point_offsets.sort()
	var point_index: int = 1
	for offset in _point_offsets:
		add_point(start_position + offset * from_to, point_index)
		point_index += 1


func sway(normal: Vector2) -> void:
	var last_index: int = get_point_count() - 1
	for i in last_index:
		if i == 0:
			continue
		var offset: Vector2 = (get_point_position(i) + get_point_position(i - 1)) / 2.0
		offset += normal * randf_range(-_sway_amount, _sway_amount)
		set_point_position(i, offset)


func play_fade() -> void:
	_place_light()
	var tween := create_tween()
	_tween = tween
	var step: float = (life * 0.4) / float(maxi(flicker_steps, 1))
	for i in flicker_steps:
		tween.tween_callback(_set_brightness.bind(randf_range(0.45, 1.0)))
		tween.tween_interval(step)
	tween.tween_property(self, "self_modulate", Color(TEAL.r, TEAL.g, TEAL.b, 0.0), life * 0.6)
	if _light:
		tween.parallel().tween_property(_light, "energy", 0.0, life * 0.6)
	tween.finished.connect(_on_fade_finished)


func _on_fade_finished() -> void:
	fade_finished.emit(self)


func _set_brightness(value: float) -> void:
	self_modulate = Color(value, value, value, 1.0)
	if _light:
		_light.energy = value * light_energy
