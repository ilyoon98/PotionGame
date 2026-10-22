extends Control
## A shared, fixed-baseline growth sprite; harvesting is driven by actual events.
var progress := 0.0
var storage_full := false
var harvest_flash := 0.0
var frames: Array[AtlasTexture] = []
var sprite_path := "res://assets/herb_growth.png"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var sheet: Texture2D = load(sprite_path)
	for index in range(4):
		var frame := AtlasTexture.new()
		frame.atlas = sheet
		frame.region = Rect2((index % 2) * 32, (index / 2) * 40, 32, 40)
		frames.append(frame)


func on_harvest() -> void:
	harvest_flash = 0.7


func _process(delta: float) -> void:
	harvest_flash = maxf(0.0, harvest_flash - delta)
	queue_redraw()


func _draw() -> void:
	if frames.is_empty():
		return
	var frame := 3 if harvest_flash > 0.0 else mini(2, int(progress * 3.0))
	draw_texture_rect(frames[frame], Rect2(Vector2.ZERO, size), false)
