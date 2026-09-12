extends ArenaBase

@export var ambient_tint: Color = Color(0.62, 0.66, 0.78)

@export var platform_lift: float = 1.25
@export var platform_tint: Color = Color(0.88, 0.97, 1.0)

@export var glow_layer_path: NodePath = ^"tiles/TileMapLayer4"
@export var glow_layer_lift: float = 1.7
@export var glow_layer_tint: Color = Color(0.62, 0.95, 1.0)
@export var glow_layer_additive: bool = false


func _ready() -> void:
	super()
	var dim := CanvasModulate.new()
	dim.name = "AmbientDim"
	dim.color = ambient_tint
	add_child(dim)
	_lift_platforms()
	_light_glow_layer()


func _light_glow_layer() -> void:
	var layer := get_node_or_null(glow_layer_path)
	if layer == null:
		push_warning("power_station.gd: no node at '%s' to glow." % glow_layer_path)
		return
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	if glow_layer_additive:
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	layer.material = mat
	layer.modulate = Color(
		glow_layer_tint.r * glow_layer_lift,
		glow_layer_tint.g * glow_layer_lift,
		glow_layer_tint.b * glow_layer_lift,
	)


func _lift_platforms() -> void:
	var platforms := get_node_or_null("tiles/TileMapLayer2")
	if platforms == null:
		push_warning("power_station.gd: no tiles/TileMapLayer2 to light — platforms stay dim.")
		return
	platforms.modulate = Color(
		platform_tint.r * platform_lift,
		platform_tint.g * platform_lift,
		platform_tint.b * platform_lift,
	)
