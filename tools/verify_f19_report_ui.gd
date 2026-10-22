extends "res://tools/export_management_layout.gd"
## Isolated model/real Control proof. The unused period API is saved as text,
## never fabricated as a game screen. No player data, OS input or visible UI.
const Fixtures = preload("res://tools/f19_management_fixture.gd")
const F18 = preload("res://tests/contracts_fixture.gd")
const Content = preload("res://scripts/shop_content.gd")
const Status = preload("res://scripts/management_status.gd")
var checks := 0
var failures := 0
var evidence := []

func _initialize() -> void:
	assert(DisplayServer.get_name() == "headless")
	set_meta("isolated_preview", true)
	server = TextServerManager.get_primary_interface()
	output = "res://.verification/f19-supplement-20261019/ui"
	strict_export_bounds = false
	allow_text_clipping = true
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func write_text(name: String, value: String) -> void:
	var file := FileAccess.open(output.path_join(name), FileAccess.WRITE)
	assert(file != null)
	file.store_string(value)
	file.close()

func fresh() -> RefCounted:
	var state := Fixtures.completed(2, 3)
	Fixtures.buy_to(state, "supply_support", 1)
	F18.clear_materials(state)
	state.start_report_period()
	state.progression.report_started = "2026-10-19T12:00:00" # Explicit synthetic clock label.
	return state

func receive(state: RefCounted) -> Dictionary:
	state.late_investments.supply_tick(60.0)
	state.progression.clock += 60.0
	var event: Dictionary = state.late_investments.supply_boundary(state)
	check(int(event.get("quantity", -1)) == 7, "A real module boundary deposits the frozen first-stage seven items")
	return event

func supply_lines(text: String) -> PackedStringArray:
	var result := PackedStringArray()
	for line in text.split("\n"):
		if " 보급 +" in line: result.append(line)
	return result

func period_proof(id: String, state: RefCounted, expected: Dictionary) -> void:
	var before: Dictionary = state.to_data().duplicate(true)
	var text: String = state.report_text()
	var summary := Status.report_summary(state)
	check(summary.supply_materials.size() == expected.size(), "The pure period view keeps every supplied material, independently of the legacy three-item limit")
	var projected := {}
	for entry in summary.supply_materials:
		check(entry.source == "supply" and int(entry.count) > 0, "Each new view row explicitly identifies the supply source and a positive actual delta")
		projected[entry.id] = int(entry.count)
	check(Compare.equivalent(projected, expected), "The period view and period text expose identical actual supply receipts")
	check(summary.net == state.total_sales_gold - state.progression.report_sales - (state.total_spent_materials - state.progression.report_materials) - (state.total_spent_expeditions - state.progression.report_expeditions) + int(state.contracts.totals.paid) - state.contracts.report_paid, "Supply does not change the existing period cash calculation")
	for material in expected:
		var caption: String = Content.lookup("materials", material).name
		check(text.count(caption + " 보급 +" + str(expected[material])) == 1, "Every actual material appears once with its own supply source and exact amount")
	check(supply_lines(text).size() == expected.size(), "Zero or historical supply is not invented in period text")
	check(state.report_text() == text and Compare.equivalent(before, state.to_data()), "Repeated period queries do not grant items or change State/RNG")
	var restored := State.new()
	check(restored.load_data(F18.data(state)), "The current v11 fixture roundtrips through strict validation")
	check(Compare.equivalent(before, restored.to_data()) and restored.report_text() == text and Compare.equivalent(summary, Status.report_summary(restored)), "Saved period baseline and both pure result projections restore unchanged")
	write_text("report-" + id + ".txt", text)
	evidence.append({"id": id, "period_api_visible_in_runtime": false, "report_text": text, "report_summary": summary, "expected_supply": expected, "actual_supply_totals": state.late_investments.totals.duplicate(), "report_supply": state.report_supply.duplicate(), "expedition_totals": state.progression.expansion.reward_totals.duplicate(), "materials": F18.materials(state), "state_roundtrip_equal": Compare.equivalent(before, restored.to_data())})

func same_material_arrival(state: RefCounted) -> void:
	var p: RefCounted = state.progression
	var e: RefCounted = p.expansion
	for cycle in e.cycles.values(): cycle.running = false
	var cycle: Dictionary = e.cycles.forest_edge
	cycle.merge({"id": int(cycle.id) + 1, "fee": 0, "paid": false, "running": true, "elapsed": 70.0, "duration": 70.0, "rewards": {"starleaf": 3}, "mode": "normal", "rare_valid": false, "rare_recipe": "", "rare_attempt": 0, "rare_success": false}, true)
	# Saved immutable return fixture; no new random reward or departure can occur.
	state.gold = 0
	Trips.tick(state, 0.0)
	check(int(e.reward_totals.get("starleaf", 0)) == 3 and state.material_count("starleaf") == 10, "An actual expedition return deposits three separately from the seven supplied items")
	check(state.report_text().contains("별잎 원정 보상 +3") and state.report_text().contains("별잎 보급 +7"), "The same material retains distinct expedition and supply rows")
	var summary := Status.report_summary(state)
	check(summary.materials == [{"id": "starleaf", "count": 3}] and summary.supply_materials == [{"id": "starleaf", "count": 7, "source": "supply"}], "The legacy expedition row is never inflated or merged with the separate supply row")

func migration_proof(state: RefCounted) -> void:
	var original: Dictionary = F18.data(state)
	var old_v11: Dictionary = original.duplicate(true)
	old_v11.erase("report_supply")
	var restored := State.new()
	check(int(old_v11.version) == 11 and restored.load_data(old_v11), "Previously written v11 without the optional baseline is accepted")
	var expected: Dictionary = original.duplicate(true)
	expected.report_supply = original.late_investments.totals.duplicate()
	check(Compare.equivalent(expected, restored.to_data()), "Old v11 migration changes only the missing baseline to actual historical receipts")
	check(supply_lines(restored.report_text()).is_empty(), "Migration does not assign old receipts to an unknowable period")
	var next: Dictionary = receive(restored)
	var expected_period := {str(next.material): int(next.quantity)}
	period_proof("migrated-v11-next-period", restored, expected_period)
	var after: Dictionary = restored.to_data().duplicate(true)
	var materials_before := F18.materials(restored)
	var old_report: String = restored.report_text()
	restored.start_report_period()
	check(Compare.equivalent(restored.report_supply, restored.late_investments.totals) and supply_lines(restored.report_text()).is_empty(), "A deliberate period restart snapshots the current actual receipts")
	check(F18.materials(restored) == materials_before and Compare.equivalent(after.late_investments, restored.to_data().late_investments) and restored.gold == int(after.gold) and restored.progression.seed_value == int(after.progression.seed_value), "Period restart does not change physical supply, cumulative ledger, cash or RNG")
	check(Status.report_summary(restored).supply_materials.is_empty(), "The second period projection also respects the explicit restarted baseline")
	write_text("report-v11-before-restart.txt", old_report)
	write_text("report-v11-after-restart.txt", restored.report_text())
	evidence.append({"id": "old-v11-migration", "old_version": old_v11.version, "baseline_was_missing": true, "only_baseline_added": Compare.equivalent(expected, restored_before_restart(old_v11)), "new_receipts_only": expected_period, "period_restart_supply_lines": supply_lines(restored.report_text()).size()})

func restored_before_restart(data: Dictionary) -> Dictionary:
	var copy := State.new()
	assert(copy.load_data(data))
	return copy.to_data()

func runtime_proof(state: RefCounted, page: int, target: String, id: String, label: String) -> Dictionary:
	shop.state = state
	var identity := state.get_instance_id()
	panel.close_contracts()
	for row in panel.rows.values(): row.toggle.set_pressed(false)
	panel.size = Vector2i(520, 800)
	panel.select_page(page)
	if not target.is_empty(): panel.rows[target].toggle.set_pressed(true)
	panel.refresh()
	for frame in 4: await process_frame
	if not target.is_empty():
		panel.scroll.ensure_control_visible(panel.rows[target].panel)
		if target.begins_with("late:"): panel.scroll.scroll_vertical = maxi(0, int(panel.rows[target].panel.position.y) - 28)
	for frame in 3: await process_frame
	var selected: int = panel.selected
	var selected_scroll: int = panel.scroll.scroll_vertical
	var before: Dictionary = state.to_data().duplicate(true)
	var report: String = state.report_text()
	var original_window := panel.get_instance_id()
	for repeat in 3:
		panel.close_button.pressed.emit()
		check(not panel.visible, "Existing close action hides the same management panel")
		shop.open_management()
		for frame in 3: await process_frame
		check(panel.visible and panel.get_instance_id() == original_window and shop.state.get_instance_id() == identity, "Reopen reuses the same Window and model instance")
		check(panel.selected == selected and panel.scroll.scroll_vertical == selected_scroll and (target.is_empty() or panel.rows[target].toggle.button_pressed), "Reopen preserves the original page, scroll and folded detail state")
	check(Compare.equivalent(before, state.to_data()) and state.report_text() == report, "Opening, closing and rendering retain the complete state, supply baseline and RNG")
	check(panel.tabs.size() == 7 and panel.pages.size() == 8 and panel.statistics_values.size() == 12, "Existing seven tabs and twelve cumulative statistics remain unchanged; no invented period page")
	commands = []
	nodes = []
	var boundary: Control = panel.get_child(0)
	export_node(boundary, boundary, Rect2(Vector2.ZERO, Vector2(panel.size)))
	check(Compare.equivalent(before, state.to_data()), "Actual Control/TextServer extraction is read-only")
	return {"id": id, "label": label, "size": vector(Vector2(panel.size)), "commands": commands.duplicate(true), "nodes": nodes.duplicate(true), "background": "1d242bff"}

func run() -> void:
	assert(DirAccess.make_dir_recursive_absolute(output.path_join("textures")) == OK)
	shop = Shop.new()
	root.add_child(shop)
	shop.set_process(false)
	if shop.art != null: shop.art.set_process(false)
	shop.open_management()
	panel = shop.management
	panel.set_process(false)
	var one := fresh()
	var one_event: Dictionary = receive(one)
	period_proof("one-cycle-seven-items", one, {str(one_event.material): 7})
	var seven := fresh()
	var receipts := {}
	for cycle in 7:
		var event: Dictionary = receive(seven)
		receipts[event.material] = int(receipts.get(event.material, 0)) + int(event.quantity)
	check(receipts.size() == 7, "Seven real supply cycles visit seven distinct equally empty eligible materials")
	period_proof("seven-materials", seven, receipts)
	var projection := State.new()
	check(projection.load_data(F18.data(seven)), "A cloned projection fixture retains the actual seven-material supply ledger")
	# Display-only legacy ledger fixture checks its pre-existing top-three policy.
	for material in receipts: projection.progression.expansion.reward_totals[material] = 2
	var projected_before: Dictionary = projection.to_data().duplicate(true)
	var projected_summary := Status.report_summary(projection)
	check(projected_summary.materials.size() == 3 and projected_summary.supply_materials.size() == 7, "Legacy materials remain top-three while supply retains all seven types")
	check(Compare.equivalent(projected_before, projection.to_data()), "All-source period projections remain read-only")
	var zero := fresh()
	F18.fill_materials(zero)
	zero.late_investments.supply_tick(60.0)
	zero.progression.clock += 60.0
	var zero_event: Dictionary = zero.late_investments.supply_boundary(zero)
	check(int(zero_event.quantity) == 0 and zero.late_investments.totals.is_empty(), "A full-storage boundary neither records supply nor accrues a debt")
	period_proof("zero-arrivals", zero, {})
	var same := fresh()
	receive(same)
	same_material_arrival(same)
	period_proof("same-material-expedition", same, {"starleaf": 7})
	migration_proof(seven)
	var cases := []
	cases.append(await runtime_proof(one, panel.UPGRADES, "late:supply_support", "one-cycle-detail", "실제1주기7개 · 기존 투자 상세"))
	cases.append(await runtime_proof(seven, panel.UPGRADES, "late:supply_support", "seven-materials-detail", "7종 실제누적49개 · 기존 투자 상세"))
	cases.append(await runtime_proof(seven, panel.HERBS, "supply_support", "seven-materials-herbs", "약초 · 동일한 실제 보급 누적값"))
	cases.append(await runtime_proof(seven, panel.OPERATION, "gather_supply_support", "seven-materials-operation", "가게운영 · 동일 보급·재열기 보존"))
	cases.append(await runtime_proof(zero, panel.HERBS, "supply_support", "zero-arrivals-herbs", "보관 가득 · 실제 입고0개"))
	cases.append(await runtime_proof(same, panel.HERBS, "supply_support", "same-material-herbs", "별잎 보급7+원정3 · 실제 보유10"))
	cases.append(await runtime_proof(same, panel.REPORT, "", "same-material-statistics", "기존12누적통계 · 기간결과UI는 없음"))
	write_text("management.json", JSON.stringify({"verification": "Isolated actual Controls/TextServer file composites, not desktop screenshots; report_text has no runtime UI caller", "font": ProjectSettings.globalize_path(FONT.resource_path), "palette": "sage", "cases": cases}, "\t"))
	write_text("proof.json", JSON.stringify({"checks": checks, "failures": failures, "runtime_report_text_caller": false, "runtime_statistics": "12 cumulative values; no period text", "file_cases": cases.size(), "evidence": evidence}, "\t"))
	panel.free()
	shop.free()
	print("F19 REPORT UI ", "PASS" if failures == 0 else "FAIL", ": ", checks, " isolated checks; seven material/zero/shared-expedition source text, v11 migration and repeated existing-management reopen preserve complete State/RNG; ", cases.size(), " actual Controls/TextServer layouts; report API remains explicitly separate, no GUI/player data")
	quit(1 if failures > 0 else 0)
