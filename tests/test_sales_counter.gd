extends SceneTree
const State = preload("res://scripts/shop_state.gd")
const Compare = preload("res://tests/state_compare.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var candidate: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/balance/content-data-v1.json"))
	assert(candidate["revision"] == "candidate-c")
	for row in candidate["upgrades"]:
		if row["track"] != "sales_counter": continue
		var stage: int = int(row["stage"])
		assert(is_equal_approx(State.Content.SALES_COUNTER_SECONDS[stage], row["effect"]["customer_seconds"]))
		assert(State.Content.SALES_COUNTER_COSTS[stage - 1] == int(row["cost"]))
		assert(State.Content.SALES_COUNTER_REGIONS[stage - 1] == int(row["completed_regions"]))
	var state := State.new()
	assert(not state.upgrade_sales_counter())
	state.gold = 10000
	state.progression.owned = ["moon"]
	state.progression.rare_herbs = 3
	state.advance(4.0)
	var before: Dictionary = state.to_data()
	var fraction: float = state.customer_elapsed / state.customer_interval()
	assert(state.upgrade_sales_counter())
	var expected := before.duplicate(true)
	expected["gold"] -= 240
	expected["sales_counter_level"] = 1
	expected["customer_elapsed"] = fraction * 3.05
	expected["progression"]["totals"]["manual_spent"] += 240
	assert(Compare.equivalent(expected, state.to_data()), "Counter preserves visitor, reserved ingredients, success roll and brew timer")
	assert(state.upgrade_sales_counter() and state.sales_counter_level == 2)
	assert(not state.upgrade_sales_counter() and state.sales_counter_reason() == "지역 1곳 조사 필요")
	state.progression.expedition_unlocked = true
	state.progression.expedition_count = 9
	assert(state.progression.completed_regions() == 0 and not state.upgrade_sales_counter())
	state.progression.expedition_count = 10
	assert(state.upgrade_sales_counter() and is_equal_approx(state.customer_interval(), 2.4))
	assert(not state.upgrade_sales_counter() and state.sales_counter_reason() == "지역 2곳 조사 필요")
	State.Progression.Expeditions.ensure(state.progression)
	var restored := State.new()
	assert(restored.load_data(JSON.parse_string(JSON.stringify(state.to_data()))))
	# Normalize the per-region idle entries on a constructed test state.
	State.Progression.Expeditions.ensure(state.progression)
	assert(Compare.equivalent(restored.to_data(), state.to_data()))
	var snapshot := restored.to_data()
	for invalid_level in [-1, 0.5, 11, "1"]:
		var invalid := snapshot.duplicate(true)
		invalid["sales_counter_level"] = invalid_level
		assert(not restored.load_data(invalid) and Compare.equivalent(restored.to_data(), snapshot))
	var old := state.to_data()
	old["version"] = 5
	old.erase("sales_counter_level")
	old.erase("customer_waiting")
	assert(restored.load_data(JSON.parse_string(JSON.stringify(old))))
	assert(restored.sales_counter_level == 0 and restored.gold == state.gold and restored.progression.expedition_count == 10)
	for key in ["sales_counter_level", "customer_waiting"]:
		var invalid := snapshot.duplicate(true)
		invalid.erase(key)
		assert(not restored.load_data(invalid))
	var coarse := State.new()
	coarse.level = 15
	coarse.garden_level = 12
	coarse.sales_counter_level = 3
	var fine := State.new()
	assert(fine.load_data(coarse.to_data()))
	var totals: Dictionary = coarse.advance(180.0)
	var integral := {"full_seconds": 0.0, "customer_wait_seconds": 0.0, "inventory_seconds": 0.0}
	for index in 5400:
		var event: Dictionary = fine.advance(1.0 / 30.0)
		for key in integral: integral[key] += event[key]
	assert(Compare.equivalent(coarse.to_data(), fine.to_data()))
	for key in integral: assert(is_equal_approx(integral[key], totals[key]))
	var waiting := State.new()
	assert(is_zero_approx(waiting.advance(3.2)["customer_wait_seconds"]))
	assert(waiting.customer_waiting)
	assert(is_equal_approx(waiting.advance(1.0)["customer_wait_seconds"], 1.0))
	waiting.advance(2.2)
	assert(not waiting.customer_waiting and waiting.total_sold == 1)
	waiting.stock = State.CAPACITY
	waiting.inventory_order()
	assert(waiting.bottleneck_hint()["target"] == "sales_counter")
	waiting.sales_counter_level = 10
	assert(waiting.bottleneck_hint()["target"].is_empty())
	print("SALES COUNTER PASS: candidate C data, manual payment, locks, transaction and brew preservation, v5 migration, atomic rejection, exact waiting/full/inventory metrics, frame rate independence")
	quit()
