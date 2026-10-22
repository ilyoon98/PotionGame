extends SceneTree
const Shop = preload("res://scripts/shop.gd")
const State = preload("res://scripts/shop_state.gd")
const Status = preload("res://scripts/management_status.gd")
const Content = preload("res://scripts/shop_content.gd")
const Trips = preload("res://scripts/parallel_expeditions.gd")
const Compare = preload("res://tests/state_compare.gd")
var shop: Control
var panel: Window

func _initialize() -> void:
	set_meta("isolated_preview", true)
	call_deferred("run")

func fixture(kind: String) -> RefCounted:
	var state := State.new()
	state.gold = 10000000
	var p: RefCounted = state.progression
	p.reputation = 10000
	state.advance(1.3)
	state.customer_waiting = false
	state.herbs = 3
	p.expedition_count = 10
	for region in Content.DATA.regions: p.expansion.returns[region.id] = int(region.complete_returns)
	if kind != "upgrade":
		state.level = 2
		state.garden_level = 2
	if kind in ["staff", "recipe", "training", "all"]:
		p.expedition_unlocked = true
		for region in Content.DATA.regions: p.expansion.regions.append(region.id)
		Trips.tick(state, 0.0)
	if kind in ["recipe", "training", "all"]:
		p.employee = true
		for employee in Content.DATA.employees: p.expansion.staff.append(employee.id)
	if kind in ["training", "all"]:
		for id in Content.RECIPES:
			p.owned.append(id)
			if not Content.LEGACY_RECIPES.has(id): p.expansion.grant_recipe(id)
	state.brew_elapsed = state.brew_duration() * 0.3
	state.harvest_elapsed = state.harvest_duration() * 0.2
	state.customer_elapsed = state.customer_interval() * 0.1
	return state

func run() -> void:
	assert(DisplayServer.get_name() == "headless")
	shop = Shop.new()
	root.add_child(shop)
	shop.set_process(false)
	shop.open_management()
	panel = shop.management
	panel.set_process(false)
	assert(panel.tabs.size() == 7 and panel.tabs[panel.UPGRADES].text == "가구·직원")
	for kind in ["upgrade", "region", "staff", "recipe", "training"]:
		shop.state = fixture(kind)
		panel.select_page(panel.OPERATION)
		panel.refresh()
		assert(panel.recommendation.kind == kind, "Every category must be chosen before all investments max out: " + kind)
		var choice: Dictionary = panel.recommendation.duplicate(true)
		var key: String = choice.purchase_key
		var baseline: Dictionary = shop.state.to_data().duplicate(true)
		var expected := State.new()
		assert(expected.load_data(baseline) and expected.purchase(key))
		panel.recommend_button.button_down.emit()
		# Force another recommendation category while held; release must buy the original.
		panel.recommend_button.set_meta("purchase_key", "moon" if kind != "recipe" else "staff:sales_assistant")
		panel.recommend_button.pressed.emit()
		assert(Compare.equivalent(expected.to_data(), shop.state.to_data()), "One captured action matches core including fees/batch/RNG: " + kind)
		assert(panel.selected == panel.OPERATION)
		var direct := State.new()
		assert(direct.load_data(baseline))
		shop.state = direct
		panel.refresh()
		var row_id: String = "employee" if kind == "staff" and choice.target == "sales_assistant" else choice.target
		panel.rows[row_id].button.pressed.emit()
		assert(Compare.equivalent(expected.to_data(), shop.state.to_data()), "Formal tab and recommendation purchase identical: " + kind)
		if kind in ["region", "staff", "recipe"]:
			var paid: Dictionary = shop.state.to_data().duplicate(true)
			panel.recommend_pressed_action = key
			panel.recommend_button.pressed.emit()
			assert(Compare.equivalent(paid, shop.state.to_data()), "Already-owned actions cannot pay twice")
		shop.state = fixture(kind)
		panel.refresh()
		panel.recommend_button.button_down.emit()
		shop.state.gold = 0
		panel.refresh()
		var rejected: Dictionary = shop.state.to_data().duplicate(true)
		panel.recommend_button.pressed.emit()
		assert(Compare.equivalent(rejected, shop.state.to_data()) and panel.recommend_feedback.contains("부족"))
	# Opening fee alone opens the region but does not fabricate a paid departure.
	shop.state = fixture("region")
	shop.state.gold = shop.state.purchase_cost("expedition")
	panel.refresh()
	panel.recommend_pressed_action = "expedition"
	panel.recommend_button.pressed.emit()
	assert(shop.state.progression.expedition_unlocked and shop.state.gold == 0)
	assert(not shop.state.progression.expansion.cycles.forest_edge.running)
	assert(panel.rows.forest_edge.button.text == "열림" and Status.region_status(shop.state, "forest_edge") == "출발비 부족")
	# Discovery loss during click cannot bypass the real recipe condition.
	shop.state = fixture("all")
	var discovered := ""
	for potion in Content.DATA.potions:
		if potion.unlock.has("discovery"):
			discovered = potion.id
			break
	shop.state.progression.owned.erase(discovered)
	assert(shop.state.purchase_reason(discovered).is_empty())
	panel.recommend_pressed_action = discovered
	shop.state.progression.expedition_count = 0
	shop.state.progression.expansion.returns.clear()
	var blocked: Dictionary = shop.state.to_data().duplicate(true)
	panel.recommend_button.pressed.emit()
	assert(Compare.equivalent(blocked, shop.state.to_data()) and panel.recommend_feedback.contains("원정"))
	assert(not Status.growth_candidates(shop.state).any(func(c): return c.purchase_key == discovered))
	assert(await layout_and_smooth())
	print("MANAGEMENT GROWTH PASS: six tabs; compact first screen >=6 actual bars and three groups; active potion bar/frame updates; five recommended actions equal formal/core purchases; capture/funds/duplicate/discovery/fees; stable waits, bounds, save and UI economy")
	quit()

func layout_and_smooth() -> bool:
	shop.state = fixture("all")
	shop.state.stock = 3
	shop.state.mana_stock = 1
	shop.state.inventory = [false, true, "moon"]
	shop.state.progression.customer_selected = true
	panel.select_page(panel.OPERATION)
	panel.scroll.scroll_vertical = 0
	panel.refresh()
	await process_frame
	await process_frame
	var bars := 0
	var groups := {}
	for id in panel.rows:
		var row: Dictionary = panel.rows[id]
		if row.page != panel.OPERATION or not row.panel.visible or not row.work.box.visible: continue
		if panel.scroll.get_global_rect().encloses(row.work.box.get_global_rect()):
			bars += 1
			groups["포션" if id in ["craft", "sale"] else "채집" if id.begins_with("gather_") else "원정"] = true
		if row.panel.size.y > panel.ROW_LIMIT:
			print("COMPACT ROW TOO TALL ", id, " ", row.panel.size.y)
			return false
	if bars < 6 or groups.size() != 3:
		print("FIRST SCREEN FAILURE bars=", bars, " groups=", groups)
		return false
	assert(panel.recommend_panel.size.y == 68)
	# Between two slow refresh ticks only gauges change; text remains untouched.
	var old_text: String = panel.rows.craft.detail.text
	panel.refresh_elapsed = 0.0
	shop.state.advance(0.05)
	panel._process(0.05)
	assert(panel.refresh_elapsed < 0.2 and panel.rows.craft.detail.text == old_text)
	assert(is_equal_approx(panel.rows.craft.bar.value, shop.state.brew_elapsed / shop.state.brew_duration() * 100))
	panel.select_page(panel.POTIONS)
	var active: String = "potion_" + Status.kind_id(shop.state.progression.active_recipe)
	assert(panel.rows[active].work.box.visible)
	shop.state.advance(0.05)
	panel._process(0.05)
	assert(is_equal_approx(panel.rows[active].bar.value, shop.state.brew_elapsed / shop.state.brew_duration() * 100))
	for id in panel.rows:
		if id.begins_with("potion_") and id != active:
			assert(panel.rows[id].work.box.visible and panel.rows[id].work.bar.value == 0 and panel.rows[id].work.count.text == "대기")
	# UI frame sampling cannot produce or debit independently.
	var control := State.new()
	assert(control.load_data(shop.state.to_data().duplicate(true)))
	for i in 250:
		shop.state.advance(0.04)
		control.advance(0.04)
		panel._process(0.04)
	assert(Compare.equivalent(shop.state.to_data(), control.to_data()))
	for page in panel.pages.size():
		panel.select_page(page)
		await process_frame
		await process_frame
		for row in panel.rows.values():
			if row.page != page or not row.panel.visible: continue
			for key in ["title", "detail", "button", "extra", "toggle", "summary", "icon"]:
				var node: Control = row[key]
				if node.visible and not row.panel.get_global_rect().grow(1).encloses(node.get_global_rect()):
					print("ROW BOUND FAILURE page=", page, " key=", key)
					return false
	return true
