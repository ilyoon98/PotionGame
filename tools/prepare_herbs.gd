extends SceneTree
## Import the generated four-frame source at a shared scale, centered on each pot.


func _initialize() -> void:
	var source := Image.load_from_file("res://assets/source/herb_growth.png")
	if source == null:
		quit(1)
		return
	var cell := Vector2i(source.get_width() / 2, source.get_height() / 2)
	var crops: Array[Image] = []
	var maximum := Vector2i.ZERO
	for index in range(4):
		var frame := source.get_region(Rect2i(Vector2i(index % 2, index / 2) * cell, cell))
		# Ignore nearly invisible generated pixels when finding the visible silhouette.
		var left := cell.x
		var top := cell.y
		var right := -1
		var bottom := -1
		for y in range(cell.y):
			for x in range(cell.x):
				if frame.get_pixel(x, y).a >= 0.5:
					left = mini(left, x)
					top = mini(top, y)
					right = maxi(right, x)
					bottom = maxi(bottom, y)
		assert(right >= left and bottom >= top)
		var crop := frame.get_region(Rect2i(left, top, right - left + 1, bottom - top + 1))
		crops.append(crop)
		maximum.x = maxi(maximum.x, crop.get_width())
		maximum.y = maxi(maximum.y, crop.get_height())
	var factor := minf(30.0 / maximum.x, 38.0 / maximum.y)
	var atlas := Image.create(64, 80, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	for index in range(4):
		var crop := crops[index]
		crop.resize(maxi(1, roundi(crop.get_width() * factor)), maxi(1, roundi(crop.get_height() * factor)), Image.INTERPOLATE_NEAREST)
		var offset := Vector2i((32 - crop.get_width()) / 2, 39 - crop.get_height())
		atlas.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), Vector2i(index % 2, index / 2) * Vector2i(32, 40) + offset)
	assert(atlas.save_png("res://assets/herb_growth.png") == OK)
	print("HERB IMPORT: four 32x40 frames, shared scale and feet baseline")
	quit()
