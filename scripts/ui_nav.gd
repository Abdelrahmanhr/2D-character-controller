extends Node
# Autoload as "UINav"

## Controller navigation for every menu in the game, keyboard and mouse intact.
##
## There were two separate reasons a pad could not drive the UI, and both are
## fixed together or neither works:
##
##   1. Godot 4.7's built-in ui_* actions ship D-pad and left-stick bindings on
##      ui_up/ui_down/ui_left/ui_right, but NONE on ui_accept or ui_cancel.
##      (Checked against InputMap.action_get_events at runtime rather than
##      assumed - ui_accept was Enter/Kp Enter/Space only, ui_cancel Escape
##      only.) A pad could move a focus highlight around but never press
##      anything or back out of anything. project.godot now overrides those two
##      actions with their stock events plus JOY_BUTTON_A / JOY_BUTTON_B.
##      Those are positional, so they are A/B on an Xbox pad and Cross/Circle on
##      a PlayStation one automatically - no per-family table needed, unlike
##      tutorial_keycap.gd which has to NAME the buttons.
##
##   2. Nothing in the project ever grabbed focus. Viewport's focus navigation
##      only ever moves an EXISTING focus, so with no control focused there was
##      nothing for the D-pad to move and the menus were dead regardless.
##      options_menu.gd had noticed this and grown its own _focus_first; that is
##      now this autoload's job for every menu, and the duplicate can go.
##
## Wiring mirrors UISfx and UIFeedback - hook node_added and sweep the tree - so
## no menu scene needs per-scene setup and menus added later are covered free.
##
## Everything reactive here runs in _unhandled_input rather than _input, which
## is load-bearing rather than incidental:
##   - a focused HSlider consumes ui_left/ui_right to change volume and a
##     focused LineEdit consumes them to move its caret. Acting earlier would
##     steal the event from both.
##   - Viewport's own focus-neighbour search calls set_input_as_handled() only
##     when it actually FINDS a neighbour, so a direction press at the end of a
##     list arrives here still unhandled. That is exactly, and only, the case
##     the wrap-around below wants to catch.
##   - autoloads are the first children of root and unhandled input is
##     delivered bottom-up, so the current scene's own handlers (the ui_cancel
##     ones in main_menu/pause_menu/end_menu/tutorial_overlay) still win.

## Put a Control in this group to keep the pad off it - it stays clickable and
## stays reachable by mouse, it just never gets auto-focused or navigated to.
const SKIP_GROUP := &"no_pad_focus"

## Put the ROOT of a scene in this group to suppress only the automatic focus on
## arrival, while leaving the scene fully navigable once the player asks for it
## with a direction press. For screens whose first job is "press a button", where
## a highlight sitting on something else would be a trap rather than a help - see
## local_lobby.gd, where it would otherwise be parked on BACK while everyone is
## still pressing A to join.
const NO_AUTO_FOCUS_GROUP := &"no_auto_focus"

const DIRECTIONS := {
	&"ui_up": SIDE_TOP,
	&"ui_down": SIDE_BOTTOM,
	&"ui_left": SIDE_LEFT,
	&"ui_right": SIDE_RIGHT,
}

## A stick flick past the deadzone is not one event - InputEventJoypadMotion
## fires again on every change in axis value, and each of those reads as
## is_action_pressed. Viewport eats most of them by finding a real neighbour, but
## at the end of a list they all reach the wrap below, which without this would
## run the highlight around the menu several times per flick.
const REPEAT_COOLDOWN_MS := 150

var _scan_queued := false
var _last_move_ms: int = -REPEAT_COOLDOWN_MS


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_on_node_added)
	_queue_scan()


# --- automatic focus ----------------------------------------------------------

## Gated on focus_mode rather than on Control, because every arena is full of
## Labels, ColorRects and TextureRects that would otherwise queue a tree scan
## each. Buttons default to FOCUS_ALL, so menus still trip this.
func _on_node_added(node: Node) -> void:
	if node is Control and node.focus_mode == Control.FOCUS_ALL:
		_queue_scan()


func _queue_scan() -> void:
	if _scan_queued:
		return
	_scan_queued = true
	_scan.call_deferred()


## One frame of slack before looking at anything: containers size and position
## their children after _ready, so both is_visible_in_tree and the geometry the
## candidate sort depends on are still wrong at node_added time.
func _scan() -> void:
	await get_tree().process_frame
	_scan_queued = false
	if not is_inside_tree():
		return
	var pool := _candidates()
	if pool.is_empty():
		return

	var focused := _focus_owner()
	if focused == null:
		if not _auto_focus_allowed(pool[0]):
			return
		pool[0].grab_focus()
		return
	# A modal opened over whatever was focused (ModeNotice at layer 15 over the
	# main menu, the pause menu at 20 over a match). Without this the pad would
	# keep driving the menu BEHIND the dialog, which is both invisible and able
	# to trigger things the dialog is meant to be blocking.
	if _layer_of(focused) < _layer_of(pool[0]):
		pool[0].grab_focus()


## Focus the first candidate under `scope`, for menus that swap a page in place
## instead of changing scene - no node is added there, so nothing would trip
## _on_node_added. Returns whether anything was focused.
func focus_first(scope: Node = null) -> bool:
	var pool := _candidates()
	for control in pool:
		if scope == null or scope == control or scope.is_ancestor_of(control):
			control.grab_focus()
			return true
	return false


# --- input --------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# Classify before touching the tree. _candidates() walks the whole scene, and
	# during a match every unhandled key press and every stick wobble lands here -
	# a match arena has no focusable controls at all, so that would be a full tree
	# walk per event to reach the same "nothing to do" every time.
	var side := _direction_of(event)
	var accept: bool = side == -1 and event.is_action_pressed(&"ui_accept")
	if side == -1 and not accept:
		return
	if Time.get_ticks_msec() - _last_move_ms < REPEAT_COOLDOWN_MS:
		return

	var pool := _candidates()
	if pool.is_empty():
		return

	var focused := _focus_owner()
	if focused == null or not pool.has(focused):
		# Nothing focused and the player is clearly trying to drive the UI - give
		# them something to drive. Deliberately swallowed rather than also
		# activating: a first press must not fire a button the player cannot see
		# the highlight on yet. ui_cancel is left out on purpose, since "back"
		# should stay "back" rather than turning into "select something".
		_move_to(pool[0])
		return

	if side == -1:
		return
	# Reaching here at all means Viewport already looked for a neighbour on this
	# side and found none, so this is the end of a list rather than a normal move.
	var target := _wrap_target(focused, side, pool)
	if target == null or target == focused:
		return
	_move_to(target)


func _move_to(control: Control) -> void:
	_last_move_ms = Time.get_ticks_msec()
	control.grab_focus()
	get_viewport().set_input_as_handled()


func _direction_of(event: InputEvent) -> int:
	for action in DIRECTIONS:
		if event.is_action_pressed(action):
			return DIRECTIONS[action]
	return -1


## The far end of the row or column `focused` sits in, so a menu loops instead of
## dead-ending. Scoped geometrically (do the rects overlap on the other axis?)
## rather than by shared parent, because the scope that matters is what the
## player sees - the three device tabs in the options are one HBox but so is
## every keycap row under them, and a VBox menu whose buttons are deliberately
## different widths is still visibly one column.
func _wrap_target(focused: Control, side: int, pool: Array[Control]) -> Control:
	var vertical: bool = side == SIDE_TOP or side == SIDE_BOTTOM
	var rect := focused.get_global_rect()
	var scope: Array[Control] = []
	for control in pool:
		var other := control.get_global_rect()
		var overlaps: bool = (
			other.position.x < rect.end.x and rect.position.x < other.end.x
			if vertical
			else other.position.y < rect.end.y and rect.position.y < other.end.y
		)
		if overlaps:
			scope.append(control)
	# A lone control in its row/column is not a list to loop; fall back to the
	# whole page so a dead end still goes somewhere.
	if scope.size() < 2:
		scope = pool

	var best: Control = null
	var best_value: float = 0.0
	for control in scope:
		var origin := control.get_global_rect().position
		var value: float = origin.y if vertical else origin.x
		# Wrapping means jumping to the OPPOSITE end from the direction pressed.
		var better: bool = value < best_value if (side == SIDE_BOTTOM or side == SIDE_RIGHT) else value > best_value
		if best == null or better:
			best = control
			best_value = value
	return best


# --- candidates ---------------------------------------------------------------

func _focus_owner() -> Control:
	if not is_inside_tree():
		return null
	var viewport := get_viewport()
	return null if viewport == null else viewport.gui_get_focus_owner()


## Every control a pad is allowed to land on right now, topmost CanvasLayer only,
## ordered top-to-bottom then left-to-right.
func _candidates() -> Array[Control]:
	var found: Array = []
	if is_inside_tree():
		_collect(get_tree().root, 0, found)
	if found.is_empty():
		return []

	var top_layer: int = found[0][0]
	for entry in found:
		top_layer = maxi(top_layer, entry[0])

	var pool: Array[Control] = []
	for entry in found:
		if entry[0] == top_layer:
			pool.append(entry[1])
	pool.sort_custom(func(a: Control, b: Control) -> bool:
		var pa := a.get_global_rect().position
		var pb := b.get_global_rect().position
		return pa.x < pb.x if is_equal_approx(pa.y, pb.y) else pa.y < pb.y)
	return pool


func _collect(node: Node, layer: int, out: Array) -> void:
	if node is CanvasLayer:
		layer = node.layer
	elif node is Control:
		# A hidden Control hides its whole subtree, so there is nothing below it
		# worth walking either.
		if not node.visible:
			return
		if _is_candidate(node):
			out.append([layer, node])
	for child in node.get_children():
		_collect(child, layer, out)


func _is_candidate(control: Control) -> bool:
	# FOCUS_CLICK is excluded on purpose, not by oversight: it is Godot's own way
	# of saying "mouse only", which is what player_slot's name field wants - a pad
	# cannot type, so landing on one would be a dead end.
	if control.focus_mode != Control.FOCUS_ALL:
		return false
	if control.is_in_group(SKIP_GROUP):
		return false
	# Disabled buttons keep FOCUS_ALL (the lobby's Start sits disabled until
	# enough players have joined), and focusing one strands the pad on a control
	# that cannot be pressed or, in the lobby's case, is about to disappear.
	if control is BaseButton and control.disabled:
		return false
	return control.is_visible_in_tree() and control.get_global_rect().size != Vector2.ZERO


## The opt-out covers the screen itself, not anything that opens on top of it: a
## dialog or pause menu on its own CanvasLayer is exactly the case where landing
## focus automatically is wanted, whatever the screen underneath asked for.
func _auto_focus_allowed(target: Control) -> bool:
	var scene := get_tree().current_scene
	if scene == null or not scene.is_in_group(NO_AUTO_FOCUS_GROUP):
		return true
	return _layer_of(target) > 0


func _layer_of(control: Control) -> int:
	var node: Node = control
	while node != null:
		if node is CanvasLayer:
			return node.layer
		node = node.get_parent()
	return 0
