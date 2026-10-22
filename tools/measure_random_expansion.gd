extends "res://tools/measure_parallel_expansion.gd"
## Real reward RNG and purchase paths; never load a player's save.
func totals() -> Dictionary:
	var result := super.totals()
	result["harvested"] = 0
	result["material_wait_seconds"] = 0.0
	return result
func summary(raw: Dictionary, seconds: float, state: RefCounted) -> Dictionary:
	var result := super.summary(raw, seconds, state)
	result["material_wait_percent"] = raw.material_wait_seconds / seconds * 100.0
	result["owned_recipe_shortfalls"] = {}
	for id in state.progression.owned:
		if state.brew_active and state.progression.active_recipe is String and state.progression.active_recipe == id: continue
		var missing := {}
		for material in State.Content.lookup("potions", id).ingredients:
			var lack: int = int(State.Content.lookup("potions", id).ingredients[material]) - state.material_count(material)
			if lack > 0: missing[material] = lack
		if not missing.is_empty(): result.owned_recipe_shortfalls[id] = missing
	result["shortfall_recipe_count"] = result.owned_recipe_shortfalls.size()
	result["manual_investment_total"] = state.progression.totals.manual_spent
	result["material_cost_total"] = state.total_spent_materials
	result["sales_total"] = state.total_sales_gold
	result["material_stock"] = {}
	for source in State.Content.DATA.materials: result.material_stock[source.id] = state.material_count(source.id)
	result["pending"] = state.progression.expansion.pending.duplicate(true)
	result["trip_supply"] = state.progression.expansion.reward_totals.duplicate(true)
	result["recipe_ids"] = state.progression.owned.duplicate()
	result["region_returns"] = {}
	for source in State.Content.DATA.regions: result.region_returns[source.id] = state.progression.expansion.region_returns(source.id, state.progression)
	result["stages"] = {}
	for source in State.Content.DATA.upgrades: result.stages[source.track] = state.track_level(source.track)
	return result
func _run() -> void:
	assert(DisplayServer.get_name() == "headless")
	var runs := []
	for seed in [73129, 19337, 9973]:
		for policy in ["recipe_first", "equipment_first", "return_15m"]:
			var state := State.new()
			state.progression.seed_value = seed
			var result := measure(state, "%s_%d" % [policy, seed], 28800, policy)
			var restored := State.new()
			assert(restored.load_data(JSON.parse_string(JSON.stringify(state.to_data()))))
			assert(Compare.equivalent(state.to_data(), restored.to_data()))
			assert(result.checkpoints.size() == 3 and result.windows_5m.size() == 96)
			runs.append(result)
			print("RANDOM MEASURE ", policy, " ", seed, " completion ", result.completion_minutes, " backlog ", result.longest_backlog_minutes)
	var file := FileAccess.open("res://docs/balance/runtime-random-expedition-8h.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"engine": Engine.get_version_info().string, "revision": "random material pools / special recipe acquisition excluded", "measurement": "Actual event-ordered shop_state; 3 seeds x recipe-first/equipment-first/15-minute manual checks; 30/60/120m and 8h; exact base-herb manufacture wait/full/customer durations; per-recipe ingredient shortfall snapshots excluding already-reserved active batch; ledger each 5m; JSON roundtrip", "runs": runs}, "\t"))
	print("RANDOM ECONOMY PASS: nine new eight-hour random reward runs; ledger, timings, checkpoints and restore")
	quit()
