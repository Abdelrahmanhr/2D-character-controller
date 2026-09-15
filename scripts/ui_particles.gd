class_name UIParticles

## Procedural pixel particles for menus and match outros. Same approach as the
## dust in scripts/player.gd (a 1x1 white image, nearest filtering, no asset), but
## the texture is cached here instead of rebuilt per call.
##
## Palette is the blk-nx64 set shared with scripts/title_logo_frames.gd.

const INK := Color("#12173d")
const NEON := Color("#8cdaff")
const MAGENTA := Color("#ff6eaf")
const BLAZE := Color("#ffaa6e")
const FLARE := Color("#ffe091")
const EMBER := Color("#e54286")

static var _pixel: Texture2D


static func pixel_texture() -> Texture2D:
	if _pixel == null:
		var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_pixel = ImageTexture.create_from_image(image)
	return _pixel


static func make(parent: Node, amount: int, lifetime: float) -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.texture = pixel_texture()
	particles.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	particles.amount = amount
	particles.lifetime = lifetime
	parent.add_child(particles)
	return particles


static func _ramp(colors: Array[Color]) -> Gradient:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array()
	gradient.colors = PackedColorArray()
	var last := maxi(colors.size() - 1, 1)
	for index in colors.size():
		gradient.add_point(float(index) / float(last), colors[index])
	return gradient


## Warm confetti thrown from the panel's top corners, plus a slow drift that keeps
## the screen alive once the burst has settled.
static func win(parent: Node, rect: Rect2, z: int = -1) -> void:
	for side in [-1.0, 1.0]:
		var burst := make(parent, 13, 1.1)
		burst.z_index = 10
		burst.position = Vector2(rect.position.x + (rect.size.x if side > 0.0 else 0.0), rect.position.y)
		burst.one_shot = true
		burst.explosiveness = 0.95
		burst.direction = Vector2(-side * 0.45, -1.0)
		burst.spread = 55.0
		burst.initial_velocity_min = 180.0
		burst.initial_velocity_max = 420.0
		burst.gravity = Vector2(0.0, 520.0)
		burst.angular_velocity_min = -240.0
		burst.angular_velocity_max = 240.0
		burst.damping_min = 20.0
		burst.damping_max = 60.0
		burst.scale_amount_min = 3.0
		burst.scale_amount_max = 6.0
		burst.color_ramp = _ramp([FLARE, BLAZE, Color(MAGENTA, 0.0)])
		burst.emitting = true

	var drift := make(parent, 14, 2.6)
	drift.z_index = z
	drift.position = Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y - 40.0)
	drift.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	drift.emission_rect_extents = Vector2(rect.size.x * 0.9, 8.0)
	drift.direction = Vector2(0.0, 1.0)
	drift.spread = 15.0
	drift.initial_velocity_min = 10.0
	drift.initial_velocity_max = 40.0
	drift.gravity = Vector2(0.0, 40.0)
	drift.scale_amount_min = 2.0
	drift.scale_amount_max = 4.0
	drift.color = Color(FLARE, 0.5)
	drift.emitting = true


## Cold ash: a dark puff on the slam, then motes that float rather than fall.
static func lose(parent: Node, rect: Rect2, tint: Color = Color.WHITE, z: int = -1) -> void:
	var puff := make(parent, 10, 0.7)
	puff.z_index = 10
	puff.position = rect.position + rect.size * 0.5
	puff.one_shot = true
	puff.explosiveness = 1.0
	puff.spread = 180.0
	puff.initial_velocity_min = 40.0
	puff.initial_velocity_max = 90.0
	puff.gravity = Vector2(0.0, 180.0)
	puff.damping_min = 60.0
	puff.damping_max = 120.0
	puff.scale_amount_min = 3.0
	puff.scale_amount_max = 5.0
	puff.color = Color(INK, 0.5) * tint
	puff.emitting = true

	var ash := make(parent, 18, 3.2)
	ash.z_index = z
	ash.position = Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + rect.size.y)
	ash.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	ash.emission_rect_extents = Vector2(rect.size.x * 0.6, 6.0)
	ash.spread = 40.0
	ash.initial_velocity_min = 8.0
	ash.initial_velocity_max = 28.0
	ash.gravity = Vector2(0.0, -12.0)
	ash.damping_min = 2.0
	ash.damping_max = 8.0
	ash.scale_amount_min = 2.0
	ash.scale_amount_max = 5.0
	ash.color_ramp = _ramp([
		Color(NEON, 0.0) * tint,
		Color(0.55, 0.67, 0.75, 0.35) * tint,
		Color(INK, 0.0) * tint,
	])
	ash.emitting = true


## Rises off a fallen player while the winner celebrates.
static func wisp(parent: Node, position: Vector2) -> CPUParticles2D:
	var smoke := make(parent, 9, 1.6)
	smoke.position = position + Vector2(0.0, -6.0)
	smoke.z_index = 2
	smoke.one_shot = true
	smoke.explosiveness = 0.25
	smoke.direction = Vector2(0.0, -1.0)
	smoke.spread = 22.0
	smoke.initial_velocity_min = 18.0
	smoke.initial_velocity_max = 46.0
	smoke.gravity = Vector2(0.0, -40.0)
	smoke.damping_min = 6.0
	smoke.damping_max = 18.0
	smoke.scale_amount_min = 2.0
	smoke.scale_amount_max = 5.0
	smoke.color_ramp = _ramp([
		Color(NEON, 0.0),
		Color(0.55, 0.67, 0.75, 0.30),
		Color(INK, 0.0),
	])
	smoke.emitting = true
	return smoke
