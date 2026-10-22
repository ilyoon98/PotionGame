extends SceneTree


func _initialize() -> void:
	var interior := Image.load_from_file("res://assets/source/room_layered.png")
	assert(interior != null)
	interior.resize(204, 124, Image.INTERPOLATE_NEAREST)
	interior.convert(Image.FORMAT_RGBA8)
	var clear_pixels := 0
	var outside_pixels := 0
	for y in range(interior.get_height()):
		for x in range(interior.get_width()):
			if interior.get_pixel(x, y).a < 0.1:
				clear_pixels += 1
				if not Rect2i(8, 18, 52, 40).has_point(Vector2i(x, y)):
					outside_pixels += 1
	assert(clear_pixels > 800, "Window panes must preserve generated transparency")
	assert(outside_pixels == 0, "Only the window may reveal the outdoor layer")
	assert(interior.save_png("res://assets/room_interior_204.png") == OK)
	print("INTERIOR IMPORT: ", clear_pixels, " transparent window pixels; opaque room outside window")
	quit()
