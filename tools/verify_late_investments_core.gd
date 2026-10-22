extends SceneTree
const State = preload("res://scripts/shop_state.gd")
const Content = preload("res://scripts/shop_content.gd")
const Contracts = preload("res://scripts/shop_contracts.gd")
const Late = preload("res://scripts/shop_late_investments.gd")
const F = preload("res://tests/contracts_fixture.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func fixture(rank: int = 4) -> RefCounted:
	var state := F.completed(73129)
	state.gold = 5000000
	# Trusted in-memory eligibility fixture; the fake grade history is never loaded.
	for partner in state.contracts.PARTNERS: state.contracts.partners[partner.id].points = Contracts.THRESHOLDS[rank - 1]
	return state

func serialized(module: RefCounted) -> Dictionary:
	return JSON.parse_string(JSON.stringify(module.to_data()))

func option(state: RefCounted, id: String, choice: String = "basic") -> Dictionary:
	for row in state.contracts.partner_view(state, id).options:
		if row.id == choice: return row.token
	return {}

func mark_brew(state: RefCounted, choice: Dictionary, success: bool = true) -> void:
	state.progression.active_recipe = choice.kind
	state.progression.batch_chance = choice.chance
	state.progression.batch_success = success
	state.contracts.reserve(choice, {"chance": choice.chance, "success": success})
	state.brew_active = true
	state.active_mana = choice.kind is bool and choice.kind

func test_training() -> void:
	var state := fixture(1)
	check(state.contracts.remaining_opportunities() == 9, "Fresh three partners have nine possible rank-one-through-three opportunities")
	check(state.contracts.accept(state, "caravan", option(state, "caravan")).ok, "Current base acceptance consumes its opportunity")
	check(state.contracts.remaining_opportunities() == 8 and state.contracts.training_view(state).can_buy, "Accepted first agreement retains future training opportunities")
	var gold: int = state.gold
	check(state.contracts.train(state, 1).ok and state.gold == gold - 8000, "Training uses the displayed next-stage token")
	var before := F.data(state)
	check(not state.contracts.train(state, 1).ok and F.stable_equal(before, F.data(state)), "A repeated stale stage cannot charge another price")
	state.contracts.partners.caravan.points = 240
	check(state.contracts.remaining_opportunities() == 7, "Skipped past grades are not recreated")
	for partner in Contracts.PARTNERS:
		state.contracts.partners[partner.id].points = 240
		state.contracts.seed = 1
		check(state.contracts.negotiate(state, partner.id, option(state, partner.id, "payment")).ok, "Rank-three current opportunity can be judged")
	check(state.contracts.remaining_opportunities() == 0, "Unaccepted successful judgement still consumes the chance")
	var view: Dictionary = state.contracts.training_view(state)
	check(not view.can_buy and view.reason == "적용할 흥정 없음" and view.level == 1 and view.next_level == 2, "No-use training is disabled without pretending the level is maxed")
	before = F.data(state)
	check(not state.contracts.train(state, 2).ok and F.stable_equal(before, F.data(state)), "No remaining chance means zero direct purchase mutation")
	for partner in Contracts.PARTNERS: state.contracts.partners[partner.id].points = 600
	check(state.contracts.remaining_opportunities() == 0 and not state.contracts.train(state, 2).ok, "Guaranteed final negotiations never justify probability training")
	state.contracts.training = 3
	check(state.contracts.training_view(state).reason == "최대 단계", "Actual purchased maximum remains distinct from spent opportunities")

func test_growth_and_purchase() -> void:
	var state := fixture()
	check(state.late_investments.growth_view(state).complete and state.late_investments.batch_max() == 1, "Existing growth gate has exactly the old thirty-two/eight/four/sixteen scope")
	for special in Content.RARE_ROWS: state.progression.owned.erase(special.id)
	state.progression.expansion.rare_discovered.clear()
	state.contracts.training = 0
	check(state.late_investments.growth_view(state).complete, "Special discoveries and training are not late investment prerequisites")
	var legacy := fixture()
	legacy.progression.expansion.staff.erase("sales_assistant")
	check(legacy.late_investments.growth_view(legacy).complete, "Legacy employee possession satisfies the old sales assistant ownership")
	for track in Late.EXISTING_STAGES:
		var lacking := fixture()
		lacking.progression.expansion.stages[track] = int(Late.EXISTING_STAGES[track]) - 1
		if track == "sales_counter": lacking.sales_counter_level = 9
		check(not lacking.late_investments.growth_view(lacking).complete and lacking.late_investments.view(lacking, "supply_support").reason == "가게 성장 완료 필요", "Each existing investment remains an independent required gate: " + track)
	var missing := fixture()
	missing.progression.owned.erase("vigor")
	check(not missing.late_investments.growth_view(missing).complete, "One missing ordinary recipe blocks late investment")
	for row in Content.DATA.regions:
		missing = fixture()
		if row.id == "forest_edge": missing.progression.expedition_count = int(row.complete_returns) - 1
		else: missing.progression.expansion.returns[row.id] = int(row.complete_returns) - 1
		check(not missing.late_investments.growth_view(missing).complete, "Each normal investigation completion is required: " + row.id)
	for employee in Late.EXISTING_EMPLOYEES:
		missing = fixture()
		missing.progression.expansion.staff.erase(employee)
		if employee == "sales_assistant": missing.progression.employee = false
		check(not missing.late_investments.growth_view(missing).complete, "Each employee is required: " + employee)
	state = fixture(1)
	check(state.late_investments.view(state, "supply_support").reason == "거래2등급 필요", "First late stage needs one actual rank-two partner")
	state.contracts.partners.caravan.points = 60
	check(state.late_investments.purchase(state, "supply_support", 1).ok, "One partner suffices; the other late track is not required")
	check(state.late_investments.view(state, "supply_support").reason == "거래3등급 필요", "Second stage requires the next actual grade")
	state.contracts.partners.caravan.points = 240
	check(state.late_investments.purchase(state, "supply_support", 2).ok, "Second late stage can follow immediately after satisfying real conditions")
	state.contracts.partners.caravan.points = 600
	check(state.late_investments.purchase(state, "supply_support", 3).ok, "No arbitrary time lock blocks a returning final-grade shop")
	var total := 900000
	for stage in range(1, 4):
		check(state.late_investments.purchase(state, "contract_batch", stage).ok, "The independent bulk track advances once with its displayed stage")
		total += int(Late.COSTS[stage - 1])
	check(state.gold == 5000000 - total and state.progression.totals.manual_spent == total and total == 1800000, "All six one-time costs reconcile once to direct investments")
	var before := F.data(state)
	check(not state.late_investments.purchase(state, "contract_batch", 3).ok and not state.late_investments.purchase(state, "contract_batch", 4).ok and F.stable_equal(before, F.data(state)), "Stale/max stage tokens never mutate or spend")
	missing = fixture()
	check(not missing.late_investments.purchase(missing, "contract_batch", 2).ok, "An unpurchased preceding stage cannot be skipped")
	missing.gold = 149999
	check(missing.late_investments.view(missing, "contract_batch").reason == "1 G 부족" and not missing.late_investments.purchase(missing, "contract_batch", 1).ok, "Displayed shortage matches actual refusal")
	var initial := F.data(state)
	for track in Late.TRACKS: state.late_investments.view(state, track)
	state.late_investments.supply_view(state)
	check(F.stable_equal(initial, F.data(state)), "All eligibility and supply views preserve complete state and RNG")

func test_supply() -> void:
	var state := fixture()
	var cold_before := F.data(state)
	var cold_view: Dictionary = state.late_investments.supply_view(state)
	check(not cold_view.purchased and cold_view.candidates.is_empty() and cold_view.status == "미구매" and F.stable_equal(cold_before, F.data(state)), "Unpurchased supply view is typed, safe and completely read-only")
	check(state.late_investments.purchase(state, "supply_support", 1).ok, "Supply first purchase starts a cycle")
	check(state.late_investments.supply.elapsed == 0.0 and state.late_investments.supply.quantity == Late.SUPPLY_QUANTITIES[1] and state.late_investments.totals.is_empty(), "First purchase reserves its current stage quantity but never grants immediately")
	state.progression.rare_herbs = 0
	state.progression.expansion.materials.dewgrass = 0
	var economy_before := F.data(state)
	state.late_investments.supply_tick(59.0)
	check(state.late_investments.supply_boundary(state).is_empty(), "No early supply is paid")
	state.late_investments.supply_tick(1.0)
	var supplied: Dictionary = state.late_investments.supply_boundary(state)
	check(supplied.material == "starleaf" and supplied.quantity == Late.SUPPLY_QUANTITIES[1], "Equal low storage chooses original catalog order")
	check(state.progression.seed_value == economy_before.progression.seed_value and state.progression.expansion.rare_seed == economy_before.progression.expansion.rare_seed and state.progression.totals.expeditions == economy_before.progression.totals.expeditions and state.progression.expansion.reward_totals == economy_before.progression.expansion.reward_totals, "Supply never rolls discoveries or changes expedition count/reward accounting")
	state.late_investments.supply_tick(30.0)
	var frozen: Dictionary = state.late_investments.supply.duplicate()
	check(state.late_investments.purchase(state, "supply_support", 2).ok and state.late_investments.supply == frozen, "Mid-cycle upgrade preserves elapsed and reserved quantity")
	state.late_investments.supply_tick(30.0)
	supplied = state.late_investments.supply_boundary(state)
	check(supplied.material == "dewgrass" and supplied.quantity == Late.SUPPLY_QUANTITIES[1] and state.late_investments.supply.quantity == Late.SUPPLY_QUANTITIES[2], "Arrival chooses the now-low material; increased quantity starts only the next cycle")
	F.fill_materials(state)
	state.progression.expansion.materials.star_seed = state.progression.expansion.special_capacity() - 1
	state.late_investments.supply_tick(60.0)
	supplied = state.late_investments.supply_boundary(state)
	check(supplied.material == "star_seed" and supplied.quantity == 1 and supplied.reserved_quantity == Late.SUPPLY_QUANTITIES[2], "Only empty storage is filled; excess is never stockpiled")
	state.late_investments.supply_tick(60.0)
	supplied = state.late_investments.supply_boundary(state)
	check(supplied.quantity == 0 and state.late_investments.supply.elapsed == 0.0 and state.late_investments.supply_view(state).status == "보관 가득", "A full-storage period passes without creating owed supply")
	check(state.late_investments.supply_boundary(state).is_empty(), "Repeated boundary calls cannot pay twice")
	var restored := Late.new()
	check(restored.load_data(serialized(state.late_investments), state) and serialized(restored) == serialized(state.late_investments), "Cycle and actual supply totals survive atomic JSON restore")
	var candidates: Array = state.late_investments.supply_candidates(state)
	check(candidates.size() == 9 and not candidates.has("herb") and not candidates.has("moon_mushroom"), "Only nine purchased-recipe special inputs and actual open sources qualify")
	var isolated := fixture()
	isolated.progression.owned.clear()
	isolated.progression.expansion.plants.clear()
	isolated.late_investments.stages.supply_support = 1
	isolated.late_investments.supply = {"elapsed": 0.0, "duration": 60.0, "quantity": Late.SUPPLY_QUANTITIES[1]}
	check(isolated.late_investments.supply_candidates(isolated).is_empty() and isolated.late_investments.supply_view(isolated).status == "대상 없음", "Unpurchased recipes and unopened sources do not leak into supply candidates")
	isolated.progression.owned = ["rare_forest_breath"]
	isolated.progression.expansion.rare_discovered.clear()
	check(isolated.late_investments.supply_candidates(isolated).is_empty(), "Malformed undiscovered rare ownership reveals no supply recipe")
	var pending: Dictionary = state.progression.expansion.pending.duplicate()
	state.progression.expansion.materials.star_seed = 0
	state.late_investments.supply_tick(60.0)
	state.late_investments.supply_boundary(state)
	check(state.progression.expansion.pending == pending, "Supply never overwrites pending expedition rewards")

func test_bulk() -> void:
	for maximum in range(1, 5):
		var state := fixture(1)
		state.late_investments.stages.contract_batch = maximum - 1
		check(state.contracts.accept(state, "caravan", option(state, "caravan")).ok, "Each bulk fixture accepts a real current agreement")
		state.contracts.ordinary_batches = 4
		var choice: Dictionary = state.contracts.candidate(state)
		check(choice.quantity == maximum and choice.id == "eternity", "Highest feasible kind is selected before sizing the actual batch")
		var row: Dictionary = Content.lookup("potions", choice.id)
		for material in row.ingredients: check(choice.ingredients[material] == int(row.ingredients[material]) * maximum, "Every input, including base herb, scales by actual quantity")
		mark_brew(state, choice)
		var frozen: Dictionary = state.contracts.batch.duplicate(true)
		state.late_investments.stages.contract_batch = 3
		check(state.contracts.batch == frozen, "Buying a larger bulk effect cannot resize a running batch")
		var before_gold: int = state.gold
		var result: Dictionary = state.contracts.complete(state, choice.kind)
		check(result.ok and result.shipped == maximum and state.contracts.totals.shipped == maximum and state.contracts.partners.caravan.round.base_total == int(state.contracts.partners.caravan.round.allowed[choice.id].unit) * maximum, "One successful batch directly dispatches all reserved bottles at frozen unit prices")
		check(state.gold == before_gold and state.total_sold == 0 and state.stock == 0 and state.progression.expansion.first_sold.size() > 0, "Partial dispatch changes neither cash nor normal inventory/sales")
		check(not state.contracts.complete(state, choice.kind).ok, "Repeated bulk completion cannot produce duplicate bottles")
	var state := fixture(1)
	state.late_investments.stages.contract_batch = 3
	state.contracts.accept(state, "caravan", option(state, "caravan"))
	state.contracts.ordinary_batches = 4
	state.progression.expansion.materials.star_seed = 1
	var choice: Dictionary = state.contracts.candidate(state)
	check(choice.id == "eternity" and choice.quantity == 1, "One high-tier bottle is preferred over four lower-tier bottles")
	state.progression.expansion.materials.star_seed = 42
	state.contracts.partners.caravan.round.shipped.vitality = 9
	choice = state.contracts.candidate(state)
	check(choice.quantity == 1, "Batch cannot spill past the family's last required bottle")
	state = fixture(1)
	state.late_investments.stages.contract_batch = 3
	state.progression.owned = ["agility", "purify", "moon"]
	state.contracts.accept(state, "caravan", option(state, "caravan"))
	state.contracts.ordinary_batches = 4
	choice = state.contracts.candidate(state)
	check(choice.kind is bool and not choice.kind and choice.quantity == 4 and choice.ingredients.herb == 8, "Basic health bulk reserves the entire actual herb blend")
	state.contracts.clear_batch()
	state.contracts.partner_cursor = 1
	state.contracts.accept(state, "academy", option(state, "academy"))
	state.progression.rare_herbs = 0
	choice = state.contracts.candidate(state)
	check(choice.kind is bool and choice.kind and choice.quantity == 4 and choice.ingredients.herb == 8 and choice.ingredients.moon_mushroom == 4, "Basic mana scales mushroom and herb together")
	mark_brew(state, choice, false)
	var before := serialized(state.contracts)
	check(not state.contracts.complete(state, choice.kind).ok and serialized(state.contracts) == before, "A failed multi-bottle judgement cannot dispatch any bottle")
	state.contracts.clear_batch()
	check(state.contracts.ordinary_batches == 0, "Bulk failure consumes one start slot, not a slot per bottle or a retry debt")

func test_atomic_restore() -> void:
	var state := fixture()
	state.late_investments.purchase(state, "supply_support", 1)
	state.late_investments.supply_tick(19.25)
	var good := serialized(state.late_investments)
	var changes: Array[Callable] = [func(x): x.stages.supply_support = true, func(x): x.stages.contract_batch = 4, func(x): x.supply.elapsed = -1, func(x): x.supply.elapsed = 61, func(x): x.supply.duration = 30, func(x): x.supply.quantity = Late.SUPPLY_QUANTITIES[2], func(x): x.supply.quantity = 2, func(x): x.totals.herb = 1, func(x): x.stages.unrelated = 1]
	for change in changes:
		var bad := good.duplicate(true)
		change.call(bad)
		var target := Late.new()
		var before := serialized(target)
		check(not target.load_data(bad, state) and serialized(target) == before, "Malformed late save is rejected without partial state")
	var no_grade := fixture(1)
	check(not Late.new().load_data(good, no_grade), "Owned late stage cannot bypass its historical trade grade requirement")
	var no_growth := fixture()
	no_growth.progression.owned.erase("vigor")
	check(not Late.new().load_data(good, no_growth), "Owned late stage cannot bypass old growth completion")
	check(Late.new().load_data(good), "Structural first pass can precede mutually dependent contract/late validation")
	state = fixture(1)
	state.late_investments.stages.contract_batch = 3
	state.contracts.accept(state, "caravan", option(state, "caravan"))
	state.contracts.ordinary_batches = 4
	var choice: Dictionary = state.contracts.candidate(state)
	mark_brew(state, choice)
	var context := {"chance": state.progression.batch_chance, "success": true, "max_quantity": 4, "duration": state.brew_duration_for(choice.kind)}
	var saved := serialized(state.contracts)
	var target := Contracts.new()
	check(target.load_data(saved, state.progression, true, choice.kind, context), "Actual quantity/material/time/chance/judgement survive new contract save")
	for field in ["quantity", "ingredients", "duration", "chance", "success"]:
		var bad := saved.duplicate(true)
		match field:
			"quantity": bad.batch.quantity = 5
			"ingredients": bad.batch.ingredients.herb -= 1
			"duration": bad.batch.duration = 0.0
			"chance": bad.batch.chance = 0.01
			"success": bad.batch.success = false
		var before := serialized(target)
		check(not target.load_data(bad, state.progression, true, choice.kind, context) and serialized(target) == before, "Invalid frozen field atomically rejects: " + field)
	var accelerated := saved.duplicate(true)
	accelerated.batch.duration = 0.81
	var before_fast := serialized(target)
	check(not target.load_data(accelerated, state.progression, true, choice.kind, context) and serialized(target) == before_fast, "An internally bounded duration cannot be faster than actually owned brewing effects")
	var weak_filter := fixture(1)
	weak_filter.progression.filter_owned = false
	weak_filter.progression.expansion.stages.erase("precision_filter")
	weak_filter.progression.active_recipe = choice.kind
	weak_filter.progression.batch_chance = 0.99
	weak_filter.progression.batch_success = true
	var excessive_chance := saved.duplicate(true)
	excessive_chance.batch.chance = 0.99
	var weak_context := context.duplicate()
	weak_context.chance = 0.99
	var before_chance := serialized(target)
	check(not target.load_data(excessive_chance, weak_filter.progression, true, choice.kind, weak_context) and serialized(target) == before_chance, "Even jointly forged progression and batch chance cannot exceed current filter plus the recipe's best environment")
	context.max_quantity = 1
	check(not target.load_data(saved, state.progression, true, choice.kind, context), "Saved batch cannot exceed the saved late stage's actual maximum")
	var old := saved.duplicate(true)
	for key in ["quantity", "ingredients", "duration", "chance", "success"]: old.batch.erase(key)
	check(not Contracts.new().load_data(old, state.progression, true, choice.kind, context), "New saves cannot silently treat missing bulk fields as legacy")
	var migrated := Contracts.new()
	check(migrated.load_data(old, state.progression, true, choice.kind, context, true) and migrated.batch.quantity == 1 and migrated.batch.ingredients.herb == 2, "Explicit legacy mode preserves an already-paid old batch at one bottle")
	check(migrated.batch.duration == context.duration and migrated.batch.chance == context.chance and migrated.batch.success == context.success, "Legacy migration never rerolls or restarts the saved batch")

func _initialize() -> void:
	var appdata := OS.get_environment("APPDATA").replace("\\", "/")
	if DisplayServer.get_name() != "headless" or not appdata.contains("/.verification/late-investment-f19-20261019/"):
		push_error("F19 core requires headless and isolated workspace APPDATA")
		quit(2)
		return
	test_training()
	test_growth_and_purchase()
	test_supply()
	test_bulk()
	test_atomic_restore()
	print("F19 CORE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
