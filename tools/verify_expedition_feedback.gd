extends SceneTree
const Shop = preload("res://scripts/shop.gd")
const Trips = preload("res://scripts/parallel_expeditions.gd")
const Compare = preload("res://tests/state_compare.gd")

func _initialize() -> void:
	set_meta("isolated_preview", true)
	call_deferred("run")

func run() -> void:
	var shop := Shop.new()
	root.add_child(shop)
	shop._set_window_mode(shop.State.WindowMode.WORKSHOP)
	shop.state.gold = 100000
	var p = shop.state.progression
	p.reputation = 10000
	assert(shop.state.purchase("expedition"))
	p.expedition_count = 10
	assert(shop.state.purchase("region:abandoned_greenhouse"))
	p.expansion.cycles["forest_edge"]["elapsed"] = 35.0
	p.expansion.cycles["abandoned_greenhouse"]["elapsed"] = 60.0
	var before: Dictionary = shop.state.to_data()
	shop.workshop_gauges.detail_buttons.expeditions.pressed.emit()
	assert(shop.management.visible and shop.management.selected == shop.management.EXPEDITIONS)
	assert(Compare.equivalent(before, shop.state.to_data()), "Poster details only navigate, never charge")
	var panel = shop.management
	panel.refresh()
	await process_frame
	await process_frame
	assert(is_equal_approx(panel.rows["forest_edge"]["bar"].value, 50))
	assert(is_equal_approx(panel.rows["abandoned_greenhouse"]["bar"].value, 40))
	assert(not panel.rows.has("journey"), "Parallel legs must not be averaged into one gauge")
	for region in shop.State.Content.DATA["regions"]:
		var row: Dictionary = panel.rows[region["id"]]
		assert(row.summary.source_text.contains("주재료") and row.summary.source_text.contains("매회") and not row.summary.source_text.contains("원정 열기"))
		assert(row.summary.coin_count == 1 and not row.detail.visible)
		assert(row["bar"].size.y == 7)
		assert(Rect2(Vector2.ZERO, row["bar"].get_parent().size).encloses(row["bar"].get_rect()))
	panel.scroll.scroll_vertical = 220
	panel.refresh()
	assert(panel.scroll.scroll_vertical == 220, "Updates preserve region position")
	panel.hide()
	shop._update_interface()
	assert(shop.workshop_gauges.active_regions == 2 and shop.workshop_gauges.active_regions == Trips.active_count(p))
	assert(shop.workshop_gauges.region_summary == "2곳 탐사 중")
	p.expansion.cycles["abandoned_greenhouse"]["elapsed"] = 149.0
	shop._advance_game(1.0)
	assert(p.expansion.region_returns("abandoned_greenhouse", p) == 1 and shop.state.material_count("silver_moss") == 2)
	assert(shop.art.reward_icons["herb"] != null and shop.art.reward_icons["gold"] != null)
	if DisplayServer.get_name() != "headless":
		shop.workshop_gauges.detail_buttons.expeditions.pressed.emit()
		await process_frame
		await RenderingServer.frame_post_draw
		panel.get_texture().get_image().save_png("res://.verification/parallel-expedition-management.png")
		panel.hide()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.verification/parallel-expedition-poster.png")
	print("EXPEDITION UI PASS: poster details navigate without paying, actual active count, per-region progress/fees/rewards/opening prices, scroll preserved, no averaged gauge, return reward and icons")
	quit()
