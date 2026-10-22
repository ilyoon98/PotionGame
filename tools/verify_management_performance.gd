extends SceneTree
## Isolated profiling: never reads or writes the player's save or login setting.
const Shop = preload("res://scripts/shop.gd")
const Management = preload("res://scripts/management_panel.gd")
const Compare = preload("res://tests/state_compare.gd")
const Content = preload("res://scripts/shop_content.gd")
const FOLDER := "res://.verification/management-performance/"

func _initialize() -> void:
	set_meta("isolated_preview", true)
	call_deferred("run")

func run() -> void:
	var shop := Shop.new()
	root.add_child(shop)
	shop.set_process(false)
	shop.state.gold = 1000000
	shop.state.progression.reputation = 10000
	for id in Content.RECIPES:
		if not shop.state.progression.owned.has(id): shop.state.progression.owned.append(id)
		if not Content.LEGACY_RECIPES.has(id): shop.state.progression.expansion.grant_recipe(id)
	shop._advance_game(1.7)
	var before: Dictionary = shop.state.to_data().duplicate(true)
	var panel := Management.new()
	panel.host = shop
	panel.visible = false
	shop.add_child(panel)
	panel.show()
	panel.set_process(false)
	await process_frame
	await process_frame
	panel.refresh()
	await process_frame
	await process_frame
	# An unchanged presentation must not invalidate all button styles again.
	var changes := {"count": 0, "rows": []}
	var watched := {}
	for row: Dictionary in panel.rows.values():
		var styles: Array = [row.style]
		if row.has("button"):
			styles.append_array(row.button.get_meta(Management.CenteredButtonContent.STYLE_META, {}).values())
		for style: StyleBox in styles:
			if watched.has(style.get_instance_id()): continue
			watched[style.get_instance_id()] = true
			var row_id := str(row.panel.get_meta("row_id"))
			style.changed.connect(func():
				changes.count += 1
				changes.rows.append(row_id))
	panel.refresh()
	panel.refresh()
	if changes.count > 0: print("UNEXPECTED STYLE CHANGES: ", changes.rows)
	assert(changes.count == 0, "Stable refreshes must not emit theme changes")
	var stable_theme_changes: int = changes.count
	# The real periodic path must leave hidden tabs alone.
	panel.rows.potion_health.extra.set_value("hidden tab sentinel")
	panel.refresh_elapsed = 0.2
	panel._process(1.0 / 30.0)
	assert(panel.rows.potion_health.extra.source_text == "hidden tab sentinel", "Periodic refresh must not touch hidden potion rows")
	panel.select_page(Management.POTIONS)
	assert(panel.rows.potion_health.extra.source_text != "hidden tab sentinel", "Selecting a page immediately refreshes its content")
	panel.snap_gauges = true
	panel.refresh_gauges(1.0 / 30.0)
	panel.snap_gauges = false
	for kind in [false, true] + Content.RECIPES.keys():
		var data := Management.Status.potion(shop.state, kind)
		var row: Dictionary = panel.rows["potion_" + Management.Status.kind_id(kind)]
		assert(is_equal_approx(row.work.bar.value, data.work.get("progress", 0.0) * 100.0))
		assert(is_equal_approx(row.stock.bar.value, data.inventory * 100.0), "Fast gauges must agree with the complete read-only projection")
	panel.open_contracts()
	panel.rows.potion_health.extra.set_value("contracts sentinel")
	panel.refresh(true)
	panel.refresh_gauges(1.0 / 30.0)
	assert(panel.rows.potion_health.extra.source_text == "contracts sentinel", "Contract polling must not refresh underlying tabs")
	panel.close_contracts()
	var measurements := []
	for page in 7:
		panel.select_page(page)
		for row: Dictionary in panel.rows.values():
			if row.page == page: row.extra.set_value("visible scope sentinel")
		panel.refresh(true)
		var scoped := {}
		for id in panel.rows:
			var row: Dictionary = panel.rows[id]
			if row.page == page and (page not in [panel.POTIONS, panel.RECIPES] or panel._row_on_screen(row)):
				scoped[id] = row.extra.source_text
		panel.refresh()
		for id in scoped:
			assert(scoped[id] == panel.rows[id].extra.source_text, "Scoped refresh must update every visible row like the complete refresh")
		await process_frame
		await process_frame
		var refresh_us := 0
		var gauge_us := 0
		var frame_us: Array[int] = []
		for sample in 12:
			var frame_started := Time.get_ticks_usec()
			var started := Time.get_ticks_usec()
			panel.refresh("--full-refresh" not in OS.get_cmdline_user_args())
			refresh_us += Time.get_ticks_usec() - started
			started = Time.get_ticks_usec()
			panel.refresh_gauges(1.0 / 30.0)
			gauge_us += Time.get_ticks_usec() - started
			await process_frame
			frame_us.append(Time.get_ticks_usec() - frame_started)
		frame_us.sort()
		var measurement := {"page": page, "refresh_ms": refresh_us / 12000.0, "gauges_ms": gauge_us / 12000.0, "frame_median_ms": frame_us[6] / 1000.0, "nodes": get_node_count()}
		measurements.append(measurement)
		print(JSON.stringify(measurement))
	assert(Compare.equivalent(before, shop.state.to_data()), "Management profiling must preserve every simulation field")
	DirAccess.make_dir_recursive_absolute(FOLDER)
	var label := "full-refresh" if "--full-refresh" in OS.get_cmdline_user_args() else "after"
	var file := FileAccess.open(FOLDER + label + "-" + DisplayServer.get_name() + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"measurements": measurements, "player_save_accessed": false, "state_preserved": true, "stable_theme_changes": stable_theme_changes, "hidden_tabs_skipped": true, "fast_gauges_match_projection": true}, "\t"))
	shop.queue_free()
	await process_frame
	print("MANAGEMENT PERFORMANCE PASS: state preserved")
	quit()
