extends SceneTree

func _initialize() -> void:
	for character in ["keeper", "customer"]:
		_prepare(character)
	quit()


func _prepare(character: String) -> void:
	var source := Image.load_from_file("res://assets/source/" + character + "_animation.png")
	assert(source != null)
	var cell_size := source.get_size() / 2
	var cells: Array[Image] = []
	var shared_bounds := Rect2i()
	for index in range(4):
		var cell := source.get_region(Rect2i(Vector2i(index % 2, index / 2) * cell_size, cell_size))
		cells.append(cell)
		var bounds := _visible_bounds(cell)
		shared_bounds = bounds if index == 0 else shared_bounds.merge(bounds)
	var factor := minf(44.0 / shared_bounds.size.x, 60.0 / shared_bounds.size.y)
	var fitted := Vector2i(roundi(shared_bounds.size.x * factor), roundi(shared_bounds.size.y * factor))
	var atlas := Image.create(96, 128, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	for index in range(4):
		var cropped := cells[index].get_region(shared_bounds)
		cropped.resize(fitted.x, fitted.y, Image.INTERPOLATE_NEAREST)
		cropped.convert(Image.FORMAT_RGBA8)
		var origin := Vector2i(index % 2, index / 2) * Vector2i(48, 64)
		var offset := Vector2i((48 - fitted.x) / 2, 62 - fitted.y)
		atlas.blit_rect(cropped, Rect2i(Vector2i.ZERO, fitted), origin + offset)
	assert(atlas.save_png("res://assets/" + character + "_animations.png") == OK)
	print(character, ": four registered frames, ", fitted, " inside 48x64 cells")


func _visible_bounds(image: Image) -> Rect2i:
	var minimum := image.get_size()
	var maximum := Vector2i(-1, -1)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a >= 0.5:
				minimum.x = mini(minimum.x, x)
				minimum.y = mini(minimum.y, y)
				maximum.x = maxi(maximum.x, x)
				maximum.y = maxi(maximum.y, y)
	assert(maximum.x >= minimum.x)
	return Rect2i(minimum, maximum - minimum + Vector2i.ONE)
