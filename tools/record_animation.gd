extends SceneTree
## Render a deterministic eight-second preview without accessing player saves.

const Art = preload("res://scripts/shop_art.gd")
const State = preload("res://scripts/shop_state.gd")


func _initialize() -> void:
	call_deferred("_record")


func _record() -> void:
	Engine.max_fps = 30
	root.size = Vector2i(408, 248)
	root.content_scale_size = Vector2i(408, 248)
	root.always_on_top = false
	var art := Art.new()
	art.size = Vector2(408, 248)
	root.add_child(art)
	art.set_process(false)
	var state := State.new()
	state.stock = 6
	art.bottles.restore(state.stock, state.mana_stock)
	DirAccess.make_dir_recursive_absolute("res://.verification/motion-frames")
	for index in range(80):
		var events := state.advance(0.1)
		art.apply_potion_events(events, state.stock, state.mana_stock)
		if events["harvested"] > 0:
			art.on_harvest(events["harvested"])
		art.brewing = state.is_brewing()
		art.active_mana = state.active_mana
		art.mana_stock = state.mana_stock
		art.garden_progress = state.harvest_elapsed / state.harvest_duration()
		art.herb_storage_full = state.herbs >= state.herb_capacity()
		art.stock = state.stock
		art.customer_phase = state.customer_elapsed / state.customer_interval()
		art._process(0.1)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.verification/motion-frames/frame-%03d.png" % index)
	assert(state.total_sold == 2 and state.gold == 12)
	print("RECORD PASS: 80 frames; two real sales drive two handovers")
	quit()
