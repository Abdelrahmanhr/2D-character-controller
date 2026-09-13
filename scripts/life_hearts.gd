extends Node2D
class_name LifeHearts


const HEART_ROWS: Array[String] = [
	".XX.XX.",
	"XXXXXXX",
	"XXXXXXX",
	".XXXXX.",
	"..XXX..",
	"...X...",
]

const FLASH_TIMEOUT := 3.0

@export var heart_color: Color = Color(0.8667, 0.2157, 0.2706)
@export var heart_scale: float = 2.0
@export var spacing: float = 2.0
@export var height_above_player: float = -66.0
@export var flash_speed: float = 0.1

var _bomb: Node
var _player: Node2D
var _hearts: Array[Sprite2D] = []
var _displayed_lives: int = 0
var _losing: bool = false
var _texture: Texture2D


func setup(player: Node2D, bomb: Node) -> void:
	_player = player
	_bomb = bomb


func _ready() -> void:
	position.y = height_above_player
	z_index = 10
	if _bomb:
		_displayed_lives = _bomb.get_lives_remaining()
	_rebuild(_displayed_lives)


func _process(_delta: float) -> void:
	if _bomb == null or _losing:
		return
	var actual: int = _bomb.get_lives_remaining()
	if actual > _displayed_lives:
		_displayed_lives = actual
		_rebuild(actual)
		return
	if actual == _displayed_lives:
		return
	if actual <= 0:
		_displayed_lives = 0
		_rebuild(0)
		return
	if _player and _player.is_invulnerable:
		_flash_and_drop(actual)


func _flash_and_drop(target: int) -> void:
	_losing = true
	var doomed: Sprite2D = _hearts.back() if not _hearts.is_empty() else null
	var elapsed: float = 0.0
	while is_instance_valid(doomed) and _player and _player.is_invulnerable and elapsed < FLASH_TIMEOUT:
		doomed.visible = not doomed.visible
		await get_tree().create_timer(flash_speed).timeout
		elapsed += flash_speed
	_displayed_lives = target
	_rebuild(target)
	_losing = false


func _rebuild(count: int) -> void:
	for heart in _hearts:
		if is_instance_valid(heart):
			heart.queue_free()
	_hearts.clear()
	if count <= 0:
		return
	var heart_width: float = float(HEART_ROWS[0].length())
	var step: float = (heart_width + spacing) * heart_scale
	var total: float = step * count - spacing * heart_scale
	var first_x: float = (-total + heart_width * heart_scale) / 2.0
	for i in count:
		var sprite := Sprite2D.new()
		sprite.texture = _heart_texture()
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.material = _unshaded()
		sprite.scale = Vector2(heart_scale, heart_scale)
		sprite.position = Vector2(first_x + step * float(i), 0.0)
		add_child(sprite)
		_hearts.append(sprite)


func _heart_texture() -> Texture2D:
	if _texture:
		return _texture
	var w: int = HEART_ROWS[0].length()
	var h: int = HEART_ROWS.size()
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var row: String = HEART_ROWS[y]
		for x in w:
			img.set_pixel(x, y, heart_color if row[x] == "X" else Color(0, 0, 0, 0))
	_texture = ImageTexture.create_from_image(img)
	return _texture


func _unshaded() -> CanvasItemMaterial:
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return mat
