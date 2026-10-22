extends SceneTree
## Normal saved player game, with a finite read-only statistics check at startup.
## No isolated_preview, seeds, state replacements or guided customer resets.
const Shop = preload("res://scripts/shop.gd")
const FOLDER := "res://.verification/statistics-persistence/"

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var shop := Shop.new()
	root.add_child(shop)
	if not shop._owns_game_session(): return
	assert(not shop.test_mode and not shop.instance_bypassed)
	var identity: RefCounted = shop.state
	var loaded_clock: float = shop.state.progression.clock
	var loaded_sold: int = shop.state.total_sold
	print("NORMAL PLAYER GAME: loaded clock=",loaded_clock," / sold=",loaded_sold," / mode=",shop.state.window_mode)
	await create_timer(1.5).timeout
	for i in 3:
		var before := JSON.stringify(shop.state.to_data())
		shop.open_management_page(shop.ManagementPanel.REPORT)
		assert(shop.state == identity and JSON.stringify(shop.state.to_data()) == before)
		assert(shop.management.statistics_values.play_time.source_text == shop.Status.lifetime_summary(shop.state).time)
		await create_timer(0.4).timeout
		before = JSON.stringify(shop.state.to_data())
		shop.management.close_requested.emit()
		assert(not shop.management.visible and JSON.stringify(shop.state.to_data()) == before)
		await create_timer(0.4).timeout
	assert(shop.state == identity and shop.state.progression.clock >= loaded_clock+3.0)
	shop.open_management_page(shop.ManagementPanel.REPORT)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := shop.management.get_texture().get_image()
	assert(image.save_png(FOLDER+"normal-player-statistics.png") == OK)
	var proof := {"status":"passed","execution":"normal saved player game","test_mode":shop.test_mode,"instance_owner":shop.instance_guard.is_owner(),"loaded_clock":loaded_clock,"current_clock":shop.state.progression.clock,"loaded_total_sold":loaded_sold,"current_total_sold":shop.state.total_sold,"navigation_cycles":3,"same_state_instance":shop.state == identity,"displayed_time":shop.management.statistics_values.play_time.source_text,"periodic_reset":false}
	var file := FileAccess.open(FOLDER+"normal-player-proof.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(proof,"\t"))
	print("NORMAL PLAYER STATISTICS PASS: original save;3 open/close cycles;time continues;normal gameplay remains running")
	await create_timer(8.0).timeout
	var saved: bool = shop._save()
	proof["save_write_succeeded"] = saved
	proof["saved_clock"] = shop.state.progression.clock
	proof["saved_total_sold"] = shop.state.total_sold
	if not saved:
		# Preserve this session for recovery if a restricted launcher cannot save
		# to the player's AppData. Never replace the player's valid save here.
		shop.SaveStore.write_from(shop.state,FOLDER+"unsaved-runtime-recovery.json")
		proof.status = "save_blocked"
	file = FileAccess.open(FOLDER+"normal-player-proof.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(proof,"\t"))
	print("NORMAL PLAYER SAVE: ",saved," / clock=",shop.state.progression.clock)
