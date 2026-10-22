extends SceneTree
const ShopSky = preload("res://scripts/shop_sky.gd")
var sky: Control

func _initialize() -> void:
	call_deferred("_run")

func capture() -> Image:
	sky.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _run() -> void:
	root.size = Vector2i(408, 248)
	root.content_scale_size = root.size
	root.transparent_bg = true
	root.always_on_top = false
	sky = ShopSky.new()
	sky.transparent_scene = true
	root.add_child(sky)
	sky.set_process(false)
	sky.preview_weather = 0
	sky.preview_phase = 0.25
	var baseline := await capture()
	var pane := Rect2(ShopSky.WORKSHOP_WINDOW.position + ShopSky.TIME_PANE.position, ShopSky.TIME_PANE.size)
	var centers: Array[Vector2] = []
	for value in [0.35, 0.5, 0.65, 0.85, 0.0, 0.15]:
		sky.preview_phase = value
		var picture := await capture()
		var changed := 0
		for y in range(picture.get_height()):
			for x in range(picture.get_width()):
				if picture.get_pixel(x, y) == baseline.get_pixel(x, y): continue
				assert(pane.has_point(Vector2(x, y)), "Sun/moon pixels must never escape the left opening")
				changed += 1
		assert(changed > 20, "Sun or moon must be visible during its journey")
		if value in [0.35, 0.5, 0.65]: centers.append(sky.celestial_rect(false).get_center())
		if value == 0.5: picture.save_png("res://.verification/window-orbit-noon.png")
		if value == 0.0: picture.save_png("res://.verification/window-orbit-midnight.png")
	assert(centers[0].x < centers[1].x and centers[1].x < centers[2].x)
	assert(centers[1].y < centers[0].y and centers[1].y < centers[2].y)
	print("WINDOW ORBIT PASS: sun and moon follow time; rising/setting edges clip; zero pixels outside time pane")
	quit()
