extends Node
# Autoload as "UISfx"

@export var click_sound: AudioStream
@export var click_pitch_variance: float = 0.05
@export var hover_volume_db: float = -18.0
@export var hover_pitch_shift: float = 1.6

func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	_connect_existing_buttons()

func _connect_existing_buttons() -> void:
	_connect_recursive(get_tree().root)

func _connect_recursive(node: Node) -> void:
	if node is Button:
		_wire_button(node)
	for child in node.get_children():
		_connect_recursive(child)

func _on_node_added(node: Node) -> void:
	if node is Button:
		_wire_button(node)

func _wire_button(button: Button) -> void:
	if not button.pressed.is_connected(_play_click):
		button.pressed.connect(_play_click)
	if not button.mouse_entered.is_connected(_play_hover):
		button.mouse_entered.connect(_play_hover)

func _play_click() -> void:
	SfxManager.play(click_sound, 0.0, click_pitch_variance)  

func _play_hover() -> void:
	SfxManager.play(click_sound, hover_volume_db, 0.0, hover_pitch_shift)  
