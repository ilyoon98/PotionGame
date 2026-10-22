extends SceneTree
const Shop = preload("res://scripts/shop.gd")
const Compare = preload("res://tests/state_compare.gd")


func _initialize() -> void:
	set_meta("isolated_preview", true)
	call_deferred("_run")


func _run() -> void:
	var shop := Shop.new()
	root.add_child(shop)
	shop.state.gold = 10000
	shop.state.stock = shop.State.CAPACITY
	shop.state.inventory_order()
	shop.open_management()
	var panel = shop.management
	panel.refresh()
	assert(panel.tabs.size() == 7)
	assert(panel.rows["sales_counter"]["icon"].texture != null)
	assert(not panel.rows["sales_counter"]["button"].disabled)
	assert(panel.recommendation.target == "sales_counter")
	panel.recommend_button.pressed.emit()
	await process_frame
	assert(panel.selected == panel.OPERATION, "Recommendation upgrades without changing page")
	assert(shop.state.sales_counter_level == 1 and shop.state.gold == 9760)
	panel.rows["sales_counter"]["button"].pressed.emit()
	assert(shop.state.sales_counter_level == 2 and panel.rows["sales_counter"]["button"].disabled)
	assert(panel.rows["sales_counter"]["button"].text.contains("조사 완료 필요"))
	shop.state.progression.expedition_unlocked = true
	shop.state.progression.expedition_active = true
	shop.state.progression.expedition_count = 10
	panel.refresh()
	assert(not panel.rows["sales_counter"]["button"].disabled)
	panel.rows["sales_counter"]["button"].pressed.emit()
	assert(shop.state.sales_counter_level == 3 and panel.rows["sales_counter"]["button"].disabled)
	assert(panel.rows.forest_edge.extra.source_text.contains("조사 완료") and not panel.rows.forest_edge.summary.source_text.contains("조사"))
	assert(not panel.rows.forest_edge.button.visible)
	shop.state.stock = 0
	shop.state.inventory.clear()
	shop.state.customer_waiting = true
	shop.state.progression.customer_selected = true
	shop.state.level = shop.State.MAX_LEVEL
	shop.state.progression.expansion.stages["cauldron"] = 20
	panel.refresh()
	assert(panel.recommendation.get("target", "") != "cauldron", "Maximum cauldron is not recommended for upgrade")
	shop.workshop_minimize.pressed.emit()
	assert(shop.state.window_mode == shop.State.WindowMode.COMPANION)
	if DisplayServer.get_name() != "headless": assert(root.mode != Window.MODE_MINIMIZED)
	assert(not panel.visible)
	print("COUNTER UI PASS: six tabs, direct recommendation/manual upgrades, region locks/investigation, max hints and compact progress")
	quit()
