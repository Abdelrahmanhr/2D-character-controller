extends Object
class_name TutorialKeycap

const KEY_BG := Color(0.0706, 0.0784, 0.1098, 0.92)
const KEY_BORDER := Color(0.3216, 0.6392, 1.0, 0.55)
const KEY_TEXT := Color(1.0, 0.8784, 0.5686)
const LABEL_TEXT := Color(0.7686, 0.8392, 0.9216)


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
