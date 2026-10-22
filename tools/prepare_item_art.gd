extends SceneTree
## Keep generated alpha; fit whole silhouettes with nearest sampling, no repainting.
const SOURCE := "res://assets/source/items_v1/"
const OUTPUT := "res://assets/items_v1/"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	for kind in ["moon", "purify", "agility"]:
		var source := Image.load_from_file(SOURCE + kind + ".png")
		assert(source != null)
		_fit(source, Vector2i(12, 16)).save_png(OUTPUT + kind + "_12x16.png")
		_fit(source, Vector2i(32, 40)).save_png(OUTPUT + kind + "_icon.png")
	var herb := Image.load_from_file(SOURCE + "herb.png")
	assert(herb != null)
	_fit(herb, Vector2i(32, 32)).save_png(OUTPUT + "herb_icon.png")
	for entry in [["health", "res://assets/source/potion_v2.png"], ["mana", "res://assets/source/mana.png"]]:
		_fit(Image.load_from_file(entry[1]), Vector2i(32, 40)).save_png(OUTPUT + entry[0] + "_icon.png")
	_prepare_starleaf()
	print("ITEM ART IMPORT: three unique bottles, seven icons, four starleaf growth frames; preserved alpha")
	quit()


func _bounds(source: Image) -> Rect2i:
	var start := source.get_size()
	var finish := Vector2i(-1, -1)
	for y in source.get_height():
		for x in source.get_width():
			if source.get_pixel(x, y).a >= 0.5:
				start = Vector2i(mini(start.x, x), mini(start.y, y))
				finish = Vector2i(maxi(finish.x, x), maxi(finish.y, y))
	assert(finish.x >= start.x, "Source must contain a visible sprite")
	return Rect2i(start, finish - start + Vector2i.ONE)


func _fit(source: Image, cell: Vector2i) -> Image:
	var cropped := source.get_region(_bounds(source))
	var factor := minf(float(cell.x - 2) / cropped.get_width(), float(cell.y - 2) / cropped.get_height())
	cropped.resize(maxi(1, roundi(cropped.get_width() * factor)), maxi(1, roundi(cropped.get_height() * factor)), Image.INTERPOLATE_NEAREST)
	cropped.convert(Image.FORMAT_RGBA8)
	var result := Image.create(cell.x, cell.y, false, Image.FORMAT_RGBA8)
	result.fill(Color.TRANSPARENT)
	result.blit_rect(cropped, Rect2i(Vector2i.ZERO, cropped.get_size()), (cell - cropped.get_size()) / 2)
	return result


func _prepare_starleaf() -> void:
	var source := Image.load_from_file(SOURCE + "starleaf_growth.png")
	assert(source != null)
	var cell := source.get_size() / 2
	var crops: Array[Image] = []
	var maximum := Vector2i.ZERO
	for index in range(4):
		var frame := source.get_region(Rect2i(Vector2i(index % 2, index / 2) * cell, cell))
		var crop := frame.get_region(_bounds(frame))
		crops.append(crop)
		maximum = Vector2i(maxi(maximum.x, crop.get_width()), maxi(maximum.y, crop.get_height()))
	var factor := minf(30.0 / maximum.x, 38.0 / maximum.y)
	var atlas := Image.create(64, 80, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	for index in range(4):
		var crop := crops[index]
		crop.resize(maxi(1, roundi(crop.get_width() * factor)), maxi(1, roundi(crop.get_height() * factor)), Image.INTERPOLATE_NEAREST)
		crop.convert(Image.FORMAT_RGBA8)
		var offset := Vector2i((32 - crop.get_width()) / 2, 39 - crop.get_height())
		atlas.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), Vector2i(index % 2, index / 2) * Vector2i(32, 40) + offset)
	assert(atlas.save_png(OUTPUT + "starleaf_growth.png") == OK)
	atlas.get_region(Rect2i(0, 40, 32, 40)).save_png(OUTPUT + "starleaf_icon.png")
