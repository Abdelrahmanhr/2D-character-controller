class_name UICascade

## Menu entrance motion, in the same "animate on twos" grammar as the title sting
## (scripts/title_logo_frames.gd): poses are HELD and then SNAP, rather than easing
## between. There the snap comes from double-keyed Animation tracks; here it comes
## from zero-duration tween_property + tween_interval pairs, because the element
## list is built at runtime and a baked NodePath per track would not survive the
## pause menu swapping pages or main_menu.gd reparenting OptionsPanel.
##
## Only scale and modulate are animated. Everything these run on lives inside a
## VBoxContainer, and containers own their children's position and size - a slide
## would be fought back every frame.

const FRAME: float = 1.0 / 30.0
const STAGGER: float = FRAME * 2.0
const PANEL_SLAM: float = 0.26

## squash -> overshoot -> correct -> settle, each held two frames.
const POSES: Array[Vector2] = [
	Vector2(1.38, 0.58),
	Vector2(0.88, 1.18),
	Vector2(1.06, 0.95),
	Vector2(0.98, 1.02),
	Vector2.ONE,
]

const TWEEN_META := "_cascade_tween"
const PIVOT_META := "_cascade_pivot_size"


static func reset(elements: Array[Control]) -> void:
	for element in elements:
		if is_instance_valid(element):
			_kill(element)
			element.scale = Vector2.ZERO
			element.modulate.a = 0.0


static func play(elements: Array[Control], start_delay: float = 0.0, stagger: float = STAGGER) -> void:
	var index := 0
	for element in elements:
		if not is_instance_valid(element):
			continue
		pop_in(element, start_delay + stagger * float(index))
		index += 1


static func pop_in(node: Control, delay: float = 0.0) -> void:
	if not is_instance_valid(node):
		return
	_kill(node)
	_refresh_pivot(node)
	node.scale = Vector2.ZERO
	node.modulate.a = 0.0

	var tw := node.create_tween()
	node.set_meta(TWEEN_META, tw)
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(node, "modulate:a", 1.0, 0.0)
	for pose in POSES:
		tw.tween_property(node, "scale", pose, 0.0)
		tw.tween_interval(FRAME * 2.0)
	tw.tween_property(node, "scale", Vector2.ONE, 0.0)


## The panel itself is not inside a container, so it can take a position offset
## as well. Eased rather than stepped - a heavy object arriving, not a pixel pop.
static func slam_panel(panel: Control, duration: float = PANEL_SLAM) -> void:
	if not is_instance_valid(panel):
		return
	_kill(panel)
	_refresh_pivot(panel)
	var rest := panel.position
	panel.scale = Vector2(1.18, 0.72)
	panel.position = rest - Vector2(0.0, 26.0)

	var tw := panel.create_tween()
	panel.set_meta(TWEEN_META, tw)
	tw.set_parallel(true)
	tw.tween_property(panel, "scale", Vector2.ONE, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "position", rest, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Containers size their children after _ready, and a scale pivot of (0,0) makes
## an element grow out of its top-left corner. Recompute whenever size moved.
static func _refresh_pivot(node: Control) -> void:
	var cached: Vector2 = node.get_meta(PIVOT_META, Vector2.INF)
	if cached != node.size:
		node.pivot_offset = node.size * 0.5
		node.set_meta(PIVOT_META, node.size)


static func _kill(node: Control) -> void:
	if not node.has_meta(TWEEN_META):
		return
	var previous: Tween = node.get_meta(TWEEN_META)
	if previous != null and previous.is_valid():
		previous.kill()
	node.remove_meta(TWEEN_META)
