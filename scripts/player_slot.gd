extends PanelContainer
class_name PlayerSlotUI

const SLOT_COLORS: Array[Color] = [
	Color(1, 0.4118, 0.3529, 1),
	Color(1, 0.8784, 0.5686, 1),
	Color(0.3137, 0.7255, 0.9216, 1),
	Color(0.549, 1, 0.6078, 1),
]

@onready var color_bar: ColorRect = $ColorBar
@onready var slot_label: Label = $SlotLabel

func setup(slot_index: int, label_text: String) -> void:
	var color: Color = SLOT_COLORS[clampi(slot_index, 0, SLOT_COLORS.size() - 1)]
	color_bar.color = color
	slot_label.text = "P%d - %s" % [slot_index + 1, label_text]
	slot_label.add_theme_color_override("font_color", color)
