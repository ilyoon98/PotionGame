extends SceneTree
const Shop = preload("res://scripts/shop.gd")
const State = preload("res://scripts/shop_state.gd")
const Content = preload("res://scripts/shop_content.gd")
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
func fixture() -> RefCounted:
	var state := State.new()
	state.gold = 1000000
	state.progression.reputation = 10000
	return state
func set_stock(state: RefCounted, amount: int) -> void:
	state.stock = amount
	state.mana_stock = 0
	state.inventory.clear()
	for i in amount: state.inventory.append(false)
func verify_partition(page: int) -> void:
	var completed := false
	var last_order := [-1, -1]
	for child in panel.pages[page].get_children():
		if not child.has_meta("row_id"):
			completed = false
			last_order = [-1, -1]
			continue
		var row: Dictionary = panel.rows[child.get_meta("row_id")]
		assert(not completed or row.completed, "No unfinished purchase appears after the completed partition")
		completed = completed or row.completed
		var bucket := int(row.completed)
		assert(row.order > last_order[bucket], "Stable catalog order inside each partition")
		last_order[bucket] = row.order
func run() -> void:
	assert(DisplayServer.get_name() == "headless")
	shop = Shop.new()
	root.add_child(shop)
	shop.set_process(false)
	shop.state = fixture()
	shop.open_management()
	panel = shop.management
	panel.set_process(false)
	for child in panel.get_child(0).get_children():
		if child is Button: assert(child.position.y < 600, "Remove all three footer actions")
	assert(panel.tabs.size() == 7 and panel.pages.size() == 8 and panel.tabs[panel.UPGRADES].text == "가구·직원")
	assert(panel.REPORT == 6 and panel.SETTINGS == 7 and panel.tabs[-1].text == "설정")
	var settings: Node = panel.pages[panel.SETTINGS].get_node("GameSettings")
	assert(settings.is_ancestor_of(panel.startup_toggle) and settings.is_ancestor_of(panel.startup_status))
	assert(panel.pages[panel.UPGRADES].find_child("GameSettings", true, false) == null, "Staff and upgrades no longer contain settings")
	var navigation_before: Dictionary = shop.state.to_data().duplicate(true)
	for index in panel.tabs.size():
		panel.tabs[index].pressed.emit()
		await layout()
		assert(panel.selected == panel.TAB_PAGES[index], "Every visible tab opens its own page, including settings rather than statistics")
		assert(panel.tabs[index].button_pressed and panel.tabs[index].get_rect().end.x <= 500.01)
		if index > 0: assert(panel.tabs[index - 1].get_rect().end.x <= panel.tabs[index].position.x, "Seven readable tabs must not overlap")
	panel.result_button.pressed.emit()
	await layout()
	assert(panel.selected == panel.REPORT)
	for tab in panel.tabs: assert(not tab.button_pressed, "The independent statistics shortcut does not select the settings tab")
	panel.select_page(panel.SETTINGS)
	panel.open_contracts()
	panel.close_contracts()
	await layout()
	assert(panel.selected == panel.SETTINGS and panel.tabs[-1].button_pressed)
	assert(Compare.equivalent(navigation_before, shop.state.to_data()), "Separating settings and returning from statistics/contracts preserves the complete saved game")
	panel.select_page(panel.HERBS)
	assert(panel.scroll.get_rect().end.y == panel.size.y - 20, "Reclaim the footer area")
	# Full / growing / no funds use exactly the same card and subsequent positions.
	var herb_height := -1.0
	var mushroom_y := -1.0
	for mode in ["growing", "full", "no_funds", "growing"]:
		shop.state.herbs = shop.state.herb_capacity() if mode == "full" else 2
		shop.state.gold = 0 if mode == "no_funds" else 1000000
		await layout()
		var row: Dictionary = panel.rows.herb_inventory
		if herb_height < 0:
			herb_height = row.panel.size.y
			mushroom_y = panel.rows.material_moon_mushroom.panel.position.y
		assert(is_equal_approx(row.panel.size.y, herb_height) and is_equal_approx(panel.rows.material_moon_mushroom.panel.position.y, mushroom_y))
		assert(row.detail.visible and row.work.box.visible and row.stock.box.visible)
		assert(panel.rows.material_moon_mushroom.work.box.visible and panel.rows.material_moon_mushroom.detail.visible)
		if mode == "no_funds": assert(panel.rows.material_moon_mushroom.work.count.text == "대기")
	# A recipe changing the active potion never inserts/removes manufacturing bars.
	panel.select_page(panel.POTIONS)
	var potion_height := -1.0
	var mana_y := -1.0
	for mode in ["health", "full", "mana", "idle", "health"]:
		shop.state.progression.active_recipe = mode == "mana"
		shop.state.brew_active = mode != "idle"
		shop.state.brew_elapsed = 1.0 if shop.state.brew_active else 0.0
		shop.state.herbs = 4
		set_stock(shop.state, shop.state.capacity() if mode == "full" else 0)
		await layout()
		var row: Dictionary = panel.rows.potion_health
		if potion_height < 0:
			potion_height = row.panel.size.y
			mana_y = panel.rows.potion_mana.panel.position.y
		assert(is_equal_approx(row.panel.size.y, potion_height) and is_equal_approx(panel.rows.potion_mana.panel.position.y, mana_y))
		for id in ["potion_health", "potion_mana"]:
			assert(panel.rows[id].work.box.visible and panel.rows[id].stock.box.visible)
		if mode in ["mana", "idle"]: assert(row.work.bar.value == 0 and row.work.count.text == "대기")
	# Potion rows also show the blend; their pre-settings baseline is168px.
	assert(herb_height <= panel.ROW_LIMIT and potion_height <= 180, "Keep compact herb rows and readable potion blend/progress rows")
	# Subsecond progress is visible before an actual one-second expedition/growth tick.
	shop.state = fixture()
	assert(shop.state.purchase("expedition") and shop.state.purchase("moon"))
	set_stock(shop.state, shop.state.capacity())
	shop.state.brew_active = false
	shop.state.progression.rare_herbs = 1
	panel.select_page(panel.EXPEDITIONS)
	var cycle: Dictionary = shop.state.progression.expansion.cycles.forest_edge
	var cycle_elapsed: float = cycle.elapsed
	var previous: float = panel.rows.forest_edge.work.bar.value
	for i in 5:
		shop.state.advance(0.05)
		panel._process(0.05)
		assert(panel.rows.forest_edge.work.bar.value > previous and cycle.elapsed == cycle_elapsed)
		previous = panel.rows.forest_edge.work.bar.value
	panel.select_page(panel.HERBS)
	var growth: float = shop.state.progression.rare_growth
	previous = panel.rows.rare_inventory.work.bar.value
	for i in 5:
		shop.state.advance(0.05)
		panel._process(0.05)
		assert(panel.rows.rare_inventory.work.bar.value > previous and shop.state.progression.rare_growth == growth)
		previous = panel.rows.rare_inventory.work.bar.value
	# Stock follows a real change over frames rather than jumping on text refresh.
	shop.state.herbs = 2
	panel.select_page(panel.HERBS)
	var stock: Dictionary = panel.rows.herb_inventory.stock
	var old_stock: float = stock.bar.value
	shop.state.herbs = 6
	panel.refresh()
	assert(stock.bar.value == old_stock and stock.target > old_stock)
	panel._process(0.04)
	assert(stock.bar.value > old_stock and stock.bar.value < stock.target)
	previous = stock.bar.value
	shop.workshop_dragging = true
	panel._process(0.1)
	assert(stock.bar.value == previous)
	shop.workshop_dragging = false
	for i in 30: panel._process(0.04)
	assert(is_equal_approx(stock.bar.value, stock.target))
	# Real purchase rows move below incomplete rows, with sections and details intact.
	shop.state = fixture()
	assert(shop.state.purchase("moon") and shop.state.purchase("expedition") and shop.state.purchase("staff:sales_assistant"))
	shop.state.level = State.MAX_LEVEL
	shop.state.progression.expansion.stages["cauldron"] = int(Content.track_rows("cauldron")[-1].stage)
	panel.rows.moon.toggle.button_pressed = true
	await layout()
	for page in [panel.RECIPES, panel.EXPEDITIONS, panel.UPGRADES]: verify_partition(page)
	assert(panel.rows.moon.completed and panel.rows.cauldron.completed and panel.rows.employee.completed and panel.rows.forest_edge.completed)
	assert(panel.rows.moon.extra.visible and panel.rows.moon.toggle.button_pressed)
	var children: Array = panel.pages[panel.UPGRADES].get_children()
	var before: Dictionary = shop.state.to_data().duplicate(true)
	for i in 20: panel.refresh()
	assert(panel.pages[panel.UPGRADES].get_children() == children and Compare.equivalent(before, shop.state.to_data()))
	# Reordering keeps callbacks bound to the original recipe and charges once.
	var expected := State.new()
	assert(expected.load_data(shop.state.to_data().duplicate(true)))
	assert(expected.purchase("purify"))
	panel.rows.purify.button.pressed.emit()
	assert(Compare.equivalent(expected.to_data(), shop.state.to_data()) and panel.rows.purify.completed)
	verify_partition(panel.RECIPES)
	# Display ticks and animation never change production, fees, awards or RNG.
	var control := State.new()
	assert(control.load_data(shop.state.to_data().duplicate(true)))
	for page in [panel.HERBS, panel.POTIONS, panel.EXPEDITIONS]:
		panel.select_page(page)
		for i in 80:
			shop.state.advance(0.03)
			control.advance(0.03)
			panel._process(0.03)
		assert(Compare.equivalent(control.to_data(), shop.state.to_data()))
	print("STABLE TABS PASS: footer removed/reclaimed; compact herb/potion fixed slots and heights; independent subsecond expedition/growth progress; actual-stock animation/drag pause; completed items below unfinished within sections; stable details/callbacks; unchanged economy/RNG/fees/save; headless only")
	quit()
