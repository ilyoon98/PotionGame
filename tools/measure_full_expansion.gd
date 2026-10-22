extends "res://tools/measure_runtime_balance.gd"
## Simulated manual shopping at return times; no game auto-upgrade behavior.


func totals() -> Dictionary:
	var result := super.totals()
	result["inventory_ratio_seconds"] = 0.0
	return result


func summary(raw: Dictionary, seconds: float, state: RefCounted) -> Dictionary:
	var result := super.summary(raw, seconds, state)
	result["average_stock_percent"] = 100.0 * raw["inventory_ratio_seconds"] / seconds
	result["stock_capacity"] = state.capacity()
	result["opened_regions"] = state.progression.expansion.regions.size() + int(state.progression.expedition_unlocked and not state.progression.expansion.regions.has("forest_edge"))
	result["investments"] = 0
	var seen := []
	for row in State.Content.DATA["upgrades"]:
		if not seen.has(row["track"]):
			seen.append(row["track"])
			result["investments"] += state.track_level(row["track"])
	result["employees"] = state.progression.expansion.staff.size() + int(state.progression.employee and not state.progression.expansion.staff.has("sales_assistant"))
	return result


func remaining(state: RefCounted) -> Dictionary:
	var count := 0
	for row in State.Content.DATA["upgrades"]:
		if int(row["stage"]) > state.track_level(row["track"]): count += 1
	return {"recipes": 30 - state.progression.owned.size(), "regions": 8 - state.progression.completed_regions(), "investments": count, "employees": 4 - state.progression.expansion.staff.size() - int(state.progression.employee and not state.progression.expansion.staff.has("sales_assistant"))}


func purchase(state: RefCounted, policy: String) -> String:
	var log := PackedStringArray()
	for decision in 160:
		var candidates := []
		var completed: int = state.progression.completed_regions()
		var reserve := 0
		for potion in State.Content.DATA["potions"]:
			var id: String = potion["id"]
			if potion["owned_at_start"] or state.purchase_reason(id) != "": continue
			var rank := 5.0 if potion["existing"] else 20.0 - float(potion["order"]) / 100.0
			candidates.append({"kind": id, "cost": state.purchase_cost(id), "rank": rank})
			if not potion["existing"]: reserve = state.purchase_cost(id) if reserve == 0 else mini(reserve, state.purchase_cost(id))
		for region in State.Content.DATA["regions"]:
			var id: String = region["id"]
			var kind := "expedition" if id == "forest_edge" else "region:" + id
			if state.purchase_reason(kind) != "": continue
			candidates.append({"kind": kind, "cost": state.purchase_cost(kind), "rank": 25.0 if policy == "equipment_first" else 8.0})
			reserve = state.purchase_cost(kind) if reserve == 0 else mini(reserve, state.purchase_cost(kind))
		for employee in State.Content.DATA["employees"]:
			var kind := "staff:" + str(employee["id"])
			if state.purchase_reason(kind) == "": candidates.append({"kind": kind, "cost": state.purchase_cost(kind), "rank": 23.0 if employee["id"] == "sales_assistant" else 34.0})
		var seen := []
		for row in State.Content.DATA["upgrades"]:
			var track: String = row["track"]
			if seen.has(track): continue
			seen.append(track)
			var kind := "upgrade:" + track
			if state.purchase_reason(kind) != "": continue
			var next: Dictionary = state.next_investment(track)
			var essential: bool = (track == "cauldron" and int(next["stage"]) <= mini(14, 4 + completed * 2)) or (track == "herb_pot" and int(next["stage"]) <= mini(11, 2 + completed))
			var rank := (2.0 if int(next["stage"]) <= 2 else 15.0) if essential else (27.0 if track == "sales_counter" and int(next["stage"]) <= 2 + completed else 40.0)
			if policy == "equipment_first": rank -= 12.0
			if not essential and state.gold - state.purchase_cost(kind) < reserve and policy != "equipment_first": continue
			candidates.append({"kind": kind, "cost": state.purchase_cost(kind), "rank": rank})
		if candidates.is_empty(): break
		candidates.sort_custom(func(a, b): return a["rank"] < b["rank"] or (is_equal_approx(a["rank"], b["rank"]) and a["cost"] < b["cost"]))
		assert(state.purchase(candidates[0]["kind"]))
		log.append(candidates[0]["kind"])
	return ",".join(log)


func _run() -> void:
	var runs := []
	for seed in [73129, 19337, 9973]:
		for policy in ["recipe_first", "equipment_first", "return_15m"]:
			var state := State.new()
			state.progression.seed_value = seed
			runs.append(measure(state, "full_%s_%d" % [policy, seed], 28800, policy))
			print("FULL RUNTIME PROGRESS: ", policy, " seed ", seed, " recipes ", state.progression.owned.size() + 2, " regions ", state.progression.completed_regions())
	if not live_snapshot.is_empty():
		var restored := State.new()
		assert(restored.load_data(JSON.parse_string(FileAccess.get_file_as_string(live_snapshot))))
		runs.append(measure(restored, "existing_save_expanded", 7200, "recipe_first"))
	var output := {"engine": Engine.get_version_info()["string"], "revision": "candidate-c full runtime", "scope": "32 potions, 11 materials, 8 regions, 125 investments, 4 employees", "measurement": "Actual event-ordered Godot economy, 1-second calls; exact duration integration; 5-minute windows; simulated shopping batches at 30-second or 15-minute returns", "runs": runs}
	var file := FileAccess.open("res://docs/balance/runtime-full-expansion.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(output, "\t"))
	file.close()
	print("FULL RUNTIME MEASUREMENT PASS: ", runs.size(), " runs; 30/60/120 minute checkpoints and 8-hour growth; docs/balance/runtime-full-expansion.json")
	quit()
