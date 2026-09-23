@tool
extends Node2D
class_name NeonSign


const SYMBOL_PATH := "res://resources/residential-area-tileset-pixel-art/3 Objects/Symbols/%d.png"
const SYMBOL_COUNT := 21

@export_range(1, SYMBOL_COUNT) var symbol_index: int = 1: set = _set_symbol_index
@export var neon_color: Color = Color(1, 0.35, 0.85): set = _set_neon_color
@export_range(0.0, 4.0, 0.05) var brightness: float = 1.1: set = _set_brightness
@export_range(0.5, 8.0, 0.25) var sign_scale: float = 3.0: set = _set_sign_scale

@export_group("Halo")
@export_range(0.0, 2.0, 0.05) var halo_strength: float = 0.5: set = _set_halo_strength
@export_range(0.1, 8.0, 0.05) var halo_size: float = 0.45: set = _set_halo_size

@export_group("Cast light")
# Off by default: under the GL Compatibility renderer every Light2D costs an extra
# draw pass over everything it overlaps, and the residential arena carries 44 signs.
# The additive Halo sprite plus the WorldEnvironment glow carry the look instead.
@export var cast_light: bool = false: set = _set_cast_light
@export_range(0.0, 4.0, 0.05) var light_energy: float = 0.7: set = _set_light_energy
@export_range(0.1, 12.0, 0.05) var light_radius: float = 0.9: set = _set_light_radius

@export_group("Animation")
@export var flicker: bool = false
@export_range(0.0, 1.0, 0.005) var flicker_chance: float = 0.02
@export var flicker_min_duration: float = 0.03
@export var flicker_max_duration: float = 0.12
@export var flicker_dim_min: float = 0.15
@export var flicker_dim_max: float = 0.55
@export_range(0.0, 1.0, 0.05) var double_flicker_chance: float = 0.35
@export var pulse: bool = true
@export var pulse_speed: float = 1.4
@export_range(0.0, 1.0, 0.01) var pulse_depth: float = 0.12
@export_range(0.0, 1.0, 0.05) var pulse_variance: float = 0.35

@onready var _symbol: Sprite2D = $Symbol
@onready var _halo: Sprite2D = $Halo
@onready var _light: PointLight2D = $Light

var _flicker_time_left: float = 0.0
var _flicker_level: float = 1.0
var _queued_flicker: bool = false
var _pulse_phase: float = 0.0
var _pulse_speed: float = 0.0
var _pulse_depth: float = 0.0
var _applied_level: float = -1.0
var _loaded_symbol_index: int = -1

const LEVEL_EPSILON: float = 0.002


func _ready() -> void:
	_pulse_phase = randf() * TAU
	_pulse_speed = pulse_speed * randf_range(1.0 - pulse_variance, 1.0 + pulse_variance)
	_pulse_depth = pulse_depth * randf_range(1.0 - pulse_variance, 1.0 + pulse_variance)
	_refresh()
	# A sign that neither flickers nor pulses is static art - it needs no frame budget.
	set_process(flicker or pulse)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_advance_flicker(delta)
	_pulse_phase += _pulse_speed * delta
	var pulse_level: float = 1.0
	if pulse:
		pulse_level = 1.0 - _pulse_depth * (0.5 - 0.5 * cos(_pulse_phase))
	_apply_intensity(_flicker_level * pulse_level)


func _advance_flicker(delta: float) -> void:
	if not flicker:
		_flicker_level = 1.0
		return
	if _flicker_time_left > 0.0:
		_flicker_time_left -= delta
		if _flicker_time_left <= 0.0:
			if _queued_flicker:
				_queued_flicker = false
				_start_flicker()
			else:
				_flicker_level = 1.0
		return
	_flicker_level = 1.0
	if randf() < flicker_chance:
		_start_flicker()


func _start_flicker() -> void:
	_flicker_time_left = randf_range(flicker_min_duration, flicker_max_duration)
	_flicker_level = randf_range(flicker_dim_min, flicker_dim_max)
	if randf() < double_flicker_chance:
		_queued_flicker = true


func _apply_intensity(level: float) -> void:
	if _symbol == null:
		return
	# The pulse moves by a fraction of a percent per frame, so most frames would
	# re-upload an identical shader uniform. Skip those.
	if absf(level - _applied_level) < LEVEL_EPSILON:
		return
	_applied_level = level
	var mat := _symbol.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("brightness", brightness * level)
	_halo.modulate.a = halo_strength * level
	if cast_light:
		_light.energy = light_energy * level


func _refresh() -> void:
	if not is_inside_tree():
		return
	if _symbol == null:
		_symbol = get_node_or_null("Symbol")
		_halo = get_node_or_null("Halo")
		_light = get_node_or_null("Light")
	if _symbol == null or _halo == null or _light == null:
		return

	# _refresh() fires from nine setters, so every property applied at scene load used
	# to trigger a ResourceLoader round-trip. Only reload when the symbol changed.
	if symbol_index != _loaded_symbol_index:
		_loaded_symbol_index = symbol_index
		_symbol.texture = load(SYMBOL_PATH % symbol_index)
	_symbol.scale = Vector2.ONE * sign_scale
	_symbol.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	var mat := _symbol.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("neon_color", neon_color)
		mat.set_shader_parameter("brightness", brightness)

	_halo.scale = Vector2.ONE * halo_size
	_halo.modulate = Color(neon_color.r, neon_color.g, neon_color.b, halo_strength)

	_applied_level = -1.0
	_light.enabled = cast_light
	_light.color = neon_color
	_light.energy = light_energy
	_light.texture_scale = light_radius


func _set_symbol_index(value: int) -> void:
	symbol_index = clampi(value, 1, SYMBOL_COUNT)
	_refresh()


func _set_neon_color(value: Color) -> void:
	neon_color = value
	_refresh()


func _set_brightness(value: float) -> void:
	brightness = value
	_refresh()


func _set_sign_scale(value: float) -> void:
	sign_scale = value
	_refresh()


func _set_halo_strength(value: float) -> void:
	halo_strength = value
	_refresh()


func _set_halo_size(value: float) -> void:
	halo_size = value
	_refresh()


func _set_cast_light(value: bool) -> void:
	cast_light = value
	_refresh()


func _set_light_energy(value: float) -> void:
	light_energy = value
	_refresh()


func _set_light_radius(value: float) -> void:
	light_radius = value
	_refresh()
