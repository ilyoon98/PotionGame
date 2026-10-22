extends SceneTree


func _initialize() -> void:
	_prepare("mana", Vector2i(12, 16), "mana_12x16")
	_prepare("mushroom", Vector2i(24, 24), "mushroom_24")
	quit()


func _prepare(asset: String, cell: Vector2i, output: String) -> void:
	var source := Image.load_from_file("res://assets/source/" + asset + ".png")
	assert(source != null)
	var start := source.get_size()
	var finish := Vector2i(-1, -1)
	for y in range(source.get_height()):
		for x in range(source.get_width()):
			if source.get_pixel(x, y).a >= 0.5:
				start.x = mini(start.x, x)
				start.y = mini(start.y, y)
				finish.x = maxi(finish.x, x)
				finish.y = maxi(finish.y, y)
	assert(finish.x >= start.x)
	var cropped := source.get_region(Rect2i(start, finish - start + Vector2i.ONE))
	var factor := minf(float(cell.x - 2) / cropped.get_width(), float(cell.y - 2) / cropped.get_height())
	cropped.resize(maxi(1, roundi(cropped.get_width() * factor)), maxi(1, roundi(cropped.get_height() * factor)), Image.INTERPOLATE_NEAREST)
	cropped.convert(Image.FORMAT_RGBA8)
	var sprite := Image.create(cell.x, cell.y, false, Image.FORMAT_RGBA8)
	sprite.fill(Color.TRANSPARENT)
	sprite.blit_rect(cropped, Rect2i(Vector2i.ZERO, cropped.get_size()), (cell - cropped.get_size()) / 2)
	assert(sprite.save_png("res://assets/" + output + ".png") == OK)
	print("Prepared ", output)
