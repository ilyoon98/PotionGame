extends SceneTree
const Shop = preload("res://scripts/shop.gd")
const Compare = preload("res://tests/state_compare.gd")
var shop: Control

func _initialize() -> void:
	set_meta("isolated_preview", true)
	call_deferred("_run")

func capture(name: String) -> Image:
	shop.art._process(0)
	shop.companion.refresh()
	shop.companion.scene.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("res://.verification/main-pixel-light/" + name + ".png")
	return image

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://.verification/main-pixel-light")
	shop = Shop.new()
	root.add_child(shop)
	shop.set_process(false)
	shop.art.set_process(false)
	shop.companion.set_process(false)
	shop.art.sky.set_process(false)
	shop.art.workshop_weather.set_process(false)
	shop.state.stock = 8
	shop.state.mana_stock = 3
	shop.state.gold = 12345
	shop._update_interface()
	shop.art.motion.visit = shop.art.Motion.Visit.WAITING
	shop.art.motion.customer_x = shop.art.Motion.COUNTER_X
	shop.art.motion.elapsed = 1.0
	for mode in [shop.State.WindowMode.WORKSHOP, shop.State.WindowMode.FULL, shop.State.WindowMode.SMALL]:
		shop._set_window_mode(mode)
		assert(not shop.art.hearth_rect().intersects(shop.art.rug_rect()), "Flame hearth and keeper rug must have separate footprints")
		var images := []
		for entry in [{"id": "day-clear", "clock": 0.0}, {"id": "night-clear", "clock": 80.0}, {"id": "day-rain", "clock": 240.0}, {"id": "night-rain", "clock": 190.0}]:
			shop.state.progression.clock = entry.clock
			var before: Dictionary = shop.state.to_data().duplicate(true)
			var picture := await capture("mode-%d-%s" % [mode, entry.id])
			images.append(picture)
			assert(Compare.equivalent(before, shop.state.to_data()), "Rendering must not mutate economy, reservations, journey timers or RNG")
			var values: Dictionary = shop.art.lighting_values.duplicate(true)
			shop._show_companion_view()
			shop.companion.refresh()
			for key in ["ambient", "local_gain", "flicker"]:
				assert(shop.companion.light.get_shader_parameter(key) == values[key], "Modes must share lighting and flame clock")
			shop._restore_compact_view()
			assert(shop.state.window_mode == (shop.State.WindowMode.FULL if mode == shop.State.WindowMode.SMALL else mode))
			if mode == shop.State.WindowMode.SMALL: shop._set_window_mode(mode)
			assert(Compare.equivalent(before, shop.state.to_data()))
		var origin: Vector2i = Vector2i(shop.art.position)
		var pot: Rect2 = shop.art.pot_rect()
		var source: Image = shop.art.cauldron.get_image()
		var emitter_count := 0
		for y in 48:
			for x in 48:
				var raw := source.get_pixel(x, y)
				var flame := y > 36 and raw.r > 0.588 and raw.g > 0.196 and raw.b < 0.471
				var liquid := y < 26 and raw.r > 0.510 and raw.b > 0.255 and raw.r > raw.g * 1.4
				if raw.a < 0.99 or not (flame or liquid): continue
				var point := origin + Vector2i(pot.position) + Vector2i(x * 2, y * 2)
				var day: Color = images[0].get_pixelv(point)
				var night: Color = images[3].get_pixelv(point)
				assert(day.r > raw.r * 0.95 and night.r > raw.r * 0.95, "Flame and potion must remain emissive across environments")
				emitter_count += 1
		assert(emitter_count > 25)
		assert(images[0].get_data() != images[3].get_data(), "Environment must visibly change")
	shop._set_window_mode(shop.State.WindowMode.WORKSHOP)
	var transparent := await capture("transparent")
	assert(transparent.get_pixel(438, 238).a < 0.01, "Gap beyond the new counter must stay transparent")
	shop._show_companion_view()
	await capture("companion-shared")
	print("MAIN PIXEL LIGHT PASS: workshop/full/small, pot-relative shader coordinates, separate stone hearth/rug, emissive flame/liquid, shared environment/flicker, transparent margins, unchanged economy across mode switches")
	quit()

