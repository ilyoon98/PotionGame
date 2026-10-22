extends SceneTree
const State = preload("res://scripts/shop_state.gd")
const Contracts = preload("res://scripts/shop_contracts.gd")
const Content = preload("res://scripts/shop_content.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func fixture() -> RefCounted:
	var state := State.new()
	state.gold = 1000000
	state.progression.expansion.regions = ["star_garden"]
	state.progression.owned = ["moon", "purify", "agility", "vigor", "antidote", "fortune", "focus", "eternity", "sage_elixir", "worldtree_elixir", "shadow_elixir"]
	state.herbs = state.herb_capacity()
	state.mushrooms = state.MUSHROOM_CAPACITY
	state.progression.rare_herbs = state.progression.expansion.special_capacity()
	for row in Content.DATA.materials:
		if row.id not in ["herb", "moon_mushroom", "starleaf"]: state.progression.expansion.materials[row.id] = state.progression.expansion.special_capacity()
	return state

func data(module: RefCounted) -> Dictionary:
	return JSON.parse_string(JSON.stringify(module.to_data()))

func token(module: RefCounted, state: RefCounted, id: String, option: String = "basic") -> Dictionary:
	for choice in module.partner_view(state, id).options:
		if choice.id == option: return choice.token.duplicate(true)
	return {}

func accept_basic(module: RefCounted, state: RefCounted, id: String) -> void:
	check(module.accept(state, id, token(module, state, id)).ok, "Base proposal accepts once")

func reserve_batch(module: RefCounted, state: RefCounted, choice: Dictionary) -> void:
	# These module fixtures force a successful judgement without rolling RNG;
	# its chance, duration and cauldron context still use the real current recipe.
	var snapshot := choice.duplicate(true)
	snapshot["quantity"] = int(snapshot.get("quantity", 1))
	snapshot["duration"] = state.brew_duration_for(snapshot.kind)
	state.progression.active_recipe = snapshot.kind
	state.progression.batch_chance = state.progression.success_chance(snapshot.kind)
	state.progression.batch_success = true
	state.brew_active = true
	state.active_mana = snapshot.kind is bool and snapshot.kind
	module.reserve(snapshot, {"chance": state.progression.batch_chance, "success": true})

func send_one(module: RefCounted, state: RefCounted, id: String, potion: String = "") -> Dictionary:
	var p: Dictionary = module.partners[id]
	var selected := ""
	var family_index := 0
	for family in p.round.requirements:
		if p.round.shipped[family] >= p.round.requirements[family]:
			family_index += 1
			continue
		for allowed in p.round.allowed:
			if p.round.allowed[allowed].family == family and (potion.is_empty() or potion == allowed):
				selected = allowed
				break
		if not selected.is_empty(): break
		family_index += 1
	if selected.is_empty(): return {}
	module.ordinary_batches = 4
	var kind: Variant = false if selected == "health" else true if selected == "mana" else selected
	reserve_batch(module, state, {"partner": id, "round_id": p.round.id, "kind": kind, "id": selected, "family": p.round.allowed[selected].family, "family_index": family_index})
	return module.complete(state, kind)

func finish_round(module: RefCounted, state: RefCounted, id: String) -> Dictionary:
	var serial: int = int(module.partners[id].serial)
	var last := {}
	for index in 100:
		if module.partners[id].serial != serial: return last
		last = send_one(module, state, id)
		check(last.get("ok", false), "A real reserved successful bottle ships once")
	return last

func roundtrip(module: RefCounted, state: RefCounted, active: bool = false, kind: Variant = false) -> RefCounted:
	var restored := Contracts.new()
	check(restored.load_data(data(module), state.progression, active, kind, state.contract_batch_context()), "Contract snapshot survives JSON save roundtrip")
	check(data(restored) == data(module), "All contract snapshots, histories, counters and RNG survive")
	return restored

func test_initial_and_pure() -> void:
	var state := fixture()
	var module := Contracts.new()
	var before: Dictionary = state.to_data()
	var saved := data(module)
	for index in 12:
		for item in Contracts.PARTNERS: module.partner_view(state, item.id)
		module.training_view(state)
		module.candidate(state)
	check(state.to_data() == before and data(module) == saved, "Views and candidate leave complete economy and all RNG unchanged")
	check(module.candidate(state).is_empty() and module.totals == {"shipped": 0, "paid": 0, "rounds": 0, "points": 0}, "No accepted contract creates production or historical rewards")
	roundtrip(module, state)
	state.progression.expansion.regions.clear()
	check(not module.unlocked(state), "Star garden opening is required")
	check(not module.accept(state, "caravan", token(module, state, "caravan")).ok and not module.train(state).ok, "Locked system rejects acceptance and training without mutation")
	check(data(module) == saved, "Locked actions preserve state")
	state.progression.expansion.regions = ["star_garden"]
	check(module.unlocked(state) and state.progression.expansion.region_returns("star_garden", state.progression) == 0, "Opening unlocks before normal investigation completion")
	state.progression.owned.clear()
	var missing := module.partner_view(state, "caravan")
	check(missing.status.contains("기교") and not missing.options[0].can_accept, "Unavailable purchased family has its actual missing condition")
	check(not module.accept(state, "caravan", missing.options[0].token).ok and data(module) == saved, "Missing family does not consume opportunity or freeze an impossible round")
	for item in missing.allowed_items: check(not str(item.id).begins_with("rare_"), "Contract projections never reveal special recipes")

func test_negotiation_and_training() -> void:
	for stage in 4:
		var state := fixture()
		var module := Contracts.new()
		var spent: int = state.progression.totals.manual_spent
		var gold: int = state.gold
		for index in stage: check(module.train(state).ok, "Training is purchased without an employee prerequisite")
		var expected_cost := 0
		for index in stage: expected_cost += Contracts.TRAINING_COSTS[index]
		check(state.gold == gold - expected_cost and state.progression.totals.manual_spent == spent + expected_cost, "Training is one direct investment, not retail or material expense")
		check(is_equal_approx(module.training_view(state).chance, 0.6 + stage * 0.1), "Actual general chances are 60/70/80/90 percent")
		module.seed = 1
		var offer := token(module, state, "caravan", "payment")
		var main_seed: int = state.progression.seed_value
		var rare_seed: int = state.progression.expansion.rare_seed
		var result := module.negotiate(state, "caravan", offer)
		check(result.ok and result.success and is_equal_approx(result.chance, 0.6 + stage * 0.1), "Independent fixed-seed success uses the shown chance")
		check(state.progression.seed_value == main_seed and state.progression.expansion.rare_seed == rare_seed, "Negotiation never touches production/customer/expedition/discovery RNG")
		var frozen := data(module)
		check(not module.negotiate(state, "caravan", token(module, state, "caravan", "relationship")).ok and data(module) == frozen, "Changing an improvement cannot reroll the same opportunity")
		if stage < 3:
			check(module.train(state).ok, "Later training can be purchased")
			check(is_equal_approx(module.partner_view(state, "caravan").chance, result.chance), "Already rolled chance stays frozen after training")
		check(module.accept(state, "caravan", offer).ok, "Successful improvement can be accepted")
		var r: Dictionary = module.partners.caravan.round
		check(r.requirements == {"vitality": 12, "craft": 12} and is_equal_approx(module.partner_view(state, "caravan").multiplier, 1.80), "Payment option changes real quantity and the adjusted payment rule")
		var accepted := data(module)
		check(not module.accept(state, "caravan", token(module, state, "caravan")).ok and data(module) == accepted, "Same opportunity cannot accept another condition")
		roundtrip(module, state)
	var state := fixture()
	var failed := Contracts.new()
	failed.seed = 44488
	var result := failed.negotiate(state, "caravan", token(failed, state, "caravan", "relationship"))
	check(result.ok and not result.success, "Independent fixed-seed failure is covered")
	check(failed.partner_view(state, "caravan").options[0].can_accept, "First failure still permits the base agreement")
	accept_basic(failed, state, "caravan")
	check(failed.partners.caravan.round.requirements == {"vitality": 10, "craft": 10}, "Failure never applies larger failed quantities or penalties")
	var failed_save := data(failed)
	roundtrip(failed, state)
	check(not failed.negotiate(state, "caravan", token(failed, state, "caravan", "payment")).ok and data(failed) == failed_save, "Acceptance consumes a failed negotiation opportunity permanently")

func test_dispatch_and_snapshots() -> void:
	var state := fixture()
	var module := Contracts.new()
	for item in Contracts.PARTNERS: accept_basic(module, state, item.id)
	for index in 4:
		check(module.candidate(state).is_empty(), "First four actual starts remain ordinary")
		module.note_ordinary_start()
	var cursor: int = state.progression.expansion.family_cursor
	var choice := module.candidate(state)
	check(choice.partner == "caravan" and choice.id == "eternity", "Contract slot selects bought, feasible highest ordinary potion")
	check(state.progression.expansion.family_cursor == cursor, "Contract candidate never changes existing ordinary cursors")
	reserve_batch(module, state, choice)
	check(module.ordinary_batches == 0 and module.batch.kind == choice.kind, "Starting reservation consumes the single contract slot")
	var saved_batch: Dictionary = data(module).batch
	var restored := roundtrip(module, state, true, choice.kind)
	check(restored.batch == saved_batch and restored.candidate(state).is_empty(), "Resume preserves reserved purpose/kind and cannot repeat allocation slot")
	module.clear_batch()
	check(module.totals.shipped == 0 and module.candidate(state).is_empty(), "Failed batch consumes its start but never ships or retries immediately")
	for index in 4: module.note_ordinary_start()
	choice = module.candidate(state)
	check(choice.partner == "academy", "Partners rotate independently after an actual reserved attempt")
	reserve_batch(module, state, choice)
	var economy: Dictionary = state.to_data()
	var event := module.complete(state, choice.kind)
	check(event.ok and event.shipped == 1 and event.paid == 0 and module.totals.shipped == 1, "Partial dispatch records only the successful reserved bottle")
	check(state.to_data() == economy, "Partial dispatch does not alter retail stock, gold, sales, fame or RNG")
	check(not module.complete(state, choice.kind).ok and module.totals.shipped == 1, "Repeated completion cannot ship a second copy")
	var round_before: Dictionary = module.partners.caravan.round.duplicate(true)
	state.progression.expansion.stages.cauldron = 20
	state.progression.expansion.staff.append("brewing_assistant")
	state.progression.expansion.stages.brewing_assistant = 5
	state.progression.owned.append("restoration")
	check(module.partners.caravan.round == round_before, "Quality upgrades and new ownership do not rewrite a current round")
	var baseline_gold: int = state.gold
	var payment := finish_round(module, state, "caravan")
	var completed: Dictionary = module.partners.caravan.last_round
	var expected := 0
	for id in completed.shipped_by_kind: expected += int(completed.shipped_by_kind[id]) * int(round_before.allowed[id].unit)
	check(completed.base_total == expected and payment.paid == int(round(expected * 1.60)) and state.gold == baseline_gold + payment.paid, "Mixed kinds sum frozen unit prices, then round one adjusted total payment")
	check(module.partners.caravan.round.serial == 2 and module.partners.caravan.round.shipped == {"vitality": 0, "craft": 0}, "Completion automatically creates the next unique empty round")
	check(module.partners.caravan.round.allowed.has("restoration") and module.partners.caravan.round.allowed.health.unit == int(round(6 * 1.12)), "Next round refreshes owned kinds and quality only")
	var projected: Dictionary = module.partner_view(state, "academy")
	var current_health := 0
	var current_mana := 0
	for item in projected.allowed_items:
		if item.id == "mana": current_mana = item.price
	for item in projected.proposal_items:
		if item.id == "mana": current_health = item.price
	check(current_mana == 18 and current_health == int(round(18 * 1.12)), "Proposal price preview remains separate from the current round's frozen units")
	check(state.total_sales_gold == 0 and state.total_sold == 0 and state.progression.totals.sold == 0 and state.progression.reputation == 0 and state.progression.expansion.first_sold.is_empty(), "Contract payment/dispatch never impersonates an ordinary sale")
	roundtrip(module, state)
	module.report_paid = module.totals.paid
	roundtrip(module, state)

func test_grades_and_pending() -> void:
	var state := fixture()
	var module := Contracts.new()
	accept_basic(module, state, "caravan")
	for index in 3: finish_round(module, state, "caravan")
	check(module.grade("caravan") == 2 and module.partners.caravan.agreement.grade == 1, "Earned trade grade does not rewrite the accepted agreement")
	var old_round: Dictionary = module.partners.caravan.round.duplicate(true)
	module.seed = 1
	var offer := token(module, state, "caravan", "relationship")
	check(module.negotiate(state, "caravan", offer).success, "Grade-two opportunity can improve relationship terms")
	check(module.accept(state, "caravan", offer).ok, "Higher agreement enters pending state")
	check(module.partners.caravan.round == old_round and module.partners.caravan.pending.grade == 2, "Pending terms preserve every current-round field")
	finish_round(module, state, "caravan")
	check(module.partners.caravan.round.terms.option == "relationship" and module.partners.caravan.round.requirements == {"vitality": 24, "craft": 24} and module.partners.caravan.pending.is_empty(), "Only the next round takes accepted grade and improved quantities")
	for index in 2: finish_round(module, state, "caravan")
	check(module.grade("caravan") == 3 and module.partners.caravan.points == 272, "Relationship completions award shipped order quantity times two")
	var stale := token(module, state, "caravan", "payment")
	module.seed = 1
	check(module.negotiate(state, "caravan", stale).success, "Grade-three success may wait unaccepted")
	for index in 4: finish_round(module, state, "caravan")
	check(module.grade("caravan") == 4 and module.partners.caravan.history["3"].success, "Skipped negotiation keeps previous result history")
	var before := data(module)
	check(not module.accept(state, "caravan", stale).ok and data(module) == before, "A stale lower-grade success cannot be accepted later")
	var final_offer := token(module, state, "caravan", "payment")
	check(module.partner_view(state, "caravan").options.size() == 2, "Maximum grade omits the relationship condition")
	var unavailable := final_offer.duplicate()
	unavailable.option = "relationship"
	check(not module.negotiate(state, "caravan", unavailable).ok and not module.accept(state, "caravan", unavailable).ok, "Maximum-grade relationship cannot be invoked through stale or forged clicks")
	var seed_before := module.seed
	check(module.negotiate(state, "caravan", final_offer).success and module.seed == seed_before and module.partner_view(state, "caravan").chance == 1.0, "Final grade guarantees 100 percent without a pointless draw")
	check(module.accept(state, "caravan", final_offer).ok, "Final guaranteed proposal can be accepted")
	finish_round(module, state, "caravan")
	check(module.partners.caravan.round.requirements == {"vitality": 48, "craft": 48}, "Final improved order exceeds sixty-slot common inventory")
	finish_round(module, state, "caravan")
	check(module.grade("caravan") == 4 and module.partners.caravan.round.serial > 1, "Maximum grade contracts continue automatically")
	roundtrip(module, state)

func test_missed_slot() -> void:
	var state := fixture()
	var module := Contracts.new()
	accept_basic(module, state, "caravan")
	for index in 4: module.note_ordinary_start()
	state.herbs = 0
	state.progression.expansion.materials.clear()
	state.progression.rare_herbs = 0
	check(module.candidate(state).is_empty() and module.ordinary_batches == 4, "No actual start never advances phase")
	module.note_ordinary_start()
	check(module.ordinary_batches == 0, "A missed contract slot actually used by ordinary production leaves no debt")
	state = fixture()
	check(module.candidate(state).is_empty(), "Replenished ingredients do not immediately repay the missed slot")
	for index in 4: module.note_ordinary_start()
	check(not module.candidate(state).is_empty(), "Only four new ordinary starts offer another contract slot")
	state.stock = state.capacity()
	state.inventory = []
	for index in state.stock: state.inventory.append(false)
	check(not module.candidate(state).is_empty(), "Full common inventory never blocks an available contract batch")
	module.ordinary_batches = 0
	check(not module.candidate(state).is_empty(), "Full-storage exception avoids deadlock even before the next ordinary allocation slot")

func test_validation() -> void:
	var state := fixture()
	var module := Contracts.new()
	accept_basic(module, state, "caravan")
	send_one(module, state, "caravan", "health")
	var saved := data(module)
	var mutations: Array[Callable] = [
		func(x): x.version = 2,
		func(x): x.training = true,
		func(x): x.seed = 0,
		func(x): x.ordinary_batches = 5,
		func(x): x.report_paid = 1,
		func(x): x.totals.shipped += 1,
		func(x): x.partners.caravan.round.id = "academy:1",
		func(x): x.partners.caravan.round.serial = 2,
		func(x): x.partners.caravan.round.allowed.health.unit += 1,
		func(x): x.partners.caravan.round.allowed.rare_forest_breath = {"family": "nature", "unit": 80},
		func(x): x.partners.caravan.round.base_total += 1,
		func(x): x.partners.caravan.round.shipped.vitality = 11,
		func(x): x.partners.caravan.round.paid = true,
		func(x): x.partners.caravan.round.shipped_by_kind.unknown = 1,
		func(x): x.partners.caravan.round.allowed.health.family = "arcane",
		func(x): x.partners.caravan.agreement.option = "unknown",
		func(x): x.partners.caravan.history["1"].accepted = false,
		func(x): x.partners.caravan.history["1"].chance = 0.7,
		func(x): x.batch = {"purpose": "elsewhere"},
		func(x): x.partners.uninvited = {},
	]
	for mutate in mutations:
		var malformed := saved.duplicate(true)
		mutate.call(malformed)
		var destination := Contracts.new()
		destination.seed = 777
		var before := data(destination)
		check(not destination.load_data(malformed, state.progression, false, false), "Malformed contract snapshot is rejected")
		check(data(destination) == before, "Rejected load leaves destination entirely unchanged")
	for quality in ["cauldron_quality", "assistant_quality"]:
		var inflated := saved.duplicate(true)
		var inflated_round: Dictionary = inflated.partners.caravan.round
		inflated_round[quality] = 0.12 if quality == "cauldron_quality" else 0.07
		for id in inflated_round.allowed:
			var row := Content.lookup("potions", id)
			inflated_round.allowed[id].unit = int(round(int(row.sale_price) * (1.0 + float(inflated_round.cauldron_quality) + (float(inflated_round.assistant_quality) if not row.existing else 0.0))))
		inflated_round.base_total = 0
		for id in inflated_round.shipped_by_kind: inflated_round.base_total += int(inflated_round.shipped_by_kind[id]) * int(inflated_round.allowed[id].unit)
		var destination := Contracts.new()
		destination.seed = 777
		var before := data(destination)
		check(not destination.load_data(inflated, state.progression, false, false), "Internally consistent inflated snapshot quality cannot exceed actually owned equipment quality")
		check(data(destination) == before, "Inflated quality rejection is atomic despite matching unit prices and base total")
	module.ordinary_batches = 4
	var choice := module.candidate(state)
	reserve_batch(module, state, choice)
	var reserved := data(module)
	for active in [false, true]:
		var restored := Contracts.new()
		check(not restored.load_data(reserved, state.progression, active, "purify"), "Reserved kind/purpose must match actual running cauldron")
	roundtrip(module, state, true, choice.kind)
	var malformed := reserved.duplicate(true)
	malformed.ordinary_batches = 4
	check(not Contracts.new().load_data(malformed, state.progression, true, choice.kind), "Started contract allocation cannot regain its consumed phase")
	var unowned := fixture()
	unowned.progression.owned.erase("eternity")
	check(not Contracts.new().load_data(saved, unowned.progression, false, false), "Frozen lists cannot include an unowned ordinary potion")
	var locked := fixture()
	locked.progression.expansion.regions.clear()
	check(not Contracts.new().load_data(saved, locked.progression, false, false), "Saved contract progress cannot bypass the opening gate")
	var phantom := Contracts.new().to_data()
	phantom.partners.caravan.history = module.partners.caravan.history.duplicate(true)
	check(not Contracts.new().load_data(phantom, state.progression, false, false), "An accepted history without an agreement and round is rejected")
	var training_only := Contracts.new()
	check(training_only.train(state).ok and not Contracts.new().load_data(data(training_only), locked.progression, false, false), "Training alone also requires the saved opening gate")

func test_stale_and_failed_upgrade() -> void:
	var state := fixture()
	var module := Contracts.new()
	var original := token(module, state, "caravan", "payment")
	for key in ["option", "grade", "opportunity", "version"]:
		var stale := original.duplicate()
		stale.erase(key)
		var before := data(module)
		check(not module.negotiate(state, "caravan", stale).ok and not module.accept(state, "caravan", stale).ok and data(module) == before, "Both actions require all four immutable opportunity fields")
	var wrong := original.duplicate()
	wrong.version = 2
	check(not module.negotiate(state, "caravan", wrong).ok and not module.accept(state, "caravan", wrong).ok, "Both actions reject a stale condition version")
	wrong = original.duplicate()
	wrong.opportunity = "academy:1:v1"
	check(not module.negotiate(state, "caravan", wrong).ok and not module.accept(state, "caravan", wrong).ok, "An opportunity cannot be replayed for another partner")
	module.seed = 1
	check(module.negotiate(state, "caravan", original).success, "Fixed successful result is available")
	var success := data(module)
	check(not module.accept(state, "caravan", token(module, state, "caravan")).ok and data(module) == success and not module.partner_view(state, "caravan").options[0].can_accept, "A successful proposal cannot be replaced by a contradictory base acceptance")
	check(module.accept(state, "caravan", original).ok, "Only the successful chosen proposal is accepted")
	for index in 3: finish_round(module, state, "caravan")
	check(module.grade("caravan") == 2, "Quantity-based payment agreements reach the next grade")
	module.seed = 44488
	check(not module.negotiate(state, "caravan", token(module, state, "caravan", "relationship")).success, "A grade upgrade can fail without cancelling the old agreement")
	var current: Dictionary = module.partners.caravan.round.duplicate(true)
	finish_round(module, state, "caravan")
	check(module.partners.caravan.round.terms == current.terms and module.partners.caravan.points > 60, "Failure and deferred negotiation leave automatic old-term shipments running")
	check(module.accept(state, "caravan", token(module, state, "caravan")).ok, "Failed upgrade still permits the current grade's base agreement")
	roundtrip(module, state)
	var pending: Dictionary = module.partners.caravan.pending.duplicate(true)
	for index in 7: finish_round(module, state, "caravan")
	check(module.grade("caravan") == 3 and module.partners.caravan.agreement == pending, "An accepted pending condition survives later earned-grade changes")
	check(module.accept(state, "caravan", token(module, state, "caravan")).ok and module.partners.caravan.pending.grade == 3, "A higher-grade acceptance can replace the pending proposal")
	roundtrip(module, state)

func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		push_error("Contract core verification requires headless")
		quit(2)
		return
	var appdata := OS.get_environment("APPDATA").replace("\\", "/")
	if not appdata.contains("/.verification/contracts-core-appdata"):
		push_error("Contract core verification requires isolated workspace APPDATA")
		quit(2)
		return
	test_initial_and_pure()
	test_negotiation_and_training()
	test_dispatch_and_snapshots()
	test_grades_and_pending()
	test_missed_slot()
	test_validation()
	test_stale_and_failed_upgrade()
	print("Contract core verification: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
