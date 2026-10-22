extends SceneTree
const Shop = preload("res://scripts/shop.gd")
const Compare = preload("res://tests/state_compare.gd")
const Motion = preload("res://scripts/shop_motion.gd")


func _initialize() -> void:
	assert(DisplayServer.get_name() == "headless")
	set_meta("isolated_preview", true)
	call_deferred("_run")


func _run() -> void:
	var shop := Shop.new()
	root.add_child(shop)
	shop.state.gold = 25458
	shop.state.advance(2.0)
	for mode in [shop.State.WindowMode.WORKSHOP, shop.State.WindowMode.FULL]:
		shop._set_window_mode(mode)
		var before: Dictionary = shop.state.to_data().duplicate(true)
		shop._show_companion_view()
		assert(shop.state.window_mode == shop.State.WindowMode.COMPANION and root.size == Vector2i(256, 172))
		assert(shop.companion.visible and not shop.art.visible and not shop.minimal_hud.visible)
		assert(shop.desktop_input.layout_size == Vector2i(256, 172) and shop.desktop_input.art_height == 128)
		assert(shop.companion.toolbar.size == Vector2(256, 44), "Companion adds vertical breathing room without widening or stretching the artwork")
		for button in [shop.companion.move_button, shop.companion.manage_button, shop.companion.minimize_button, shop.companion.restore_button, shop.companion.close_button]:
			assert(button.position.y == 6 and button.size.y == 32)
		assert(not shop.desktop_input.enabled, "Isolated verification must never modify desktop input routing")
		assert(shop.companion.gold.text == "25,458")
		shop.companion.restore_button.pressed.emit()
		assert(shop.state.window_mode == mode and Compare.equivalent(before, shop.state.to_data()))
	shop._set_window_mode(shop.State.WindowMode.WORKSHOP)
	shop.workshop_minimize.pressed.emit()
	assert(shop.state.window_mode == shop.State.WindowMode.COMPANION)
	shop.companion.manage_button.pressed.emit()
	assert(shop.management.visible)
	shop.management.find_child("InformationOnlyButton", true, false).pressed.emit()
	assert(shop.state.window_mode == shop.State.WindowMode.MINIMAL and not shop.management.visible)
	shop._restore_compact_view()
	assert(shop.state.window_mode == shop.State.WindowMode.COMPANION)
	shop._restore_compact_view()
	assert(shop.state.window_mode == shop.State.WindowMode.WORKSHOP)
	shop._show_companion_view()
	var saved := shop.state.to_data()
	var restored := shop.State.new()
	assert(restored.load_data(JSON.parse_string(JSON.stringify(saved))) and restored.window_mode == shop.State.WindowMode.COMPANION)
	# Migration uses only this isolated fixture, never an earlier player snapshot.
	var old_snapshot: Dictionary = saved.duplicate(true)
	old_snapshot.version = 6
	assert(restored.load_data(old_snapshot) and restored.gold == int(old_snapshot["gold"]))
	shop._advance_game(1.25)
	shop.companion.refresh()
	assert(is_equal_approx(shop.companion.gauge.value, shop.Status.crafting(shop.state).progress * 100.0))
	shop._advance_game(1.0)
	shop.companion.refresh()
	assert(shop.state.is_brewing() and shop.companion.gauge.value > 0.0)
	var motion := Motion.new()
	motion.tick(0.01, true, 0.0, 1.5)
	for cycle in 3:
		for frame in 90: motion.tick(1.0 / 60.0, true, float(frame) / 90.0, 1.5)
		assert(motion.visit == Motion.Visit.WAITING, "Even the fastest counter allows walking to finish before sale")
		motion.sale(6)
	if "--render" in OS.get_cmdline_user_args():
		await render_cases(shop)
	print("COMPANION PASS: B 256x172/44px footer/32px controls, real progress/gold, management and information view, previous-mode restore, v6 migration, unchanged 128px picture routing, fast-counter motion; isolated headless only, no OS input injection")
	quit()


func render_cases(shop: Control) -> void:
	DirAccess.make_dir_recursive_absolute("res://.verification/companion")
	for case in [{"id": "day-clear", "clock": 0.0}, {"id": "night-clear", "clock": 80.0}, {"id": "day-cloud", "clock": 100.0}, {"id": "day-rain", "clock": 240.0}, {"id": "night-rain", "clock": 190.0}]:
		shop.state.progression.clock = case["clock"]
		shop.companion.refresh()
		shop.companion.scene.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		assert(picture.get_size() == Vector2i(256, 172))
		assert(picture.get_pixel(250, 60).a < 0.01 and picture.get_pixel(120, 15).a < 0.01, "Unlit margins remain transparent")
		assert(shop.companion.gauge.size.y == 3, "Pixel gauge must not inherit the theme font minimum height")
		assert(picture.get_pixel(240, 115).a < 0.01, "No oversized gauge may cover the transparent margin")
		assert(picture.get_pixel(20, 140).a > 0.99, "Toolbar stays opaque and operable")
		picture.save_png("res://.verification/companion/" + case["id"] + ".png")
	for page in range(5):
		shop.open_management()
		shop.management.select_page(page)
		await process_frame
		await RenderingServer.frame_post_draw
		shop.management.get_texture().get_image().save_png("res://.verification/companion/management-%d.png" % page)
