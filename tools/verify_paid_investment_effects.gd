extends SceneTree
const State = preload("res://scripts/shop_state.gd")
const Compare = preload("res://tests/state_compare.gd")

func _initialize() -> void: call_deferred("run")

func fixture() -> RefCounted:
	var s := State.new()
	s.gold = 1000000
	s.garden_level = 12
	s.herbs = s.herb_capacity()
	s.mushrooms = 6
	s.progression.owned = ["moon", "purify", "agility"]
	s.progression.rare_herbs = 12
	s.progression.reputation = 10000
	s.progression.expedition_unlocked = true
	s.progression.expedition_count = 10
	s.progression.expansion.materials["dewgrass"] = 12
	State.Progression.Expeditions.ensure(s.progression)
	return s

func clone(s: RefCounted) -> RefCounted:
	var copy := State.new()
	assert(copy.load_data(s.to_data()))
	return copy

func outcome(s: RefCounted, seconds: float) -> Dictionary:
	var event: Dictionary = s.advance(seconds)
	return {"sold": event["sold"], "brewed": event["brewed"], "waiting_percent": 100.0 * event["customer_wait_seconds"] / seconds, "full_percent": 100.0 * event["full_seconds"] / seconds}

func run() -> void:
	var results := []
	for kind in ["cauldron", "sales_counter"]:
		var before := fixture()
		before.level = 2 if kind == "cauldron" else 15
		before.sales_counter_level = 2
		before.stock = 0 if kind == "cauldron" else 12
		before.inventory_order()
		before.advance(0.2)
		var after := clone(before)
		var old_gold: int = after.gold
		var old_cost: int = after.upgrade_cost() if kind == "cauldron" else after.sales_counter_cost()
		var old_fraction: float = after.brew_elapsed / after.brew_duration()
		var roll: bool = after.progression.batch_success
		var seed: int = after.progression.seed_value
		assert(after.upgrade() if kind == "cauldron" else after.upgrade_sales_counter())
		assert(after.gold == old_gold - old_cost and after.progression.batch_success == roll and after.progression.seed_value == seed)
		assert(is_equal_approx(after.brew_elapsed / after.brew_duration(), old_fraction))
		var baseline := outcome(before, 600)
		var upgraded := outcome(after, 600)
		assert(upgraded["sold"] > baseline["sold"])
		if kind == "cauldron": assert(upgraded["waiting_percent"] < baseline["waiting_percent"])
		else: assert(upgraded["full_percent"] < baseline["full_percent"])
		results.append({"purchase": kind, "paid": old_cost, "before": baseline, "after": upgraded})
	var before := fixture()
	before.level = 10
	before.sales_counter_level = 10
	before.progression.owned = ["vigor"]
	before.progression.expansion.plants = ["dewgrass"]
	before.progression.expansion.growth = {"dewgrass": 0.0}
	for row in State.Content.DATA["regions"]:
		if row["id"] != "forest_edge":
			before.progression.expansion.regions.append(row["id"])
			before.progression.expansion.returns[row["id"]] = int(row["complete_returns"])
	before.progression.filter_owned = true
	before.progression.expansion.stages["precision_filter"] = int(State.Content.track_rows("precision_filter")[-1]["stage"])
	State.Progression.Expeditions.ensure(before.progression)
	assert(before.purchase("staff:brewing_assistant"))
	before.advance(0.2)
	assert(before.progression.active_recipe == "vigor" and before.progression.batch_success)
	var after := clone(before)
	var original: Dictionary = before.to_data()
	var fraction: float = before.brew_elapsed / before.brew_duration()
	var training_cost: int = after.purchase_cost("upgrade:brewing_assistant")
	assert(after.purchase("upgrade:brewing_assistant"))
	assert(after.gold == before.gold - training_cost)
	assert(after.herbs == before.herbs and after.progression.seed_value == before.progression.seed_value and after.progression.batch_success == before.progression.batch_success and is_equal_approx(after.brew_elapsed / after.brew_duration(), fraction))
	var times := []
	for s in [before, after]:
		var seconds := 0.0
		while s.progression.totals["brewed"] < 10 and seconds < 180:
			s.advance(0.05)
			seconds += 0.05
		assert(s.progression.totals["brewed"] == 10)
		times.append(seconds)
	assert(times[1] < times[0])
	results.append({"purchase": "brewing_assistant_training", "paid": training_cost, "first_10_potions_seconds_before": times[0], "first_10_potions_seconds_after": times[1], "reserved_state": original["progression"]["active_recipe"]})
	var file := FileAccess.open("res://docs/balance/runtime-paid-investments.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"revision": "candidate-d actual paid isolated comparisons", "cases": results}, "\t"))
	file.close()
	print("PAID EFFECT PASS: cauldron reduces customer waiting, counter reduces full-stock time, assistant speeds ten new batches; actual fees and reserved progress/RNG preserved; old-five exclusion covered by test_expansion")
	quit()
