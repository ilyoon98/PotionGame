extends SceneTree
const State = preload("res://scripts/shop_state.gd")
const Trips = preload("res://scripts/parallel_expeditions.gd")
const Compare = preload("res://tests/state_compare.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	assert(DisplayServer.get_name() == "headless")
	var results := []
	for seed in [7, 73129, 1199999]:
		var state := State.new()
		state.gold = 100000
		var p: RefCounted = state.progression
		p.seed_value = seed
		p.reputation = 10000
		p.expedition_unlocked = true
		for source in State.Content.DATA.regions: p.expansion.regions.append(source.id)
		for id in State.Content.RECIPES:
			p.owned.append(id)
			if not State.Content.LEGACY_RECIPES.has(id): p.expansion.grant_recipe(id)
		Trips.tick(state, 0)
		var split := State.new()
		assert(split.load_data(JSON.parse_string(JSON.stringify(state.to_data()))))
		state.advance(1200)
		for frame in 3000: split.advance(0.4)
		assert(Compare.equivalent(state.to_data(), split.to_data()), "Reward RNG and deposits must be frame independent")
		state.advance(2400)
		assert(state.gold == 100000 + state.total_sales_gold - state.total_spent_materials - state.total_spent_expeditions)
		for material in State.Content.DATA.materials:
			var cap: int = state.herb_capacity() if material.id == "herb" else state.MUSHROOM_CAPACITY if material.id == "moon_mushroom" else p.expansion.special_capacity()
			assert(state.material_count(material.id) >= 0 and state.material_count(material.id) <= cap)
		assert(state.stock <= state.capacity() and state.inventory.size() == state.stock)
		var restored := State.new()
		assert(restored.load_data(JSON.parse_string(JSON.stringify(state.to_data()))))
		assert(Compare.equivalent(state.to_data(), restored.to_data()))
		results.append({"seed": seed, "seconds": 3600, "gold": state.gold, "sales": state.total_sales_gold, "material_cost": state.total_spent_materials, "expedition_cost": state.total_spent_expeditions, "returns": p.totals.expeditions, "pending": p.expansion.pending, "recipe_count": p.owned.size()})
	var file := FileAccess.open("res://.verification/expedition-pool-economy.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	print("EXPEDITION POOL ECONOMY PASS: three seeded hour simulations; coarse/fine state/RNG, exact ledger, separate inventory caps/overflow, JSON save roundtrip")
	quit()
