extends SceneTree
## Export animation art only; does not modify the game's active sprites.

const NAMES = ["keeper", "traveler", "mage", "elf", "rogue"]
const OUTPUT = "res://assets/characters/animations_v1/"

func visible_bounds(picture: Image) -> Rect2i:
	var minimum := picture.get_size()
	var maximum := Vector2i(-1, -1)
	for y in picture.get_height():
		for x in picture.get_width():
			if picture.get_pixel(x, y).a >= 0.5:
				minimum = minimum.min(Vector2i(x, y))
				maximum = maximum.max(Vector2i(x, y))
	assert(maximum.x >= minimum.x)
	return Rect2i(minimum, maximum - minimum + Vector2i.ONE)

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var board := Image.create(224, 360, false, Image.FORMAT_RGBA8)
	board.fill(Color("292331"))
	var manifest := {"cell_size": [48, 64], "sheet_size": [96, 128], "sheet_order": "row-major 2x2", "baseline_y": 61, "game_scale": 2, "bottle": "Rendered separately by the game; not baked into sprites", "characters": {}}
	for character_index in NAMES.size():
		var character: String = NAMES[character_index]
		var source := Image.load_from_file("res://assets/source/character_animations_v1/" + character + ".png")
		assert(source != null)
		source.convert(Image.FORMAT_RGBA8)
		var cell_size := source.get_size() / 2
		var cells: Array[Image] = []
		var bounds: Array[Rect2i] = []
		var anchors: Array[float] = []
		var span := 0.0
		var tallest := 0
		for index in 4:
			var cell := source.get_region(Rect2i(Vector2i(index % 2, index / 2) * cell_size, cell_size))
			var body := visible_bounds(cell)
			# Align heads instead of centering the extended hand or swinging gear.
			var head := visible_bounds(cell.get_region(Rect2i(body.position, Vector2i(body.size.x, maxi(1, roundi(body.size.y * 0.43))))))
			var anchor := body.position.x + head.position.x + head.size.x / 2.0
			span = maxf(span, maxf(anchor - body.position.x, body.end.x - anchor))
			tallest = maxi(tallest, body.size.y)
			cells.append(cell)
			bounds.append(body)
			anchors.append(anchor)
		# One uniform scale per character across every pose, not four independent fits.
		var factor := minf(21.0 / span, 60.0 / tallest)
		# Export the original animation source. Rejected walking revisions are not used.
		var sheet := Image.create(96, 128, false, Image.FORMAT_RGBA8)
		sheet.fill(Color.TRANSPARENT)
		var pose_names: Array = ["idle", "brew_1", "brew_2", "sell"] if character == "keeper" else ["idle", "walk_1", "walk_2", "purchase_complete"]
		var frame_files: Array[String] = []
		var hashes: Array[int] = []
		for index in 4:
			var body := cells[index].get_region(bounds[index])
			var fitted := Vector2i(roundi(body.get_width() * factor), roundi(body.get_height() * factor))
			body.resize(fitted.x, fitted.y, Image.INTERPOLATE_NEAREST)
			for y in body.get_height():
				for x in body.get_width():
					var color := body.get_pixel(x, y)
					color.a = 1.0 if color.a >= 0.5 else 0.0
					body.set_pixel(x, y, color)
			var offset := Vector2i(24 - roundi((anchors[index] - bounds[index].position.x) * factor), 62 - fitted.y)
			assert(offset.x >= 1 and offset.x + fitted.x <= 47 and offset.y >= 2)
			var frame := Image.create(48, 64, false, Image.FORMAT_RGBA8)
			frame.fill(Color.TRANSPARENT)
			frame.blit_rect(body, Rect2i(Vector2i.ZERO, fitted), offset)
			var filename: String = character + "_" + pose_names[index] + "_48x64.png"
			assert(frame.save_png(OUTPUT + filename) == OK)
			var saved := Image.load_from_file(OUTPUT + filename)
			assert(saved.get_size() == Vector2i(48, 64) and saved.get_pixel(0, 0).a == 0.0)
			assert(visible_bounds(saved).end.y <= 62)
			hashes.append(hash(saved.get_data()))
			frame_files.append(filename)
			sheet.blit_rect(frame, Rect2i(0, 0, 48, 64), Vector2i(index % 2, index / 2) * Vector2i(48, 64))
			board.blend_rect(frame, Rect2i(0, 0, 48, 64), Vector2i(4 + index * 56, 4 + character_index * 72))
		assert(hashes[1] != hashes[2], "Motion frames must differ")
		assert(hashes[0] != hashes[3], "Action must differ from idle")
		assert(sheet.save_png(OUTPUT + character + "_animations_96x128.png") == OK)
		var row_preview := board.get_region(Rect2i(0, character_index * 72, 224, 72))
		for scale_factor in [2, 4]:
			var row_enlarged := row_preview.duplicate() as Image
			row_enlarged.resize(224 * scale_factor, 72 * scale_factor, Image.INTERPOLATE_NEAREST)
			assert(row_enlarged.save_png(OUTPUT + character + "_preview_" + str(scale_factor) + "x.png") == OK)
		manifest["characters"][character] = {"sheet": character + "_animations_96x128.png", "poses": pose_names, "frames": frame_files, "loop": {"frames": [1, 2], "fps": 4 if character == "keeper" else 6}}
		print("PASS ", character, ": 4 distinct action frames, 48x64 RGBA, 96x128 sheet, registered baseline")
	for scale_factor in [2, 4]:
		var enlarged := board.duplicate() as Image
		enlarged.resize(224 * scale_factor, 360 * scale_factor, Image.INTERPOLATE_NEAREST)
		assert(enlarged.save_png(OUTPUT + "contact_sheet_" + str(scale_factor) + "x.png") == OK)
	var file := FileAccess.open(OUTPUT + "manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	quit()
