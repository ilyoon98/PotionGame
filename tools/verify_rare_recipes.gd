extends SceneTree
const State = preload("res://scripts/shop_state.gd")
const Content = preload("res://scripts/shop_content.gd")
const Rare = preload("res://scripts/rare_recipes.gd")
const Trips = preload("res://scripts/parallel_expeditions.gd")
const Baseline = preload("res://.verification/rare-baseline/scripts/shop_state.gd")
const OldTrips = preload("res://.verification/rare-baseline/scripts/parallel_expeditions.gd")
const Compare = preload("res://tests/state_compare.gd")
var checks := 0
var failures := 0

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)

func normalized_old(data: Dictionary) -> Dictionary:
	data = data.duplicate(true)
	data.version = 8
	# F18/F19 bookkeeping did not exist in this frozen v8 model.
	data.erase("contracts")
	data.erase("late_investments")
	data.erase("report_supply")
	var ex: Dictionary = data.progression.expansion
	for key in ["rare_version", "rare_discovered", "rare_failures", "rare_seed", "rare_cursor", "rare_turn"]: ex.erase(key)
	for cycle in ex.cycles.values():
		for key in ["mode", "rare_valid", "rare_recipe", "rare_success", "rare_attempt"]: cycle.erase(key)
	return data

func data(state: RefCounted) -> Dictionary:
	return JSON.parse_string(JSON.stringify(state.to_data()))

func readonly(state: RefCounted) -> void:
	var before := data(state)
	for item in Rare.ROWS:
		Rare.state(item.id, state.progression)
		Rare.recipe_info(item.id, state.progression)
		Rare.preview(item.region, state.progression)
		Trips.departure_mode(item.region, state.progression)
	state.production_candidates()
	state.production_preview()
	check(Compare.equivalent(before, data(state)), "Discovery/recipe/dispatch/production previews preserve full save and both RNG streams")

func opened(region: String, complete: bool = false) -> RefCounted:
	var state := State.new()
	state.gold = 100000
	if region == "forest_edge": state.progression.expedition_unlocked = true
	else:
		state.progression.expansion.regions.append(region)
		state.progression.expedition_unlocked = true
		# Keep the forest unavailable for paid departures in this isolated region fixture.
		state.progression.expedition_count = 10
		state.progression.expansion.materials.dewgrass = state.progression.expansion.special_capacity()
		state.progression.expansion.rare_discovered.append("rare_forest_breath")
	if complete:
		if region == "forest_edge": state.progression.expedition_count = int(Content.lookup("regions", region).complete_returns)
		else: state.progression.expansion.returns[region] = int(Content.lookup("regions", region).complete_returns)
	Trips.ensure(state.progression)
	return state

func stock_ingredients(state: RefCounted) -> void:
	state.herbs = state.herb_capacity()
	state.mushrooms = state.MUSHROOM_CAPACITY
	state.progression.rare_herbs = state.progression.expansion.special_capacity()
	for material in Content.DATA.materials:
		if material.id not in ["herb", "moon_mushroom", "starleaf"]: state.progression.expansion.materials[material.id] = state.progression.expansion.special_capacity()

func test_catalog() -> void:
	check(Content.DATA.potions.size() == 32 and Rare.ROWS.size() == 4 and Content.RECIPES.size() == 34, "General32 catalog is intact; four rare rows stay separate")
	var expected := [{"dewgrass": 2, "starleaf": 1, "moon_mushroom": 1}, {"blue_reed": 2, "silver_moss": 1, "dewgrass": 1}, {"moonflower": 2, "ash_sage": 1, "starleaf": 1}, {"star_seed": 2, "moonflower": 1, "crystal_herb": 1}]
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/rare_recipes_v1/catalog.json"))
	for i in Rare.ROWS.size():
		var item: Dictionary = Rare.ROWS[i]
		check(item.ingredients == expected[i] and item.grant_sources.is_empty(), "Approved exact blend uses no duplicate supply grants")
		check(Content.lookup("potions", item.id) == item and Content.valid_kind(item.id), "Special kind is accepted by runtime lookup/recipe/inventory")
		var asset: Dictionary = catalog.assets[i]
		check(item.id == asset.id and item.icon_candidate == asset.potion_path and item.bottle_candidate == asset.bottle_path and item.recipe_icon_candidate == asset.recipe_path, "Runtime names and paths connect approved art catalog")
		for path in [item.icon_candidate, item.bottle_candidate, item.recipe_icon_candidate]: check(FileAccess.file_exists(path), "All approved art files exist")
	var state := State.new()
	for item in Rare.ROWS:
		var masked := Rare.recipe_info(item.id, state.progression)
		check(masked.state == Rare.UNFOUND and not masked.known and masked.id == "" and masked.ingredients.is_empty() and masked.icon == "" and masked.recipe_icon == "" and masked.cost == 0 and masked.name == "특별 레시피 · 미발견", "Unknown public projection hides real name/art/blend/price")
		check(state.purchase_reason(item.id) == "특별 레시피 미발견" and not state.purchase(item.id), "Discovery is required before a purchase")
	check(not Rare.preview("crystal_mine", state.progression).exists, "Regions without a special recipe expose no fake unknown slot")
	readonly(state)

func test_normal_leg() -> void:
	var state := opened("forest_edge")
	var old := Baseline.new()
	old.gold = state.gold
	old.progression.expedition_unlocked = true
	state.progression.expansion.rare_seed = 1
	Trips.tick(state, 0.0)
	OldTrips.tick(old, 0.0)
	var cycle: Dictionary = state.progression.expansion.cycles.forest_edge
	check(cycle.mode == "normal" and cycle.rare_valid and cycle.rare_success and cycle.rare_attempt == 1, "New ordinary departure fixes one eligible discovery outcome")
	check(cycle.rewards == old.progression.expansion.cycles.forest_edge.rewards and state.progression.seed_value == old.progression.seed_value, "Rare roll preserves ordinary material roll and main RNG")
	check(not Rare.is_discovered("rare_forest_breath", state.progression), "Successful reserved outcome stays hidden before completion")
	cycle.elapsed = 35.0
	var reserved := cycle.duplicate(true)
	var restored := State.new()
	check(restored.load_data(data(state)), "Running normal leg with reserved outcome roundtrips")
	check(Compare.equivalent(restored.progression.expansion.cycles.forest_edge, reserved) and restored.progression.expansion.rare_seed == state.progression.expansion.rare_seed, "Restore preserves leg ID/mode/outcome/materials/duration and discovery RNG")
	readonly(restored)
	restored.progression.clock += 90.0
	restored.progression.expansion.stages.expedition_path = 8
	check(Compare.equivalent(restored.progression.expansion.cycles.forest_edge, reserved), "Weather and new trip upgrade never change a departed leg")
	restored.gold = 30
	Trips.tick(restored, cycle.duration - cycle.elapsed)
	check(Rare.state("rare_forest_breath", restored.progression) == Rare.DISCOVERED and not restored.progression.owned.has("rare_forest_breath"), "Completion reveals discovery without purchase or fabrication rights")
	check(restored.progression.expedition_count == 1 and restored.progression.totals.expeditions == 1, "Ordinary discovery leg still increments ordinary investigation and return totals")
	var before := data(restored)
	Trips.tick(restored, 0.0)
	check(Compare.equivalent(before, data(restored)), "An already-completed leg never reveals or charges twice")

func test_special_guarantee() -> void:
	for item in Rare.ROWS:
		var state := opened(item.region, true)
		var p: RefCounted = state.progression
		# The non-forest fixture has a previously discovered forest only.
		p.expansion.rare_discovered.erase(item.id)
		var pool_main: String = Content.lookup("regions", item.region).material
		p.expansion.materials[pool_main] = p.expansion.special_capacity()
		p.expansion.pending[pool_main] = 3
		var general_count: int = p.expansion.region_returns(item.region, p)
		var main_seed: int = p.seed_value
		var initial_rewards: Dictionary = p.expansion.reward_totals.duplicate(true)
		check(Trips.departure_mode(item.region, p) == "special", "Full ordinary material storage permits only an undiscovered special search")
		for attempt in range(1, 31):
			state.gold = 100000
			p.expansion.rare_seed = 4444 # This isolated stream produces a known failed3% draw.
			Trips.tick(state, 0.0)
			var c: Dictionary = p.expansion.cycles[item.region]
			check(c.running and c.mode == "special" and c.rewards.is_empty() and c.rare_attempt == attempt and c.rare_success == (attempt == 30), "Paid search fixes mode/outcome and exact guarantee boundary")
			check(c.fee == int(Content.lookup("regions", item.region).departure_cost) and c.duration == float(Content.lookup("regions", item.region).explore_seconds + Content.lookup("regions", item.region).return_seconds), "Special search uses existing fee and duration")
			check(not Rare.is_discovered(item.id, p), "Departure never publishes even guaranteed success")
			if attempt in [1, 29, 30]:
				var restored := State.new()
				check(restored.load_data(data(state)), "Search cycle/failures/RNG save checkpoint roundtrips")
				check(Compare.equivalent(data(state), data(restored)), "Checkpoint restores every reserved value exactly")
				state = restored
				p = state.progression
				c = p.expansion.cycles[item.region]
			state.gold = 30
			p.clock += c.duration
			Trips.tick(state, c.duration)
			check(int(p.expansion.rare_failures.get(item.id, 0)) == mini(attempt, 29), "Only valid failed completions advance pity; guarantee does not add a failure")
			check(p.expansion.region_returns(item.region, p) == general_count and p.totals.expeditions == attempt, "Search returns count as trips without filling general investigation gates")
			check(p.seed_value == main_seed and p.expansion.reward_totals == initial_rewards and p.expansion.pending[pool_main] == 3, "Search leaves main RNG, general rewards and pending materials unchanged")
		check(Rare.state(item.id, p) == Rare.DISCOVERED and p.expansion.rare_discovered.count(item.id) == 1, "Thirtieth completion discovers exactly once")
		state.gold = 100000
		var spent: int = state.total_spent_expeditions
		Trips.tick(state, 0.0)
		check(not p.expansion.cycles[item.region].running and state.total_spent_expeditions == spent and Trips.departure_mode(item.region, p) == "", "Discovery stops paid search while storage waits and purchase remains optional")
		p.expansion.pending.erase(pool_main)
		p.expansion.materials[pool_main] = 0
		check(Trips.departure_mode(item.region, p) == "normal", "Later material demand resumes ordinary travel after discovery")
		readonly(state)

func test_budget_and_simultaneous() -> void:
	var state := opened("forest_edge", true)
	state.progression.expansion.rare_discovered.clear()
	state.progression.expansion.materials.dewgrass = state.progression.expansion.special_capacity()
	state.progression.expansion.regions.append("abandoned_greenhouse")
	Trips.ensure(state.progression)
	state.gold = 41
	Trips.tick(state, 0.0)
	check(not state.progression.expansion.cycles.forest_edge.running and not state.progression.expansion.cycles.abandoned_greenhouse.running and state.gold == 41, "Insufficient unfinished-general fee protects12 plus30 before an8-cost search")
	state.gold = 49
	Trips.tick(state, 0.0)
	check(state.progression.expansion.cycles.abandoned_greenhouse.running and not state.progression.expansion.cycles.forest_edge.running and state.gold == 37, "First general departure consumes its12 before search affordability is checked")
	state.gold = 38
	Trips.tick(state, 0.0)
	check(state.progression.expansion.cycles.forest_edge.running and state.gold == 30, "Search uses exact8 fee while preserving30 after general departure")
	var simultaneous := opened("forest_edge", true)
	var p: RefCounted = simultaneous.progression
	p.expansion.rare_discovered.clear()
	for item in Rare.ROWS:
		if item.region != "forest_edge": p.expansion.regions.append(item.region)
		p.expansion.returns[item.region] = int(Content.lookup("regions", item.region).complete_returns)
		p.expansion.materials[Content.lookup("regions", item.region).material] = p.expansion.special_capacity()
		p.expansion.rare_failures[item.id] = 29
	Trips.ensure(p)
	Trips.tick(simultaneous, 0.0)
	for item in Rare.ROWS: p.expansion.cycles[item.region].elapsed = p.expansion.cycles[item.region].duration - 1.0
	simultaneous.gold = 30
	Trips.tick(simultaneous, 1.0)
	check(p.expansion.rare_discovered.size() == 4 and p.totals.expeditions == 4 and p.expedition_count == 10, "Four simultaneous guaranteed returns reveal once without advancing forest investigation")
	var before := data(simultaneous)
	Trips.tick(simultaneous, 0.0)
	check(Compare.equivalent(before, data(simultaneous)), "Simultaneous return processing is idempotent")

func test_purchase_and_crafting() -> void:
	var state := State.new()
	var p: RefCounted = state.progression
	p.expansion.rare_discovered.append("rare_forest_breath")
	state.gold = 899
	check(not state.purchase("rare_forest_breath") and state.gold == 899, "Discovered recipe still requires exact purchase price")
	state.gold = 900
	var materials: Dictionary = p.expansion.materials.duplicate()
	check(state.purchase("rare_forest_breath") and state.gold == 0 and p.totals.manual_spent == 900 and p.totals.unlocks == 1, "One purchase spends once and records ownership separately from discovery")
	check(p.expansion.materials == materials and p.expansion.plants.is_empty() and p.expansion.pending.is_empty() and p.expansion.first_batches == ["rare_forest_breath"], "Rare purchase queues first actual batch without seeds/new plant/free supplies")
	var purchased := data(state)
	check(not state.purchase("rare_forest_breath") and Compare.equivalent(purchased, data(state)), "Repeated purchase never pays/grants again")
	stock_ingredients(state)
	state.herbs = 0
	var blend: Dictionary = Rare.row("rare_forest_breath").ingredients
	var stocks := {}
	for material in blend: stocks[material] = state.material_count(material)
	readonly(state)
	check(state.production_preview().id == "rare_forest_breath" and not state.waiting_for_herbs(), "Ready herb-free special blend is a first-batch candidate")
	state._start_batch()
	check(state.brew_active and p.active_recipe == "rare_forest_breath", "Herb-free special recipe starts its paid reserved batch")
	for material in blend: check(state.material_count(material) == stocks[material] - int(blend[material]), "Exact ingredient quantity is consumed once")
	var reserved := data(state)
	state._start_batch()
	check(Compare.equivalent(reserved, data(state)), "An active reserved batch cannot consume again")
	var restored := State.new()
	check(restored.load_data(data(state)), "Owned active special batch serializes safely")
	check(Compare.equivalent(data(state), data(restored)), "Restore preserves reservation, kind, chance and both RNG streams")
	state.progression.batch_success = true
	state.advance(state.brew_duration())
	check(state.inventory.has("rare_forest_breath") and not p.expansion.first_batches.has("rare_forest_breath"), "First actual successful special bottle joins inventory and finishes priority")
	var fair := State.new()
	for item in Rare.ROWS:
		fair.progression.expansion.rare_discovered.append(item.id)
		fair.progression.owned.append(item.id)
	for id in ["vigor", "focus", "growth", "clarity"]: fair.progression.owned.append(id)
	var counts := {}
	for i in range(32):
		stock_ingredients(fair)
		readonly(fair)
		fair._start_batch()
		var id: String = fair.progression.active_recipe
		counts[id] = int(counts.get(id, 0)) + 1
		check(Rare.is_special(id) == (i % 2 == 0), "Ready special and ordinary groups alternate without starvation")
		fair.brew_active = false
		fair.brew_elapsed = 0.0
	for item in Rare.ROWS: check(counts.get(item.id, 0) == 4, "Every ready special recipe gets fair rotation")
	for id in ["vigor", "focus", "growth", "clarity"]: check(counts.get(id, 0) == 4, "Every ordinary family winner remains in rotation")
	var base := State.new()
	base.progression.expansion.rare_discovered.append("rare_forest_breath")
	base.progression.owned.append("rare_forest_breath")
	for i in 8:
		stock_ingredients(base)
		base._start_batch()
		check((base.progression.active_recipe is String) == (i % 2 == 0), "Basic/legacy fallback also receives fair turns")
		base.brew_active = false
	var first := fair
	first.progression.expansion.first_batches.append("growth")
	stock_ingredients(first)
	check(first.production_preview().id == "growth" and first.production_preview().first_batch, "Existing purchased first batch retains priority over fair groups")
	var sale := State.new()
	sale.herbs = 0
	sale.progression.expansion.rare_discovered.append("rare_forest_breath")
	sale.progression.owned.append("rare_forest_breath")
	sale.inventory.append("rare_forest_breath")
	sale.stock = 1
	sale.progression.customer_selected = true
	sale.progression.customer = 0
	sale.advance(sale.customer_interval())
	check(sale.total_sold == 1 and sale.total_sales_gold == 80 and sale.stock == 0 and sale.progression.by_potion.get("숲숨결 물약", 0) == 1, "Actual special bottle sells through normal FIFO/customer/ledger pipeline")

func test_frame_independence() -> void:
	for owned_special in [false, true]:
		var coarse := State.new()
		var p: RefCounted = coarse.progression
		coarse.gold = 100000
		p.reputation = 10000
		p.expedition_unlocked = true
		for region in Content.DATA.regions: p.expansion.regions.append(region.id)
		for source in Content.DATA.potions:
			if source.id in ["health", "mana"]: continue
			p.owned.append(source.id)
			if not Content.LEGACY_RECIPES.has(source.id): p.expansion.grant_recipe(source.id)
		if owned_special:
			for item in Rare.ROWS:
				p.expansion.rare_discovered.append(item.id)
				p.owned.append(item.id)
				p.expansion.grant_recipe(item.id)
		Trips.tick(coarse, 0.0)
		var fine := State.new()
		check(fine.load_data(data(coarse)), "Simulated expedition/production fixture starts from saved exact state")
		coarse.advance(1200.0)
		for frame in 3000: fine.advance(0.4)
		check(Compare.equivalent(data(coarse), data(fine)), "Ordinary discovery or owned-rare crafting is frame independent across twenty minutes")
		check(coarse.gold == 100000 + coarse.total_sales_gold - coarse.total_spent_materials - coarse.total_spent_expeditions, "All automatic sales/material/search/departure money reconciles exactly")
		check(coarse.stock <= coarse.capacity() and coarse.stock == coarse.inventory.size(), "Shared potion capacity and actual bottle order stay consistent")
		var restored := State.new()
		check(restored.load_data(data(coarse)) and Compare.equivalent(data(coarse), data(restored)), "Simulated settled/reserved discovery and crafting state restores without a roll")

func test_legacy_and_invalid() -> void:
	var old := Baseline.new()
	old.progression.expedition_unlocked = true
	old.gold = 100000
	OldTrips.tick(old, 0.0)
	old.progression.expansion.cycles.forest_edge.elapsed = 69.0
	old.progression.expedition_count = 99
	var state := State.new()
	check(state.load_data(data(old)), "Version8 old active leg loads with new optional fields")
	var cycle: Dictionary = state.progression.expansion.cycles.forest_edge
	check(cycle.mode == "normal" and not cycle.rare_valid and state.progression.expansion.rare_failures.is_empty() and state.progression.expansion.rare_discovered.is_empty(), "Prior returns and already-departed leg are not retroactive attempts/discoveries")
	state.gold = 30
	var seed: int = state.progression.seed_value
	var rewards: Dictionary = cycle.rewards.duplicate(true)
	Trips.tick(state, 1.0)
	check(state.progression.expedition_count == 100 and not Rare.is_discovered("rare_forest_breath", state.progression) and state.progression.expansion.rare_failures.is_empty() and state.progression.seed_value == seed, "Grandfathered completion preserves normal reward with zero special roll")
	for material in rewards: check(int(state.progression.expansion.reward_totals.get(material, 0)) >= int(rewards[material]), "Grandfathered pending/material reward is retained")
	var start := State.new()
	for item in Rare.ROWS: start.progression.expansion.rare_discovered.append(item.id)
	start.progression.owned.append("moon")
	start.progression.rare_herbs = 2
	start._start_batch()
	var payload := data(start)
	for mutate in [func(d): d.progression.expansion.rare_discovered.append("rare_forest_breath"), func(d): d.progression.expansion.rare_discovered.append("not-a-recipe"), func(d): d.progression.expansion.rare_seed = 0, func(d): d.progression.expansion.rare_seed = "1", func(d): d.progression.expansion.rare_turn = 1, func(d): d.progression.expansion.rare_cursor = 4, func(d): d.progression.expansion.rare_failures.rare_forest_breath = 30, func(d): d.progression.expansion.rare_failures.rare_forest_breath = -1, func(d): d.progression.expansion.rare_version = 0, func(d): d.progression.expansion.erase("rare_version")]:
		var broken := payload.duplicate(true)
		mutate.call(broken)
		var target := State.new()
		var untouched := data(target)
		check(not target.load_data(broken) and Compare.equivalent(untouched, data(target)), "Malformed special save is rejected without mutating the destination")
	var locked := State.new()
	var unowned := data(locked)
	unowned.progression.owned.append("rare_forest_breath")
	check(not locked.load_data(unowned), "Owned-but-undiscovered rare recipe is rejected")
	var source := opened("forest_edge")
	Trips.tick(source, 0.0)
	var running := data(source)
	for mutate in [func(d): d.progression.expansion.cycles.forest_edge.mode = "wrong", func(d): d.progression.expansion.cycles.forest_edge.rare_valid = 1, func(d): d.progression.expansion.cycles.forest_edge.rare_recipe = "rare_mist_veil", func(d): d.progression.expansion.cycles.forest_edge.rare_attempt = 0, func(d): d.progression.expansion.cycles.forest_edge.rare_success = "yes", func(d): d.progression.expansion.cycles.forest_edge.mode = "special", func(d): d.progression.expansion.cycles.forest_edge.erase("rare_attempt"), func(d): d.progression.expansion.cycles.forest_edge.paid = false, func(d): d.progression.expansion.cycles.forest_edge.id = 0, func(d): d.progression.expansion.cycles.forest_edge.duration = 0]:
		var broken := running.duplicate(true)
		mutate.call(broken)
		check(not State.new().load_data(broken), "Malformed reserved cycle mode/outcome is rejected")
	var current := State.new()
	var baseline := Baseline.new()
	for item in Rare.ROWS: current.progression.expansion.rare_discovered.append(item.id)
	for model in [current, baseline]:
		model.gold = 100000
		model.progression.owned.assign(["moon", "purify", "agility", "vigor", "focus", "growth", "clarity"])
		model.progression.rare_herbs = 12
		for id in ["dewgrass", "silver_moss", "blue_reed"]: model.progression.expansion.materials[id] = 12
		model.progression.expedition_unlocked = true
		model.progression.expansion.regions.append("abandoned_greenhouse")
		model.progression.expansion.regions.append("mist_valley")
		model.progression.expansion.plants.assign(["dewgrass", "silver_moss", "blue_reed"])
		model.progression.expansion.first_batches.assign(["focus", "vigor"])
		model.advance(1800.0)
	check(Compare.equivalent(normalized_old(data(current)), data(baseline)), "Thirty-minute ordinary production/rewards/main RNG equals frozen pre-feature model when optional searches are finished")

func _initialize() -> void:
	assert(DisplayServer.get_name() == "headless")
	set_meta("isolated_preview", true)
	test_catalog()
	test_normal_leg()
	test_special_guarantee()
	test_budget_and_simultaneous()
	test_purchase_and_crafting()
	test_frame_independence()
	test_legacy_and_invalid()
	print("RARE CORE %s: %d checks; four approved blends/art, masked discovery/purchase, fixed paid normal/search legs, four30-leg guarantees, fees/reserve/protection, simultaneous/restore/grandfather/malformed saves, first reservation/fair production, thirty-minute ordinary economy/main RNG baseline; isolated headless only" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
