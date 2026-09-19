extends Object
class_name TutorialKeycap

const KEY_BG := Color(0.0706, 0.0784, 0.1098, 0.92)
const KEY_BORDER := Color(0.3216, 0.6392, 1.0, 0.55)
const KEY_TEXT := Color(1.0, 0.8784, 0.5686)
const LABEL_TEXT := Color(0.7686, 0.8392, 0.9216)

## Every action's button name has to come from the SAME controller family, or
## the prompts end up an incoherent mix (this was the actual bug: mash showed
## Xbox's "A" while confirm showed PlayStation's "CIRCLE" - two different
## conventions on screen at once, and worse, mash's "A" didn't even match the
## button mash_minigame.gd actually reads, which is JOY_BUTTON_Y). These two
## tables are each internally consistent with what the game code actually
## listens for: player.gd (jump -> JOY_BUTTON_A, dash -> JOY_BUTTON_X),
## mash_minigame.gd (JOY_BUTTON_Y), tutorial_overlay.gd's own confirm check
## (JOY_BUTTON_B), and the *_minigame.gd files' D-PAD checks. There is no
## per-action joypad rebinding anywhere in the project (Settings only ever
## stores keyboard keys - see its own header comment on why), so these are
## fixed names rather than something read out of a binding.
enum PadFamily { XBOX, PLAYSTATION }

const PAD_BUTTON_NAMES_BY_FAMILY := {
	PadFamily.XBOX: {
		&"jump": "A",
		&"mash": "Y",
		&"dash": "X",
		&"dash_alt": "X",
		&"confirm": "B",
		&"confirm_alt": "B",
		&"pause": "START",
		&"mg_up": "D-PAD UP",
		&"mg_down": "D-PAD DOWN",
		&"mg_left": "D-PAD LEFT",
		&"mg_right": "D-PAD RIGHT",
		&"move_left": "L-STICK <",
		&"move_right": "L-STICK >",
		&"move_up": "L-STICK ^",
		&"move_down": "L-STICK v",
	},
	PadFamily.PLAYSTATION: {
		&"jump": "CROSS",
		&"mash": "TRIANGLE",
		&"dash": "SQUARE",
		&"dash_alt": "SQUARE",
		&"confirm": "CIRCLE",
		&"confirm_alt": "CIRCLE",
		&"pause": "OPTIONS",
		&"mg_up": "D-PAD UP",
		&"mg_down": "D-PAD DOWN",
		&"mg_left": "D-PAD LEFT",
		&"mg_right": "D-PAD RIGHT",
		&"move_left": "L-STICK <",
		&"move_right": "L-STICK >",
		&"move_up": "L-STICK ^",
		&"move_down": "L-STICK v",
	},
}

## How hard a stick has to be pushed before it counts as "using a controller" -
## well above idle drift, so a pad sitting on a table doesn't flip this.
const PAD_MOTION_DEADZONE := 0.5

## Last-used-device tracking, live-updated from tutorial_overlay.gd's own
## _input() (already the single place every tutorial input event passes
## through) rather than a separate one-off listener just for this. Static
## because this whole class is a stateless utility called from many places
## (tutorial_director.gd's cards, the mash prompt, ...) - there is only ever
## one real player in the tutorial/singleplayer contexts this is used in, so a
## single shared "which device last spoke" flag is all that's needed here.
static var _last_input_is_pad: bool = false
static var _last_pad_family: int = PadFamily.XBOX


static func note_input(event: InputEvent) -> void:
	if event is InputEventKey:
		_last_input_is_pad = false
	elif event is InputEventJoypadButton and event.pressed:
		_last_input_is_pad = true
		_last_pad_family = _detect_pad_family(event.device)
	elif event is InputEventJoypadMotion and absf(event.axis_value) > PAD_MOTION_DEADZONE:
		_last_input_is_pad = true
		_last_pad_family = _detect_pad_family(event.device)


static func is_using_pad() -> bool:
	return _last_input_is_pad


static func _detect_pad_family(device: int) -> int:
	return _family_from_name(Input.get_joy_name(device))


## Split out from _detect_pad_family so the string-matching itself is testable
## without a real connected device (Input.get_joy_name only returns a real
## name for an actual attached joypad).
static func _family_from_name(joy_name: String) -> int:
	var lname := joy_name.to_lower()
	for keyword in ["sony", "playstation", "ps3", "ps4", "ps5", "dualshock", "dualsense"]:
		if lname.find(keyword) != -1:
			return PadFamily.PLAYSTATION
	return PadFamily.XBOX


static func style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = KEY_BG
	box.border_color = KEY_BORDER
	box.set_border_width_all(2)
	box.content_margin_left = 10.0
	box.content_margin_right = 10.0
	box.content_margin_top = 4.0
	box.content_margin_bottom = 4.0
	box.corner_radius_top_left = 4
	box.corner_radius_top_right = 4
	box.corner_radius_bottom_left = 4
	box.corner_radius_bottom_right = 4
	return box


static func key_text(action: StringName) -> String:
	if _last_input_is_pad:
		var table: Dictionary = PAD_BUTTON_NAMES_BY_FAMILY[_last_pad_family]
		if table.has(action):
			return table[action]
	var key: Key = Settings.get_key(action)
	return "?" if key == KEY_NONE else OS.get_keycode_string(key)


static func cap(text: String, font_size: int = 15) -> PanelContainer:
	var box := PanelContainer.new()
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_theme_stylebox_override("panel", style())

	var label := Label.new()
	label.text = text
	MinigameUI.style_label(label, KEY_TEXT, font_size)
	box.add_child(label)
	return box


static func cap_for(action: StringName, font_size: int = 15) -> PanelContainer:
	return cap(key_text(action), font_size)


static func captioned(action: StringName, caption: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 4)
	column.add_child(cap_for(action))

	var label := Label.new()
	label.text = caption
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MinigameUI.style_label(label, LABEL_TEXT, 11)
	column.add_child(label)
	return column


static func row(entries: Array) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	for entry in entries:
		box.add_child(captioned(StringName(entry[0]), String(entry[1])))
	return box
