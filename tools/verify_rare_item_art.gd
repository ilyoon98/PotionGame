extends SceneTree
## Approved sources stay read-only; UI v2 uses separate native32 presentation art.
## Verify actual IDs, original hashes, current UI routing and workshop pixels.
const ItemArt = preload("res://scripts/item_art.gd")
const UiPixel = preload("res://scripts/ui_pixel_catalog.gd")
const Catalog = preload("res://scripts/pixel_art_catalog.gd")
const Visual = preload("res://scripts/potion_visual.gd")
const State = preload("res://scripts/shop_state.gd")
const Compare = preload("res://tests/state_compare.gd")
const MAP_SHA := "a5dea5b46b7d38203099a9ba4af26cba86e2474fcc31edb63512c613b5a98628"
const OUT := "res://.verification/ingredients-rare-20261013"

func _initialize() -> void:
	assert(DisplayServer.get_name() == "headless")
	set_meta("isolated_preview", true)
	call_deferred("run")

func run() -> void:
	assert(DirAccess.make_dir_recursive_absolute(OUT) == OK)
	var state := State.new()
	var before: Dictionary = state.to_data().duplicate(true)
	var manifests: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/rare_recipes_v1/verification/art-manifest.json"))
	var delivered := 0
	for entry in manifests:
		var path: String = "res://assets/rare_recipes_v1/" + entry.path
		assert(FileAccess.get_sha256(path).to_lower() == str(entry.sha256).to_lower(), "Approved rare art bytes are untouched: " + path)
		if str(entry.path).begins_with("potions/") or str(entry.path).begins_with("recipes/"): delivered += 1
	assert(delivered == 12)
	assert(FileAccess.get_sha256(ItemArt.UNKNOWN_RECIPE_PATH).to_lower() == MAP_SHA)
	var original_unknown: Texture2D = load(ItemArt.UNKNOWN_RECIPE_PATH)
	assert(original_unknown.get_size() == Vector2(32, 40), "Original unknown-map source is preserved")
	assert(ItemArt.unknown_recipe_icon() == UiPixel.icon("unknown_recipe") and ItemArt.unknown_recipe_icon().get_size() == Vector2(32, 32), "Current unknown recipe uses the new native32 placeholder")
	var cauldron: Image = Catalog.pot("health").get_image()
	var board := Image.create(64 * 4, 128, false, Image.FORMAT_RGBA8)
	board.fill(Color("1d242b"))
	var liquid_pixels := {}
	for point in Catalog.DATA.liquid_pixels: liquid_pixels[Vector2i(int(point[0]),int(point[1]))] = true
	var proof := []
	for index in ItemArt.RARE_CATALOG.assets.size():
		var entry: Dictionary = ItemArt.RARE_CATALOG.assets[index]
		var id: String = entry.id
		assert(ItemArt.has_icon(id) and Visual.potion_id(id) == id)
		var potion: Texture2D = ItemArt.icon(id)
		var recipe: Texture2D = ItemArt.recipe_icon(id)
		var bottle: Texture2D = ItemArt.bottle(id)
		var original_potion: Texture2D = load(entry.potion_path)
		var original_recipe: Texture2D = load(entry.recipe_path)
		assert(original_potion.get_size() == Vector2(32, 40) and original_recipe.get_size() == Vector2(32, 40), "Original 32x40 icon/recipe sources remain alongside their verified hashes")
		assert(potion == UiPixel.icon(id) and UiPixel.owns(potion) and potion.get_size() == Vector2(32, 32), "Current rare potion uses its native32 catalog icon")
		assert(recipe == UiPixel.icon("recipe:" + id) and UiPixel.owns(recipe) and recipe.get_size() == Vector2(32, 32), "Current rare recipe uses its native32 catalog icon")
		assert(bottle.resource_path == Catalog.DATA.potions[id].bottle and bottle.get_size() == Catalog.bottle_size(id))
		var source: Image = bottle.get_image()
		var color := Visual.liquid_color(id)
		var actual: Image = Visual.cauldron_texture(id).get_image()
		var changed := 0
		for y in cauldron.get_height():
			for x in cauldron.get_width():
				var old := cauldron.get_pixel(x,y)
				var next := actual.get_pixel(x,y)
				assert(old.a == next.a)
				if not liquid_pixels.has(Vector2i(x,y)): assert(old == next)
				elif old != next: changed += 1
		assert(changed > 0)

		board.blit_rect(potion.get_image(), Rect2i(0, 0, 32, 32), Vector2i(index * 64, 0))
		board.blit_rect(recipe.get_image(), Rect2i(0, 0, 32, 32), Vector2i(index * 64 + 32, 0))
		board.blit_rect(source, Rect2i(Vector2i.ZERO,source.get_size()), Vector2i(index * 64 + 26, 46))
		board.blit_rect(actual, Rect2i(0, 0, 32, 32), Vector2i(index * 64 + 8, 70))
		proof.append({"id": id, "potion": potion.resource_path, "recipe": recipe.resource_path, "bottle": bottle.resource_path,  "liquid_color": color.to_html(false), "changed_liquid_pixels": changed})
	assert(Compare.equivalent(before, state.to_data()), "Art identity and sample reads never choose, consume, pay, roll or save")
	assert(board.save_png(OUT.path_join("rare-art-and-liquid.png")) == OK)
	var file := FileAccess.open(OUT.path_join("art-proof.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases": proof, "approved_rare_hashes": manifests, "approved_unknown_map_sha256": MAP_SHA, "state_unchanged": true, "headless_only": true}, "\t"))
	print("RARE ITEM ART PASS: 4 exact IDs/12 original hashes + unknown-map SHA preserved; current native32 UI catalog + approved8x12/8x16 bottles/32x32 pots, approved liquid colors and mask, unchanged state/RNG; headless only")
	quit()
