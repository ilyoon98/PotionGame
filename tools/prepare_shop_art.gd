extends SceneTree

func _initialize() -> void:
	var room := Image.load_from_file("res://assets/source/room_v2.png")
	assert(room != null)
	room.resize(204, 124, Image.INTERPOLATE_NEAREST)
	assert(room.save_png("res://assets/room_204.png") == OK)
	_prepare("cauldron", Vector2i(48, 48), "cauldron_48")
	_prepare("potion", Vector2i(12, 16), "potion_12x16")
	print("Prepared room 204x124, cauldron 48x48, potion 12x16")
	quit()


func _prepare(asset: String, cell_size: Vector2i, output: String) -> void:
	var source := Image.load_from_file("res://assets/source/" + asset + "_v2.png")
	assert(source != null)
	var bounds := source.get_used_rect()
	var cropped := source.get_region(bounds)
	var fit := Vector2(cell_size - Vector2i(2, 2))
	var factor := minf(fit.x / bounds.size.x, fit.y / bounds.size.y)
	cropped.resize(maxi(1, roundi(bounds.size.x * factor)), maxi(1, roundi(bounds.size.y * factor)), Image.INTERPOLATE_NEAREST)
	cropped.convert(Image.FORMAT_RGBA8)
	var sprite := Image.create(cell_size.x, cell_size.y, false, Image.FORMAT_RGBA8)
	sprite.fill(Color.TRANSPARENT)
	sprite.blit_rect(cropped, Rect2i(Vector2i.ZERO, cropped.get_size()), (cell_size - cropped.get_size()) / 2)
	assert(sprite.save_png("res://assets/" + output + ".png") == OK)
