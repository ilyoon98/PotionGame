extends SceneTree
## Supplement-only frozen price comparison. Never reads user:// or player data.
const Current = preload("res://.verification/f19-supplement-20261019/pricing/current210/model/tests/late_investment_fixture.gd")
const Candidate = preload("res://.verification/f19-supplement-20261019/pricing/candidate180/model/tests/late_investment_fixture.gd")
const DIR := "res://.verification/f19-supplement-20261019/pricing"
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
	for variant in ["current210", "candidate180"]:
		var fixture: GDScript = Current if variant == "current210" else Candidate
		var expected_costs := [150000, 300000, 600000] if variant == "current210" else [150000, 300000, 450000]
		for seed_value in [73129, 19337, 9973]:
			for cash in [700000, 775000, 850000]:
				var state: RefCounted = fixture.completed_store(seed_value, "final", "none", "normal")
				state.gold = cash
				state.progression.clock = 32400.0
				var initial := {"sales": state.total_sales_gold, "contracts": state.contracts.totals.paid, "materials": state.total_spent_materials, "fees": state.total_spent_expeditions, "manual": state.progression.totals.manual_spent}
				var purchases: Array = []
				fixture.purchase_late(state, purchases)
				check(Array(state.late_investments.COSTS) == expected_costs, "Frozen fixture uses its own approved or unapplied candidate prices")
				check(purchases.size() == 3 and state.late_investments.stages == {"supply_support": 2, "contract_batch": 1}, "700k..850k cannot immediately buy all six under either price schedule")
				check(state.gold == cash - 600000 and state.gold == fixture.cash_identity(state, cash, initial), "Actual three-stage cost is600k and cash ledger agrees")
				check(state.late_investments.totals.is_empty() and is_zero_approx(state.late_investments.supply.elapsed), "Synthetic9h returning clock grants no immediate or offline support")
				check(not state.late_investments.view(state, "contract_batch").can_buy, "Next bulk2 remains unaffordable at the actual remaining cash")
				var restored: RefCounted = fixture.clone(state)
				check(restored.gold == state.gold and restored.late_investments.to_data() == state.late_investments.to_data(), "Actual returning purchases restore exactly")
				cases.append({"variant": variant, "seed": seed_value, "starting_gold": cash, "synthetic_clock": 32400, "unapplied_candidate": variant == "candidate180", "total_six_stage_price": 2 * (expected_costs[0] + expected_costs[1] + expected_costs[2]), "purchases": purchases, "ending_gold": state.gold, "all_six_bought": false, "next_bulk2_cost": state.late_investments.view(state, "contract_batch").cost, "next_bulk2_shortage": state.late_investments.view(state, "contract_batch").cost - state.gold})
	Current.write_json(DIR.path_join("returning-comparison.json"), {"scope": "18 explicit9h returning synthetic fixtures, not actually reached natural-growth balances", "cases": cases, "checks": checks, "failures": failures, "passed": failures.is_empty()})
	print("%s F19 PRICE returning %d checks %d cases %d failures" % ["PASS" if failures.is_empty() else "FAIL", checks, cases.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
