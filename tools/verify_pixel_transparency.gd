extends SceneTree
## Capture actual desktop modes with no review backing and no player save access.
const Shop = preload("res://scripts/shop.gd")
const State = preload("res://scripts/shop_state.gd")
const FOLDER := "res://.verification/pixel-runtime-v1/"

func _initialize() -> void:
	set_meta("isolated_preview", true)
	call_deferred("run")

func freeze(node: Node) -> void:
	node.set_process(false)
	for child in node.get_children(): freeze(child)

func run() -> void:
	assert(DisplayServer.get_name() != "headless", "Actual alpha capture needs a rendering driver")
	var shop := Shop.new()
	root.add_child(shop)
	assert(shop.test_mode and shop.instance_bypassed)
	freeze(shop)
	root.always_on_top = false
	var report := {"status":"running", "player_save_accessed":false, "cases":[]}
	for mode in [State.WindowMode.WORKSHOP, State.WindowMode.COMPANION]:
		shop._set_window_mode(mode)
		shop._update_interface()
		shop.art._process(0)
		shop.art.queue_redraw()
		shop.companion.refresh()
		shop.companion.scene.queue_redraw()
		assert(root.transparent and root.transparent_bg)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var workshop: bool = mode == State.WindowMode.WORKSHOP
		var name := "workshop" if workshop else "companion"
		var expected := Vector2i(540,300) if workshop else shop.MiniWorkshop.SIZE
		assert(image.get_size() == expected)
		for point in [Vector2i(0,0), Vector2i(200,20), Vector2i(expected.x-1,100)]:
			assert(image.get_pixelv(point).a == 0.0, name+": empty space must have alpha 0 at "+str(point))
		var floor_y := 238 if workshop else shop.MiniWorkshop.FLOOR_Y
		for x in expected.x:
			assert(image.get_pixel(x,floor_y).a == 1.0, name+": floor must remain visible across the map")
		var transparent_pixels := 0
		for y in expected.y:
			for x in expected.x:
				if image.get_pixel(x,y).a == 0.0: transparent_pixels += 1
		assert(transparent_pixels > expected.x*expected.y/3)
		assert(image.save_png(FOLDER+name+"-transparent.png") == OK)
		report.cases.append({"mode":name,"size":[expected.x,expected.y],"transparent_pixels":transparent_pixels,"empty_space_alpha":0,"full_width_floor_alpha":1})
	report.status = "passed"
	var file := FileAccess.open(FOLDER+"transparency-proof.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("PIXEL TRANSPARENCY PASS: actual workshop/companion alpha 0; full-width floor alpha 1")
	shop.queue_free()
	await process_frame
	quit()
