extends PanelContainer
class_name PlayerSlotUI

const SLOT_COLORS: Array[Color] = [
	Color(1, 0.18, 0.22, 1),
	Color(1, 0.95, 0.15, 1),
	Color(0.2, 0.55, 1, 1),
	Color(0.15, 1, 0.4, 1),
]

@onready var color_bar: ColorRect = $ColorBar
@onready var slot_label: Label = $SlotLabel

func setup(slot_index: int, label_text: String) -> void:
	var color: Color = SLOT_COLORS[clampi(slot_index, 0, SLOT_COLORS.size() - 1)]
	color_bar.color = color
	slot_label.text = "P%d - %s" % [slot_index + 1, label_text]
	slot_label.add_theme_color_override("font_color", color)
