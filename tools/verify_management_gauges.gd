extends SceneTree
## Headless only: no desktop input, native window show, focus or window movement.
const Shop = preload("res://scripts/shop.gd")
const State = preload("res://scripts/shop_state.gd")
const Management = preload("res://scripts/management_panel.gd")
const Status = preload("res://scripts/management_status.gd")
const Content = preload("res://scripts/shop_content.gd")
const Trips = preload("res://scripts/parallel_expeditions.gd")
const Compare = preload("res://tests/state_compare.gd")
const Palette = preload("res://scripts/management_palette.gd")
var shop: Control
var panel: Window

func _initialize() -> void:
	set_meta("isolated_preview", true)
	call_deferred("run")

func run() -> void:
	assert(DisplayServer.get_name() == "headless", "This test must never open a user-visible window")
	shop = Shop.new()
	root.add_child(shop)
	shop.set_process(false)
	shop.state.gold = 1000000
	var p: RefCounted = shop.state.progression
	p.reputation = 10000
	for id in Content.RECIPES:
		p.owned.append(id)
		if not Content.LEGACY_RECIPES.has(id): p.expansion.grant_recipe(id)
	for region in Content.DATA.regions: p.expansion.regions.append(region.id)
	p.expedition_unlocked = true
	Trips.tick(shop.state, 0.0)
	shop.state.advance(1.7)
	shop.state.stock = 3
	shop.state.mana_stock = 1
	shop.state.inventory = [false, true, "moon"]
	var baseline: Dictionary = shop.state.to_data().duplicate(true)
	panel = Management.new()
	panel.host = shop
	panel.visible = false
	shop.add_child(panel)
	panel.visible = true # Virtual headless viewport only; required for container layout.
	panel.set_process(false)
	await process_frame
	await process_frame
	assert(Compare.equivalent(baseline, shop.state.to_data()), "Building management is read-only")
	assert(panel.tabs.size() == 7 and panel.pages.size() == 8 and panel.tabs[Management.UPGRADES].text == "가구·직원")
	assert(panel.tabs[Management.POTIONS].text == "포션" and panel.tabs[Management.RECIPES].text == "레시피")
	assert(panel.gold_icon.texture != null and panel.gold_icon.get_global_rect().end.x < panel.gold_caption.get_global_rect().position.x and panel.gold_caption.get_global_rect().end.x < panel.gold_label.get_global_rect().position.x)
	assert(panel.gold_label.text.begins_with(shop._number(shop.state.gold)))
	assert(panel.rows.moon.button.get_theme_stylebox("normal").bg_color == Palette.ACTION)
	assert(panel.recommend_button.get_theme_color("font_color") == Palette.ACTION_TEXT)
	assert(not panel.rows.has("flow") and not panel.rows.has("bottleneck"))
	assert(panel.rows.craft.work.box.visible and is_equal_approx(panel.rows.craft.bar.value, shop.state.brew_elapsed / shop.state.brew_duration() * 100))
	assert(panel.rows.sale.panel.visible and is_equal_approx(panel.rows.sale.bar.value, shop.state.customer_elapsed / shop.state.customer_interval() * 100))
	assert(panel.rows.potion_moon.stock.count.text == "1/12")
	assert(panel.rows.potion_health.stock.count.text == "1/12" and panel.rows.potion_mana.stock.count.text == "1/12")
	assert(panel.potion_heading.text == "포션 · 총 보유 3/12")
	var work_values := []
	for material in Content.DATA.materials:
		var data := Status.material(shop.state, material.id)
		var row: Dictionary = panel.rows[panel.material_row(material.id)]
		assert(row.page == Management.HERBS and row.stock.bar.value == data.inventory * 100)
		assert(row.work.box.visible and row.detail.visible)
		if data.running:
			assert(is_equal_approx(row.work.bar.value, data.get("display_progress", data.progress) * 100))
			work_values.append(row.work.bar.value)
	for region in Content.DATA.regions:
		var data := Status.region(shop.state, region.id)
		var operation: Dictionary = panel.rows["trip_" + region.id]
		var detail: Dictionary = panel.rows[region.id]
		assert(operation.panel.visible == panel.operation_regions.has(region.id) and is_equal_approx(operation.bar.value, detail.bar.value))
		assert(is_equal_approx(operation.bar.value, Status.region(shop.state, region.id).display_progress * 100))
		work_values.append(operation.bar.value)
	assert(work_values.max() != work_values.min(), "Independent actual clocks must differ")
	for kind in [false, true] + Content.RECIPES.keys():
		var row: Dictionary = panel.rows["potion_" + Status.kind_id(kind)]
		var data := Status.potion(shop.state, kind)
		assert(row.page == Management.POTIONS and row.panel.visible == data.available and row.detail.visible)
		if data.active: assert(row.detail.text.begins_with("제작 중"))
		assert(row.work.box.visible, "Every potion retains its manufacturing slot")
		if not data.active: assert(row.work.bar.value == 0 and row.work.count.text == "대기")
		assert(is_equal_approx(row.stock.bar.value, data.inventory * 100))
	# Environment highlights correspond to real effects, not visual settings.
	p.clock = 190.0
	p.effects = 0.0
	panel.refresh()
	assert(panel.rows.rare_inventory.highlighted)
	assert(not panel.rows.potion_health.highlighted)
	assert(panel.rows.potion_moon.highlighted)
	p.customer_selected = false
	panel.refresh()
	assert(panel.rows.sale.panel.visible and panel.rows.sale.work.box.visible and panel.rows.sale.bar.value == 0, "No customer retains a fixed sale row with no fabricated progress")
	assert(panel.rows.sale.detail.text == "손님 기다리는 중")
	assert(await verify_sale_height())
	# A waiting supply does not have a moving work bar.
	shop.state.gold = 0
	panel.refresh()
	assert(panel.rows.material_moon_mushroom.work.box.visible and panel.rows.material_moon_mushroom.work.count.text == "대기" and panel.rows.material_moon_mushroom.detail.source_text.contains(" G 부족") and panel.rows.material_moon_mushroom.detail.coin_count == 1)
	shop.state.herbs = shop.state.herb_capacity()
	panel.refresh()
	assert(panel.rows.herb_inventory.work.box.visible and panel.rows.herb_inventory.work.count.text == "대기" and panel.rows.herb_inventory.stock.bar.value == 100)
	assert(await verify_craft_height())
	# Buy the pressed upgrade even if the displayed recommendation changes.
	shop.state.gold = 1000000
	shop.state.herbs = 3
	shop.state.stock = 0
	shop.state.mana_stock = 0
	shop.state.inventory.clear()
	panel.refresh()
	assert(panel.rows.potion_moon.panel.visible and panel.rows.potion_moon.stock.count.text == "0/12", "Learned potions remain in their tab even when sold out")
	var old_target: String = panel.recommendation.target
	var old_track: String = panel.recommendation.track
	panel.recommend_button.button_down.emit()
	shop.state.stock = shop.state.capacity()
	shop.state.inventory = []
	for i in shop.state.stock: shop.state.inventory.append(false)
	panel.refresh()
	assert(panel.recommendation.target != old_target)
	var expected := State.new()
	assert(expected.load_data(shop.state.to_data().duplicate(true)))
	assert(expected.purchase("upgrade:" + old_track))
	panel.recommend_button.pressed.emit()
	await process_frame
	await process_frame
	assert(panel.selected == Management.OPERATION and panel.recommend_button.text.contains("강화"))
	assert(Compare.equivalent(expected.to_data(), shop.state.to_data()), "Exactly one purchase of the pressed track, with all batch/inventory/journey changes matching the core")
	# Funds can disappear while held: the latest purchase conditions must reject it.
	panel.recommend_button.button_down.emit()
	shop.state.gold = 0
	panel.refresh()
	var rejected: Dictionary = shop.state.to_data().duplicate(true)
	panel.recommend_button.pressed.emit()
	assert(Compare.equivalent(rejected, shop.state.to_data()), "Insufficient funds cannot charge or upgrade")
	shop.state.gold = 1000000
	panel.select_page(Management.UPGRADES)
	# Open details and preserve scroll/details/order through timer/environment refresh.
	panel.rows.cauldron.toggle.button_pressed = true
	panel.scroll.scroll_vertical = 150
	await process_frame
	var position: int = panel.scroll.scroll_vertical
	var children: Array = panel.pages[Management.UPGRADES].get_children()
	for i in 30: panel.refresh()
	assert(panel.scroll.scroll_vertical == position and panel.rows.cauldron.extra.visible and panel.rows.cauldron.toggle.button_pressed)
	assert(panel.pages[Management.UPGRADES].get_children() == children)
	panel.select_page(Management.HERBS)
	await process_frame
	await process_frame
	panel.select_page(Management.UPGRADES)
	await process_frame
	await process_frame
	assert(panel.scroll.scroll_vertical == position, "Tab switches restore their own scroll")
	# A recommendation deep in the equipment list also upgrades immediately.
	shop.state.level = shop.state.MAX_LEVEL
	shop.state.garden_level = shop.state.MAX_GARDEN_LEVEL
	shop.state.sales_counter_level = 10
	p.filter_owned = true
	for track in ["cauldron", "herb_pot", "sales_counter", "herb_storage", "potion_cabinet", "drying_rack", "precision_filter"]:
		p.expansion.stages[track] = int(Content.track_rows(track)[-1].stage)
	for region in Content.DATA.regions: p.expansion.returns[region.id] = int(region.complete_returns)
	p.expedition_count = 10
	for employee in Content.DATA.employees: p.expansion.staff.append(employee.id)
	p.employee = true
	for entry in Content.DATA.upgrades:
		if entry.track != "expedition_path": p.expansion.stages[entry.track] = int(entry.stage)
	# Raising stages directly in a fixture must also keep timers within new durations.
	shop.state.brew_elapsed = shop.state.brew_duration() * 0.4
	shop.state.harvest_elapsed = shop.state.harvest_duration() * 0.3
	shop.state.customer_elapsed = shop.state.customer_interval() * 0.2
	panel.select_page(Management.OPERATION)
	panel.refresh()
	assert(panel.recommendation.target == "growth:expedition_path")
	var before_deep: Dictionary = shop.state.to_data().duplicate(true)
	assert(expected.load_data(before_deep))
	assert(expected.purchase("upgrade:expedition_path"))
	panel.recommend_button.pressed.emit()
	await process_frame
	await process_frame
	await process_frame
	assert(panel.selected == Management.OPERATION)
	assert(Compare.equivalent(expected.to_data(), shop.state.to_data()), "Path recommendation purchases once without resetting active journeys")
	# Maxed investments cannot be recommended and their stage bars are exact.
	panel.recommend_button.button_down.emit()
	shop.state.level = shop.state.MAX_LEVEL
	shop.state.garden_level = shop.state.MAX_GARDEN_LEVEL
	shop.state.sales_counter_level = 10
	p.filter_owned = true
	for entry in Content.DATA.upgrades: p.expansion.stages[entry.track] = int(entry.stage)
	panel.refresh()
	assert(panel.recommendation.is_empty())
	var maxed_snapshot: Dictionary = shop.state.to_data().duplicate(true)
	panel.recommend_button.pressed.emit()
	assert(Compare.equivalent(maxed_snapshot, shop.state.to_data()), "An upgrade maxed while held cannot charge again")
	for entry in Content.DATA.upgrades:
		var data := Status.investment(shop.state, entry.track)
		assert(data.maxed and panel.rows[data.target].bar.value == 100 and panel.rows[data.target].button.disabled)
	# Closing and switching cannot manufacture or deposit a second time.
	baseline = shop.state.to_data().duplicate(true)
	var control := State.new()
	assert(control.load_data(JSON.parse_string(JSON.stringify(baseline))))
	for page in panel.pages.size():
		panel.select_page(page)
		panel.refresh()
	panel.close_requested.emit()
	assert(not panel.visible and Compare.equivalent(baseline, shop.state.to_data()))
	for i in 400:
		shop.state.advance(0.2)
		control.advance(0.2)
		panel.refresh()
	assert(Compare.equivalent(shop.state.to_data(), control.to_data()), "UI refresh must not duplicate production, receipts, fees, growth, sales or RNG")
	# Legacy input with no new UI field is still supported.
	var old := control.to_data()
	old.erase("main_window_mode")
	var restored := State.new()
	assert(restored.load_data(old))
	assert(await export_layout())
	print("MANAGEMENT GAUGES PASS: 6 tabs, compact fixed-height operation, real active potion bar, capture/max/funds, stable details/scroll/save, unchanged economy; headless only")
	quit()

func verify_sale_height() -> bool:
	var original: RefCounted = shop.state
	var fixture := State.new()
	assert(fixture.load_data(original.to_data().duplicate(true)))
	shop.state = fixture
	fixture.herbs = 3
	var height := -1.0
	var next_y := -1.0
	for mode in ["selling", "no_customer", "no_stock", "closed", "selling"]:
		fixture.shop_open = mode != "closed"
		fixture.progression.customer_selected = mode != "no_customer"
		fixture.customer_waiting = mode == "no_stock"
		fixture.stock = 0 if mode == "no_stock" else 3
		fixture.mana_stock = 0
		fixture.inventory.clear()
		for i in fixture.stock: fixture.inventory.append(false)
		fixture.customer_elapsed = fixture.customer_interval() * 0.25
		panel.refresh()
		await process_frame
		await process_frame
		if height < 0:
			height = panel.rows.sale.panel.size.y
			next_y = panel.rows.gather_herb.panel.position.y
		if not panel.rows.sale.panel.visible or not panel.rows.sale.work.box.visible or not is_equal_approx(panel.rows.sale.panel.size.y, height) or not is_equal_approx(panel.rows.gather_herb.panel.position.y, next_y):
			print("SALE LAYOUT FAILURE ", mode)
			return false
		assert(is_equal_approx(panel.rows.sale.bar.value, 25.0 if mode == "selling" else 0.0))
	shop.state = original
	panel.refresh()
	return true

func verify_craft_height() -> bool:
	var original: RefCounted = shop.state
	var fixture := State.new()
	assert(fixture.load_data(original.to_data().duplicate(true)))
	shop.state = fixture
	fixture.shop_open = false # Keep sale row out of this manufacturing-layout check.
	fixture.brew_active = true
	fixture.brew_elapsed = fixture.brew_duration() * 0.4
	fixture.stock = 0
	fixture.mana_stock = 0
	fixture.inventory.clear()
	panel.select_page(Management.OPERATION)
	panel.refresh()
	await process_frame
	await process_frame
	var height: float = panel.rows.craft.panel.size.y
	var next_y: float = panel.rows.gather_herb.panel.position.y
	var progress: float = panel.rows.craft.bar.value
	for mode in ["full_batch", "resumed", "full_idle", "no_materials", "preparing"]:
		fixture.stock = fixture.capacity() if mode.begins_with("full") else 0
		fixture.inventory.clear()
		for i in fixture.stock: fixture.inventory.append(false)
		fixture.brew_active = mode == "full_batch" or mode == "resumed"
		fixture.brew_elapsed = fixture.brew_duration() * 0.4 if fixture.brew_active else 0.0
		fixture.herbs = 0 if mode == "no_materials" else 3
		if mode == "full_batch":
			var elapsed: float = fixture.brew_elapsed
			fixture.advance(1.0)
			assert(fixture.brew_elapsed == elapsed, "Full inventory preserves the real paused batch")
		panel.refresh()
		await process_frame
		await process_frame
		if not panel.rows.craft.work.box.visible or not panel.rows.craft.detail.visible or not is_equal_approx(panel.rows.craft.panel.size.y, height) or not is_equal_approx(panel.rows.gather_herb.panel.position.y, next_y):
			print("CRAFT LAYOUT FAILURE ", mode, " height=", panel.rows.craft.panel.size.y, " expected=", height)
			return false
		assert(is_equal_approx(panel.rows.craft.bar.value, progress if fixture.brew_active else 0.0), "Keep real progress while blocked, never invent a full bar")
		if fixture.brew_active:
			var active_row: Dictionary = panel.rows["potion_" + Status.kind_id(fixture.progression.active_recipe)]
			assert(active_row.detail.text.begins_with("재고 가득") if mode == "full_batch" else active_row.detail.text.begins_with("제작 중"))
	shop.state = original
	panel.refresh()
	return true

func export_layout() -> bool:
	panel.visible = true # Still a virtual headless viewport, never a native user window.
	DirAccess.make_dir_recursive_absolute("res://.verification/management-gauges")
	var layouts := []
	for i in panel.tabs.size():
		assert(panel.tabs[i].get_rect().end.x <= panel.size.x - 20)
		if i > 0: assert(panel.tabs[i - 1].get_rect().end.x <= panel.tabs[i].position.x)
	for page in panel.pages.size():
		panel.select_page(page)
		await process_frame
		await process_frame
		var info := {"page": page, "scroll": panel.scroll.scroll_vertical, "rows": []}
		for id in panel.rows:
			var row: Dictionary = panel.rows[id]
			if row.page != page or not row.panel.visible: continue
			assert(row.panel.size.x <= panel.scroll.size.x + 1, "Rows must not require horizontal scrolling")
			for key in ["title", "detail", "summary", "button", "toggle", "extra", "icon"]:
				var node: Control = row[key]
				if not node.visible: continue
				var local := node.get_global_rect()
				local.position -= row.panel.global_position
				if not Rect2(Vector2.ZERO, row.panel.size).grow(1).encloses(local):
					print("BOUND FAILURE ", id, "/", key, " local=", local, " panel=", row.panel.size)
					return false
			info.rows.append({"id": id, "title": row.title.text, "status": row.detail.text, "work": row.work.bar.value, "inventory": row.stock.bar.value, "width": row.panel.size.x, "height": row.panel.size.y})
		layouts.append(info)
	var file := FileAccess.open("res://.verification/management-gauges/layout.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"verification": "headless layout bounds; not GPU pixels", "pages": layouts}, "  "))


	return true

