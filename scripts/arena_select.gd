extends Control

const ARENAS := [
	{"id": "power_station", "name": "Power Station", "scene_path": "res://scenes/power_station.tscn"},
	{"id": "residential_area", "name": "Residential Area", "scene_path": "res://scenes/residential_area.tscn"},
]

var selected_index := 0

@onready var arena_list: VBoxContainer = $Panel/ArenaList
@onready var continue_button: Button = $Panel/ContinueButton
@onready var back_button: Button = $BackButton

func _ready() -> void:
	_populate_arena_list()
	continue_button.pressed.connect(_on_continue_pressed)
	back_button.pressed.connect(_on_back_pressed)

func _populate_arena_list() -> void:
	for i in ARENAS.size():
		var arena: Dictionary = ARENAS[i]
		var button := Button.new()
		button.text = arena["name"]
		button.toggle_mode = true
		button.button_pressed = i == selected_index
		button.custom_minimum_size = Vector2(0, 44)
		_style_menu_button(button)
		button.pressed.connect(_on_arena_pressed.bind(i))
		arena_list.add_child(button)

func _style_menu_button(button: Button) -> void:
	button.add_theme_color_override("font_color", Color(1, 1, 1, 0.96))
	button.add_theme_color_override("font_hover_color", Color(0.2, 0.95, 1, 1))
	button.add_theme_color_override("font_outline_color", Color(0.2, 0.95, 1, 0.7))
	button.add_theme_constant_override("outline_size", 3)
	button.add_theme_stylebox_override("normal", _make_stylebox(Color(0.02, 0.06, 0.08, 0.3), Color(0.2, 0.95, 1, 0.45)))
	button.add_theme_stylebox_override("pressed", _make_stylebox(Color(0.2, 0.95, 1, 0.25), Color(0.75, 1, 1, 1)))
	button.add_theme_stylebox_override("hover", _make_hover_stylebox())
	button.add_theme_stylebox_override("disabled", _make_stylebox(Color(0.03, 0.05, 0.06, 0.2), Color(0.3, 0.4, 0.42, 0.35)))
	button.add_theme_stylebox_override("focus", _make_hover_stylebox())

func _make_stylebox(bg_color: Color, border_color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg_color
	box.border_width_left = 1
	box.border_width_top = 1
	box.border_width_right = 1
	box.border_width_bottom = 1
	box.border_color = border_color
	box.corner_radius_top_left = 4
	box.corner_radius_top_right = 4
	box.corner_radius_bottom_right = 4
	box.corner_radius_bottom_left = 4
	return box

func _make_hover_stylebox() -> StyleBoxFlat:
	var box := _make_stylebox(Color(0.04, 0.13, 0.16, 0.55), Color(0.2, 0.95, 1, 1))
	box.shadow_color = Color(0.2, 0.95, 1, 0.4)
	box.shadow_size = 10
	return box

func _on_arena_pressed(index: int) -> void:
	selected_index = index
	for i in arena_list.get_child_count():
		(arena_list.get_child(i) as Button).button_pressed = i == index

func _on_continue_pressed() -> void:
	var arena: Dictionary = ARENAS[selected_index]
	Networking.set_arena(arena["scene_path"], arena["name"])
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
