extends "res://tools/measure_full_expansion.gd"
const Trips = preload("res://scripts/parallel_expeditions.gd")

func totals() -> Dictionary:
	var result := super.totals()
	result["expedition_spent"] = 0
	result["active_region_seconds"] = 0
	return result

func summary(raw: Dictionary, seconds: float, state: RefCounted) -> Dictionary:
	var result := super.summary(raw, seconds, state)
	result["active_regions"] = Trips.active_count(state.progression)
	result["expedition_spent_total"] = state.total_spent_expeditions
	result["average_active_regions"] = raw["active_region_seconds"] / seconds
	result["net_operating_income"] = raw["earned"] - raw["bought"] * State.MUSHROOM_COST - raw["expedition_spent"]
	return result

func measure(state: RefCounted, label: String, duration: int, policy: String = "") -> Dictionary:
	var all := totals()
	var window := totals()
	var checkpoints := []
	var windows := []
	var purchases := []
	var finished := {"recipes": null, "regions": null, "investments": null, "employees": null}
	var interval := 900 if policy == "return_15m" else 30
	var starting_gold: int = state.gold
	var starting_sales: int = state.total_sales_gold
	var starting_materials: int = state.total_spent_materials
	var starting_fees: int = state.total_spent_expeditions
	var starting_investments: int = state.progression.totals["manual_spent"]
	for second in duration:
		var previous_fees: int = state.total_spent_expeditions
		var event: Dictionary = state.advance(1.0)
		event["expedition_spent"] = state.total_spent_expeditions - previous_fees
		event["active_region_seconds"] = Trips.active_count(state.progression)
		for key in all:
			all[key] += event[key]
			window[key] += event[key]
		if (second + 1) % interval == 0:
			var bought := purchase(state, policy)
			if not bought.is_empty(): purchases.append({"seconds": second + 1, "kind": bought})
			var left := remaining(state)
			for key in finished:
				if finished[key] == null and left[key] == 0: finished[key] = (second + 1) / 60.0
		if (second + 1) % 300 == 0:
			var row := summary(window, 300.0, state)
			row["start_minute"] = (second + 1 - 300) / 60.0
			row["end_minute"] = (second + 1) / 60.0
			windows.append(row)
			window = totals()
			var ledger: int = starting_gold + state.total_sales_gold - starting_sales - (state.total_spent_materials - starting_materials) - (state.total_spent_expeditions - starting_fees) - (int(state.progression.totals["manual_spent"]) - starting_investments)
			assert(state.gold == ledger and state.gold >= 0, "Eight-hour ledger must reconcile every five minutes")
		if second + 1 in [1800, 3600, 7200]: checkpoints.append(summary(all, second + 1, state))
	var result := {"label": label, "policy": policy, "checkpoints": checkpoints, "windows_5m": windows, "manual_purchases": purchases, "completion_minutes": finished, "final": summary(all, duration, state), "remaining": remaining(state), "ledger_verified": true}
	var longest := 0
	var run := 0
	for row in windows:
		run = run + 5 if row["average_stock_percent"] >= 90.0 and is_zero_approx(row["waiting_percent"]) else 0
		longest = maxi(longest, run)
	result["longest_backlog_minutes"] = longest
	return result

func _run() -> void:
	var runs := []
	for seed in [73129, 19337, 9973]:
		for policy in ["recipe_first", "equipment_first", "return_15m"]:
			var state := State.new()
			state.progression.seed_value = seed
			var result := measure(state, "%s_%d" % [policy, seed], 28800, policy)
			runs.append(result)
			print("PARALLEL MEASURE ", policy, " ", seed, " completion ", result["completion_minutes"])
			assert(result["completion_minutes"]["regions"] == null or result["completion_minutes"]["regions"] > 120, "Two-hour full-growth completion fails the design target")
	var file := FileAccess.open("res://docs/balance/runtime-multi-expedition.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"engine": Engine.get_version_info()["string"], "revision": "candidate-d-multi-expedition actual runtime", "scope": "32 potions, 11 materials, 8 parallel paid regions, 125 investments, 4 employees", "measurement": "Actual shop_state event ordering; 1-second calls; 3 seeds x 3 simulated manual purchase policies; 30/60/120m + 5m windows + 8h completion; ledger verified every 5m", "runs": runs}, "\t"))
	file.close()
	print("PARALLEL ECONOMY PASS: 9 x 8-hour actual runtime runs and reconciled operating ledger")
	quit()
