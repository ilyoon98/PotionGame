extends SceneTree
## Pure projections only; no scene, player save, native process, registry or input.
const State = preload("res://scripts/shop_state.gd")
const Status = preload("res://scripts/management_status.gd")
const Content = preload("res://scripts/shop_content.gd")
const Compare = preload("res://tests/state_compare.gd")
const Rare = preload("res://scripts/rare_recipes.gd")
const Trips = preload("res://scripts/parallel_expeditions.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	set_meta("isolated_preview", true)
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func maximum_fixture() -> RefCounted:
	var state := State.new()
	state.level = State.MAX_LEVEL
	state.garden_level = State.MAX_GARDEN_LEVEL
	state.sales_counter_level = Content.SALES_COUNTER_COSTS.size()
	state.progression.filter_owned = true
	state.progression.employee = true
	for employee in Content.DATA.employees: state.progression.expansion.staff.append(employee.id)
	for row in Content.DATA.upgrades: state.progression.expansion.stages[row.track] = int(row.stage)
	return state

func verify_maximum_effects() -> void:
	var state: RefCounted = maximum_fixture()
	var before: Dictionary = state.to_data().duplicate(true)
	var tracks := []
	for row in Content.DATA.upgrades:
		if tracks.has(row.track): continue
		tracks.append(row.track)
		var expected: Dictionary = Content.lookup("employees", row.track).get("effect", {}).duplicate()
		for stage in Content.track_rows(row.track):
			for key in stage.effect: expected[key] = float(stage.effect[key])
		var data := Status.investment(state, row.track)
		check(data.maxed and data.reason == "최대 단계" and data.cost == 0 and data.level == data.maximum, "Maximum investment preserves completion without another cost: " + row.track)
		check(data.current_effects.size() == expected.size(), "All earlier effect keys survive the final stage: " + row.track)
		for key in expected:
			check(data.current_effects.has(key) and is_equal_approx(float(data.current_effects[key]), float(expected[key])), "Current effect is the final replacement value, never the sum: " + row.track + "/" + key)
		check(data.effect.begins_with("현재 효과 · ") and data.effect != "현재 효과 · " and not data.effect.contains("→"), "Every maxed equipment/family/training keeps readable current abilities: " + row.track)
		check(data.preview_effect == data.effect, "A completed card retains its final effect in the concise projection: " + row.track)
	check(tracks.size() == 16, "All eight equipment, four families and four employee training tracks are covered")
	var cauldron := Status.investment(state, "cauldron")
	check(cauldron.effect.contains("제조 0.84초") and cauldron.effect.contains("품질 +12%"), "The final quality-only cauldron stage preserves its earlier real manufacture time")
	var counter := Status.investment(state, "sales_counter")
	check(counter.effect == "현재 효과 · 거래 1.50초", "The completed sales counter displays the real transaction interval")
	check(Status.investment(state, "expedition_path").effect == "현재 효과 · 원정 시간 16% 단축", "The path displays its own 16% effect")
	check(Status.investment(state, "expedition_guide").effect == "현재 효과 · 원정 시간 14% 단축", "The guide displays its own 14% effect")
	var cabinet := Status.investment(state, "potion_cabinet")
	check(cabinet.current_effects.visible_capacity == 12 and cabinet.effect == "현재 효과 · 물약 60", "The unused catalog display capacity is preserved structurally without claiming a false rendering upgrade")
	check(Compare.equivalent(before, state.to_data()), "Maximum effect reads preserve the complete serialized state and RNG")

func verify_expedition_timing() -> void:
	var state := State.new()
	var ex: RefCounted = state.progression.expansion
	for region in Content.DATA.regions:
		var base: float = float(region.explore_seconds) + float(region.return_seconds)
		ex.cycles[region.id] = {"running": true, "elapsed": 12.5, "duration": base, "mode": "normal"}
	var before: Dictionary = state.to_data().duplicate(true)
	for region in Content.DATA.regions:
		var timing := Status.expedition_timing(state, region.id)
		check(timing.total == 0 and timing.base == timing.next and timing.current == timing.base, "Unmodified trips retain their catalog and paid-leg time: " + region.id)
	check(Compare.equivalent(before, state.to_data()), "Timing reads create no cycles and consume no rewards/RNG")
	ex.stages.expedition_path = 8
	ex.staff.append("expedition_guide")
	ex.stages.expedition_guide = 5
	before = state.to_data().duplicate(true)
	for region in Content.DATA.regions:
		var timing := Status.expedition_timing(state, region.id)
		check(is_equal_approx(timing.path, 0.16) and is_equal_approx(timing.guide, 0.14) and is_equal_approx(timing.total, 0.3), "Self effects remain separate and combined reduction stays capped at 30%: " + region.id)
		check(is_equal_approx(timing.next, timing.base * 0.7) and timing.current == timing.base, "Only the next departure uses upgrades; stored running duration is immutable: " + region.id)
		check(timing.text.contains("상한 30%") and timing.text.contains("현재 회차") and timing.text.contains("출발 시 소요 시간 유지"), "Detail explicitly distinguishes current and next paid-leg durations: " + region.id)
	check(Compare.equivalent(before, state.to_data()), "Upgrade timing projections preserve the running legs and all economy/RNG")
	ex.cycles.clear()
	before = state.to_data().duplicate(true)
	var idle := Status.expedition_timing(state, "forest_edge")
	check(not idle.running and idle.current == 0 and not idle.text.contains("현재 회차"), "Idle/missing cycles do not invent a current paid trip")
	check(Compare.equivalent(before, state.to_data()), "Missing-cycle projection never runs ensure or changes saves")

func put_material(state: RefCounted, id: String, quantity: int) -> void:
	if id == "herb": state.herbs = quantity
	elif id == "moon_mushroom": state.mushrooms = quantity
	elif id == "starleaf": state.progression.rare_herbs = quantity
	else: state.progression.expansion.materials[id] = quantity

func verify_ingredients() -> void:
	var state := State.new()
	state.progression.owned.assign(Content.RECIPES.keys())
	for rare in Rare.ROWS: state.progression.expansion.rare_discovered.append(rare.id)
	for kind in [false, true] + Content.RECIPES.keys():
		var id := Status.kind_id(kind)
		var source := Content.lookup("potions", id)
		for material in Content.DATA.materials: put_material(state, material.id, 0)
		state.brew_active = false
		var before: Dictionary = state.to_data().duplicate(true)
		var entries := Status.ingredients(state, kind)
		check(entries.size() == source.ingredients.size(), "Every real one-bottle recipe retains all material species: " + id)
		for entry in entries:
			check(entry.required == int(source.ingredients[entry.id]) and entry.name == Content.lookup("materials", entry.id).name, "Ingredient quantity and full name come from the actual recipe: " + id + "/" + entry.id)
			check(entry.owned == 0 and entry.missing == entry.required and entry.next_missing == entry.required and not entry.reserved, "An idle empty recipe exposes its actual shortages without changing its required quantity: " + id)
		check(Compare.equivalent(before, state.to_data()), "Ingredients never reserve or consume resources/RNG: " + id)
		state.brew_active = true
		state.progression.active_recipe = kind
		state.active_mana = kind is bool and kind
		before = state.to_data().duplicate(true)
		for entry in Status.ingredients(state, kind):
			check(entry.reserved and entry.missing == 0 and entry.next_missing == entry.required, "Reserved current batch is never reported short; the next bottle is checked separately: " + id)
		var data := Status.potion(state, kind)
		check(data.active and data.status == "제작 중" and data.condition.contains("예약 완료") and data.condition.contains("다음 병 필요"), "Current production keeps running despite consumed ingredients: " + id)
		check(Compare.equivalent(before, state.to_data()), "Active batch projections preserve its reserved chance and complete state/RNG: " + id)
		state.brew_active = false
		for entry in entries: put_material(state, entry.id, entry.required)
		before = state.to_data().duplicate(true)
		for entry in Status.ingredients(state, kind): check(entry.owned == entry.required and entry.missing == 0 and entry.next_missing == 0 and not entry.reserved, "Available ingredients keep their recipe quantities: " + id)
		check(Compare.equivalent(before, state.to_data()), "Sufficient ingredient reads do not choose production: " + id)

func verify_priority_and_mask() -> void:
	var state := State.new()
	state.progression.owned.assign(["vigor", "restoration"])
	state.herbs = 20
	put_material(state, "dewgrass", 3)
	put_material(state, "silver_moss", 3)
	var before: Dictionary = state.to_data().duplicate(true)
	var low := Status.potion(state, "vigor")
	check(low.status == "상위 물약 우선 · 부족 시 자동 대체" and low.priority.higher_id == "restoration" and Status.potion_primary(state, "vigor", low) == low.status, "Ready lower family bottles identify the real higher ordinary candidate")
	check(Compare.equivalent(before, state.to_data()), "Priority reads never advance the family cursor, reserve a batch or draw RNG")
	state.progression.owned.append("moon")
	state.progression.rare_herbs = 3
	state.mushrooms = 2
	before = state.to_data().duplicate(true)
	for fallback in [false, true, "moon"]:
		var priority := Status.potion_priority(state, fallback)
		check(priority.higher_id == "restoration" and priority.status == "신규 일반품 우선 · 부족 시 자동 대체", "Basic/legacy fallback reflects any ready ordinary family, even across its own family")
	check(Compare.equivalent(before, state.to_data()), "Global legacy fallback reads preserve production and recipe cursors/RNG")
	put_material(state, "silver_moss", 0)
	before = state.to_data().duplicate(true)
	check(Status.potion_priority(state, "vigor").higher_id.is_empty(), "A missing higher recipe does not block automatic lower substitution")
	check(Status.potion(state, "restoration").status == "재료 부족", "Actual missing ingredients take precedence over automatic priority")
	check(Compare.equivalent(before, state.to_data()), "Lower substitution inspection remains read-only")
	put_material(state, "silver_moss", 3)
	state.progression.expansion.first_batches.append("vigor")
	check(Status.potion(state, "vigor").status == "첫 제조 우선 · 자동 제작 대기", "A purchased first batch remains ahead of a higher ready family recipe")
	state.progression.expansion.first_batches.clear()
	state.stock = state.capacity()
	check(Status.potion(state, "vigor").status == "재고 가득", "Shared full potion storage takes precedence over candidate order")
	state.stock = 0
	check(Status.potion(state, "ward").status == "레시피 필요", "Unpurchased ordinary bottles retain their distinct recipe condition")
	state.progression.owned.clear()
	for row in Rare.ROWS:
		before = state.to_data().duplicate(true)
		var hidden := Status.potion(state, row.id)
		check(not hidden.known and hidden.icon.is_empty() and hidden.name == "특별 물약 · 미발견" and not hidden.available and hidden.ingredients.is_empty(), "Undiscovered special bottles expose no actual name, image, permission or blend")
		check(Status.ingredients(state, row.id).is_empty() and Status.potion_primary(state, row.id, hidden) == "특별 레시피 · 미발견", "Undiscovered composition and basic status share the discovery mask")
		check(not Status.region_preview(state, row.region).any(func(item): return str(item.get("id", "")).begins_with("rare_")), "Ordinary expedition previews contain no deferred special-name/art disclosure")
		check(not Status.growth_candidates(state).any(func(item): return item.purchase_key == row.id), "Undiscovered recipes never enter a purchase recommendation")
		check(Compare.equivalent(before, state.to_data()), "Mask checks never reveal, roll or buy a discovery")
		state.progression.expansion.rare_discovered.append(row.id)
		before = state.to_data().duplicate(true)
		var discovered := Status.potion(state, row.id)
		check(discovered.known and not discovered.available and discovered.name == row.name and not discovered.ingredients.is_empty(), "Discovery permits true naming/blend display but does not purchase or permit manufacturing")
		check(Compare.equivalent(before, state.to_data()), "Reading a discovered recipe never grants its purchase or sources")
		state.progression.owned.append(row.id)
		for entry in Status.ingredients(state, row.id): put_material(state, entry.id, entry.required)
		var owned := Status.potion(state, row.id)
		check(owned.available and owned.priority.higher_id.is_empty(), "Purchased special bottles are eligible without permanently replacing ordinary families")

func filled_region_fixture() -> RefCounted:
	var state := State.new()
	state.herbs = 0
	state.progression.expedition_unlocked = true
	for region in Content.DATA.regions:
		state.progression.expansion.regions.append(region.id)
		if region.id == "forest_edge": state.progression.expedition_count = int(region.complete_returns)
		else: state.progression.expansion.returns[region.id] = int(region.complete_returns)
		put_material(state, region.material, state.progression.expansion.special_capacity())
	Trips.ensure(state.progression) # Fixture setup only; never part of UI lookup.
	return state

func verify_special_departure_budget() -> void:
	for incomplete in [false, true]:
		for gold in [0, 30, 37, 41, 42, 45, 49, 50, 58, 70, 110, 180, 248, 250]:
			var state: RefCounted = filled_region_fixture()
			state.gold = gold
			if incomplete: state.progression.expansion.returns.abandoned_greenhouse = 0
			var before: Dictionary = state.to_data().duplicate(true)
			var candidate_modes := {}
			for source in Content.DATA.regions:
				var mode := Trips.departure_mode(source.id, state.progression)
				if not mode.is_empty(): candidate_modes[source.id] = mode
				var projected := Status.region(state, source.id)
				check(projected.mode == "normal" and projected.next_mode == mode, "Idle mode does not reuse a stale paid leg; next mode matches pure core eligibility")
				Status.region_card_conditions(state, source.id)
			check(candidate_modes.size() == (5 if incomplete else 4), "Full storage only dispatches four missing discoveries plus unfinished ordinary investigation")
			check(Compare.equivalent(before, state.to_data()), "Special eligibility/status/conditions never create cycles, draw a discovery or alter finances")
			var clone := State.new()
			check(clone.load_data(before), "The budget comparison uses only a valid isolated saved fixture")
			Trips.tick(clone, 0.0)
			for id in candidate_modes:
				var budget := Status._region_departure_budget(state, id)
				var started: bool = clone.progression.expansion.cycles[id].running
				check(started == (state.gold >= int(budget.total)), "Special/ordinary protection and earlier fees predict actual zero-time core departure: %s/%d/%s" % [id, gold, incomplete])
				if started: check(clone.progression.expansion.cycles[id].mode == candidate_modes[id], "Paid-leg kind agrees with the public next-departure projection")
			check(Compare.equivalent(before, state.to_data()), "Actual dispatch comparison only mutates its private clone")
	var state: RefCounted = filled_region_fixture()
	state.gold = 1000
	var ex: RefCounted = state.progression.expansion
	ex.pending.dewgrass = 3
	var before: Dictionary = state.to_data().duplicate(true)
	check(Status.region_status(state, "forest_edge") == "특별 탐색 대기", "Existing pending material does not falsely block an affordable material-free special search")
	check(Compare.equivalent(before, state.to_data()), "Pending rewards survive special-search projections")
	Trips.tick(state, 0.0) # Setup one real isolated special leg, no visible app.
	before = state.to_data().duplicate(true)
	var special := Status.region(state, "forest_edge")
	check(special.mode == "special" and Status.region_status(state, "forest_edge") == "특별 탐색 중" and special.status.contains("특별 탐색") and special.next_mode.is_empty(), "The current paid special leg shows its actual kind without a next-departure reroll")
	check(Compare.equivalent(before, state.to_data()), "Running special status never exposes or redraws its stored outcome")
	ex.cycles.forest_edge.running = false
	ex.rare_discovered.append(Rare.by_region("forest_edge").id)
	before = state.to_data().duplicate(true)
	var idle := Status.region(state, "forest_edge")
	check(idle.mode == "normal" and idle.next_mode.is_empty() and idle.status != "특별 탐색 중", "Discovery stops paid special repeats and discards stale display mode while retaining material wait")
	check(Compare.equivalent(before, state.to_data()), "A discovered idle projection grants no material/purchase and starts no trip")

func run() -> void:
	if DisplayServer.get_name() != "headless":
		push_error("Pure recipe/effect status checks require headless mode")
		quit(1)
		return
	verify_maximum_effects()
	verify_expedition_timing()
	verify_ingredients()
	verify_priority_and_mask()
	verify_special_departure_budget()
	if failures == 0: print("RECIPE EFFECT STATUS PASS: %d pure checks; all 16 maxed tracks, retained earlier keys/final replacement values, real sales interval, separate 16/14/capped30 percent trip timing and immutable paid legs, complete real one-bottle blends/current reserved vs next shortages, ordinary higher/fallback/first/full/unpurchased states, shared special discovery masks, pure special/ordinary protection budgets cross-checked against actual cloned dispatch and unchanged complete state/RNG; headless only" % checks)
	else: print("RECIPE EFFECT STATUS FAILED: %d/%d" % [failures, checks])
	quit(1 if failures else 0)
