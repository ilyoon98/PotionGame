extends SceneTree
## Sample the existing rain texture at four evenly spaced scroll positions.
const OUTPUT = "res://assets/weather/v1/"
const FRAME_SIZE = Vector2i(96, 96)
const FRAME_COUNT = 4
const STEP_Y = 24

func shifted(source: Image, offset_y: int) -> Image:
	var frame := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	for y in 96:
		for x in 96:
			frame.set_pixel(x, y, source.get_pixel(x, posmod(y - offset_y, 96)))
	return frame

func _initialize() -> void:
	var source := Image.load_from_file(OUTPUT + "rain_96x96.png")
	source.convert(Image.FORMAT_RGBA8)
	assert(source.get_size() == FRAME_SIZE)
	var cloud := Image.load_from_file(OUTPUT + "cloud_rain_96x32.png")
	var sheet := Image.create(192, 192, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.TRANSPARENT)
	var contact := Image.create(416, 104, false, Image.FORMAT_RGBA8)
	contact.fill(Color("282231"))
	var filenames: Array[String] = []
	var frame_hashes: Array[int] = []
	for index in FRAME_COUNT:
		var frame := shifted(source, index * STEP_Y)
		var frame_hash := hash(frame.get_data())
		assert(not frame_hashes.has(frame_hash))
		frame_hashes.append(frame_hash)
		var filename := "rain_frame_%d_96x96.png" % index
		assert(frame.save_png(OUTPUT + filename) == OK)
		filenames.append(filename)
		sheet.blit_rect(frame, Rect2i(Vector2i.ZERO, FRAME_SIZE), Vector2i(index % 2, index / 2) * FRAME_SIZE)
		contact.blend_rect(frame, Rect2i(Vector2i.ZERO, FRAME_SIZE), Vector2i(4 + index * 104, 4))
		# The cloud is combined ONLY for this viewing aid, never in exported rain frames.
		var preview := Image.create(112, 136, false, Image.FORMAT_RGBA8)
		preview.fill(Color("282231"))
		preview.blend_rect(frame, Rect2i(Vector2i.ZERO, FRAME_SIZE), Vector2i(8, 34))
		preview.blend_rect(cloud, Rect2i(0, 0, 96, 32), Vector2i(8, 4))
		preview.resize(224, 272, Image.INTERPOLATE_NEAREST)
		var file := FileAccess.open(OUTPUT + "rain_preview_frame_%d.rgba" % index, FileAccess.WRITE)
		file.store_buffer(preview.get_data())
		file.close()
	assert(shifted(source, FRAME_COUNT * STEP_Y).get_data() == source.get_data(), "Loop closure must equal frame zero")
	assert(sheet.save_png(OUTPUT + "rain_animation_192x192.png") == OK)
	contact.resize(832, 208, Image.INTERPOLATE_NEAREST)
	assert(contact.save_png(OUTPUT + "rain_frames_preview_2x.png") == OK)
	var metadata := {"source": "rain_96x96.png", "method": "Exact vertical wrap of existing generated artwork; no new drawing", "frame_size": [96, 96], "sheet_size": [192, 192], "sheet": "rain_animation_192x192.png", "frames": filenames, "order": "row-major 2x2; 0,1,2,3", "offsets_y": [0,24,48,72], "loop": true, "fps": 8, "note": "Rain-only RGBA frames; cloud_rain_96x32.png remains a separate static object", "gif_preview_size": [224,272]}
	var manifest_file := FileAccess.open(OUTPUT + "rain_animation.json", FileAccess.WRITE)
	manifest_file.store_string(JSON.stringify(metadata, "\t"))
	manifest_file.close()
	print("PASS: 4 distinct 96x96 RGBA frames; uniform +24px motion; frame 4 wraps exactly to frame 0; separate cloud")
	quit()
