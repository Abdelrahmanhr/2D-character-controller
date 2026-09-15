extends Node
# Autoload as "UIFeedback"

## Subtle reactive accents on every Button in the game. Wiring mirrors UISfx:
## hook node_added and sweep the existing tree, so nothing needs per-scene setup.
##
## Deliberately quiet. The hard limits below are the point, not placeholders:
##   - scale never leaves 0.96 .. 1.06 (6%)
##   - nothing translates, rotates or shakes
##   - particles are 2-4px, alpha <= 0.55, and all dead within 0.35s
## No audio: UISfx already owns button sound, and doubling up is exactly the
## "too much" failure this is trying to avoid.

const OPT_OUT := &"no_ui_feedback"

const HOVER_SCALE := Vector2(1.03, 1.03)
const HOVER_TIME: float = 0.09
const BLUR_TIME: float = 0.12
const FLASH_TINT := Color(1.10, 1.10, 1.10)

const PRESS_SQUASH := Vector2(0.96, 1.05)
const RELEASE_POSES: Array[Vector2] = [Vector2(1.06, 0.94), Vector2(0.99, 1.01)]
const FRAME: float = 1.0 / 30.0

const POOL_SIZE := 4

@export var enabled: bool = true
@export var particles_enabled: bool = true

var _layer: CanvasLayer
var _pool: Array[CPUParticles2D] = []
var _next_pool_index: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_pool()
	get_tree().node_added.connect(_on_node_added)
	_wire_recursive(get_tree().root)


# --- wiring -------------------------------------------------------------------

func _on_node_added(node: Node) -> void:
	if node is Button:
		_wire_button(node)


func _wire_recursive(node: Node) -> void:
	if node is Button:
		_wire_button(node)
	for child in node.get_children():
		_wire_recursive(child)


func _wire_button(button: Button) -> void:
	if button.is_in_group(OPT_OUT) or button.has_meta(OPT_OUT):
		return
	if not button.mouse_entered.is_connected(_on_focus):
		button.mouse_entered.connect(_on_focus.bind(button))
	if not button.focus_entered.is_connected(_on_focus):
		button.focus_entered.connect(_on_focus.bind(button))
	if not button.mouse_exited.is_connected(_on_blur):
		button.mouse_exited.connect(_on_blur.bind(button))
	if not button.focus_exited.is_connected(_on_blur):
		button.focus_exited.connect(_on_blur.bind(button))
	if not button.button_down.is_connected(_on_press):
		button.button_down.connect(_on_press.bind(button))
	if not button.pressed.is_connected(_on_release):
		button.pressed.connect(_on_release.bind(button))


# --- responses ----------------------------------------------------------------

func _on_focus(button: Button) -> void:
	if not _active(button):
		return
	_prepare(button)
	var tw := _restart_tween(button)
	tw.set_parallel(true)
	tw.tween_property(button, "scale", HOVER_SCALE, HOVER_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(button, "modulate", FLASH_TINT, 0.05)
	tw.chain().tween_property(button, "modulate", Color.WHITE, 0.10)
	_sparks(button, 3, 0.35, 25.0, 55.0, Vector2(0.0, 240.0), 0.45, true)


func _on_blur(button: Button) -> void:
	if not _active(button):
		return
	var tw := _restart_tween(button)
	tw.set_parallel(true)
	tw.tween_property(button, "scale", Vector2.ONE, BLUR_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(button, "modulate", Color.WHITE, BLUR_TIME)


func _on_press(button: Button) -> void:
	if not _active(button):
		return
	_prepare(button)
	_kill_tween(button)
	button.scale = PRESS_SQUASH


func _on_release(button: Button) -> void:
	if not _active(button):
		return
	var settled: Vector2 = HOVER_SCALE if (button.has_focus() or button.is_hovered()) else Vector2.ONE
	var tw := _restart_tween(button)
	for pose in RELEASE_POSES:
		tw.tween_property(button, "scale", pose, 0.0)
		tw.tween_interval(FRAME * 2.0)
	tw.tween_property(button, "scale", settled, 0.0)
	_sparks(button, 5, 0.30, 60.0, 130.0, Vector2(0.0, 380.0), 0.55, false)


# --- plumbing -----------------------------------------------------------------

func _active(button: Button) -> bool:
	return enabled and is_instance_valid(button) and not button.disabled


## Containers size their children after _ready, so the pivot has to be taken
## lazily and refreshed whenever the size moves, or the pop grows from the corner.
func _prepare(button: Button) -> void:
	if button.get_meta("_fb_size", Vector2.INF) != button.size:
		button.pivot_offset = button.size * 0.5
		button.set_meta("_fb_size", button.size)


func _kill_tween(button: Button) -> void:
	if not button.has_meta("_fb_tween"):
		return
	var previous: Tween = button.get_meta("_fb_tween")
	if previous != null and previous.is_valid():
		previous.kill()
	button.remove_meta("_fb_tween")


func _restart_tween(button: Button) -> Tween:
	_kill_tween(button)
	var tw := button.create_tween()
	button.set_meta("_fb_tween", tw)
	return tw


## Pooled on one always-processing layer rather than parented per button: this
## keeps three extra nodes off every Button in the game, and keeps the accents
## alive if anything ever pauses the tree again.
func _build_pool() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "UIFeedbackFx"
	_layer.layer = 90
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_layer)
	for i in POOL_SIZE:
		var particles := UIParticles.make(_layer, 5, 0.35)
		particles.emitting = false
		particles.one_shot = true
		particles.explosiveness = 1.0
		particles.scale_amount_min = 2.0
		particles.scale_amount_max = 4.0
		_pool.append(particles)


func _sparks(button: Button, amount: int, lifetime: float, vmin: float, vmax: float,
		gravity: Vector2, alpha: float, bottom_edge: bool) -> void:
	if not particles_enabled or _pool.is_empty():
		return
	var rect := button.get_global_rect()
	if rect.size == Vector2.ZERO:
		return
	var particles := _pool[_next_pool_index]
	_next_pool_index = (_next_pool_index + 1) % _pool.size()

	particles.amount = amount
	particles.lifetime = lifetime
	particles.initial_velocity_min = vmin
	particles.initial_velocity_max = vmax
	particles.gravity = gravity
	particles.damping_min = 30.0
	particles.damping_max = 70.0
	particles.color_ramp = null
	particles.color = Color(UIParticles.FLARE, alpha)
	if bottom_edge:
		particles.position = Vector2(rect.position.x + rect.size.x * 0.5, rect.end.y)
		particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		particles.emission_rect_extents = Vector2(rect.size.x * 0.4, 1.0)
		particles.direction = Vector2(0.0, -1.0)
		particles.spread = 30.0
	else:
		particles.position = rect.position + rect.size * 0.5
		particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
		particles.direction = Vector2(0.0, -1.0)
		particles.spread = 180.0
	particles.restart()
