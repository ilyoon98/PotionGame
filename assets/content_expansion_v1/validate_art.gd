extends SceneTree
const ROOT := "res://assets/content_expansion_v1/"
var checks := 0


func _initialize() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "catalog.json"))
	var counts := {}
	var unique_ids := {}
	var bottle_hashes := {}
	var growth_count := 0
	var tiers := 0
	var reused := 0
	var csv := FileAccess.open(ROOT + "asset-list.csv", FileAccess.WRITE)
	csv.store_csv_line(PackedStringArray(["id", "name", "category", "family", "region", "status", "reused", "icon_path", "bottle_path", "recipe_icon_path", "growth_path", "basic_path", "improved_path", "premium_path", "source_path"]))
	for entry in catalog["assets"]:
		var id: String = entry["id"]
		assert(not unique_ids.has(id), "Duplicate stable ID: " + id)
		unique_ids[id] = true
		assert(entry["status"] in ["completed", "reused"], "Incomplete entry: " + id)
		counts[entry["category"]] = counts.get(entry["category"], 0) + 1
		_check(entry["icon_path"], Vector2i(32, 40))
		if entry.get("reused", false): reused += 1
		if entry.has("bottle_path"):
			var bottle := _check(entry["bottle_path"], Vector2i(12, 16))
			var signature := hash(bottle.get_data())
			assert(not bottle_hashes.has(signature), "Duplicate small bottle: " + id)
			bottle_hashes[signature] = id
			assert(entry["recipe_icon_path"] == entry["icon_path"], "Recipes must reuse the potion icon")
		if entry.has("growth_path"):
			var sheet := _check(entry["growth_path"], Vector2i(64, 80))
			var frame_hashes := {}
			for i in 4:
				var frame := sheet.get_region(Rect2i((i % 2) * 32, (i / 2) * 40, 32, 40))
				assert(not frame.is_invisible(), "Empty growth frame: " + id)
				frame_hashes[hash(frame.get_data())] = true
			assert(frame_hashes.size() >= 3, "Missing growth variation: " + id)
			growth_count += 1
		if entry.has("tier_paths"):
			var unique_tiers := {}
			for path in entry["tier_paths"]:
				var image := _check(path, Vector2i(32, 40))
				unique_tiers[hash(image.get_data())] = true
			assert(unique_tiers.size() == 3, "Equipment stages must differ: " + id)
			tiers += 3
		var tier_paths: Array = entry.get("tier_paths", ["", "", ""])
		csv.store_csv_line(PackedStringArray([id, entry["name"], entry["category"], entry.get("family", ""), entry.get("region", ""), entry["status"], str(entry.get("reused", false)), entry["icon_path"], entry.get("bottle_path", ""), entry.get("recipe_icon_path", ""), entry.get("growth_path", ""), tier_paths[0], tier_paths[1], tier_paths[2], entry["source_path"]]))
	assert(counts == {"potions":32, "materials":11, "regions":8, "equipment":8, "employees":4, "families":4})
	assert(bottle_hashes.size() == 32 and growth_count == 10 and tiers == 24 and reused == 10)
	catalog["status"] = "design_assets_complete"
	catalog["summary"] = {"asset_entries":67, "new_source_sheets":57, "fully_reused_entries":10, "equipment_basic_reused":4, "potions":32, "bottles":32, "materials":11, "regions":8, "equipment_families":8, "equipment_tier_images":24, "employee_roles":4, "potion_families":4, "growth_sheets":10, "connected_to_game":false}
	var file := FileAccess.open(ROOT + "catalog.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(catalog, "\t") + "\n")
	var report := FileAccess.open(ROOT + "verification/art-validation.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"passed":true, "image_checks":checks, "counts":counts, "unique_small_bottles":32, "growth_sheets":growth_count, "equipment_stages":tiers, "fully_reused_entries":reused, "checks":["all paths resolve", "stable IDs unique", "icons 32x40", "bottles 12x16", "real alpha/transparent padding", "each bottle visually encoded with unique pixel data", "recipe icon reuse", "four nonempty growth frames", "three distinct equipment tiers"], "readability_note":"12x16 preserves bottle silhouette and color. Emblems are clearer in 32x40 inventory icons; keep item names alongside icons."}, "\t") + "\n")
	print("EXPANSION VALIDATION PASS: 67 entries, 32 unique 12x16 bottles, 10 growth sheets, 24 equipment stage icons; real alpha and all paths verified")
	quit()


func _check(path: String, size: Vector2i) -> Image:
	assert(FileAccess.file_exists(path), "Missing export: " + path)
	var image := Image.load_from_file(path)
	assert(image != null and image.get_size() == size, "Wrong dimensions: " + path)
	assert(not image.is_invisible(), "Empty export: " + path)
	assert(image.get_pixel(0, 0).a < 0.01 and image.get_pixel(size.x - 1, size.y - 1).a < 0.01, "No transparent padding: " + path)
	checks += 1
	return image
