extends SceneTree
## Discrete transparent weather objects for the desktop overlay. Art export only.
const OUTPUT = "res://assets/weather/v1/"
const SIZES = {"sun": Vector2i(24, 24), "moon": Vector2i(24, 32), "star": Vector2i(8, 8), "cloud_clear": Vector2i(64, 24), "cloud_rain": Vector2i(96, 32), "rain": Vector2i(96, 96)}

func bounds_of(picture: Image, threshold: float = 0.85) -> Rect2i:
	var minimum := picture.get_size()
	var maximum := Vector2i(-1, -1)
	for y in picture.get_height():
		for x in picture.get_width():
			if picture.get_pixel(x, y).a >= threshold:
				minimum = minimum.min(Vector2i(x, y))
				maximum = maximum.max(Vector2i(x, y))
	assert(maximum.x >= minimum.x)
	return Rect2i(minimum, maximum - minimum + Vector2i.ONE)

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var assets := {}
	var manifest := {"scale": 2, "filter": "nearest", "alpha": "RGBA; no sky/background rectangles", "assets": {}, "combinations": {"day_clear": ["sun", "cloud_clear"], "night_clear": ["moon", "star"], "day_rain": ["cloud_rain", "rain"], "night_rain": ["moon", "cloud_rain", "rain"]}, "layer_order_back_to_front": ["sun or moon", "star", "rain", "cloud", "shop characters"], "rain_note": "Cloud and rain are independent textures. Scroll rain with repeat enabled; a single raindrop is also supplied for particles. Clip rain below the cloud canopy, not across the entire desktop."}
	for key in SIZES:
		var source := Image.load_from_file("res://assets/source/weather_v1/" + key + ".png")
		source.convert(Image.FORMAT_RGBA8)
		var bounds := bounds_of(source)
		var cropped := source.get_region(bounds)
		var target: Vector2i = SIZES[key]
		var inner := target - Vector2i(2, 2)
		var factor := minf(float(inner.x) / bounds.size.x, float(inner.y) / bounds.size.y)
		var fitted := Vector2i(maxi(1, roundi(bounds.size.x * factor)), maxi(1, roundi(bounds.size.y * factor)))
		cropped.resize(fitted.x, fitted.y, Image.INTERPOLATE_NEAREST)
		for y in cropped.get_height():
			for x in cropped.get_width():
				var color := cropped.get_pixel(x, y)
				color.a = 1.0 if color.a >= 0.85 else 0.0
				cropped.set_pixel(x, y, color)
		var sprite := Image.create(target.x, target.y, false, Image.FORMAT_RGBA8)
		sprite.fill(Color.TRANSPARENT)
		sprite.blit_rect(cropped, Rect2i(Vector2i.ZERO, fitted), (target - fitted) / 2)
		var filename: String = "%s_%dx%d.png" % [key, target.x, target.y]
		assert(sprite.save_png(OUTPUT + filename) == OK)
		var saved := Image.load_from_file(OUTPUT + filename)
		assert(saved.get_size() == target and saved.get_format() == Image.FORMAT_RGBA8)
		var occupied := 0
		for y in target.y:
			for x in target.x:
				var alpha := saved.get_pixel(x, y).a
				assert(alpha == 0.0 or alpha == 1.0)
				if alpha > 0.0:
					occupied += 1
				if x == 0 or y == 0 or x == target.x - 1 or y == target.y - 1:
					assert(alpha == 0.0)
		var coverage := float(occupied) / (target.x * target.y)
		assert(coverage > 0.0 and coverage < 0.9)
		if key == "rain":
			assert(coverage < 0.15, "Rain layer must remain mostly empty")
		assets[key] = sprite
		manifest["assets"][key] = {"file": filename, "size": [target.x, target.y], "visible_fraction": coverage}
		print("PASS ", key, " ", target, " alpha occupancy=", snappedf(coverage, 0.001))
	# Extract one generated rain streak for particle-based animation as well.
	var rain: Image = assets["rain"]
	var visited := {}
	var best := Rect2i()
	for y in rain.get_height():
		for x in rain.get_width():
			var seed := Vector2i(x, y)
			if visited.has(seed) or rain.get_pixelv(seed).a < 0.5:
				continue
			var queue: Array[Vector2i] = [seed]
			visited[seed] = true
			var minimum := seed
			var maximum := seed
			while not queue.is_empty():
				var point := queue.pop_back() as Vector2i
				minimum = minimum.min(point)
				maximum = maximum.max(point)
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var neighbor := point + Vector2i(dx, dy)
						if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= rain.get_width() or neighbor.y >= rain.get_height() or visited.has(neighbor):
							continue
						if rain.get_pixelv(neighbor).a >= 0.5:
							visited[neighbor] = true
							queue.append(neighbor)
			var component := Rect2i(minimum, maximum - minimum + Vector2i.ONE)
			if component.size.y > best.size.y:
				best = component
	assert(best.size.y >= 3)
	var drop := Image.create(best.size.x + 2, best.size.y + 2, false, Image.FORMAT_RGBA8)
	drop.fill(Color.TRANSPARENT)
	drop.blit_rect(rain, best, Vector2i.ONE)
	assert(drop.save_png(OUTPUT + "raindrop.png") == OK)
	manifest["assets"]["raindrop"] = {"file": "raindrop.png", "size": [drop.get_width(), drop.get_height()]}
	# Same assets on light and dark surfaces for transparency/contrast inspection.
	var board := Image.create(256, 240, false, Image.FORMAT_RGBA8)
	board.fill(Color("282231"))
	board.fill_rect(Rect2i(128, 0, 128, 240), Color("e8e2d8"))
	for column in 2:
		var origin := Vector2i(column * 128, 0)
		board.blend_rect(assets["sun"], Rect2i(Vector2i.ZERO, SIZES["sun"]), origin + Vector2i(12, 12))
		board.blend_rect(assets["moon"], Rect2i(Vector2i.ZERO, SIZES["moon"]), origin + Vector2i(64, 8))
		for star in [Vector2i(99, 12), Vector2i(110, 33), Vector2i(93, 45)]:
			board.blend_rect(assets["star"], Rect2i(Vector2i.ZERO, SIZES["star"]), origin + star)
		board.blend_rect(assets["cloud_clear"], Rect2i(Vector2i.ZERO, SIZES["cloud_clear"]), origin + Vector2i(32, 60))
		board.blend_rect(assets["cloud_rain"], Rect2i(Vector2i.ZERO, SIZES["cloud_rain"]), origin + Vector2i(16, 100))
		board.blend_rect(assets["rain"], Rect2i(Vector2i.ZERO, SIZES["rain"]), origin + Vector2i(16, 140))
	board.resize(512, 480, Image.INTERPOLATE_NEAREST)
	assert(board.save_png(OUTPUT + "weather_objects_preview_2x.png") == OK)
	var file := FileAccess.open(OUTPUT + "manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	quit()
