extends SceneTree
const Art = preload("res://scripts/shop_art.gd")
const State = preload("res://scripts/shop_state.gd")
var art: Control


func _initialize() -> void:
	call_deferred("_run")


func capture(name: String) -> Image:
	art._process(0)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	picture.save_png("res://.verification/" + name + ".png")
	return picture


func _run() -> void:
	root.size = Vector2i(408, 248)
	root.content_scale_size = Vector2i(408, 248)
	root.transparent_bg = true
	root.always_on_top = false
	art = Art.new()
	root.add_child(art)
	art.set_process(false)
	art.size = Vector2(408, 248)
	var state := State.new()
	art.world = state.progression
	art.workshop = true
	state.stock = 8
	state.mana_stock = 3
	state.herbs = 30
	state.progression.customer = 4
	state.progression.customer_selected = true
	art.sync_inventory(state.stock, state.mana_stock, state.inventory_order())
	assert(art.keeper_frames[0].atlas.resource_path.contains("characters/animations_v1/keeper"))
	assert(art.customer_sheets.size() == 4 and not art.customer_sheets.has("knight"))
	for id in art.customer_sheets:
		var folder := "animations_v1" if id == "traveler" else "customer_redesign_v4"
		var poses := ["idle", "walk_1", "walk_2", "purchase_complete"]
		for index in range(4):
			var texture: AtlasTexture = art.customer_sheets[id][index]
			assert(texture.atlas.resource_path.contains("/%s/" % folder))
			assert(texture.get_size() == Vector2(48, 64))
			if id == "traveler": continue
			var source_texture: Texture2D = load("res://assets/characters/%s/%s_%s_48x64.png" % [folder, id, poses[index]])
			var source := source_texture.get_image()
			var actual := texture.get_image()
			for y in range(64):
				for x in range(48):
					var expected_pixel := source.get_pixel(x, y)
					var actual_pixel := actual.get_pixel(x, y)
					assert(is_equal_approx(actual_pixel.a, expected_pixel.a))
					# Import may fill RGB in transparent edge pixels to prevent fringes.
					if expected_pixel.a > 0.0:
						assert(actual_pixel.is_equal_approx(expected_pixel), "Loaded frame must match supplied pose: %s %s" % [id, poses[index]])
	# Exercise both walking poses and the mirrored exit through the real renderer.
	for customer in [2, 3, 4]:
		state.progression.customer = customer
		var id: String = art.Content.CUSTOMERS[customer]["id"]
		art.motion.visit = art.Motion.Visit.ARRIVING
		art.motion.customer_x = art.Motion.COUNTER_X
		art.motion.departing_elapsed = -1.0
		art.motion.elapsed = 0.0
		assert(art.motion.visitor_frame() == 1)
		var walk_a := await capture("customer-v4-%s-walk-1" % id)
		art.motion.elapsed = 1.0 / 6.0 + 0.001
		assert(art.motion.visitor_frame() == 2)
		var walk_b := await capture("customer-v4-%s-walk-2" % id)
		assert(walk_a.get_region(Rect2i(302, 117, 96, 128)).get_data() != walk_b.get_region(Rect2i(302, 117, 96, 128)).get_data())
		art.motion.visit = art.Motion.Visit.ABSENT
		art.departing_customer = id
		art.motion.departing_elapsed = art.Motion.HANDOVER_SECONDS + 0.1
		await capture("customer-v4-%s-exit" % id)
	art.motion.close_shop()
	var baseline: Dictionary = state.to_data().duplicate(true)
	for case in [{"name": "day-clear", "clock": 0.0}, {"name": "night-clear", "clock": 80.0}, {"name": "day-rain", "clock": 240.0}, {"name": "night-rain", "clock": 190.0}]:
		state.progression.clock = case.clock
		art.motion.visit = art.Motion.Visit.WAITING
		art.motion.customer_x = art.Motion.COUNTER_X
		var picture := await capture("assets-" + case.name)
		assert(picture.get_pixel(20, 150).a < 0.01)
		assert(art.workshop_weather.elapsed == state.progression.clock)
	# Disabling visual effects must clear only the weather, without touching rules.
	state.progression.effects = 0
	var off := await capture("assets-effects-off")
	# The wooden frame stays visible; only weather inside its open panes clears.
	for y in range(25, 80):
		for x in range(34, 90):
			assert(off.get_pixel(x, y).a < 0.01)
	assert(state.gold == baseline.gold and state.stock == baseline.stock)
	state.progression.effects = 0.8
	state.progression.clock = 190
	# Also verify the unchanged full-room outdoor animation.
	art.workshop = false
	var first := await capture("assets-rain-frame-0")
	state.progression.clock += 0.125
	var second := await capture("assets-rain-frame-1")
	assert(first.get_data() != second.get_data(), "The supplied rain sheet must animate")
	art.workshop = true
	DirAccess.make_dir_recursive_absolute("res://.verification/assets-frames")
	for frame in range(64):
		var events: Dictionary = state.advance(0.125)
		art.apply_potion_events(events, state.stock, state.mana_stock, state.inventory_order())
		art.brewing = state.is_brewing()
		art.active_mana = state.active_mana
		art.customer_phase = state.customer_elapsed / state.customer_interval()
		art._process(0.125)
		assert(art.bottles.inventory_order() == state.inventory_order())
		await capture("assets-frames/frame-%03d" % frame)
	assert(state.total_sold >= 2)
	print("ASSETS PASS: v4 mage/elf/rogue poses match supplied art; traveler retained; walking and mirrored exit render; four environments; purchase/brew/exit sequence preserves inventory")
	quit()
