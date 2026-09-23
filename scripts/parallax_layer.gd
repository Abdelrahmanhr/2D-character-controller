extends Control
class_name ParallaxLayer2D

@export var texture: Texture2D
@export var scroll_speed: float = 20.0 
@export var align_bottom: bool = true

var _tiles: Array[TextureRect] = []
var _tile_width: float = 0.0
var _scroll_x: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if texture == null:
		return
	for i in 3:
		var rect := TextureRect.new()
		rect.texture = texture
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rect)
		_tiles.append(rect)
	get_viewport().size_changed.connect(_layout_tiles)
	_layout_tiles()

func _layout_tiles() -> void:
	if _tiles.is_empty() or texture == null:
		return
	var view_size := get_viewport_rect().size
	var tex_size := texture.get_size()
	if tex_size.y <= 0.0:
		return
	var scale_factor: float = view_size.y / tex_size.y
	var scaled_size := Vector2(tex_size.x * scale_factor, view_size.y)

	if scaled_size.x < view_size.x:
		var extra_scale: float = view_size.x / scaled_size.x
		scaled_size *= extra_scale
	_tile_width = scaled_size.x
	for rect in _tiles:
		rect.size = scaled_size
		rect.position.y = view_size.y - scaled_size.y if align_bottom else 0.0
	_position_tiles()

func _position_tiles() -> void:
	for i in _tiles.size():
		_tiles[i].position.x = _scroll_x + float(i) * _tile_width

func _process(delta: float) -> void:
	if _tiles.is_empty():
		return
	_scroll_x -= scroll_speed * delta
	if _scroll_x <= -_tile_width:
		_scroll_x += _tile_width
	elif _scroll_x > 0.0:
		_scroll_x -= _tile_width
	_position_tiles()
