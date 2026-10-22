extends SceneTree
const Art = preload("res://scripts/shop_art.gd")
var art: Control


func _initialize() -> void:
	call_deferred("_run")


func capture(name: String) -> Image:
	art.queue_redraw()
	art.sky.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("res://.verification/" + name + ".png")
	return image


func _run() -> void:
	Engine.max_fps = 30
	root.size = Vector2i(408, 248)
	root.content_scale_size = Vector2i(408, 248)
	root.always_on_top = false
	root.transparent_bg = true
	art = Art.new()
	art.size = Vector2(408, 248)
	root.add_child(art)
	art.set_process(false)
	art.sky.set_process(false)
	art.stock = 8
	art.mana_stock = 3
	art.garden_progress = 0.75
	DirAccess.make_dir_recursive_absolute("res://.verification")
	art.sky.preview_phase = 0.5
	art.sky.preview_weather = 0
	var day := await capture("room-day")
	art.sky.preview_phase = 0.0
	var night := await capture("room-night")
	assert(day.get_pixel(30, 50) != night.get_pixel(30, 50), "Window sky must visibly change between day and night")
	assert(day.get_pixel(30, 50).a > 0.99 and night.get_pixel(30, 50).a > 0.99, "Outdoor layer must fill the window instead of revealing the desktop")
	art.sky.preview_phase = 0.5
	art.sky.preview_weather = 2
	var rain_a := await capture("room-rain")
	art.sky.elapsed = 0.2
	var rain_b := await capture("room-rain-motion")
	var moving_window_pixels := 0
	var moving_room_pixels := 0
	for y in range(248):
		for x in range(408):
			if rain_a.get_pixel(x, y) != rain_b.get_pixel(x, y):
				if Rect2i(16, 36, 104, 80).has_point(Vector2i(x, y)):
					moving_window_pixels += 1
				else:
					moving_room_pixels += 1
	assert(moving_window_pixels > 30, "Rain must animate visibly")
	assert(moving_room_pixels == 0, "Weather must remain behind the opaque interior")
	print("ENVIRONMENT PASS: day/night visible; window filled; ", moving_window_pixels, " moving sky pixels; no weather leaks into the room")
	if "--record-weather" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute("res://.verification/weather-frames")
		art.sky.preview_phase = -1.0
		art.sky.preview_weather = -1
		for index in range(96):
			art.sky.elapsed = index * 240.0 / 96.0
			art._process(0.1)
			await capture("weather-frames/frame-%03d" % index)
		print("WEATHER PREVIEW: 96 accelerated frames of one four-minute game day")
	quit()
