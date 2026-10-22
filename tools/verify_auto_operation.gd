extends SceneTree
const Shop = preload("res://scripts/shop.gd")
const State = preload("res://scripts/shop_state.gd")
const Compare = preload("res://tests/state_compare.gd")


func _initialize() -> void:
	set_meta("isolated_preview", true)
	call_deferred("_run")


func _run() -> void:
	var fresh := State.new()
	assert(fresh.shop_open and fresh.auto_purchase and not fresh.progression.expedition_active)
	fresh.advance(180.0)
	assert(fresh.total_sold > 0 and fresh.total_spent_materials > 0 and fresh.gold >= 0)
	assert(fresh.level == 1 and fresh.garden_level == 1 and fresh.progression.owned.is_empty())
	assert(not fresh.progression.expedition_unlocked and fresh.progression.expedition_count == 0)
	var old := State.new()
	old.gold = 550
	old.shop_open = false
	old.auto_purchase = false
	old.delivery_elapsed = 9.75
	old.herbs = 7
	old.mushrooms = 3
	old.brew_active = true
	old.brew_elapsed = 6.25 # Longer than a basic batch: must not clamp back to 5 s.
	old.progression.owned = ["moon"]
	old.progression.active_recipe = "moon"
	old.progression.batch_success = false
	old.progression.batch_chance = 0.86
	old.progression.expedition_unlocked = true
	old.progression.expedition_active = false
	old.progression.expedition_elapsed = 66.0
	old.progression.customer_selected = true
	old.customer_elapsed = 1.25
	var saved := old.to_data()
	saved["version"] = 6
	saved["progression"].erase("expansion")
	var restored := State.new()
	assert(restored.load_data(JSON.parse_string(JSON.stringify(saved))))
	for key in ["gold", "herbs", "mushrooms", "delivery_elapsed", "brew_elapsed", "customer_elapsed"]: assert(restored.get(key) == old.get(key))
	assert(restored.shop_open and restored.auto_purchase and restored.progression.expedition_active)
	assert(restored.progression.expansion.cycles["forest_edge"]["elapsed"] == 66.0 and not restored.progression.expansion.cycles["forest_edge"]["paid"])
	assert(restored.progression.active_recipe == "moon" and not restored.progression.batch_success)
	var restored_again := State.new()
	assert(restored_again.load_data(restored.to_data()))
	assert(Compare.equivalent(restored_again.to_data(), restored.to_data()), "Repeated loading must not grant rewards or repeat unlock charges")
	var journey := State.new()
	journey.gold = 1000
	journey.progression.reputation = State.Content.EXPEDITION_REPUTATION
	assert(journey.purchase("expedition") and journey.progression.expedition_active)
	assert(journey.gold == 1000 - State.Content.EXPEDITION_COST - 8)
	assert(not journey.purchase("expedition"))
	journey.advance(71.0)
	assert(journey.progression.expedition_count == 1 and journey.progression.rare_herbs == 2)
	journey.progression.expedition_count = 10
	journey.progression.expansion.cycles["forest_edge"]["running"] = false
	journey.progression.rare_herbs = 12
	journey.progression.expansion.pending["starleaf"] = 2
	var waiting := State.new()
	assert(waiting.load_data(journey.to_data()))
	waiting.advance(1.0)
	assert(waiting.progression.expansion.pending["starleaf"] == 2)
	waiting.progression.rare_herbs -= 2
	waiting.advance(1.0)
	assert(not waiting.progression.expansion.pending.has("starleaf") and waiting.progression.rare_herbs == 12)
	var shop := Shop.new()
	root.add_child(shop)
	shop._set_window_mode(State.WindowMode.WORKSHOP)
	shop.state.gold = 1000
	shop.state.progression.reputation = 40
	shop.open_management()
	for id in ["craft", "gather_moon_mushroom", "trip_forest_edge"]:
		assert(not shop.management.rows[id]["button"].visible, "Automatic operation must have no on/off actions")
	assert(not shop.supply_button.visible)
	assert(shop.business_status is Label and shop.mini_business_status is Label)
	var before: Dictionary = shop.state.to_data()
	for page in shop.management.pages.size():
		shop.management.select_page(page)
		shop.management.refresh()
	assert(Compare.equivalent(before, shop.state.to_data()))
	shop.management.rows["forest_edge"]["button"].pressed.emit()
	assert(shop.state.progression.expedition_active and shop.state.gold == 592)
	shop.management.rows["moon"]["button"].pressed.emit()
	assert(shop.state.progression.owned.has("moon") and shop.state.gold == 472)
	shop.management.hide()
	shop._advance_game(71.0)
	assert(shop.state.progression.expedition_count == 1 and shop.state.progression.totals["rare"] >= 2 and shop.state.total_sold > 0)
	shop.open_management()
	if DisplayServer.get_name() != "headless" and "--render" in OS.get_cmdline_user_args():
		for page in shop.management.tabs.size():
			shop.management.select_page(page)
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			shop.management.get_texture().get_image().save_png("res://.verification/automatic-management-%d.png" % page)
	print("AUTO OPERATION PASS: fresh start; legacy switches resume without lost progress; unlock starts expedition; pending reward retained; no control switches; manual purchases; management close/reopen")
	quit()
