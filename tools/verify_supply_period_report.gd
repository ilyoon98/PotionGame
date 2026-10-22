extends SceneTree
const State = preload("res://scripts/shop_state.gd")
const Before = preload("res://.verification/f19-supplement-20261019/report/before-shop_state.gd")
const Content = preload("res://scripts/shop_content.gd")
const Late = preload("res://scripts/shop_late_investments.gd")
const F = preload("res://tests/late_investment_fixture.gd")
const M = preload("res://tests/contracts_fixture.gd")
const PROOF := "res://.verification/f19-supplement-20261019/report/"
var checks := 0
var failures: Array[String] = []
var evidence := {}

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		push_error(description)

func fixture() -> RefCounted:
	return F.completed_store(73129, "final", "support1", "normal")

func line(material: String, amount: int, source: String = "보급") -> String:
	return "%s %s +%d" % [Content.lookup("materials", material).name, source, amount]

func economic_data(state: RefCounted) -> Dictionary:
	var saved := F.data(state)
	saved.erase("report_supply")
	saved.contracts.erase("report_paid")
	for key in ["last_report_clock", "report_baseline", "report_sales", "report_materials", "report_started", "report_expeditions"]: saved.progression.erase(key)
	for key in ["report_returns", "report_rewards"]: saved.progression.expansion.erase(key)
	return saved

func grant_partial(state: RefCounted, material: String, space: int) -> Dictionary:
	M.fill_materials(state)
	if material == "starleaf": state.progression.rare_herbs -= space
	else: state.progression.expansion.materials[material] -= space
	state.late_investments.supply_tick(60.0)
	return state.late_investments.supply_boundary(state)

func test_period_and_readonly() -> void:
	var state := fixture()
	state.start_report_period()
	var received := grant_partial(state, "star_seed", 2)
	check(received.quantity == 2 and received.reserved_quantity == Late.SUPPLY_QUANTITIES[1], "Report fixture uses actual clipped receipt, not reserved supply")
	check(state.report_text().contains(line("star_seed", 2)) and not state.report_text().contains(line("star_seed", Late.SUPPLY_QUANTITIES[1])), "Period report labels the actual two received units as supply")
	var before := F.data(state)
	var text: String = state.report_text()
	for reopen in 20: check(state.report_text() == text and M.stable_equal(before, F.data(state)), "Reopening the period report cannot mutate, replay or pay rewards")
	var restored := State.new()
	check(restored.load_data(before) and restored.report_text() == text and M.stable_equal(before, F.data(restored)), "Period baseline and displayed receipt survive strict JSON save restore")
	var before_reset := economic_data(restored)
	var total_before: Dictionary = restored.late_investments.totals.duplicate()
	restored.start_report_period()
	check(restored.report_supply == total_before and not restored.report_text().contains(" 보급 +"), "A new period snapshots receipts and does not report old supply again")
	check(M.stable_equal(before_reset, economic_data(restored)), "Restarting the period changes only report metadata, preserving all economy, clocks, reservations and RNG")
	received = grant_partial(restored, "star_seed", 1)
	check(received.quantity == 1 and restored.report_text().contains(line("star_seed", 1)) and restored.late_investments.totals.star_seed == 3, "Only post-reset actual receipt enters the next period")
	evidence.period = {"actual_first_receipt": 2, "first_report": text, "second_report": restored.report_text(), "lifetime_supply": restored.late_investments.totals.duplicate(), "period_baseline": restored.report_supply.duplicate()}
	var multiple := fixture()
	for material in ["star_seed", "starleaf", "ash_sage", "dewgrass"]: grant_partial(multiple, material, 1)
	var multiple_text: String = multiple.report_text()
	var sorted_save := State.new()
	check(sorted_save.load_data(F.data(multiple)) and sorted_save.report_text() == multiple_text, "Multiple material lines retain catalog order across sorted JSON serialization")
	for material in ["star_seed", "starleaf", "ash_sage", "dewgrass"]: check(multiple_text.contains(line(material, 1)), "Every actual received material remains in the stable multi-source report")

func test_unpaid_and_source_separation() -> void:
	var state := fixture()
	state.start_report_period()
	state.late_investments.supply_tick(59.0)
	check(state.late_investments.supply_boundary(state).is_empty() and not state.report_text().contains(" 보급 +"), "An unfinished supply cycle is neither paid nor included in the report")
	M.fill_materials(state)
	state.late_investments.supply_tick(1.0)
	var received: Dictionary = state.late_investments.supply_boundary(state)
	check(received.quantity == 0 and state.late_investments.totals.is_empty() and not state.report_text().contains(" 보급 +"), "Full storage excludes discarded supply from period and lifetime totals")
	check(state.late_investments.supply_boundary(state).is_empty(), "Repeated full-period completion never creates deferred payment")
	var unavailable := State.new()
	unavailable.late_investments.stages.supply_support = 1
	unavailable.late_investments.supply = {"elapsed": 60.0, "duration": 60.0, "quantity": Late.SUPPLY_QUANTITIES[1]}
	received = unavailable.late_investments.supply_boundary(unavailable)
	check(received.quantity == 0 and unavailable.late_investments.totals.is_empty() and not unavailable.report_text().contains(" 보급 +"), "No eligible purchased-recipe source means no receipt and no reported supply")
	# Real same-boundary expedition delivery and support select separate storage.
	state = fixture()
	state.shop_open = false
	state.auto_purchase = false
	state.inventory.clear()
	for index in state.capacity(): state.inventory.append(false)
	state.stock = state.capacity()
	state.brew_active = true
	state.progression.active_recipe = false
	state.progression.batch_chance = 1.0
	state.progression.batch_success = true
	state.contracts.clear_batch()
	state.progression.rare_herbs = state.progression.expansion.special_capacity() - 1
	state.progression.expansion.materials.dewgrass = state.progression.expansion.special_capacity() - 2
	state.late_investments.supply.elapsed = 59.0
	var cycle: Dictionary = state.progression.expansion.cycles.forest_edge
	cycle.merge({"id": 1, "fee": 0, "paid": false, "running": true, "elapsed": 59.0, "duration": 60.0, "rewards": {"dewgrass": 2}, "mode": "normal", "rare_valid": false, "rare_recipe": "", "rare_success": false, "rare_attempt": 0}, true)
	state.start_report_period()
	var event: Dictionary = state.advance(1.0)
	var text: String = state.report_text()
	check(event.supplied == 1 and event.supply_events[0].material == "starleaf", "Real event ordering pays the expedition first and only one fitting support unit")
	check(text.contains(line("dewgrass", 2, "원정 보상")) and text.contains(line("starleaf", 1)), "Same-period expedition and support receipts keep their actual material, source and quantity")
	check(not text.contains(line("dewgrass", 2)) and not text.contains(line("starleaf", 1, "원정 보상")), "No source is misclassified or counted twice in the period material lines")
	evidence.sources = {"events": event.supply_events, "report": text, "expedition_rewards": state.progression.expansion.reward_totals.duplicate(), "actual_supply": state.late_investments.totals.duplicate()}

func test_compatibility_and_atomicity() -> void:
	var state := fixture()
	grant_partial(state, "star_seed", 2)
	var old_v11 := F.data(state)
	old_v11.erase("report_supply")
	var incoming := old_v11.duplicate(true)
	var restored := State.new()
	check(restored.load_data(old_v11), "Already-issued v11 without supply baseline remains loadable")
	check(restored.report_supply == restored.late_investments.totals and not restored.report_text().contains(" 보급 +"), "Missing old v11 baseline conservatively begins at saved cumulative receipts")
	check(old_v11 == incoming, "Baseline migration does not rewrite its input payload")
	check(M.stable_equal(economic_data(state), economic_data(restored)), "Old v11 migration preserves every economy field, supply cycle and RNG")
	grant_partial(restored, "star_seed", 1)
	check(restored.report_text().contains(line("star_seed", 1)), "After old v11 migration, only genuinely new supply is reported")
	var new_save := F.data(restored)
	var repeated := State.new()
	check(repeated.load_data(new_save) and repeated.report_text() == restored.report_text() and M.stable_equal(new_save, F.data(repeated)), "Migrated baseline persists across the next normal save and reload")
	for version in range(1, 11):
		var payload := F.data(State.new())
		payload.version = version
		payload.erase("late_investments")
		payload.erase("report_supply")
		if version < 10: payload.erase("contracts")
		if version < 5: payload.erase("progression")
		if version < 4: payload.erase("inventory")
		var destination := State.new()
		check(destination.load_data(payload) and destination.report_supply.is_empty() and destination.late_investments.totals.is_empty(), "Version%d migration keeps a zero supply baseline and no retroactive reward" % version)
	var good := F.data(restored)
	var malformed: Array = [null, [], {"star_seed": 0}, {"star_seed": -1}, {"star_seed": 0.5}, {"star_seed": true}, {"star_seed": "1"}, {"star_seed": INF}, {"star_seed": NAN}, {"star_seed": 4}, {"herb": 1}, {"dewgrass": 1}, {1: 1}]
	for invalid in malformed:
		var payload := good.duplicate(true)
		payload.report_supply = invalid
		var before := F.data(repeated)
		check(not repeated.load_data(payload) and M.stable_equal(before, F.data(repeated)), "Malformed baseline rejects before any economy/report/reservation/RNG mutation")
	for target in ["late", "contract"]:
		var payload := good.duplicate(true)
		if target == "late": payload.late_investments.supply.quantity = 999
		else: payload.contracts.batch.quantity = 4
		var before := F.data(repeated)
		check(not repeated.load_data(payload) and M.stable_equal(before, F.data(repeated)), "Valid period baseline cannot partially apply with malformed " + target)
	evidence.migration = {"old_v11_cumulative": old_v11.late_investments.totals, "migrated_baseline": new_save.report_supply, "only_new_receipt_report": restored.report_text(), "legacy_versions": "1..10", "missing_v11_policy": "Snapshot saved actual supply totals; unavailable historical period is not guessed or re-reported"}

func test_economy_equivalence() -> void:
	for combo in ["none", "support1", "both3"]:
		var current := F.completed_store(19337, "final", combo, "scarce_upper")
		var before := Before.new()
		check(before.load_data(F.data(current)), "Frozen pre-report model accepts equivalent " + combo)
		for seconds in [0.125, 59.875, 60.0, 300.0]:
			var actual: Dictionary = current.advance(seconds)
			var expected: Dictionary = before.advance(seconds)
			check(M.stable_equal(actual, expected), "Report metadata does not change actual arrival/batch/retail/contract events: " + combo)
			check(M.stable_equal(economic_data(current), economic_data(before)), "Report patch preserves complete economy, all inventories, reserved supply/batches and all RNG: " + combo)
		var snapshot := F.data(current)
		for reopen in 3: current.report_text()
		check(M.stable_equal(snapshot, F.data(current)), "Actual-play sequence report reopen is read-only: " + combo)

func _initialize() -> void:
	var isolated := OS.get_environment("APPDATA").replace("\\", "/")
	if DisplayServer.get_name() != "headless" or not isolated.contains("/.verification/f19-supplement-20261019/report/"):
		push_error("Supply period report verification requires isolated headless workspace data")
		quit(2)
		return
	test_period_and_readonly()
	test_unpaid_and_source_separation()
	test_compatibility_and_atomicity()
	test_economy_equivalence()
	evidence.merge({"checks": checks, "failures": failures, "passed": failures.is_empty(), "source_sha256": {"before_shop_state": FileAccess.get_sha256(PROOF + "before-shop_state.gd"), "shop_state": FileAccess.get_sha256("res://scripts/shop_state.gd"), "shop_late_investments": FileAccess.get_sha256("res://scripts/shop_late_investments.gd")}, "scope": "Only in-memory synthetic states, workspace JSON and isolated headless; no GUI/user saves/process access"})
	F.write_json(PROOF + "proof.json", evidence)
	print("SUPPLY PERIOD REPORT: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
