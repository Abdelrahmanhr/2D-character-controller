extends PanelContainer
class_name PlayerSlotUI

const SLOT_COLORS: Array[Color] = [
	Color(1, 0.4118, 0.3529, 1),
	Color(1, 0.8784, 0.5686, 1),
	Color(0.3137, 0.7255, 0.9216, 1),
	Color(0.549, 1, 0.6078, 1),
]

@onready var color_bar: ColorRect = $ColorBar
@onready var slot_label: Label = $Layout/SlotLabel
@onready var name_edit: LineEdit = $Layout/NameEdit

var _device_id: int = 0

## label_text is the device descriptor ("Keyboard" / "Controller N"); device_id is
## what NameEdit's typed-in name gets stored against in LocalPlayers, whose
## get_display_name is what every in-match name lookup falls back through if the
## field is left blank.
func setup(slot_index: int, label_text: String, device_id: int) -> void:
	_device_id = device_id
	var color: Color = SLOT_COLORS[clampi(slot_index, 0, SLOT_COLORS.size() - 1)]
	color_bar.color = color
	slot_label.text = "P%d - %s" % [slot_index + 1, label_text]
	slot_label.add_theme_color_override("font_color", color)
	# Mouse/click focus only, never keyboard or pad navigation. A pad cannot type,
	# so a name field is a dead end for it -- and now that the couch lobby's Start
	# and Back are pad-reachable, a D-pad run down the slot list would otherwise
	# land here and eat the presses meant for the menu.
	name_edit.focus_mode = Control.FOCUS_CLICK
	name_edit.placeholder_text = "P%d" % (slot_index + 1)
	name_edit.text = LocalPlayers.get_raw_player_name(device_id)
	name_edit.add_theme_color_override("font_color", color)
	if not name_edit.text_changed.is_connected(_on_name_changed):
		name_edit.text_changed.connect(_on_name_changed)
	# LineEdit never releases focus on its own once clicked into -- without this,
	# hitting Enter (or clicking away, since nothing else in this UI steals focus
	# back) left it eating every subsequent key press as more typing, with no way
	# back to the lobby's own keyboard handling (join/start) or into a match.
	if not name_edit.text_submitted.is_connected(_on_name_submitted):
		name_edit.text_submitted.connect(_on_name_submitted)


func _on_name_changed(new_text: String) -> void:
	LocalPlayers.set_player_name(_device_id, new_text)


func _on_name_submitted(_new_text: String) -> void:
	name_edit.release_focus()
