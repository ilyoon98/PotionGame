extends SceneTree
const F = preload("res://tests/late_investment_fixture.gd")
const M = preload("res://tests/contracts_fixture.gd")
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func run() -> void:
	var cases := []
	for seed_value in [73129, 19337, 9973]:
		for cash in [700000, 775000, 850000]:
			var state := F.completed_store(seed_value, "final", "none", "normal")
			state.gold = cash
			state.progression.clock = 32400.0
			var initial := {"sales": state.total_sales_gold, "contracts": state.contracts.totals.paid, "materials": state.total_spent_materials, "fees": state.total_spent_expeditions, "manual": state.progression.totals.manual_spent}
			var purchases: Array = []
			F.purchase_late(state, purchases)
			check(purchases.size() == 3 and state.late_investments.stages.supply_support == 2 and state.late_investments.stages.contract_batch == 1, "700k..850k returning cash buys three real stages, not all six")
			check(state.gold == cash - 600000 and state.gold == F.cash_identity(state, cash, initial), "Returning cash minus actual150k+150k+300k equals both balance and manual-spent accounting")
			check(state.late_investments.totals.is_empty() and is_zero_approx(state.late_investments.supply.elapsed), "A9h clock never causes instant or offline support at the first purchase")
			var before := F.data(state)
			check(state.contracts.remaining_opportunities() == 0 and not state.contracts.train(state, 1).ok and M.stable_equal(before, F.data(state)), "Final-grade returning shop refuses useless training with zero debit")
			var goals := []
			for track in F.TRACKS: goals.append(state.late_investments.view(state, track))
			check(not state.late_investments.view(state, "contract_batch").can_buy and int(state.late_investments.view(state, "contract_batch").cost) - state.gold > 0, "Next bulk stage remains a concrete automatic-income savings goal")
			var restored := F.clone(state)
			check(M.stable_equal(restored.late_investments.to_data(), state.late_investments.to_data()) and restored.gold == state.gold, "Real returning purchases and the same reserved supply cycle survive restore")
			cases.append({"seed": seed_value, "starting_gold": cash, "synthetic_clock": 32400, "purchases": purchases, "ending_gold": state.gold, "next_goals": goals, "late_state": state.late_investments.to_data(), "training_view": state.contracts.training_view(state)})
	F.write_json("res://.verification/late-investment-f19-20261019/returning-synthetic.json", {"scope": "Nine explicit9h returning synthetic fixtures with700k/775k/850k cash; not inferred reached balances from a million-gold effect comparison", "cases": cases, "checks": checks, "failures": failures, "passed": failures.is_empty(), "source_sha256": {"late": FileAccess.get_sha256("res://scripts/shop_late_investments.gd"), "state": FileAccess.get_sha256("res://scripts/shop_state.gd"), "contracts": FileAccess.get_sha256("res://scripts/shop_contracts.gd")}})
	print("%s F19 returning synthetic %d checks %d failures" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
