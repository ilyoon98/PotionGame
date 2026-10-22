extends SceneTree
const Shop = preload("res://scripts/shop.gd")
const Art = preload("res://scripts/management_art.gd")
const Compare = preload("res://tests/state_compare.gd")
const Palette = preload("res://scripts/management_palette.gd")
func _initialize() -> void:
	set_meta("isolated_preview", true)
	call_deferred("run")
func run() -> void:
	assert(DisplayServer.get_name() == "headless")
	var icon: AtlasTexture = Art.icon("reputation")
	assert(icon == Art.icon("reputation") and icon.atlas != null and icon.filter_clip)
	var pixels: Image = icon.get_image()
	assert(pixels.get_size() == Vector2i(1181, 1179) and pixels.detect_alpha() != Image.ALPHA_NONE)
	var shop := Shop.new()
	root.add_child(shop)
	shop.set_process(false)
	shop.open_management()
	var panel: Window = shop.management
	panel.set_process(false)
	shop.state.progression.reputation = 0
	shop.state.gold = 1000000
	var before: Dictionary = shop.state.to_data().duplicate(true)
	panel.select_page(panel.EXPEDITIONS)
	await process_frame
	await process_frame
	assert(panel.reputation_icon.texture == icon and panel.reputation_icon.size == Vector2(24, 24) and panel.gold_icon.size == Vector2(24, 24))
	assert(panel.reputation_icon.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST)
	assert(is_equal_approx(panel.gold_icon.get_global_rect().get_center().y, panel.reputation_icon.get_global_rect().get_center().y))
	assert(panel.gold_label.get_global_rect().end.x < panel.reputation_icon.get_global_rect().position.x)
	assert(panel.reputation_icon.get_global_rect().end.x < panel.reputation_label.get_global_rect().position.x)
	assert(panel.reputation_caption.text == "명성" and panel.gold_caption.text == "골드" and panel.reputation_label.text == "0")
	assert(panel.reputation_caption.get_theme_font_size("font_size") == 14 and panel.reputation_label.get_theme_font_size("font_size") == 18)
	var row: Dictionary = panel.rows.forest_edge
	assert(not row.reputation_marker.visible and row.button.icon == icon and row.button.text == "명성 10 필요")
	assert(row.reputation_marker.texture == icon and row.reputation_marker.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST)
	assert(row.panel.get_global_rect().encloses(row.button.get_global_rect()), "Required fame remains in the visible purchase button")
	var height: float = row.panel.size.y
	assert(Compare.equivalent(before, shop.state.to_data()), "Displaying the new icon never changes economy")
	shop.state.progression.reputation = 10000
	panel.refresh()
	await process_frame
	await process_frame
	assert(row.button.icon == panel.CurrencyText.COIN and row.button.text == "400 · 원정 열기" and is_equal_approx(height, row.panel.size.y))
	# CPU-only nearest sampling of the shared Atlas at actual 20/24/32px.
	# This is an asset preview, not a GPU screen capture or native UI interaction.
	var preview := Image.create(240, 128, false, Image.FORMAT_RGBA8)
	for band in 2:
		var bg := Palette.BG if band == 0 else Palette.TEXT
		preview.fill_rect(Rect2i(0, band * 64, 240, 64), bg)
		var slot := 0
		for dimension in [20, 24, 32]:
			var occupied := 0
			for y in dimension:
				for x in dimension:
					var sx := mini(pixels.get_width() - 1, int((x + 0.5) * pixels.get_width() / dimension))
					var sy := mini(pixels.get_height() - 1, int((y + 0.5) * pixels.get_height() / dimension))
					var color := pixels.get_pixel(sx, sy)
					if color.a > 0.5: occupied += 1
					preview.set_pixel(20 + slot * 80 + x, band * 64 + 16 + y, bg.blend(color))
			assert(occupied > dimension * dimension / 4 and occupied < dimension * dimension * 0.8)
			slot += 1
	DirAccess.make_dir_recursive_absolute("res://.verification/reputation")
	assert(preview.save_png("res://.verification/reputation/icon-preview.png") == OK)
	print("REPUTATION ICON PASS: shared transparent Atlas, 20/24/32 nearest CPU preview on light/dark, aligned gold/fame header, exact condition text and fixed row height, unchanged economy; headless only")
	quit()
