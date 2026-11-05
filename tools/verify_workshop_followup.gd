extends SceneTree
const Shop = preload("res://scripts/shop.gd")
const State = preload("res://scripts/shop_state.gd")
const Content = preload("res://scripts/shop_content.gd")
const Status = preload("res://scripts/management_status.gd")
const Art = preload("res://scripts/item_art.gd")
const Gauges = preload("res://scripts/workshop_gauges.gd")
const Compare = preload("res://tests/state_compare.gd")
var shop: Control
var panel: Window
func _initialize() -> void:
	set_meta("isolated_preview", true)
	call_deferred("run")
func layout() -> void:
	panel.refresh()
	await process_frame
	await process_frame
func stock(amount: int) -> void:
	shop.state.stock = amount
	shop.state.mana_stock = 0
	shop.state.inventory.clear()
	for i in amount: shop.state.inventory.append(false)
func verify_fixed_rows() -> void:
	for page in [panel.HERBS, panel.POTIONS]:
		panel.select_page(page)
		await layout()
		var sizes := {}
		for row in panel.rows.values():
			if row.page != page: continue
			assert(row.panel.size.y <= panel.ROW_LIMIT, "Keep one readable condition with larger icons and type")
			assert(not row.summary.visible and row.detail.visible and row.work.box.visible and row.stock.box.visible)
			assert(row.detail.get_content_width() <= row.detail.size.x, row.title.text + " condition must not be cut")
			sizes[row.order] = [row.panel.size.y, row.panel.position.y]
		for phase in ["full", "poor", "ready"]:
			stock(shop.state.capacity() if phase == "full" else 0)
			shop.state.herbs = shop.state.herb_capacity() if phase == "full" else 0 if phase == "poor" else 5
			shop.state.gold = 0 if phase == "poor" else 1000000
			shop.state.brew_active = false
			await layout()
			for row in panel.rows.values():
				if row.page != page: continue
				assert([row.panel.size.y, row.panel.position.y] == sizes[row.order])
				assert(row.detail.get_content_width() <= row.detail.size.x)
func run() -> void:
	assert(DisplayServer.get_name() == "headless")
	shop = Shop.new()
	root.add_child(shop)
	shop.set_process(false)
	shop.state.gold = 1000000
	shop.state.progression.reputation = 10000
	shop.open_management()
	panel = shop.management
	panel.set_process(false)
	await verify_fixed_rows()
	# Real signals open lifetime statistics without resetting the existing period.
	shop.state = State.new()
	shop.state.gold = 100000
	shop.state.progression.reputation = 10000
	assert(shop.state.purchase("expedition"))
	shop.state.advance(230)
	var baseline: Dictionary = shop.state.to_data().duplicate(true)
	panel.result_button.pressed.emit()
	assert(panel.selected == panel.REPORT and panel.result_button.text == "통계")
	var report := Status.lifetime_summary(shop.state)
	assert(panel.statistics_values.net.source_text == ("+" if report.net > 0 else "−" if report.net < 0 else "") + shop._number(absi(report.net)) + " G")
	assert(panel.statistics_values.play_time.source_text == report.time)
	assert(panel.statistics_values.expeditions.source_text == "%s회" % shop._number(report.expeditions))
	assert(panel.pages[panel.REPORT].find_children("*", "Button", true, false).is_empty())
	for i in 5:
		panel.select_page(panel.OPERATION)
		panel.result_button.pressed.emit()
	assert(Compare.equivalent(baseline, shop.state.to_data()))
	assert(panel.heading.get_rect().end.x < panel.result_button.position.x)
	# All eleven sheets use exact 32x40 regions and a separate species path.
	var growth_count := 0
	for source in Content.DATA.materials:
		if source.id in ["moon_mushroom"]:
			assert(Art.growth_path(source.id).is_empty())
			continue
		growth_count += 1
		for phase in [0.0, 0.4, 0.8]:
			var texture: AtlasTexture = Art.growth_frame(source.id, phase)
			assert(texture.atlas.resource_path == Art.growth_path(source.id) and texture.region.size == Vector2(32, 40))
			assert(Rect2(Vector2.ZERO, texture.atlas.get_size()).encloses(texture.region))
	assert(growth_count == 11)
	# Representatives stay fixed while every real source keeps running independently.
	var p: RefCounted = shop.state.progression
	p.owned = ["vigor", "moon", "focus"]
	p.expansion.grant_recipe("vigor")
	p.expansion.grant_recipe("focus")
	p.expansion.materials["blue_reed"] = 2
	p.expansion.regions = ["forest_edge", "abandoned_greenhouse", "mist_valley"]
	p.expansion.parallel_version = 1
	State.Progression.Expeditions.ensure(p)
	shop._set_window_mode(State.WindowMode.WORKSHOP)
	var overlay: Control = shop.workshop_gauges
	overlay.refresh()
	assert(overlay.visible and overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	assert(overlay.herb_ids == ["herb"] and overlay.region_ids == ["forest_edge"])
	assert(overlay.active_herbs == Status.activity_counts(shop.state).herbs and overlay.active_regions == Status.activity_counts(shop.state).regions)
	assert(not overlay.herb_ids.has("moon_mushroom") and not overlay.herb_ids.has("blue_reed"))
	var order := [overlay.herb_ids.duplicate(), overlay.region_ids.duplicate()]
	shop.state.herbs = 3
	p.expansion.materials.dewgrass = 1
	p.rare_herbs = 1
	p.expansion.growth.dewgrass = 5.0
	p.rare_growth = 8.0
	overlay.refresh()
	var before: Dictionary = shop.state.to_data().duplicate(true)
	for phase in [0.0, 0.2, 0.6]:
		p.tick_elapsed = phase
		overlay.refresh()
		assert([overlay.herb_ids, overlay.region_ids] == order)
	p.tick_elapsed = before.progression.tick_elapsed
	for i in 5: overlay.refresh()
	assert(Compare.equivalent(before, shop.state.to_data()))
	for i in overlay.herbs.size():
		var data := Status.material(shop.state, overlay.herb_ids[i])
		assert(is_equal_approx(overlay.herbs[i].get("display_progress", overlay.herbs[i].progress), data.get("display_progress", data.progress)))
	for i in overlay.trips.size(): assert(is_equal_approx(overlay.trips[i].display_progress, Status.region(shop.state, overlay.region_ids[i]).display_progress))
	shop.state.brew_active = false
	overlay.refresh()
	assert(not overlay.craft.running and overlay.craft.progress == 0)
	# The longest summary must fit the existing world label without clipping.
	for caption in ["10종 재배 중 · 보관", "재배 대기 · 보관"]:
		assert(shop.body_font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x <= Gauges.HERB_SUMMARY.size.x)
	for caption in ["8곳 탐사 중", "원정 대기"]:
		assert(shop.body_font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x <= Gauges.TRIPS[0].size.x)
	# Manifest, alpha bounds, actual transfers and scaled native rectangles are checked
	# independently by verify_wide_workshop.gd and verify_wide_workshop_motion.gd.
	assert(shop.desktop_input.art_height == 248 and shop.desktop_input.layout_size == shop.WorkshopAssets.SIZE and shop.desktop_input.process.is_empty())
	for mode in [State.WindowMode.COMPANION, State.WindowMode.MINIMAL, State.WindowMode.WORKSHOP]:
		shop._set_window_mode(mode)
		overlay.refresh()
		assert(overlay.visible == (mode == State.WindowMode.WORKSHOP))
		assert([overlay.herb_ids, overlay.region_ids] == order)
	print("WORKSHOP FOLLOWUP PASS: compact fixed rows/visible conditions, header statistics/read-only signals, ten species growth sheets, fixed herb/forest representatives and real activity counts, no inventory-only growth or mushroom farming, virtual bounds/click-through/modes; actual desktop interaction not tested")
	quit()
