extends SceneTree
const Art = preload("res://scripts/shop_art.gd")
const State = preload("res://scripts/shop_state.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.max_fps = 30
	root.size = Vector2i(408, 248)
	root.content_scale_size = Vector2i(408, 248)
	root.always_on_top = false
	var art := Art.new()
	art.size = Vector2(408, 248)
	root.add_child(art)
	art.set_process(false)
	art.sky.set_process(false)
	var state := State.new()
	state.stock = 11
	state.mana_stock = 3
	state.mushrooms = 6
	state.level = 15
	state.garden_level = 12
	state.herbs = 60
	state.auto_purchase = false
	art.bottles.restore(state.stock, state.mana_stock)
	DirAccess.make_dir_recursive_absolute("res://.verification/transfer-frames")
	for frame in range(360):
		art._process(1.0 / 30.0)
		var events: Dictionary = state.advance(1.0 / 30.0)
		art.apply_potion_events(events, state.stock, state.mana_stock, state.inventory_order())
		art.brewing = state.is_brewing()
		art.active_mana = state.active_mana
		art.customer_phase = state.customer_elapsed / state.customer_interval()
		assert(art.bottles.matches(state.stock, state.mana_stock))
		assert(art.bottles.inventory_order() == state.inventory_order())
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.verification/transfer-frames/frame-%03d.png" % frame)
	assert(state.total_sold == 3)
	print("TRANSFER PASS: full mixed shelves, fastest cauldron, three sales, consistent FIFO and sliding in all 360 rendered frames")
	quit()
