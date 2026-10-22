extends SceneTree
## F21 aging management rows: locked/unlocked upgrade buttons, purchase through
## the save-safe gateway with rollback, operation row progress. Isolated preview.
const Shop = preload("res://scripts/shop.gd")
const State = preload("res://scripts/shop_state.gd")
const Aging = preload("res://scripts/shop_aging.gd")
const M = preload("res://tests/contracts_fixture.gd")
const Compare = preload("res://tests/state_compare.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func _initialize() -> void:
	set_meta("isolated_preview", true); call_deferred("run")
func fail_save() -> bool: return false
func ok_save() -> bool: return true
func show(panel: Object, page: int) -> void:
	panel.select_page(page); panel.refresh()
	for i in 3: await process_frame
func run() -> void:
	check(DisplayServer.get_name() == "headless", "Headless controls only")
	var shop := Shop.new(); root.add_child(shop)
	await process_frame
	shop.set_process(false); shop.art.set_process(false); shop.open_management()
	var panel = shop.management; panel.set_process(false)
	shop.state = State.new(); shop.state.gold = 1000000; shop.state.set_shop_open(false)
	await show(panel, panel.UPGRADES)
	var open_row: Dictionary = panel.rows.aging_open
	check(open_row.panel.visible and open_row.button.disabled and open_row.button.text == "명성 %d 필요" % Aging.UNLOCK_REPUTATION and open_row.button.icon != null, "Aging rack locked by reputation with icon")
	await show(panel, panel.OPERATION)
	check(not panel.rows.aging.panel.visible, "Operation aging row hidden before opening")
	shop.state.progression.reputation = Aging.UNLOCK_REPUTATION
	await show(panel, panel.UPGRADES)
	check(not open_row.button.disabled and open_row.button.get_meta("next_level") == 1, "Unlocked rack is buyable")
	check(panel.rows.aging_barrels.button.disabled and panel.rows.aging_barrels.button.text == "숙성 선반 필요", "Barrels wait for the rack")
	# Failed save rolls back completely.
	shop.set_meta("aging_save_fixture", fail_save)
	var before: Dictionary = M.data(shop.state)
	check(not shop.perform_aging_action("open", 1).ok and Compare.equivalent(before, M.data(shop.state)), "Failed save restores gold, spend and aging")
	shop.set_meta("aging_save_fixture", ok_save)
	open_row.button.button_down.emit(); open_row.button.pressed.emit()
	await show(panel, panel.UPGRADES)
	check(shop.state.aging.opened() and shop.state.gold == 1000000 - 20000, "Panel button buys the rack once")
	check(open_row.completed and open_row.button.disabled and open_row.button.text == "최대 단계", "Rack row shows completed")
	check(panel.rows.aging_barrels.title.text == "숙성통 추가 · 0/3단계" and not panel.rows.aging_barrels.button.disabled, "Barrel row unlocked after the rack")
	# Operation row with a filled barrel.
	var s: RefCounted = shop.state
	s.inventory.clear()
	for i in 12: s.inventory.append(false)
	s.stock = 12; s.mana_stock = 0
	s._start_batch(); s.advance(60.0)
	await show(panel, panel.OPERATION)
	var row: Dictionary = panel.rows.aging
	check(row.panel.visible and row.detail.text == "숙성통 1/1 · 진열 0/12병", "Operation row shows barrels and shelf (%s)" % row.detail.text)
	check(row.work.box.visible and row.work.caption.text == "숙성" and row.work.count.text == "9분 00초", "Gauge shows time to maturity (%s)" % row.work.count.text)
	check(row.summary.get_parsed_text().begins_with("목표 숙성 · 판매가 ×3"), "Summary shows target stage and multiplier")
	before = M.data(s)
	for page in panel.TAB_PAGES: panel.select_page(page); panel.refresh_gauges(0.016)
	panel.select_page(panel.OPERATION)
	check(Compare.equivalent(before, M.data(s)), "Aging row refreshes never change the simulation")
	M.write_json("res://.verification/f21-aging-20261021/ui.json", {"checks": checks, "failures": failures, "passed": failures.is_empty()})
	panel.free(); shop.free()
	print("F21 AGING UI %s %d checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)
