extends SceneTree
const State = preload("res://scripts/shop_state.gd")
const Compare = preload("res://tests/state_compare.gd")
const Display = preload("res://scripts/potion_display.gd")
const Art = preload("res://scripts/item_art.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# The original 32 rows and 8 regions are unchanged; F26 and F27 (content_set) each add 4 recipes and one region.
	var originals: Array = State.Content.DATA.potions.filter(func(row): return not row.has("content_set"))
	var later_regions: Array = State.Content.DATA["regions"].filter(func(row): return row.has("content_set"))
	assert(originals.size() == 32 and State.Content.DATA.potions.size() - originals.size() == 4 + 4 and State.Content.RECIPES.size() + 2 == State.Content.DATA.potions.size() + 4)
	assert(State.Content.DATA["regions"].size() - later_regions.size() == 8 and later_regions.size() == 2)
	assert(State.Content.DATA["upgrades"].size() == 125)
	var state := State.new()
	state.gold = 1000000 + 1850000 + 2100000 # + the four F26 recipes (25/35/45/80만 G) and the four F27 recipes (30/40/50/90만 G)
	state.progression.reputation = 1000
	assert(not state.purchase("vigor") and not state.purchase("region:abandoned_greenhouse"))
	state.purchase("moon")
	assert(state.purchase("expedition"))
	state.advance(214.0)
	assert(state.progression.expedition_count == 3)
	assert(state.purchase_reason("vigor").is_empty() and state.purchase("vigor"))
	assert(state.progression.expansion.plants.has("dewgrass") and state.material_count("dewgrass") >= 2)
	var paid: int = state.gold
	assert(not state.purchase("vigor") and state.gold == paid)
	state.advance(state.brew_duration() + 0.1)
	assert(state.progression.active_recipe == "vigor")
	var herbs: int = state.herbs
	var ingredients: int = state.material_count("dewgrass")
	var restored := State.new()
	assert(restored.load_data(JSON.parse_string(JSON.stringify(state.to_data()))))
	assert(Compare.equivalent(state.to_data(), restored.to_data()))
	assert(restored.herbs == herbs and restored.material_count("dewgrass") == ingredients)
	state.advance(state.brew_duration() + 5.0)
	assert(state.progression.expansion.first_brewed.has("vigor"))
	assert(state.progression.expansion.first_sold.has("vigor"))
	assert(state.progression.by_potion.get("활력", 0) > 0)
	# Opening another region adds an independent leg and preserves the first one.
	state.progression.expedition_count = 10
	var old_elapsed: float = state.progression.expansion.cycles["forest_edge"]["elapsed"]
	var old_duration: float = state.progression.expansion.cycles["forest_edge"]["duration"]
	assert(state.purchase("region:abandoned_greenhouse"))
	assert(state.progression.expansion.cycles["abandoned_greenhouse"]["running"])
	assert(state.progression.expansion.cycles["forest_edge"]["elapsed"] == old_elapsed and state.progression.expansion.cycles["forest_edge"]["duration"] == old_duration)
	state.advance(71.0)
	assert(state.progression.expansion.cycles["abandoned_greenhouse"]["elapsed"] == 71.0)
	assert(not state.purchase("region:mist_valley"))
	state.progression.expansion.returns["abandoned_greenhouse"] = 6
	state.progression.expansion.returns["mist_valley"] = 6
	state.progression.expansion.regions.append("mist_valley")
	state.progression.expansion.regions.append("crystal_mine")
	state.progression.expansion.returns["crystal_mine"] = 5
	# Exercise every recipe's discovery, source grant and production reservation.
	for region in State.Content.DATA["regions"]:
		if region["id"] != "forest_edge":
			if not state.progression.expansion.regions.has(region["id"]): state.progression.expansion.regions.append(region["id"])
			state.progression.expansion.returns[region["id"]] = int(region["complete_returns"])
	for potion in State.Content.DATA["potions"]:
		var id: String = potion["id"]
		if not potion["owned_at_start"] and not state.progression.owned.has(id): assert(state.purchase(id))
		assert(Art.icon(id) != null and Art.bottle(false if id == "health" else true if id == "mana" else id) != null)
	State.Progression.Expeditions.ensure(state.progression)
	assert(state.progression.owned.size() + 2 == State.Content.DATA.potions.size() and state.progression.completed_regions() == State.Content.DATA["regions"].size())
	for kind in ["health", "mana", "moon", "purify", "agility", "vigor"]:
		state.brew_active = true
		state.progression.active_recipe = false if kind == "health" else true if kind == "mana" else kind
		state.active_mana = kind == "mana"
		state.brew_elapsed = state.brew_duration() * 0.4
		var original_time: float = state.brew_duration()
		if not state.progression.expansion.staff.has("brewing_assistant"): assert(state.purchase("staff:brewing_assistant"))
		assert(is_equal_approx(state.brew_elapsed / state.brew_duration(), 0.4))
		if kind != "vigor": assert(is_equal_approx(original_time, state.brew_duration()), "Assistant never changes the five existing recipes")
	# All training stages are final values; preserve reserved batch and RNG.
	state.progression.active_recipe = "vigor"
	var seed: int = state.progression.seed_value
	var roll: bool = state.progression.batch_success
	for i in 5: assert(state.purchase("upgrade:brewing_assistant"))
	assert(is_equal_approx(state.progression.expansion.effect("brewing_assistant", "new_recipe_time_multiplier"), 0.72))
	assert(state.progression.seed_value == seed and state.progression.batch_success == roll)
	assert(not state.purchase("upgrade:brewing_assistant"))
	# Every investment track is payable exactly up to its last row.
	var tracks := []
	for investment in State.Content.DATA["upgrades"]:
		if not tracks.has(investment["track"]): tracks.append(investment["track"])
	for employee in State.Content.DATA["employees"]:
		if state.purchase_reason("staff:" + str(employee["id"])) == "": assert(state.purchase("staff:" + str(employee["id"])))
	for track in tracks:
		while not state.next_investment(track).is_empty(): assert(state.purchase("upgrade:" + str(track)))
		assert(state.expansion_purchase_reason("upgrade:" + str(track)) == "최대 단계")
	assert(state.capacity() == 60 and state.herb_capacity() == 176 and state.progression.expansion.special_capacity() == 42)
	# Every new recipe must actually complete once, including a failed first try.
	var catalog_state := State.new()
	assert(catalog_state.load_data(state.to_data()))
	catalog_state.stock = 0
	catalog_state.mana_stock = 0
	catalog_state.inventory.clear()
	catalog_state.brew_active = false
	catalog_state.progression.expansion.first_brewed.clear()
	catalog_state.progression.expansion.first_batches = []
	for id in Content_ids():
		catalog_state.progression.expansion.first_batches.append(id)
		for material in state.Content.lookup("potions", id)["ingredients"]:
			if material == "herb": catalog_state.herbs = catalog_state.herb_capacity()
			elif material == "starleaf": catalog_state.progression.rare_herbs = 42
			elif material == "moon_mushroom": catalog_state.mushrooms = 6
			else: catalog_state.progression.expansion.materials[material] = 42
	catalog_state.advance(600.0)
	for id in Content_ids(): assert(catalog_state.progression.expansion.first_brewed.has(id), "Recipe never manufactured: " + id)
	state.stock = 60
	state.inventory = []
	for i in 60: state.inventory.append("vigor")
	state.mana_stock = 0
	assert(restored.load_data(JSON.parse_string(JSON.stringify(state.to_data()))))
	assert(Compare.equivalent(state.to_data(), restored.to_data()))
	var bottles := Display.new()
	bottles.set_workshop_layout(true)
	bottles.restore(60, 0, state.inventory)
	assert(bottles.matches(60, 0) and bottles.visible_capacity() == 8)
	bottles.take(50)
	assert(bottles.matches(59, 0))
	var corrupt := state.to_data()
	corrupt["progression"]["expansion"]["stages"]["brewing_assistant"] = 6
	var before := restored.to_data()
	assert(not restored.load_data(corrupt) and Compare.equivalent(before, restored.to_data()))
	var coarse := State.new()
	state.stock = 0
	state.inventory.clear()
	assert(coarse.load_data(state.to_data()))
	var fine := State.new()
	assert(fine.load_data(state.to_data()))
	coarse.advance(90.0)
	for i in 2700: fine.advance(1.0 / 30.0)
	assert(Compare.equivalent(coarse.to_data(), fine.to_data()), "Expanded plants, reservations, trips and stock are frame independent")
	print("EXPANSION PASS: 32+4+4 potions/8+1+1 regions/125 investments/4 employees; discovery and plants; automatic manufacture/sale; parallel region opening; final assistant values; old recipes unchanged; 60-slot inventory and 8-bottle display; save integrity and deterministic resume")
	quit()


func Content_ids() -> Array:
	# This suite exercises ordinary discovery/source grants; the four optional
	# discoveries and herb-free recipes have their own full pipeline verifier.
	return State.Content.RECIPES.keys().filter(func(id): return not State.Content.LEGACY_RECIPES.has(id) and not State.Rare.is_special(id))
