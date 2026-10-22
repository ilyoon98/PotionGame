extends SceneTree
## Register AI-authored leg poses under a single immutable approved torso.
const OUTPUT = "res://assets/characters/walk_cycles_v3/"
const CONFIG = {"elf": {"cut": 48, "source_cut": 0.67}, "mage": {"cut": 55, "source_cut": 0.87}, "rogue": {"cut": 48, "source_cut": 0.75}}

func bounds_of(picture: Image) -> Rect2i:
	var low := picture.get_size()
	var high := Vector2i(-1, -1)
	for y in picture.get_height():
		for x in picture.get_width():
			if picture.get_pixel(x, y).a >= 0.5:
				low = low.min(Vector2i(x, y))
				high = high.max(Vector2i(x, y))
	assert(high.x >= low.x)
	return Rect2i(low, high - low + Vector2i.ONE)

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var all_manifest := {"cell_size": [48,64], "sheet_size": [96,128], "phases": ["contact_a","passing_a","contact_b","passing_b"], "fps": 8, "loop": true, "characters": {}}
	for character in CONFIG:
		var source_path: String = "res://assets/source/walk_cycles_v2/" + character + ".png"
		if not FileAccess.file_exists(source_path):
			continue
		var base := Image.load_from_file("res://assets/characters/animations_v1/" + character + "_idle_48x64.png")
		base.convert(Image.FORMAT_RGBA8)
		var source := Image.load_from_file(source_path)
		source.convert(Image.FORMAT_RGBA8)
		var cell_size := source.get_size() / 2
		var cells: Array[Image] = []
		var bounds: Array[Rect2i] = []
		var max_lower_height := 0
		var split_rows: Array[int] = []
		for i in 4:
			var cell := source.get_region(Rect2i(Vector2i(i % 2, i / 2) * cell_size, cell_size))
			var body := bounds_of(cell)
			var split := body.position.y + roundi(body.size.y * float(CONFIG[character]["source_cut"]))
			cells.append(cell)
			bounds.append(body)
			split_rows.append(split)
			max_lower_height = maxi(max_lower_height, body.end.y - split)
		var cut: int = CONFIG[character]["cut"]
		var factor := float(62 - cut) / max_lower_height
		var sheet := Image.create(96,128,false,Image.FORMAT_RGBA8)
		sheet.fill(Color.TRANSPARENT)
		var contact := Image.create(224,72,false,Image.FORMAT_RGBA8)
		contact.fill(Color("282231"))
		var exported: Array[String] = []
		var frames: Array[Image] = []
		for i in 4:
			var body := bounds[i]
			var head := bounds_of(cells[i].get_region(Rect2i(body.position, Vector2i(body.size.x, roundi(body.size.y * 0.35)))))
			var anchor := body.position.x + head.position.x + head.size.x / 2.0
			var lower := cells[i].get_region(Rect2i(body.position.x, split_rows[i], body.size.x, body.end.y - split_rows[i]))
			var fitted := Vector2i(roundi(lower.get_width()*factor), roundi(lower.get_height()*factor))
			lower.resize(fitted.x,fitted.y,Image.INTERPOLATE_NEAREST)
			for y in fitted.y:
				for x in fitted.x:
					var color := lower.get_pixel(x,y)
					color.a = 1.0 if color.a >= 0.5 else 0.0
					lower.set_pixel(x,y,color)
			var frame := Image.create(48,64,false,Image.FORMAT_RGBA8)
			frame.fill(Color.TRANSPARENT)
			frame.blit_rect(base,Rect2i(0,0,48,cut),Vector2i.ZERO)
			var origin := Vector2i(24-roundi((anchor-body.position.x)*factor), cut)
			assert(origin.x >= 0 and origin.x+fitted.x <= 48)
			frame.blit_rect(lower,Rect2i(Vector2i.ZERO,fitted),origin)
			# The upper body is not resampled or regenerated between poses.
			assert(frame.get_region(Rect2i(0,0,48,cut)).get_data() == base.get_region(Rect2i(0,0,48,cut)).get_data())
			var filename := "%s_walk_%d_48x64.png" % [character,i+1]
			assert(frame.save_png(OUTPUT+filename)==OK)
			exported.append(filename)
			frames.append(frame)
			sheet.blit_rect(frame,Rect2i(0,0,48,64),Vector2i(i%2,i/2)*Vector2i(48,64))
			contact.blend_rect(frame,Rect2i(0,0,48,64),Vector2i(4+i*56,4))
		assert(sheet.save_png(OUTPUT+character+"_walk_96x128.png")==OK)
		contact.resize(896,288,Image.INTERPOLATE_NEAREST)
		assert(contact.save_png(OUTPUT+character+"_walk_preview_4x.png")==OK)
		all_manifest["characters"][character]={"frames":exported,"locked_upper_rows":cut,"sheet":character+"_walk_96x128.png"}
		print("PASS ",character,": 4 frames, top ",cut," rows identical to approved idle; lower-body-only motion")
	var manifest := FileAccess.open(OUTPUT+"manifest.json",FileAccess.WRITE)
	manifest.store_string(JSON.stringify(all_manifest,"\t"))
	manifest.close()
	quit()
