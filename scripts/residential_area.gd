extends ArenaBase


@export_group("Mood")
@export var ambient_tint: Color = Color(0.8706, 0.7412, 0.6863)

@export_group("Tiles")
# Lifted slightly to make up for the neon signs no longer spilling light on the tiles.
@export var tile_lift: float = 1.6
@export var tile_tint: Color = Color(1, 0.9686, 0.9333)

@export_group("Parallax")
@export var parallax_root: NodePath = ^"LocalParallax"

@export var parallax_tints: Array[Color] = [
	Color(0.9569, 0.6235, 0.4471),
	Color(0.5216, 0.4235, 0.5294),
	Color(0.4471, 0.3608, 0.4784),
	Color(0.3765, 0.3020, 0.4275),
	Color(0.2431, 0.1961, 0.3216),
	Color(0.1843, 0.1490, 0.2706),
]

@export_group("Dust")
@export var dust_path: NodePath = ^"DustMotes"
@export var dust_margin: float = 200.0

@export_group("Layer Shadow")
@export var shadow_layer_path: NodePath = ^"tiles/TileMapLayer"
# Off: this duplicated the 2,847-cell TileMapLayer at runtime for a fake drop
# shadow - a whole second rasterization of the largest layer. Flip back to true
# if the flat look turns out to matter.
@export var shadow_enabled: bool = false
@export_range(0, 8) var shadow_steps: int = 1
@export var shadow_offset: Vector2 = Vector2(3.0, 5.0)
@export_range(0.0, 1.0, 0.01) var shadow_opacity: float = 0.25
@export var shadow_color: Color = Color(0.0706, 0.0392, 0.1176)

var _dust: GPUParticles2D
var _dust_shape: ParticleProcessMaterial
var _dust_extents: Vector2 = Vector2.ZERO


func _music_id() -> StringName:
	return &"arena_residential"


func _ready() -> void:
	super()
	var dim := CanvasModulate.new()
	dim.name = "AmbientDusk"
	dim.color = ambient_tint
	add_child(dim)
	_lift_tiles()
	_tint_parallax()
	_setup_dust()
	_build_layer_shadow()


func _build_layer_shadow() -> void:
	if not shadow_enabled or shadow_steps <= 0:
		return
	var layer := get_node_or_null(shadow_layer_path) as TileMapLayer
	if layer == null:
		push_warning("residential_area.gd: no TileMapLayer at '%s' to shade." % shadow_layer_path)
		return
	var parent := layer.get_parent()
	var tint := Color(shadow_color.r, shadow_color.g, shadow_color.b, shadow_opacity)
	for i in shadow_steps:
		var step: float = float(i + 1) / float(shadow_steps)
		var copy := layer.duplicate() as TileMapLayer
		copy.name = "%sShadow%d" % [layer.name, i]
		copy.position = layer.position + shadow_offset * step
		copy.modulate = tint
		copy.collision_enabled = false
		copy.navigation_enabled = false
		parent.add_child(copy)
		parent.move_child(copy, layer.get_index())


func _setup_dust() -> void:
	_dust = get_node_or_null(dust_path)
	if _dust == null:
		push_warning("residential_area.gd: no node at '%s' — no ambient dust." % dust_path)
		return
	_dust.local_coords = false
	_dust_shape = _dust.process_material as ParticleProcessMaterial


func _process(_delta: float) -> void:
	if _dust == null:
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	_dust.global_position = cam.get_screen_center_position()
	if _dust_shape == null:
		return
	var zoom: Vector2 = cam.zoom
	if zoom.x <= 0.0 or zoom.y <= 0.0:
		return
	var extents := (get_viewport_rect().size / zoom) * 0.5 + Vector2(dust_margin, dust_margin)
	if not extents.is_equal_approx(_dust_extents):
		_dust_extents = extents
		_dust_shape.emission_box_extents = Vector3(extents.x, extents.y, 1.0)


func _lift_tiles() -> void:
	var tiles := get_node_or_null("tiles")
	if tiles == null:
		push_warning("residential_area.gd: no 'tiles' node — platforms stay dim.")
		return
	var lifted := Color(
		tile_tint.r * tile_lift,
		tile_tint.g * tile_lift,
		tile_tint.b * tile_lift,
	)
	for layer in tiles.get_children():
		if layer is CanvasItem:
			layer.modulate = lifted


func _tint_parallax() -> void:
	var root := get_node_or_null(parallax_root)
	if root == null:
		push_warning("residential_area.gd: no node at '%s' to tint." % parallax_root)
		return
	var index := 0
	for layer in root.get_children():
		if not layer is ParallaxLayer2D:
			continue
		if index < parallax_tints.size():
			layer.modulate = parallax_tints[index]
		index += 1
