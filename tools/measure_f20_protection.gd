extends SceneTree
const Baseline = preload("res://.verification/f20-20261020/baseline/metrics_state.gd")
const Frozen = preload("res://.verification/f20-20261020/baseline/scripts/shop_state.gd")
const Protected = preload("res://.verification/f20-20261020/A/source/scripts/shop_state.gd")
const F = preload("res://tests/late_investment_fixture.gd")
const M = preload("res://tests/contracts_fixture.gd")
const Compare = preload("res://tests/state_compare.gd")
class Off extends "res://.verification/f20-20261020/baseline/scripts/shop_contracts.gd":
	func candidate(_state: RefCounted) -> Dictionary: return {}
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var rows := []
	for seed_value in [73129, 19337, 9973]:
		for scenario in ["normal", "scarce_upper"]:
			var initial: Dictionary = M.data(F.completed_store(seed_value, "final", "both3", scenario))
			initial.version = 11; initial.erase("stock_protection")
			for mode in ["original", "protected", "contracts_off"]:
				var state: RefCounted = Protected.new() if mode == "protected" else Baseline.new()
				assert(state.load_data(initial))
				if mode == "contracts_off":
					var off := Off.new()
					assert(off.load_data(initial.contracts, state.progression, false, false, state.contract_batch_context()))
					state.contracts = off
				var original: RefCounted = Frozen.new()
				if mode == "original": assert(original.load_data(initial))
				var zero := 0.0; var wait := 0.0; var average := 0.0
				var m_wait := 0.0; var dispatched := []; var partners := {}
				for i in 240:
					var event: Dictionary = state.advance(30)
					zero += float(event.zero_stock_seconds); wait += float(event.customer_wait_seconds)
					average += float(event.inventory_seconds); m_wait += float(event.material_wait_seconds)
					for item in event.contract_events:
						partners[item.partner] = true
						if item.paid > 0: dispatched.append({"time_upper": (i+1)*30, "partner": item.partner, "paid": item.paid})
					if mode == "original":
						original.advance(30)
						assert(Compare.equivalent(original.to_data(), state.to_data()), "Metrics-only instrumentation preserves entire v11 state")
				var row := {"seed": seed_value, "scenario": scenario, "mode": mode, "seconds": 7200, "zero_stock_seconds": zero, "customer_wait_seconds": wait, "material_wait_seconds": m_wait, "mean_stock": average/7200, "cash": state.gold, "retail_revenue": state.total_sales_gold-int(initial.total_sales_gold), "sold": state.total_sold-int(initial.total_sold), "contract_paid": int(state.contracts.totals.paid)-int(initial.contracts.totals.paid), "shipped": int(state.contracts.totals.shipped)-int(initial.contracts.totals.shipped), "materials": state.total_spent_materials-int(initial.total_spent_materials), "fees": state.total_spent_expeditions-int(initial.total_spent_expeditions), "net": state.gold-int(initial.gold), "unpaid": F.unpaid_value(state), "partners": partners, "settlements": dispatched}
				rows.append(row)
				M.write_json("res://.verification/f20-20261020/A/effects/%d-%s-%s.json" % [seed_value, scenario, mode], row)
				print("A EFFECT %d %s %s net%d retail%d shipped%d zero%.1f" % [seed_value, scenario, mode, row.net, row.retail_revenue, row.shipped, zero])
				await process_frame
	M.write_json("res://.verification/f20-20261020/A/effects-summary.json", {"passed": true, "cases": rows})
	print("F20-A EFFECT PASS18 cases + original instrumentation state equivalence")
	quit()
