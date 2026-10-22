extends SceneTree
const State = preload("res://scripts/shop_state.gd")
const Late = preload("res://scripts/shop_late_investments.gd")
const OldLate = preload("res://.verification/f19-adopted180-20261019/before/shop_late_investments.gd")
const OldState = preload("res://.verification/f19-adopted180-20261019/core/old-price-state-fixture.gd")
const Content = preload("res://scripts/shop_content.gd")
const F = preload("res://tests/late_investment_fixture.gd")
const M = preload("res://tests/contracts_fixture.gd")
const PROOF := "res://.verification/f19-adopted180-20261019/core/"
var checks := 0
var failures: Array[String] = []
var evidence := {}

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		push_error(description)

func eligible(old_prices: bool = false) -> RefCounted:
	var state := M.completed(19337)
	if old_prices:
		var previous := OldState.new()
		check(previous.load_data(F.data(state)), "Frozen-price State fixture accepts equivalent fully grown setup")
		state = previous
	state.gold = 5000000 # Explicit synthetic setup money, never claimed as growth.
	check(state.contracts.train(state, 1).ok, "Historical training stage one is purchased through its actual API")
	state.contracts.seed = 1
	var offer: Dictionary = F.option(state, "caravan", "payment")
	check(state.contracts.negotiate(state, "caravan", offer.token).get("success", false), "Historical nonfinal negotiation has a real frozen successful judgement")
	check(state.contracts.train(state, 2).ok, "Later historical training cannot reroll the earlier judgement")
	check(state.contracts.accept(state, "caravan", offer.token).ok, "Historical successful condition is actually accepted")
	for id in ["academy", "grove"]: check(state.contracts.accept(state, id, F.option(state, id, "basic").token).ok, "Other historical agreements are actually accepted")
	for partner in state.contracts.PARTNERS:
		while state.contracts.grade(partner.id) < 4: F.synthetic_round(state, partner.id)
	var log: Array = []
	F.negotiate_returns(state, "payment", log)
	for partner in state.contracts.PARTNERS: F.synthetic_round(state, partner.id)
	M.fill_materials(state)
	return state

func test_new_purchases() -> void:
	var current_source := FileAccess.get_file_as_string("res://scripts/shop_state.gd")
	var previous_source := FileAccess.get_file_as_string(PROOF + "old-price-state-fixture.gd")
	check(previous_source.replace("res://.verification/f19-adopted180-20261019/before/shop_late_investments.gd", "res://scripts/shop_late_investments.gd") == current_source, "Frozen-price comparison changes only the Late module preload, with every State logic byte preserved")
	check(Late.COSTS == [150000, 300000, 450000] and OldLate.COSTS == [150000, 300000, 600000], "Only the newly adopted third-stage price differs from the frozen production module")
	check(Late.SUPPLY_QUANTITIES == OldLate.SUPPLY_QUANTITIES and Late.SUPPLY_SECONDS == OldLate.SUPPLY_SECONDS, "Price adoption preserves7/12/24 quantity and60-second periods")
	for track in Late.TRACKS:
		var state := eligible()
		state.gold = 900000
		var spent_before: int = state.progression.totals.manual_spent
		for stage in range(1, 4):
			var before_gold: int = state.gold
			var view: Dictionary = state.late_investments.view(state, track)
			var actual: Dictionary = state.late_investments.purchase(state, track, stage)
			check(actual.ok and view.cost == Late.COSTS[stage - 1] and before_gold - state.gold == Late.COSTS[stage - 1], "Each displayed stage pays precisely15/30/45만: " + track)
			var before := F.data(state)
			check(not state.late_investments.purchase(state, track, stage).ok and M.stable_equal(before, F.data(state)), "Repeated stage token never charges another payment: " + track)
		check(state.gold == 0 and state.progression.totals.manual_spent - spent_before == 900000, "Each independent track costs exactly900000 actual gold")
		var other := "contract_batch" if track == "supply_support" else "supply_support"
		check(state.late_investments.stages[other] == 0, "One complete track requires no purchase in the other track")
	var combined := eligible()
	combined.gold = 1800000
	var combined_before: int = combined.progression.totals.manual_spent
	var ledger: Array = []
	for track in Late.TRACKS:
		for stage in range(1, 4):
			var before: int = combined.gold
			var result: Dictionary = combined.late_investments.purchase(combined, track, stage)
			check(result.ok, "All six adopted stages can be bought with the exact combined budget")
			ledger.append({"track": track, "stage": stage, "paid": before - combined.gold, "gold_after": combined.gold})
	check(combined.gold == 0 and combined.progression.totals.manual_spent - combined_before == 1800000, "Six actual one-time payments reconcile to1800000 without refunds or repetition")
	var shortage := eligible()
	shortage.late_investments.purchase(shortage, "supply_support", 1)
	shortage.late_investments.purchase(shortage, "supply_support", 2)
	shortage.gold = 449999
	var before := F.data(shortage)
	check(shortage.late_investments.view(shortage, "supply_support").cost == 450000 and shortage.late_investments.view(shortage, "supply_support").reason == "1 G 부족", "Unowned third stage shows the adopted price and exact shortage")
	check(not shortage.late_investments.purchase(shortage, "supply_support", 3).ok and M.stable_equal(before, F.data(shortage)), "Insufficient third-stage gold causes no partial payment")
	evidence.new_purchase_ledger = ledger

func old_owned_fixture() -> RefCounted:
	var state := eligible(true)
	state.gold = 3000000
	var before: int = state.gold
	for track in OldLate.TRACKS:
		for stage in range(1, 4): check(state.late_investments.purchase(state, track, stage).ok, "Frozen old production actually pays the former third-stage600000 price")
	check(before - state.gold == 2100000, "Old saved investment spending was actually2100000, not recomputed using the new table")
	state.progression.expansion.materials.star_seed -= 2
	state.late_investments.supply_tick(60.0)
	check(state.late_investments.supply_boundary(state).quantity == 2, "Old owned fixture receives a real partial supply")
	state.start_report_period()
	state.progression.expansion.materials.star_seed -= 3
	state.late_investments.supply_tick(60.0)
	check(state.late_investments.supply_boundary(state).quantity == 3, "Post-baseline old fixture receives only actual additional supply")
	state.late_investments.supply_tick(13.25)
	state.contracts.ordinary_batches = 4
	state._start_batch()
	check(state.contracts.batch.get("purpose", "") == "contract" and state.contracts.batch.quantity == 4, "Old-price save includes an actual reserved four-bottle batch")
	state.brew_elapsed = state.brew_duration() * 0.375
	return state

func test_old_save_compatibility_and_effects() -> void:
	var previous := old_owned_fixture()
	var payload := F.data(previous)
	var restored := State.new()
	check(restored.load_data(payload) and M.stable_equal(payload, F.data(restored)), "Old600000-owned v11 restores every saved field with no retroactive repricing or refund")
	check(restored.progression.totals.manual_spent == 2128000 and restored.gold == previous.gold, "Actual2100000 investment plus28000 historical training spending and cash remain untouched")
	check(restored.report_supply == {"star_seed": 2} and restored.report_text().contains("보급 +3"), "Owned old-price v11 retains its period supply baseline and only subsequent actual receipts")
	check(restored.contracts.partners.caravan.history["1"].training == 1 and is_equal_approx(restored.contracts.partners.caravan.history["1"].chance, 0.7) and restored.contracts.training == 2, "Historical frozen negotiation chance and later training stage survive adoption")
	check(M.stable_equal(restored.late_investments.supply, previous.late_investments.supply) and M.stable_equal(restored.contracts.batch, previous.contracts.batch) and restored.progression.seed_value == previous.progression.seed_value, "Old reserved supply timer, batch quantity/time/judgement and production RNG are preserved")
	var before_repeat := F.data(restored)
	for track in Late.TRACKS: check(not restored.late_investments.purchase(restored, track, 3).ok and M.stable_equal(before_repeat, F.data(restored)), "Previously owned old third stage cannot charge the new price or refund the difference")
	var missing_baseline := payload.duplicate(true)
	missing_baseline.erase("report_supply")
	var migrated := State.new()
	check(migrated.load_data(missing_baseline), "Already-issued old-price v11 without period supply metadata remains valid")
	check(migrated.report_supply == migrated.late_investments.totals and not migrated.report_text().contains(" 보급 +"), "Unknown old period uses saved actual totals as its new baseline without guessed historical rewards")
	var normalized := F.data(migrated)
	normalized.erase("report_supply")
	check(M.stable_equal(normalized, missing_baseline), "Missing period baseline migration still preserves cash, spending, stages, timers, batches, histories and all RNG")
	var again := State.new()
	check(again.load_data(F.data(migrated)) and M.stable_equal(F.data(again), F.data(migrated)), "Old-price baseline migration survives the next normal JSON roundtrip")
	# Both versions resume the same save. The transient batch-event queue is
	# intentionally not persisted, so neither side replays the old start event.
	var old_resumed := OldState.new()
	check(old_resumed.load_data(payload), "Frozen-price model resumes the same snapshot without replaying its transient start queue")
	previous = old_resumed
	for seconds in [0.125, 59.875, 60.0, 180.0]:
		var old_event: Dictionary = previous.advance(seconds)
		var adopted_event: Dictionary = restored.advance(seconds)
		check(M.stable_equal(old_event, adopted_event), "Same owned stages emit identical real production/supply/contract events under old and adopted prices")
		check(M.stable_equal(F.data(previous), F.data(restored)), "Price-only adoption preserves full actual advance/economy/reservations/RNG at equal owned stages")
	evidence.compatibility = {"old_paid_investments": 2100000, "old_actual_manual_spent": payload.progression.totals.manual_spent, "old_cash": payload.gold, "old_supply_cycle": payload.late_investments.supply, "old_active_batch": payload.contracts.batch, "old_report_supply": payload.report_supply, "same_stage_advance_seconds": 300.0, "missing_baseline_policy": "Snapshot saved cumulative receipts, no historical refund/reward inference"}
	F.write_json(PROOF + "old600-owned-v11.json", payload)
	F.write_json(PROOF + "old600-owned-v11-no-period-baseline.json", missing_baseline)

func _initialize() -> void:
	var isolated := OS.get_environment("APPDATA").replace("\\", "/")
	if DisplayServer.get_name() != "headless" or not isolated.contains("/.verification/f19-adopted180-20261019/"):
		push_error("Adopted price verification requires isolated headless workspace data")
		quit(2)
		return
	test_new_purchases()
	test_old_save_compatibility_and_effects()
	evidence.merge({"checks": checks, "failures": failures, "passed": failures.is_empty(), "old_costs": OldLate.COSTS, "adopted_costs": Late.COSTS, "old_module_sha256": FileAccess.get_sha256("res://.verification/f19-adopted180-20261019/before/shop_late_investments.gd"), "adopted_module_sha256": FileAccess.get_sha256("res://scripts/shop_late_investments.gd"), "state_sha256": FileAccess.get_sha256("res://scripts/shop_state.gd"), "scope": "Synthetic in-memory states, real purchase APIs and workspace JSON; no GUI/player saves/process access"})
	F.write_json(PROOF + "compatibility.json", evidence)
	print("ADOPTED LATE PRICES: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
