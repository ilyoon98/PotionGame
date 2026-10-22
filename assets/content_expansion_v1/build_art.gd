extends SceneTree
## Design-only exports. No shop state, save files or shared scripts are loaded.
const ROOT := "res://assets/content_expansion_v1/"
const SOURCE := "res://assets/content_expansion_v1/source/"
var catalog: Dictionary


func _initialize() -> void:
	catalog = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "catalog.json"))
	for entry in catalog["assets"]:
		if entry.get("status", "planned") == "planned": continue
		var source_path: String = entry.get("source_path", "")
		if source_path.is_empty() or not FileAccess.file_exists(source_path): continue
		var source := Image.load_from_file(source_path)
		assert(source != null)
		var category: String = entry["category"]
		if entry.has("source_region"):
			var r: Array = entry["source_region"]
			source = source.get_region(Rect2i(r[0], r[1], r[2], r[3]))
		if entry.get("sheet", "") == "botanical_3x2":
			var cell := Vector2i(source.get_width() / 3, source.get_height() / 2)
			_save_fit(source.get_region(Rect2i(Vector2i.ZERO, cell)), entry["icon_path"], Vector2i(32, 40))
			_growth(source, cell, entry["growth_path"])
		elif entry.get("sheet", "") in ["equipment_2x1", "equipment_3x1"]:
			var count := 2 if entry["sheet"] == "equipment_2x1" else 3
			var cell := Vector2i(source.get_width() / count, source.get_height())
			for i in count:
				var tier_index := i + 1 if count == 2 else i
				_save_fit(source.get_region(Rect2i(Vector2i(i, 0) * cell, cell)), entry["tier_paths"][tier_index], Vector2i(32, 40))
			if count == 2:
				var base := Image.load_from_file(entry["base_source"])
				if entry.has("base_region"):
					var r: Array = entry["base_region"]
					base = base.get_region(Rect2i(r[0], r[1], r[2], r[3]))
				_save_fit(base, entry["tier_paths"][0], Vector2i(32, 40))
		else:
			_save_fit(source, entry["icon_path"], Vector2i(32, 40))
			if category == "potions":
				var bottle_source := Image.load_from_file(entry["bottle_source"]) if entry.has("bottle_source") else source
				_save_fit(bottle_source, entry["bottle_path"], Vector2i(12, 16))
		if entry.has("growth_source"):
			var growth := Image.load_from_file(entry["growth_source"])
			assert(growth.save_png(entry["growth_path"]) == OK)
		entry["status"] = "reused" if entry.get("reused", false) else "completed"
	var file := FileAccess.open(ROOT + "catalog.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(catalog, "\t") + "\n")
	print("EXPANSION EXPORT: completed available designs, icon 32x40, bottle 12x16, growth 4x32x40, alpha preserved")
	quit()


func _bounds(source: Image) -> Rect2i:
	var start := source.get_size()
	var finish := Vector2i(-1, -1)
	for y in source.get_height():
		for x in source.get_width():
			if source.get_pixel(x, y).a >= 0.5:
				start = Vector2i(mini(start.x, x), mini(start.y, y))
				finish = Vector2i(maxi(finish.x, x), maxi(finish.y, y))
	assert(finish.x >= start.x, "Empty sprite")
	return Rect2i(start, finish - start + Vector2i.ONE)


func _save_fit(source: Image, path: String, size: Vector2i) -> void:
	if source.get_size() == size:
		assert(source.save_png(path) == OK)
		return
	var image := source.get_region(_bounds(source))
	var factor := minf(float(size.x - 2) / image.get_width(), float(size.y - 2) / image.get_height())
	image.resize(maxi(1, roundi(image.get_width() * factor)), maxi(1, roundi(image.get_height() * factor)), Image.INTERPOLATE_NEAREST)
	image.convert(Image.FORMAT_RGBA8)
	var result := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	result.fill(Color.TRANSPARENT)
	result.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), (size - image.get_size()) / 2)
	assert(result.save_png(path) == OK)


func _growth(source: Image, cell: Vector2i, path: String) -> void:
	var crops: Array[Image] = []
	var maximum := Vector2i.ZERO
	for cell_index in [1, 2, 3, 4]:
		var frame := source.get_region(Rect2i(Vector2i(cell_index % 3, cell_index / 3) * cell, cell))
		var crop := frame.get_region(_bounds(frame))
		maximum = Vector2i(maxi(maximum.x, crop.get_width()), maxi(maximum.y, crop.get_height()))
		crops.append(crop)
	var factor := minf(30.0 / maximum.x, 38.0 / maximum.y)
	var atlas := Image.create(64, 80, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	for i in 4:
		var crop := crops[i]
		crop.resize(maxi(1, roundi(crop.get_width() * factor)), maxi(1, roundi(crop.get_height() * factor)), Image.INTERPOLATE_NEAREST)
		crop.convert(Image.FORMAT_RGBA8)
		atlas.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), Vector2i(i % 2, i / 2) * Vector2i(32, 40) + Vector2i((32 - crop.get_width()) / 2, 39 - crop.get_height()))
	assert(atlas.save_png(path) == OK)

