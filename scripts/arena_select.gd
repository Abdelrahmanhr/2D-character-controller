extends Control

const PREVIEW_DIR := "res://resources/ui/arena_previews/"
const PREVIEW_EXTENSIONS: Array[String] = [".png", ".jpg", ".jpeg", ".webp"]
const ROW_HEIGHT := 96

# Cyberpunk GUI pack palette (resources/themes/cyberpunk.tres)
const MENU_TEXT := Color(0.545098, 0.670588, 0.74902, 1)
const MENU_TEXT_ACTIVE := Color(1, 0.964706, 0.682353, 1)
const MENU_BORDER := Color(0.337255, 0.415686, 0.537255, 1)
const MENU_BORDER_ACTIVE := Color(0.823529, 0.184314, 0.117647, 1)

const ARENAS := [
	{"id": "power_station", "name": "Power Station", "scene_path": "res://scenes/power_station2.tscn", "preview": "power_station"},
	{"id": "residential_area", "name": "Residential Area", "scene_path": "res://scenes/residential_area.tscn", "preview": "residential_area"},
]

## A full 4-player arena: you plus three bots. There are exactly four spawn
## points, so this cannot usefully go higher.
const BOT_COUNT := 3

var selected_index := 0
var _for_local_play := false  # NEW

var _arena_buttons: Array[Button] = []

@onready var arena_list: VBoxContainer = $Panel/ArenaList
@onready var continue_button: Button = $Panel/ContinueButton
@onready var back_button: Button = $BackButton

func _ready() -> void:
	MusicManager.play_id(&"menu")
	_for_local_play = LocalPlayers.entering_arena_select_for_local  
	_populate_arena_list()
	continue_button.pressed.connect(_on_continue_pressed)
	back_button.pressed.connect(_on_back_pressed)

func _populate_arena_list() -> void:
	for i in ARENAS.size():
		var arena: Dictionary = ARENAS[i]
		var preview := _load_preview(arena.get("preview", ""))

		var row := Control.new()
		row.custom_minimum_size = Vector2(0, ROW_HEIGHT if preview else 44)
		row.clip_contents = true
		arena_list.add_child(row)

		if preview:
			var art := TextureRect.new()
			art.texture = preview
			art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			art.stretch_mode = TextureRect.STRETCH_SCALE
			art.mouse_filter = Control.MOUSE_FILTER_IGNORE
			art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			row.add_child(art)

		var button := Button.new()
		button.text = arena["name"]
		button.toggle_mode = true
		button.button_pressed = i == selected_index
		button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_style_menu_button(button, preview != null)
		button.pressed.connect(_on_arena_pressed.bind(i))
		row.add_child(button)
		_arena_buttons.append(button)

func _load_preview(base_name: String) -> Texture2D:
	if base_name.is_empty():
		return null
	for extension in PREVIEW_EXTENSIONS:
		var path := PREVIEW_DIR + base_name + extension
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	push_warning("No arena preview found for '%s' in %s" % [base_name, PREVIEW_DIR])
	return null

func _style_menu_button(button: Button, over_art: bool = false) -> void:
	# Arena rows are selection cards sitting on top of preview art, so they keep a flat
	# stylebox rather than the opaque 9-patch the menu buttons use -- just in pack colours.
	button.add_theme_color_override("font_color", MENU_TEXT)
	button.add_theme_color_override("font_hover_color", MENU_TEXT_ACTIVE)
	button.add_theme_color_override("font_pressed_color", MENU_TEXT_ACTIVE)
	button.add_theme_color_override("font_hover_pressed_color", MENU_TEXT_ACTIVE)
	button.add_theme_color_override("font_focus_color", MENU_TEXT_ACTIVE)
	button.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	button.add_theme_constant_override("outline_size", 6 if over_art else 3)
	var idle_bg := Color(0.133, 0.165, 0.361, 0.55) if over_art else Color(0.133, 0.165, 0.361, 0.85)
	var press_bg := Color(0.824, 0.184, 0.118, 0.2) if over_art else Color(0.824, 0.184, 0.118, 0.3)
	button.add_theme_stylebox_override("normal", _make_stylebox(idle_bg, MENU_BORDER))
	button.add_theme_stylebox_override("pressed", _make_stylebox(press_bg, MENU_BORDER_ACTIVE))
	button.add_theme_stylebox_override("hover", _make_hover_stylebox(over_art))
	button.add_theme_stylebox_override("disabled", _make_stylebox(Color(0, 0, 0, 0.2), Color(0.337, 0.416, 0.537, 0.35)))
	button.add_theme_stylebox_override("focus", _make_hover_stylebox(over_art))

func _make_stylebox(bg_color: Color, border_color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg_color
	box.border_width_left = 2
	box.border_width_top = 2
	box.border_width_right = 2
	box.border_width_bottom = 2
	box.border_color = border_color
	return box

func _make_hover_stylebox(over_art: bool = false) -> StyleBoxFlat:
	var bg := Color(0.824, 0.184, 0.118, 0.3) if over_art else Color(0.22, 0.05, 0.17, 0.9)
	return _make_stylebox(bg, MENU_BORDER_ACTIVE)

func _on_arena_pressed(index: int) -> void:
	selected_index = index
	for i in _arena_buttons.size():
		_arena_buttons[i].button_pressed = i == index

func _on_continue_pressed() -> void:
	var arena: Dictionary = ARENAS[selected_index]
	if LocalPlayers.singleplayer:
		# No lobby to walk through - there is only one device, and the roster is
		# decided here rather than by anyone pressing a button to join.
		LocalPlayers.reset()
		LocalPlayers.try_join(LocalPlayers.KEYBOARD_DEVICE_ID)
		LocalPlayers.add_bots(BOT_COUNT)
		LocalPlayers.selected_arena_path = arena["scene_path"]
		SceneTransition.circle_to(arena["scene_path"])
		return
	if _for_local_play:  
		LocalPlayers.selected_arena_path = arena["scene_path"]  
		get_tree().change_scene_to_file("res://scenes/local_lobby.tscn")  
	else:
		Networking.set_arena(arena["scene_path"], arena["name"])
		get_tree().change_scene_to_file("res://scenes/lobby.tscn")

func _on_back_pressed() -> void:
	if _for_local_play:  
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")  
	else:
		Networking.leave_lobby()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
