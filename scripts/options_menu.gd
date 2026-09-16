extends Control
## The options page, owned by one scene instead of two.
##
## Previously this lived inside pause_menu.tscn and main_menu.gd stole the
## subtree out of a throwaway instance, which meant every control had to be
## wired twice or it was dead on the main menu. Both hosts now instance this
## and talk to it through open() / handle_cancel() / back_pressed.
##
## Pages are built in script rather than in the .tscn so the controls table
## stays readable in one place, and because UICascade enumerates children at
## runtime anyway.

signal back_pressed
signal page_changed(title: String)

## Display name -> audio bus name.
const BUS_ROWS: Array = [
	["MASTER", "Master"],
	["MUSIC", "Music"],
	["SFX", "SFX"],
]

const DEVICES: Array[String] = ["KEYBOARD", "XBOX", "PLAYSTATION"]

## Size the page needs when this scene draws its own frame. The pause menu
## passes framed = false and sizes its own Panel around us instead.
const PAGE_SIZES := {
	"OPTIONS": Vector2(380.0, 360.0),
	"CONTROLS": Vector2(480.0, 440.0),
}

## Verified against player.gd, bomb_controller.gd, local_lobby.gd and the
## minigame _handle_input methods - NOT against the itch description, which is
## wrong about the dash key and silent about aiming, fast fall and the mash
## minigame. Rows are parallel across devices so tabbing does not reshuffle.
const CONTROLS := {
	"KEYBOARD": [
		["MOVE", ["A", "D"]],
		["JUMP", ["SPACE"]],
		["DASH / SLAM", ["SHIFT", "F"]],
		["AIM DASH", ["W", "A", "S", "D"]],
		["FAST FALL", ["S"]],
		["MINIGAME", ["^", "v", "<", ">"]],
		["BUTTON MASH", ["Y"]],
		["CONFIRM", ["SPACE", "ENTER"]],
		["START MATCH", ["ENTER"]],
	],
	"XBOX": [
		["MOVE", ["L-STICK"]],
		["JUMP", ["A"]],
		["DASH / SLAM", ["X"]],
		["AIM DASH", ["L-STICK"]],
		["FAST FALL", ["L-STICK DOWN"]],
		["MINIGAME", ["D-PAD", "R-STICK"]],
		["BUTTON MASH", ["Y"]],
		["CONFIRM", ["ANY FACE BUTTON"]],
		["START MATCH", ["START"]],
	],
	"PLAYSTATION": [
		["MOVE", ["L-STICK"]],
		["JUMP", ["CROSS"]],
		["DASH / SLAM", ["SQUARE"]],
		["AIM DASH", ["L-STICK"]],
		["FAST FALL", ["L-STICK DOWN"]],
		["MINIGAME", ["D-PAD", "R-STICK"]],
		["BUTTON MASH", ["TRIANGLE"]],
		["CONFIRM", ["ANY FACE BUTTON"]],
		["START MATCH", ["OPTIONS"]],
	],
}

## Palette lifted from resources/themes/cyberpunk.tres so the hand-built
## keycaps read as part of the same system as the themed sliders and buttons.
const TITLE_COLOR := Color(0.8, 0.886275, 0.882353, 1)
const LABEL_COLOR := Color(0.545098, 0.670588, 0.74902, 1)
const KEY_TEXT := Color(1, 0.964706, 0.682353, 1)
const KEY_BG := Color(0.133333, 0.164706, 0.360784, 1)
const KEY_BORDER := Color(0.337255, 0.415686, 0.537255, 1)

@onready var frame: Panel = $Frame
@onready var audio_page: VBoxContainer = $AudioPage
@onready var controls_page: VBoxContainer = $ControlsPage

var _audio_title: Label
var _controls_title: Label
var _row_list: VBoxContainer
var _device: String = "KEYBOARD"
var _tabs: Dictionary = {}
var _framed := false
var _page: String = "OPTIONS"


func _ready() -> void:
	_build_audio_page()
	_build_controls_page()
	controls_page.hide()
	audio_page.show()


# --- public API -------------------------------------------------------------

## Show the options from the top. Hosts call this instead of show().
func open() -> void:
	show()
	_show_audio()


## Returns true if ui_cancel was consumed by stepping back a page, so the host
## knows not to also close itself.
func handle_cancel() -> bool:
	if controls_page.visible:
		_show_audio()
		return true
	return false


## The pause menu's own TitleBar names the page, so its headings are redundant.
func set_titles_visible(value: bool) -> void:
	_audio_title.visible = value
	_controls_title.visible = value


## Draw our own panel and size ourselves to the page. The main menu needs this -
## it has no frame of its own, and a page of sliders and control rows is
## illegible straight over the parallax city. The pause menu leaves it off and
## sizes its own Panel around us instead.
func set_framed(value: bool) -> void:
	_framed = value
	frame.visible = value
	_apply_frame_size()


func _apply_frame_size() -> void:
	if not _framed:
		return
	var size: Vector2 = PAGE_SIZES.get(_page, PAGE_SIZES["OPTIONS"])
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	offset_left = -size.x * 0.5
	offset_right = size.x * 0.5
	offset_top = -size.y * 0.5
	offset_bottom = size.y * 0.5


# --- audio page -------------------------------------------------------------

func _build_audio_page() -> void:
	_audio_title = _make_title("OPTIONS")
	audio_page.add_child(_audio_title)

	for entry in BUS_ROWS:
		audio_page.add_child(_make_volume_row(entry[0], entry[1]))

	var controls_button := _make_button("CONTROLS")
	controls_button.pressed.connect(_show_controls)
	audio_page.add_child(controls_button)

	var back := _make_button("BACK")
	back.pressed.connect(func() -> void: back_pressed.emit())
	audio_page.add_child(back)


func _make_volume_row(display_name: String, bus_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER

	var label := Label.new()
	label.text = display_name
	label.custom_minimum_size = Vector2(88.0, 0.0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_style_label(label, LABEL_COLOR, 16)
	row.add_child(label)

	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(150.0, 18.0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	# Read the real value - the old slider hardcoded 1.0 and could display a lie.
	slider.value = Settings.get_volume(bus_name)
	row.add_child(slider)

	var percent := Label.new()
	percent.custom_minimum_size = Vector2(46.0, 0.0)
	percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	percent.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_style_label(percent, KEY_TEXT, 14)
	_set_percent(percent, slider.value)
	row.add_child(percent)

	slider.value_changed.connect(func(value: float) -> void:
		Settings.set_volume(bus_name, value)
		_set_percent(percent, value))
	return row


func _set_percent(label: Label, value: float) -> void:
	label.text = "%d%%" % roundi(value * 100.0)


# --- controls page ----------------------------------------------------------

func _build_controls_page() -> void:
	_controls_title = _make_title("CONTROLS")
	controls_page.add_child(_controls_title)

	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 6)
	tab_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var group := ButtonGroup.new()
	for device in DEVICES:
		var tab := Button.new()
		tab.text = device
		tab.toggle_mode = true
		tab.button_group = group
		tab.clip_text = true
		tab.custom_minimum_size = Vector2(0.0, 32.0)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# The theme pads buttons by 24px a side, which on a fixed-width tab spends
		# the space on padding and leaves the label tiny. Trim the padding and
		# give it back to the text.
		_tighten(tab)
		tab.add_theme_font_size_override("font_size", 16)
		tab.pressed.connect(_select_device.bind(device))
		tab_row.add_child(tab)
		_tabs[device] = tab
		if device == _device:
			tab.button_pressed = true
	controls_page.add_child(tab_row)

	_row_list = VBoxContainer.new()
	_row_list.add_theme_constant_override("separation", 5)
	# Shrink to the widest row and centre that block, so the label column still
	# lines up across rows but the table is not stranded against the left edge.
	_row_list.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	controls_page.add_child(_row_list)

	var back := _make_button("BACK")
	back.pressed.connect(_show_audio)
	controls_page.add_child(back)

	_build_rows()


## Copy the theme's button styleboxes with narrower side padding, so the button
## keeps its size but the label gets the room.
func _tighten(button: Button) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		# Read from the root, not the button - the button is not in the tree yet,
		# so it would resolve against the project theme instead of cyberpunk.tres.
		var style: StyleBox = get_theme_stylebox(state, "Button")
		if style == null:
			continue
		var tight: StyleBox = style.duplicate()
		tight.content_margin_left = 6.0
		tight.content_margin_right = 6.0
		button.add_theme_stylebox_override(state, tight)


func _select_device(device: String) -> void:
	if device == _device:
		return
	_device = device
	# Keep the highlight honest even when this is driven in code rather than by a
	# click - setting button_pressed does not re-emit pressed, so this cannot loop.
	if _tabs.has(device):
		_tabs[device].button_pressed = true
	_build_rows()


func _build_rows() -> void:
	# remove_child as well as queue_free - queue_free alone is deferred, so the
	# stale rows would still take up layout space for a frame.
	for child in _row_list.get_children():
		_row_list.remove_child(child)
		child.queue_free()
	for entry in CONTROLS[_device]:
		_row_list.add_child(_make_control_row(entry[0], entry[1]))


func _make_control_row(action: String, keys: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var label := Label.new()
	label.text = action
	label.custom_minimum_size = Vector2(128.0, 0.0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_style_label(label, LABEL_COLOR, 14)
	row.add_child(label)

	var keys_box := HBoxContainer.new()
	keys_box.add_theme_constant_override("separation", 5)
	keys_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for key in keys:
		keys_box.add_child(_make_key(str(key)))
	row.add_child(keys_box)
	return row


## No button-glyph art exists in the project, so keycaps are drawn from the
## theme palette rather than blitted from an atlas.
func _make_key(text: String) -> PanelContainer:
	var box := PanelContainer.new()
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var style := StyleBoxFlat.new()
	style.bg_color = KEY_BG
	style.border_color = KEY_BORDER
	style.set_border_width_all(2)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	box.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = text
	_style_label(label, KEY_TEXT, 13)
	box.add_child(label)
	return box


# --- page switching ---------------------------------------------------------

func _show_audio() -> void:
	controls_page.hide()
	audio_page.show()
	_page = "OPTIONS"
	_apply_frame_size()
	page_changed.emit(_page)
	_cascade(audio_page)


func _show_controls() -> void:
	audio_page.hide()
	controls_page.show()
	_page = "CONTROLS"
	_apply_frame_size()
	page_changed.emit(_page)
	_cascade(controls_page)


## No entrance animation here on purpose - the options pages appear flat. The
## one frame is still needed so the VBoxContainer has sized its children before
## anything grabs focus.
func _cascade(page: Control) -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_focus_first(page)


## This is a controller-first game and the project sets no focus neighbours
## anywhere, so without this a pad player has nothing selected to move from.
func _focus_first(page: Control) -> void:
	for child in page.get_children():
		var target := _first_focusable(child)
		if target != null:
			target.grab_focus()
			return


func _first_focusable(node: Node) -> Control:
	if node is Control and node.visible and node.focus_mode != Control.FOCUS_NONE:
		return node
	for child in node.get_children():
		var found := _first_focusable(child)
		if found != null:
			return found
	return null


# --- shared builders --------------------------------------------------------

func _make_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(label, TITLE_COLOR, 20)
	return label


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 40.0)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return button


func _style_label(label: Label, color: Color, font_size: int) -> void:
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
