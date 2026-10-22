extends SceneTree
const ROOT := "C:/Users/imtl/ilyoon_Git/방치형 게임/새-게임-프로젝트/assets/rare_recipes_v1/"
var checks := 0

func _initialize() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "catalog.json"))
	var png_hashes := {}
	var bottle_masks := {}
	var geometry := []
	for entry in catalog["assets"]:
		var id: String = entry["id"]
		for variant in ["potion", "bottle", "recipe"]:
			var size := Vector2i(12, 16) if variant == "bottle" else Vector2i(32, 40)
			var source_path: String = ROOT + "source/" + id + "_" + variant + ".png"
			var source := Image.load_from_file(source_path)
			assert(source != null, "Missing generated source: " + source_path)
			var bounds := source.get_used_rect()
			# Ignore faint outside alpha in the trim measurement; preserve original alpha pixels inside.
			var start := source.get_size()
			var end := Vector2i(-1, -1)
			for y in source.get_height():
				for x in source.get_width():
					if source.get_pixel(x,y).a >= 0.5:
						start = Vector2i(mini(start.x,x),mini(start.y,y))
						end = Vector2i(maxi(end.x,x),maxi(end.y,y))
			assert(end.x >= start.x, "Empty generated image")
			bounds = Rect2i(start, end - start + Vector2i.ONE)
			var crop := source.get_region(bounds)
			var scale := minf(float(size.x-2)/crop.get_width(),float(size.y-2)/crop.get_height())
			crop.resize(maxi(1,roundi(crop.get_width()*scale)),maxi(1,roundi(crop.get_height()*scale)),Image.INTERPOLATE_NEAREST)
			crop.convert(Image.FORMAT_RGBA8)
			var image := Image.create(size.x,size.y,false,Image.FORMAT_RGBA8)
			image.fill(Color.TRANSPARENT)
			image.blit_rect(crop,Rect2i(Vector2i.ZERO,crop.get_size()),(size-crop.get_size())/2)
			var path: String = entry[variant + "_path"].replace("res://assets/rare_recipes_v1/",ROOT)
			assert(image.save_png(path) == OK)
			var loaded := Image.load_from_file(path)
			assert(loaded.get_size() == size and not loaded.is_invisible())
			assert(loaded.get_pixel(0,0).a == 0 and loaded.get_pixel(size.x-1,size.y-1).a == 0)
			var signature := hash(loaded.get_data())
			assert(not png_hashes.has(signature), "Duplicate deliverable: " + path)
			png_hashes[signature] = path
			var opaque := 0
			var transparent := 0
			var mask := PackedByteArray()
			for y in size.y:
				for x in size.x:
					var a := loaded.get_pixel(x,y).a
					if a >= 0.5: opaque += 1
					if a == 0: transparent += 1
					mask.append(1 if a >= 0.5 else 0)
			assert(opaque > 0 and transparent > 0)
			if variant == "bottle":
				assert(not bottle_masks.has(hash(mask)), "Rare bottles need distinct silhouettes")
				bottle_masks[hash(mask)] = id
			geometry.append({"id":id,"variant":variant,"size":[size.x,size.y],"body_bounds":[crop.get_width(),crop.get_height()],"opaque_pixels":opaque,"transparent_pixels":transparent,"path":entry[variant + "_path"]})
			checks += 1
		entry["status"] = "design_complete"
		entry["connection_status"] = "awaiting_game_integration"
	assert(checks == 12 and bottle_masks.size() == 4)
	catalog["status"] = "design_complete"
	catalog["connected_to_game"] = false
	catalog["validation_path"] = "res://assets/rare_recipes_v1/verification/art-validation.json"
	var file := FileAccess.open(ROOT + "catalog.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(catalog,"\t")+"\n")
	var report := FileAccess.open(ROOT + "verification/art-validation.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"passed":true,"deliverables":12,"sets":4,"unique_small_bottle_silhouettes":4,"small_bottle_source":"independently_generated_logical_12x16_designs","checks":["exact PNG dimensions","nonempty genuine alpha","transparent corner padding","all 12 images distinct","4 small bottle silhouettes distinct","separate potion and recipe PNGs"],"geometry":geometry},"\t")+"\n")
	print("RARE RECIPE EXPORT AND VALIDATION PASS: 4 sets, 12 PNGs, distinct 12x16 silhouettes, real alpha")
	quit()
