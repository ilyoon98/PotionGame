extends SceneTree
## Isolated presentation review. Never reads or writes a player save.
const UiPixel = preload("res://scripts/ui_pixel_catalog.gd")
const PixelIcon = preload("res://scripts/pixel_icon.gd")
const ItemArt = preload("res://scripts/item_art.gd")
const ManagementArt = preload("res://scripts/management_art.gd")
const Currency = preload("res://scripts/currency_text.gd")
const State = preload("res://scripts/shop_state.gd")
const Centered = preload("res://scripts/centered_button_content.gd")
const Content = preload("res://scripts/shop_content.gd")
const Shop = preload("res://scripts/shop.gd")
const M = preload("res://tests/contracts_fixture.gd")
const Compare = preload("res://tests/state_compare.gd")
const OUT := "res://.verification/ui-pixel-v2/"
var checks := 0
var failures: Array[String] = []
var captures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	set_meta("isolated_preview", true)
	call_deferred("run")

func verify_assets() -> void:
	check(not UiPixel.DATA.is_empty(), "Published UI catalog exists")
	var palette := {}
	for line in FileAccess.get_file_as_string("res://art/palette.hex").split("\n"):
		var value := line.strip_edges().trim_prefix("#").to_lower()
		if value.length() == 6: palette[value] = true
	var paths := {}
	for id in UiPixel.DATA.get("icons", {}):
		var texture := UiPixel.icon(id)
		check(texture != null, "Catalog icon resolves: " + id)
		if texture != null: paths[texture.resource_path] = texture
	for track in UiPixel.DATA.get("equipment", {}):
		for tier in 3:
			var texture := UiPixel.equipment(track, tier)
			check(texture != null, "Equipment resolves: %s tier %d" % [track, tier])
			if texture != null: paths[texture.resource_path] = texture
	for path in paths:
		var texture: Texture2D = paths[path]
		var image := texture.get_image()
		var colors := {}
		var outside := 0
		var partial := 0
		for y in image.get_height():
			for x in image.get_width():
				var pixel := image.get_pixel(x, y)
				if pixel.a8 == 0: continue
				var color := pixel.to_html(false)
				colors[color] = true
				if not palette.has(color): outside += 1
				if pixel.a8 != 255: partial += 1
		check(texture.get_size() in [Vector2(32, 32), Vector2(16, 16)], "Native UI grid: " + path)
		check(outside == 0 and partial == 0 and colors.size() <= 5 and colors.size() >= 2, "Palette, opaque pixels and 2–5 colors: " + path)
	for category in ["regions", "materials", "employees", "potions"]:
		for row in Content.DATA[category]:
			var texture := ItemArt.icon(row.id)
			check(texture == UiPixel.icon(row.id), "Runtime uses published %s icon: %s" % [category, row.id])
	for id in Content.RECIPES:
		check(ItemArt.recipe_icon(id) == UiPixel.icon("recipe:" + id), "Recipe art routes through catalog: " + id)
	check(ItemArt.icon("mushroom") == ItemArt.icon("moon_mushroom"), "Legacy mushroom alias shares the new material")
	check(ItemArt.unknown_recipe_icon() == UiPixel.icon("unknown_recipe"), "Undiscovered recipes use the new placeholder")
	check(ManagementArt.small_icon("reputation").get_size() == Vector2(16, 16), "Small fame badge is native 16px")
	check(Currency.COIN == UiPixel.icon("coin_small") and Currency.COIN.get_size() == Vector2(16, 16), "Inline prices and purchase buttons use the native small coin")
	check(UiPixel.icon("not_registered") == null and UiPixel.equipment("not_registered", 0) == null, "Unknown catalog IDs safely fall back")

func check_icon(node: TextureRect, context: String) -> void:
	check(node is PixelIcon, context + " uses pixel-aware drawing")
	if not node is PixelIcon or node.texture == null: return
	var rect: Rect2 = node.drawn_rect()
	var scale := rect.size / node.texture.get_size()
	check(is_equal_approx(scale.x, scale.y) and scale.x >= 1.0 and is_equal_approx(scale.x, roundf(scale.x)), context + " keeps an integer, uniform pixel scale")
	check(Rect2(Vector2.ZERO, node.size).encloses(rect), context + " fits its slot")

func settle() -> void:
	for frame in 4: await process_frame

func verify_texture_changes() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(80, 80)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var icon := PixelIcon.new()
	icon.position = Vector2(8, 8)
	icon.size = Vector2(48, 48)
	viewport.add_child(icon)
	var native := UiPixel.icon("herb")
	var small := UiPixel.icon("coin_small")
	var legacy: Texture2D = load("res://assets/management_v1/reputation_icon.png")
	for sample in [[native, TextureRect.STRETCH_KEEP_CENTERED, Vector2(48, 48)], [small, TextureRect.STRETCH_KEEP_ASPECT_CENTERED, Vector2(48, 48)], [legacy, TextureRect.STRETCH_KEEP_ASPECT_CENTERED, Vector2(48, 48)], [native, TextureRect.STRETCH_KEEP_CENTERED, Vector2(48, 48)], [small, TextureRect.STRETCH_KEEP_ASPECT_CENTERED, Vector2(48, 48)], [native, TextureRect.STRETCH_KEEP_CENTERED, Vector2(49, 51)], [small, TextureRect.STRETCH_KEEP_CENTERED, Vector2(49, 51)]]:
		icon.size = sample[2]
		icon.texture = sample[0]
		await settle()
		check(icon.stretch_mode == sample[1], "Texture replacement selects its actual drawing mode after frames settle")
		if DisplayServer.get_name() == "headless" or sample[0] == legacy or sample[0] == null: continue
		await RenderingServer.frame_post_draw
		var rendered := viewport.get_texture().get_image()
		var source := icon.texture.get_image()
		var rect: Rect2 = icon.drawn_rect()
		var scale := int(rect.size.x / source.get_width())
		var origin := Vector2i(icon.position + rect.position)
		var mismatches := 0
		for y in rendered.get_height():
			for x in rendered.get_width():
				var local := Vector2i(x, y) - origin
				var expected := Color.TRANSPARENT
				if local.x >= 0 and local.y >= 0 and local.x < rect.size.x and local.y < rect.size.y:
					expected = source.get_pixel(local.x / scale, local.y / scale)
				var actual := rendered.get_pixel(x, y)
				if abs(actual.a8 - expected.a8) > 1 or (expected.a8 > 0 and (abs(actual.r8 - expected.r8) > 1 or abs(actual.g8 - expected.g8) > 1 or abs(actual.b8 - expected.b8) > 1)): mismatches += 1
		check(mismatches == 0, "GPU pixels equal the source at the integer scale after texture replacement (%d mismatches)" % mismatches)
		check_icon(icon, "Texture replacement fixture")
	viewport.queue_free()
	await process_frame

func capture(panel: Window, name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var path := OUT + name + ".png"
	check(panel.get_texture().get_image().save_png(path) == OK, "Captured " + name)
	captures.append(path)

func verify_locked_badges(shop: Control, panel: Window) -> void:
	var completed: RefCounted = shop.state
	shop.state = State.new()
	shop.state.gold = 1000000
	var inspected := 0
	for page in [panel.EXPEDITIONS, panel.UPGRADES, panel.OPERATION]:
		panel.select_page(page)
		panel.refresh()
		panel.scroll.scroll_vertical = 0
		await settle()
		for row: Dictionary in panel.rows.values():
			if row.page != page: continue
			var button: Button = row.button
			if not button.visible or not button.text.contains("명성") or button.icon == null: continue
			inspected += 1
			check(button.icon == UiPixel.icon("reputation_small"), "Reputation-locked button uses the small badge")
			check(button.get_theme_constant("icon_max_width") == 16 and Centered.rects(button).icon.size == Vector2(16, 16), "Reputation-locked button draws at exactly 16px, including wrapping expedition CTAs")
		if page == panel.EXPEDITIONS: await capture(panel, "reputation-locked")
	check(inspected > 0, "Inspected actual reputation-locked buttons")
	shop.state = completed
	panel.refresh()
	await settle()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	verify_assets()
	await verify_texture_changes()
	var shop := Shop.new()
	root.add_child(shop)
	shop.set_process(false)
	shop.state = M.completed()
	M.complete_post_growth(shop.state)
	shop.open_management()
	var panel = shop.management
	panel.set_process(false)
	root.always_on_top = false
	panel.always_on_top = false
	await settle()
	check_icon(panel.gold_icon, "Header coin")
	check_icon(panel.reputation_icon, "Header reputation")
	await verify_locked_badges(shop, panel)
	var before := M.data(shop.state)
	for entry in [[panel.EXPEDITIONS, "expeditions"], [panel.HERBS, "herbs"], [panel.POTIONS, "potions"], [panel.RECIPES, "recipes"], [panel.UPGRADES, "upgrades"]]:
		panel.select_page(entry[0])
		panel.refresh()
		panel.scroll.scroll_vertical = 0
		await settle()
		for id in panel.rows:
			var row: Dictionary = panel.rows[id]
			if row.page != entry[0]: continue
			check_icon(row.icon, "Row " + id)
			if row.has("primary_icon") and row.primary_icon.texture != null: check_icon(row.primary_icon, "Region material " + id)
			if row.has("growth_preview") and row.growth_preview.texture != null:
				row.toggle.button_pressed = true
				await settle()
				check_icon(row.growth_preview, "Growth preview " + id)
		await capture(panel, entry[1] + "-top")
		panel.scroll.scroll_vertical = int(panel.scroll.get_v_scroll_bar().max_value)
		await settle()
		await capture(panel, entry[1] + "-bottom")
	panel.select_page(panel.REPORT)
	panel.refresh()
	await settle()
	for id in panel.regular_cards:
		check_icon(panel.regular_cards[id].portrait, "Preserved character " + id)
		check(panel.regular_cards[id].portrait.texture.get_size() == Vector2(32, 48), "Character native frame unchanged: " + id)
	check(Compare.equivalent(before, M.data(shop.state)), "Browsing changed no gameplay state, inventory or save data")
	M.write_json(OUT + "proof.json", {"checks": checks, "failures": failures, "passed": failures.is_empty(), "captures": captures})
	print("UI PIXEL V2 %s: %d checks, %d captures" % ["PASS" if failures.is_empty() else "FAIL", checks, captures.size()])
	panel.free()
	shop.free()
	quit(0 if failures.is_empty() else 1)
