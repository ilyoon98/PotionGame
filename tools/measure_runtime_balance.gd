extends SceneTree
## Uses the actual game economy, not the independent planning simulator.
const State = preload("res://scripts/shop_state.gd")
const Compare = preload("res://tests/state_compare.gd")
const OUTPUT := "res://docs/balance/runtime-candidate-c.json"
var live_snapshot := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snapshot="): live_snapshot = arg.trim_prefix("--snapshot=")
	call_deferred("_run")


func totals() -> Dictionary:
	return {"brewed": 0, "sold": 0, "earned": 0, "bought": 0, "empty_sale_attempts": 0, "full_seconds": 0.0, "customer_wait_seconds": 0.0, "inventory_seconds": 0.0}


func summary(raw: Dictionary, seconds: float, state: RefCounted) -> Dictionary:
	var result := raw.duplicate()
	result["minutes"] = seconds / 60.0
	result["average_stock"] = raw["inventory_seconds"] / seconds
	result["average_stock_percent"] = 100.0 * result["average_stock"] / State.CAPACITY
	result["full_percent"] = 100.0 * raw["full_seconds"] / seconds
	result["waiting_percent"] = 100.0 * raw["customer_wait_seconds"] / seconds
	result["stock"] = state.stock
	result["gold"] = state.gold
	result["cauldron"] = state.level
	result["garden"] = state.garden_level
	result["sales_counter"] = state.sales_counter_level
	result["recipes"] = 2 + state.progression.owned.size()
	result["completed_regions"] = state.progression.completed_regions()
	return result


func purchase(state: RefCounted, policy: String) -> String:
	# One manual purchase per simulated return. No production-time auto upgrade.
	var order: Array = ["moon", "expedition", "purify", "agility", "garden", "cauldron", "sales_counter", "filter", "employee"]
	if policy == "equipment_first": order = ["garden", "cauldron", "sales_counter", "moon", "expedition", "purify", "agility", "filter", "employee"]
	if state.stock >= State.CAPACITY and state.sales_counter_reason().is_empty():
		state.upgrade_sales_counter()
		return "sales_counter"
	for id in order:
		if id == "garden":
			if state.upgrade_garden(): return id
		elif id == "cauldron":
			if state.upgrade(): return id
		elif id == "sales_counter":
			if state.upgrade_sales_counter(): return id
		elif state.purchase(id): return id
	return ""


func remaining(state: RefCounted) -> Dictionary:
	return {"recipes": State.Content.RECIPES.size() - state.progression.owned.size(), "cauldron_steps": State.MAX_LEVEL - state.level, "garden_steps": State.MAX_GARDEN_LEVEL - state.garden_level, "reachable_counter_steps": maxi(0, (3 if state.progression.completed_regions() > 0 else 2) - state.sales_counter_level), "forest_investigation": state.progression.completed_regions() == 0, "filter": not state.progression.filter_owned, "sales_employee": not state.progression.employee, "unimplemented": "27 new recipes, 7 regions, brewing assistant and other expansion tracks are outside this runtime measurement"}


func measure(state: RefCounted, label: String, duration: int, policy: String = "") -> Dictionary:
	var all := totals()
	var window := totals()
	var checkpoints := []
	var windows := []
	var purchases := []
	var interval := 900 if policy == "return_15m" else 30
	for second in duration:
		var event: Dictionary = state.advance(1.0)
		for key in all:
			all[key] += event[key]
			window[key] += event[key]
		if not policy.is_empty() and (second + 1) % interval == 0:
			var bought := purchase(state, policy)
			if not bought.is_empty(): purchases.append({"seconds": second + 1, "kind": bought})
		if (second + 1) % 300 == 0:
			var row := summary(window, 300.0, state)
			row["start_minute"] = (second + 1 - 300) / 60.0
			row["end_minute"] = (second + 1) / 60.0
			windows.append(row)
			window = totals()
		if second + 1 in [1800, 3600, 7200]: checkpoints.append(summary(all, second + 1, state))
	var result := {"label": label, "policy": policy, "checkpoints": checkpoints, "windows_5m": windows, "manual_purchases": purchases, "final": summary(all, duration, state), "remaining": remaining(state)}
	var longest := 0
	var run := 0
	for row in windows:
		run = run + 5 if row["average_stock_percent"] >= 90.0 and is_zero_approx(row["waiting_percent"]) else 0
		longest = maxi(longest, run)
	result["longest_backlog_minutes"] = longest
	return result


func clone(state: RefCounted) -> RefCounted:
	var copy := State.new()
	assert(copy.load_data(state.to_data()))
	return copy


func _run() -> void:
	var runs := []
	for seed in [73129, 19337, 9973]:
		for policy in ["recipe_first", "equipment_first", "return_15m"]:
			var state := State.new()
			state.progression.seed_value = seed
			runs.append(measure(state, "new_game_%s_%d" % [policy, seed], 7200, policy))
	if not live_snapshot.is_empty():
		var restored := State.new()
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(live_snapshot))
		assert(restored.load_data(data), "Existing player save must migrate without discarding progress")
		var old_progress := restored.to_data()
		runs.append(measure(restored, "existing_save", 7200, "recipe_first"))
		var roundtrip := State.new()
		assert(roundtrip.load_data(old_progress))
		assert(Compare.equivalent(roundtrip.to_data(), old_progress))
	var effects := []
	for kind in ["cauldron", "sales_counter"]:
		var before := State.new()
		before.gold = 100000
		before.level = 2 if kind == "cauldron" else 15
		before.garden_level = 12
		before.sales_counter_level = 2
		before.progression.owned = ["moon", "purify", "agility"]
		before.progression.rare_herbs = 12
		before.mushrooms = 6
		before.herbs = before.herb_capacity()
		before.progression.expedition_unlocked = true
		before.progression.expedition_active = true
		before.progression.expedition_count = 10
		before.stock = 0 if kind == "cauldron" else 12
		before.inventory_order()
		before.advance(1.0)
		var after := clone(before)
		assert(after.upgrade() if kind == "cauldron" else after.upgrade_sales_counter())
		var baseline := measure(before, kind + "_before", 600)
		var upgraded := measure(after, kind + "_after", 600)
		if kind == "cauldron":
			assert(upgraded["final"]["sold"] > baseline["final"]["sold"])
			assert(upgraded["final"]["waiting_percent"] < baseline["final"]["waiting_percent"])
		else:
			assert(upgraded["final"]["sold"] > baseline["final"]["sold"])
			assert(upgraded["final"]["full_percent"] < baseline["final"]["full_percent"])
		effects.append({"kind": kind, "before": baseline, "after": upgraded})
	var output := {"engine": Engine.get_version_info()["string"], "runtime": "shop_state.gd event-ordered economy", "revision": "candidate-c partial runtime", "scope": "5 potions, 1 forest region, sales counter reachable stages 1-3; no brewing assistant or new recipe effects", "measurement": "1-second calls; exact event durations integrated within advance; wait starts at failed purchase and ends at successful sale", "runs": runs, "isolated_upgrade_effects": effects}
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(output, "\t"))
	file.close()
	print("RUNTIME BALANCE PASS: ", runs.size(), " actual economy runs, 30/60/120 minute checkpoints, 5-minute windows, two paid isolated upgrade comparisons; ", OUTPUT)
	quit()
