extends SceneTree
const Shop = preload("res://scripts/shop.gd")
const F = preload("res://tests/late_investment_fixture.gd")
const M = preload("res://tests/contracts_fixture.gd")
const Compare = preload("res://tests/state_compare.gd")
const Store = preload("res://scripts/save_store.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func _initialize() -> void:
	set_meta("isolated_preview", true); call_deferred("run")
func ok_save() -> bool: return true
func fail_save() -> bool: return false
func run() -> void:
	check(DisplayServer.get_name() == "headless", "Headless controls only")
	var shop := Shop.new(); root.add_child(shop)
	await process_frame
	shop.set_process(false); shop.art.set_process(false); shop.open_management()
	var panel = shop.management; panel.set_process(false)
	shop.state = F.completed_store(73129, "final", "both3", "normal")
	shop.state.gold = 400000
	shop.state._start_batch()
	panel.select_page(panel.OPERATION); panel.refresh()
	for i in 4: await process_frame
	check(panel.tabs.size() == 7 and panel.pages.size() == 8 and panel.tabs[-1].text == "설정", "Separate settings and statistics mapping retained")
	check(panel.pages[panel.UPGRADES].find_child("GameSettings", true, false) == null, "No settings under staff")
	check(panel.rows.contract_summary.detail.text.contains("판매 재고 확보 중"), "Protected contracts visibly wait for actual retail recovery")
	check(panel.workshop_goal.visible and panel.recommend_panel.size.y == 180 and not panel.workshop_goal_button.disabled and not panel.workshop_goal_button.get_meta("can_buy"), "Unaffordable goal remains visible and navigable")
	panel.workshop_goal_button.button_down.emit(); panel.workshop_goal_button.pressed.emit()
	for i in 5: await process_frame
	check(panel.selected == panel.UPGRADES and panel.rows.workshop_1.panel.position.y <= panel.scroll.scroll_vertical + 1, "Goal navigates to real workshop purchase row")
	shop.state.gold = 10000000
	panel.select_page(panel.OPERATION)
	panel.refresh(); shop.set_meta("workshop_save_fixture", fail_save)
	check(not panel.workshop_goal.visible and panel.recommend_panel.size.y == 76 and panel.recommend_button.get_meta("purchase_key") == "workshop", "Affordable workshop appears only once, in the growth recommendation")
	check(panel.scroll.position.y == panel.recommend_panel.position.y + 84, "Hidden goal leaves no blank space or scroll overlap")
	var before: Dictionary = M.data(shop.state)
	check(not shop.perform_workshop_action(1).ok, "Failed save refuses purchase")
	check(Compare.equivalent(before, M.data(shop.state)), "Failed purchase restores complete lines/protection/RNG/cash/closed shop")
	shop.set_meta("workshop_save_fixture", ok_save)
	check(shop.perform_workshop_action(1).ok, "UI gateway buys expansion")
	shop.state.stock = 16; shop.state.mana_stock = 0; shop.state.inventory.clear()
	for i in 16: shop.state.inventory.append(false)
	shop.state._start_batch()
	panel.select_page(panel.OPERATION); panel.refresh()
	for i in 3: await process_frame
	check(shop.state.brew_active and not shop.state.workshop.aux.is_empty(), "Fixture has two real reserved batches")
	check(panel.rows.craft.work.box.visible and panel.rows.aux_craft.work.box.visible and panel.rows.aux_craft.panel.visible, "Two actual progress gauges")
	var reservation: Dictionary = shop.state.workshop.aux.duplicate(true)
	shop.set_meta("workshop_save_fixture", fail_save); before = M.data(shop.state)
	check(not shop.perform_workshop_action(2).ok and Compare.equivalent(before, M.data(shop.state)), "Upgrade save rollback preserves active auxiliary and main batch")
	shop.set_meta("workshop_save_fixture", ok_save)
	panel.recommend_button.button_down.emit(); panel.recommend_button.pressed.emit()
	check(shop.state.workshop.level == 2 and Compare.equivalent(reservation, shop.state.workshop.aux), "Single recommendation directly improves using same transaction API and frozen batch")
	check(not shop.perform_workshop_action(2).ok, "Stale expected-level click cannot double spend")
	var path := "res://.verification/f20-goal-dedup-20261020/save.json"
	check(Store.write_from(shop.state, path) == OK and Store.write_from(shop.state, path) == OK, "Workspace-only save and backup include both production lines")
	var file := FileAccess.open(path, FileAccess.WRITE); file.store_string("{broken"); file.close()
	var restored := F.State.new()
	check(Store.read_into(restored, path) == "recovered", "Corrupt primary recovers actual v12 backup")
	check(Compare.equivalent(shop.state.workshop.to_data(), restored.workshop.to_data()) and shop.state.stock_protection.active == restored.stock_protection.active, "Backup retains auxiliary/main time, independent RNG and protection")
	before = M.data(shop.state)
	for page in panel.TAB_PAGES: panel.select_page(page); panel.refresh_gauges(0.016)
	panel.select_page(panel.REPORT); panel.select_page(panel.SETTINGS)
	check(Compare.equivalent(before, M.data(shop.state)), "All navigation, gauges, statistics and settings previews are pure")
	M.write_json("res://.verification/f20-goal-dedup-20261020/ui.json", {"checks": checks, "failures": failures, "passed": failures.is_empty()})
	panel.free(); shop.free()
	print("F20 UI %s %d checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)
