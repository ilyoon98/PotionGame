extends SceneTree
## Advancing synthetic gameplay: no player save, desktop integration or login I/O.
const Shop = preload("res://scripts/shop.gd")
const Fixture = preload("res://tests/contracts_fixture.gd")
const Compare = preload("res://tests/state_compare.gd")
const FOLDER := "res://.verification/management-animation/"

func _initialize() -> void:
	set_meta("isolated_preview", true)
	call_deferred("run")

func run() -> void:
	var shop := Shop.new()
	root.add_child(shop)
	shop.set_process(false)
	shop.state = Fixture.completed()
	Fixture.clear_materials(shop.state)
	shop.state.herbs = 12
	shop.state.mushrooms = 3
	shop._advance_game(0.2)
	var control := Fixture.completed()
	Fixture.clear_materials(control)
	control.herbs = 12
	control.mushrooms = 3
	control.advance(0.2)
	assert(Compare.equivalent(control.to_data(), shop.state.to_data()))
	shop.open_management()
	var panel: Window = shop.management
	panel.set_process(false)
	var chip_events := {"count": 0}
	for row: Dictionary in panel.rows.values():
		if row.has("blend"):
			row.blend.child_entered_tree.connect(func(_node): chip_events.count += 1)
	var results := []
	for page in [panel.OPERATION, panel.POTIONS, panel.RECIPES, panel.HERBS, panel.EXPEDITIONS]:
		panel.select_page(page)
		await process_frame
		await process_frame
		var work: Array[float] = []
		var frames: Array[float] = []
		var previous_frame := Time.get_ticks_usec()
		var chips_before: int = chip_events.count
		for index in 90:
			var started := Time.get_ticks_usec()
			shop._advance_game(1.0 / 30.0)
			control.advance(1.0 / 30.0)
			shop._update_interface()
			panel._process(1.0 / 30.0)
			work.append((Time.get_ticks_usec() - started) / 1000.0)
			await process_frame
			var current := Time.get_ticks_usec()
			frames.append((current - previous_frame) / 1000.0)
			previous_frame = current
		assert(Compare.equivalent(control.to_data(), shop.state.to_data()), "UI animation must preserve all simulation, economy and RNG fields")
		work.sort()
		frames.sort()
		var result := {"page": page, "cpu_median_ms": work[45], "cpu_p95_ms": work[85], "cpu_max_ms": work[89], "frame_median_ms": frames[45], "frame_p95_ms": frames[85], "frame_max_ms": frames[89], "new_ingredient_chips": chip_events.count - chips_before}
		if "--after" in OS.get_cmdline_user_args():
			assert(result.new_ingredient_chips == 0, "Advancing stock must not rebuild recipe Controls")
		results.append(result)
		print(JSON.stringify(result))
	# Timer labels and progress must change between the 0.2-second list polls.
	shop.state = Shop.State.new()
	shop.state.advance(0.23)
	panel.select_page(panel.OPERATION)
	panel.refresh_elapsed = 0.0
	panel.scroll_refresh_pending = false
	var initial_count: String = panel.rows.craft.work.count.text
	var previous_progress: float = panel.rows.craft.work.bar.value
	for index in 4:
		shop.state.advance(0.03)
		var before: Dictionary = shop.state.to_data().duplicate(true)
		panel._process(0.03)
		assert(Compare.equivalent(before, shop.state.to_data()), "Subsecond presentation must never advance the simulation")
		assert(panel.rows.craft.work.bar.value > previous_progress, "Progress must advance on each intervening frame")
		previous_progress = panel.rows.craft.work.bar.value
	assert(panel.refresh_elapsed < 0.2 and panel.rows.craft.work.count.text != initial_count, "Remaining time must update without waiting for a list poll")
	panel.select_page(panel.POTIONS)
	await process_frame
	await process_frame
	var last_kind: String = Shop.ManagementPanel.Content.RECIPES.keys()[-1]
	var last: Dictionary = panel.rows["potion_" + last_kind]
	assert(not panel._row_on_screen(last))
	last.extra.set_value("offscreen sentinel")
	panel.refresh(true)
	assert(last.extra.source_text == "offscreen sentinel", "Scrolled-out rows must stay untouched")
	panel.refresh_elapsed = 0.0
	panel.scroll_refresh_pending = false
	panel.scroll.ensure_control_visible(last.panel)
	await process_frame
	panel._process(0.01)
	assert(panel._row_on_screen(last) and last.extra.source_text != "offscreen sentinel", "Scrolling must refresh newly exposed content on the next frame")
	DirAccess.make_dir_recursive_absolute(FOLDER)
	var label := "after" if "--after" in OS.get_cmdline_user_args() else "before"
	var output := FileAccess.open(FOLDER + label + "-" + DisplayServer.get_name() + ".json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"results": results, "state_preserved": true, "player_save_accessed": false, "subsecond_timers": true, "scroll_refresh": true}, "\t"))
	shop.queue_free()
	await process_frame
	print("MANAGEMENT ANIMATION PASS: advancing gameplay matches control")
	quit()
