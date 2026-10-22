extends SceneTree
const Art = preload("res://scripts/management_art.gd")
const SOURCE := "res://assets/source/management_v1/"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(Art.ROOT)
	for id in Art.GENERATED:
		var source := Image.load_from_file(SOURCE + id + ".png")
		assert(source != null, "Missing generated icon: " + id)
		var start := source.get_size()
		var finish := Vector2i(-1, -1)
		for y in source.get_height():
			for x in source.get_width():
				if source.get_pixel(x, y).a >= 0.5:
					start = Vector2i(mini(start.x, x), mini(start.y, y))
					finish = Vector2i(maxi(finish.x, x), maxi(finish.y, y))
		assert(finish.x >= start.x, "Empty icon: " + id)
		var cropped := source.get_region(Rect2i(start, finish - start + Vector2i.ONE))
		var factor := minf(30.0 / cropped.get_width(), 38.0 / cropped.get_height())
		cropped.resize(maxi(1, roundi(cropped.get_width() * factor)), maxi(1, roundi(cropped.get_height() * factor)), Image.INTERPOLATE_NEAREST)
		cropped.convert(Image.FORMAT_RGBA8)
		var result := Image.create(32, 40, false, Image.FORMAT_RGBA8)
		result.fill(Color.TRANSPARENT)
		result.blit_rect(cropped, Rect2i(Vector2i.ZERO, cropped.get_size()), (Vector2i(32, 40) - cropped.get_size()) / 2)
		assert(result.save_png(Art.ROOT + id + "_icon.png") == OK)
	print("MANAGEMENT ART IMPORT: six 32x40 icons; nearest sampling; generated alpha preserved")
	quit()
