extends Node2D
class_name SafeZone

signal expired

@export var start_radius: float = 1200.0
@export var end_radius: float = 220.0
@export var shrink_duration: float = 30.0
@export var hold_duration: float = 10.0
@export var outer_gravity_multiplier: float = 0.35
@export var outside_death_time: float = 2.0
@export var outside_fill_color: Color = Color(0.55, 0.05, 0.08, 0.35)
@export var edge_softness: float = 40.0
@export var spot_scale: float = 80.0
@export var spot_speed: float = 0.6
@export var spot_warp_strength: float = 2.2
@export var churn_scale: float = 30.0
@export var churn_speed: float = 1.4
@export var churn_strength: float = 0.6
@export var spot_darkness: float = 0.8
@export var zigzag_amplitude: float = 8.0
@export var zigzag_frequency: float = 6.0
@export var zigzag_speed: float = 2.0
@export var ripple_radius: float = 220.0
@export var ripple_strength: float = 55.0
@export var pixel_size: float = 3.0
@export var fade_duration: float = 2.0 

var _activate_time_ms: int = -1
var _overlay: ColorRect
var _overlay_material: ShaderMaterial
var _overlay_layer: CanvasLayer

const MAX_PLAYERS := 4

const OVERLAY_SHADER := """
shader_type canvas_item;
uniform float fade_alpha;
uniform vec2 view_center;
uniform float cam_zoom;
uniform vec2 viewport_size;
uniform vec2 zone_center;
uniform float zone_radius;
uniform float edge_soft;
uniform vec4 fill_color : source_color;
uniform float spot_scale;
uniform float spot_speed;
uniform float spot_warp_strength;
uniform float churn_scale;
uniform float churn_speed;
uniform float churn_strength;
uniform float spot_darkness;
uniform float time_offset;
uniform float zig_amplitude;
uniform float zig_frequency;
uniform float zig_speed;
uniform vec2 player_pos[4];
uniform int player_count;
uniform float ripple_radius;
uniform float ripple_strength;
uniform float pixel_size;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

void fragment() {
	vec2 frag_screen = SCREEN_UV * viewport_size;
	vec2 world_pos = view_center + (frag_screen - viewport_size * 0.5) / cam_zoom;
	world_pos = floor(world_pos / pixel_size) * pixel_size;
	
	vec2 delta = world_pos - zone_center;
	float dist = length(delta);
	float ang = atan(delta.y, delta.x);
	float jag = sin(ang * zig_frequency + time_offset * zig_speed) * zig_amplitude;
	float local_radius = zone_radius + jag;
	float outside = smoothstep(local_radius - edge_soft, local_radius, dist);
	
	vec2 player_push = vec2(0.0);
	for (int i = 0; i < player_count; i++) {
		vec2 to_frag = world_pos - player_pos[i];
		float d = length(to_frag);
		if (d < ripple_radius && d > 0.001) {
			float falloff = 1.0 - (d / ripple_radius);
			player_push += normalize(to_frag) * falloff * falloff * ripple_strength;
		}
	}
	
	vec2 disturbed_pos = world_pos + player_push;
	
	vec2 p = disturbed_pos / spot_scale;
	vec2 warp = vec2(
		noise(p * 0.4 + time_offset * spot_speed * 0.6),
		noise(p * 0.4 + time_offset * spot_speed * 0.6 + 8.3)
	) * spot_warp_strength;
	float base_n = noise(p + warp + time_offset * spot_speed);
	
	vec2 cp = disturbed_pos / churn_scale;
	float churn_n = noise(cp - time_offset * churn_speed);
	
	float n = base_n + (churn_n - 0.5) * churn_strength;
	float spots = smoothstep(0.5, 0.72, n);
	
	COLOR = fill_color;
	COLOR.rgb *= mix(1.0, 1.0 - spot_darkness, spots);
	COLOR.a *= outside * fade_alpha; 
}
"""

func _ready() -> void:
	add_to_group("safe_zones")
	_setup_overlay()

func _setup_overlay() -> void:
	_overlay = ColorRect.new()
	_overlay.name = "SafeZoneOverlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = OVERLAY_SHADER
	_overlay_material = ShaderMaterial.new()
	_overlay_material.shader = shader
	_overlay_material.set_shader_parameter("fill_color", outside_fill_color)
	_overlay_material.set_shader_parameter("edge_soft", edge_softness)
	_overlay_material.set_shader_parameter("spot_scale", spot_scale)
	_overlay_material.set_shader_parameter("spot_speed", spot_speed)
	_overlay_material.set_shader_parameter("spot_warp_strength", spot_warp_strength)
	_overlay_material.set_shader_parameter("churn_scale", churn_scale)
	_overlay_material.set_shader_parameter("churn_speed", churn_speed)
	_overlay_material.set_shader_parameter("churn_strength", churn_strength)
	_overlay_material.set_shader_parameter("spot_darkness", spot_darkness)
	_overlay_material.set_shader_parameter("zig_frequency", zigzag_frequency)
	_overlay_material.set_shader_parameter("zig_amplitude", zigzag_amplitude)
	_overlay_material.set_shader_parameter("zig_speed", zigzag_speed)
	_overlay_material.set_shader_parameter("ripple_radius", ripple_radius)
	_overlay_material.set_shader_parameter("ripple_strength", ripple_strength)
	_overlay_material.set_shader_parameter("pixel_size", pixel_size)
	_overlay.material = _overlay_material
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.name = "SafeZoneOverlayLayer"
	_overlay_layer.layer = 5
	_overlay_layer.add_child(_overlay)
	get_tree().current_scene.add_child.call_deferred(_overlay_layer)

func activate() -> void:
	_activate_time_ms = _get_timestamp()

func _is_networked() -> bool:
	return multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)

func _get_timestamp() -> int:
	if _is_networked():
		return Networking.get_sync_time()
	return Time.get_ticks_msec()

func get_radius() -> float:
	if _activate_time_ms < 0:
		return start_radius
	var elapsed: float = float(_get_timestamp() - _activate_time_ms) / 1000.0
	var t: float = clampf(elapsed / shrink_duration, 0.0, 1.0)
	return lerpf(start_radius, end_radius, t)

func is_outside(world_pos: Vector2) -> bool:
	return global_position.distance_to(world_pos) > get_radius()

func _process(_delta: float) -> void:
	_update_overlay()
	if _activate_time_ms < 0:
		return
	var elapsed: float = float(_get_timestamp() - _activate_time_ms) / 1000.0
	if elapsed >= shrink_duration + hold_duration:
		expired.emit()
		if is_instance_valid(_overlay_layer):
			_overlay_layer.queue_free()
		queue_free()

func _update_overlay() -> void:
	if _overlay_material == null:
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var view_center: Vector2 = cam.global_position + cam.offset
	var viewport_size: Vector2 = get_viewport_rect().size
	var t: float = float(_get_timestamp()) / 1000.0
	_overlay_material.set_shader_parameter("view_center", view_center)
	_overlay_material.set_shader_parameter("cam_zoom", cam.zoom.x)
	_overlay_material.set_shader_parameter("viewport_size", viewport_size)
	_overlay_material.set_shader_parameter("zone_center", global_position)
	_overlay_material.set_shader_parameter("zone_radius", get_radius())
	_overlay_material.set_shader_parameter("time_offset", t)
	_overlay_material.set_shader_parameter("fade_alpha", _get_fade_alpha())  
	
	var player_positions: Array[Vector2] = []
	for p in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(p) and not p.is_dead and player_positions.size() < MAX_PLAYERS:
			player_positions.append(p.global_position)
	while player_positions.size() < MAX_PLAYERS:
		player_positions.append(Vector2(-999999.0, -999999.0))
	_overlay_material.set_shader_parameter("player_pos", PackedVector2Array(player_positions))
	_overlay_material.set_shader_parameter("player_count", mini(get_tree().get_nodes_in_group("players").size(), MAX_PLAYERS))


func _get_fade_alpha() -> float:  
	if _activate_time_ms < 0:
		return 0.0
	var elapsed: float = float(_get_timestamp() - _activate_time_ms) / 1000.0
	var total: float = shrink_duration + hold_duration
	if elapsed < fade_duration:
		return clampf(elapsed / fade_duration, 0.0, 1.0)
	if elapsed > total - fade_duration:
		return clampf((total - elapsed) / fade_duration, 0.0, 1.0)
	return 1.0
