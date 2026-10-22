extends SceneTree
## F18 integration checks use only in-memory fixtures and workspace JSON outputs.
const State = preload("res://scripts/shop_state.gd")
const Content = preload("res://scripts/shop_content.gd")
const Rare = preload("res://scripts/rare_recipes.gd")
const Status = preload("res://scripts/management_status.gd")
const F = preload("res://tests/contracts_fixture.gd")
const Baseline = preload("res://.verification/contracts-20261015/retail-baseline/scripts/shop_state.gd")
const OUT := "res://.verification/contracts-f18-20261015/integration.json"
var checks := 0
var failures: Array[String] = []
var cases: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func option(state: RefCounted, id: String, choice: String = "basic") -> Dictionary:
	for row in state.contracts.partner_view(state, id).options:
		if row.id == choice: return row.token.duplicate(true)
	return {}


func accept(state: RefCounted, id: String, choice: String = "basic") -> void:
	var token := option(state, id, choice)
	if choice != "basic":
		state.contracts.seed = 1 # Deterministic isolated improved-success draw.
		check(state.contracts.negotiate(state, id, token).get("success", false), "Improved fake fixture has one fixed successful negotiation")
	check(state.contracts.accept(state, id, token).get("ok", false), "Contract fixture accepts a current valid option")


func clone(state: RefCounted) -> RefCounted:
	var restored := State.new()
	check(restored.load_data(F.data(state)), "F18 fake state roundtrips")
	return restored


func full_inventory(state: RefCounted) -> void:
	state.inventory.clear()
	for index in state.capacity(): state.inventory.append(false)
	state.stock = state.inventory.size()
	state.mana_stock = 0


func normalized_retail(state: RefCounted) -> Dictionary:
	var value := F.data(state)
	value.version = 9
	value.erase("contracts")
	return value


func test_retail_baseline() -> void:
	cases.append("no-contract pre-F18 baseline / retail FIFO / frame resolution")
	for seed_value in [1, 73129, 4444]:
		var state := clone(F.completed(seed_value))
		var before := normalized_retail(state)
		var old := Baseline.new()
		check(old.load_data(before), "Frozen pre-F18 all-special baseline accepts identical initial data")
		check(F.stable_equal(before, F.data(old)), "No-contract baseline starts with identical full retail state")
		for step in [0.15, 3.1, 45.0, 121.75]:
			var current_events: Dictionary = state.advance(step)
			var old_events: Dictionary = old.advance(step)
			check(current_events.potion_events == old_events.potion_events, "No-contract actual retail bottles/sale order/prices equal frozen pre-F18")
			check(current_events.get("contract_events", []).is_empty(), "No contract produces no contract side effects")
			check(F.stable_equal(normalized_retail(state), F.data(old)), "No-contract clocks, generators, stock, currencies, special/main RNG and stats match pre-F18")
	var fifo := State.new()
	fifo.herbs = 0
	fifo.harvest_elapsed = 0.0
	fifo.auto_purchase = false
	fifo.inventory = [false, true, false]
	fifo.stock = 3
	fifo.mana_stock = 1
	fifo.customer_elapsed = fifo.customer_interval() - 0.01
	fifo.progression.customer = 0
	fifo.progression.customer_selected = true
	var events: Dictionary = fifo.advance(0.01)
	check(events.sold == 1 and events.potion_events.size() == 1 and events.potion_events[0].mana == false and events.potion_events[0].index == 0, "Retail FIFO still sells the oldest selected kind at its actual index")
	check(fifo.inventory == [true, false], "Retail sale removes one existing bottle and preserves remaining order")


func test_batch_channels_and_reservation() -> void:
	cases.append("actual batch reservation / full-stock bypass / separate retail and contract event channels")
	var state := F.completed(1)
	state.shop_open = false
	state.auto_purchase = false
	accept(state, "caravan")
	state.contracts.ordinary_batches = 4
	var before := F.materials(state)
	var retail_cursors := [state.progression.recipe_cursor, state.progression.expansion.family_cursor, state.progression.expansion.rare_cursor, state.progression.expansion.rare_turn]
	state._start_batch()
	var reserved: Dictionary = state.contracts.batch.duplicate(true)
	var kind: Variant = state.progression.active_recipe
	check(state.brew_active and reserved.purpose == "contract" and reserved.kind == kind and reserved.partner == "caravan", "Due contract slot reserves actual partner/round/kind at start")
	if kind is String:
		state.progression.expansion.first_batches.append(kind)
		state.progression.expansion.first_brewed.erase(kind)
		state.progression.expansion.first_sold.erase(kind)
	var recipe := F.ingredients(kind)
	var after := F.materials(state)
	for material in before:
		check(int(before[material]) - int(after[material]) == int(recipe.get(material, 0)), "Contract ingredients reserved exactly once: " + material)
	state._start_batch()
	check(F.materials(state) == after and state.contracts.batch == reserved, "Starting again during an active batch cannot reserve twice")
	check(retail_cursors == [state.progression.recipe_cursor, state.progression.expansion.family_cursor, state.progression.expansion.rare_cursor, state.progression.expansion.rare_turn], "Contract reservation keeps ordinary family/special/legacy recipe cursors")
	check(state.contracts.ordinary_batches == 0, "Actual contract start consumes the fifth slot immediately")
	state.progression.batch_success = true
	state.brew_elapsed = state.brew_duration() * 0.4
	full_inventory(state)
	var snapshot := F.data(state)
	var restored := clone(state)
	restored.shop_open = false
	restored.auto_purchase = false
	check(F.stable_equal(F.data(restored).contracts, snapshot.contracts), "Mid-batch restore keeps reservation, round, phase and contracts RNG")
	check(restored.brew_active and restored.is_brewing() and restored.progression.active_recipe == kind and is_equal_approx(restored.brew_elapsed, state.brew_elapsed), "Contract continues while common inventory is full after restore")
	var projection := Status.production_current(restored)
	check(projection.kind == kind and projection.purpose == "contract" and projection.partner == reserved.partner and projection.round_id == reserved.round_id and is_equal_approx(projection.progress, 0.4) and projection.running, "Shared cauldron/gauge projection exposes actual reserved contract kind and progress at full inventory")
	var stock: int = restored.stock
	var gold: int = restored.gold
	var sales: int = restored.total_sales_gold
	var sold: int = restored.total_sold
	var shipped := int(restored.contracts.totals.shipped)
	var events: Dictionary = restored.advance(restored.brew_duration() - restored.brew_elapsed)
	check(events.get("potion_events", []).is_empty(), "Contract success adds no fake shelf bottle or ordinary customer sale event")
	check(events.get("contract_events", []).size() == 1 and int(restored.contracts.totals.shipped) == shipped + 1, "Actual contract completion ships exactly one through its separate channel")
	check(restored.stock == stock and restored.inventory == snapshot.inventory and restored.gold == gold and restored.total_sales_gold == sales and restored.total_sold == sold, "Partial shipping preserves common bottles, gold and all retail sale counters")
	if kind is String:
		check(not restored.progression.expansion.first_batches.has(kind) and restored.progression.expansion.first_brewed.has(kind) and not restored.progression.expansion.first_sold.has(kind), "Successful contract fulfills first manufacture, never first ordinary customer sale")
	check(not restored.contracts.complete(restored, kind).get("ok", true) and int(restored.contracts.totals.shipped) == shipped + 1, "Consumed completion reservation cannot ship twice")
	var again := clone(restored)
	again.shop_open = false
	again.auto_purchase = false
	again.advance(0.1)
	check(int(again.contracts.totals.shipped) == shipped + 1, "Post-completion save/reload cannot repeat a dispatch")
	var failed := F.completed(1)
	failed.shop_open = false
	failed.auto_purchase = false
	accept(failed, "caravan")
	failed.contracts.ordinary_batches = 4
	failed._start_batch()
	failed.progression.batch_success = false
	full_inventory(failed)
	var failed_count: int = failed.progression.totals.failed
	var fail_events: Dictionary = failed.advance(failed.brew_duration())
	check(fail_events.get("contract_events", []).is_empty() and fail_events.get("potion_events", []).is_empty() and int(failed.contracts.totals.shipped) == 0, "Failed contract batch never ships, pays, stocks or animates a retail bottle")
	check(failed.contracts.ordinary_batches == 0 and int(failed.progression.totals.failed) == failed_count + 1, "Failed started contract consumes its slot and records one manufacturing failure")
	var ordinary := State.new()
	ordinary.shop_open = false
	ordinary._start_batch()
	ordinary.brew_elapsed = 1.25
	full_inventory(ordinary)
	var ordinary_materials := F.materials(ordinary)
	ordinary.advance(0.25)
	check(ordinary.brew_active and is_equal_approx(ordinary.brew_elapsed, 1.25) and F.materials(ordinary) == ordinary_materials, "Existing ordinary batch pauses at full stock without re-reserving or losing progress")
	var in_progress := F.opened(1)
	in_progress.progression.owned = ["agility"]
	in_progress.progression.expedition_count = 3
	F.fill_materials(in_progress)
	in_progress._start_batch()
	in_progress.brew_elapsed = in_progress.brew_duration() * 0.3
	var old_kind: Variant = in_progress.progression.active_recipe
	var old_outcome: bool = in_progress.progression.batch_success
	var old_chance: float = in_progress.progression.batch_chance
	var old_seed: int = in_progress.progression.seed_value
	accept(in_progress, "academy")
	check(in_progress.upgrade(), "Ordinary preservation fixture performs a real cauldron upgrade")
	check(in_progress.purchase("vigor"), "Ordinary preservation fixture purchases a newly unlocked ordinary recipe")
	in_progress.progression.clock += 140.0
	in_progress.window_mode = State.WindowMode.MINIMAL
	var continued := clone(in_progress)
	check(continued.contracts.batch.purpose == "ordinary" and continued.progression.active_recipe == old_kind and continued.progression.batch_success == old_outcome and is_equal_approx(continued.progression.batch_chance, old_chance) and continued.progression.seed_value == old_seed and is_equal_approx(continued.brew_elapsed / continued.brew_duration(), 0.3), "Contract acceptance/real upgrade/purchase/weather/mode/restore preserve an already reserved ordinary batch and its judged result")


func test_phase_and_no_debt() -> void:
	cases.append("4:1 actual starts / failed slots / missing-candidate debt reset / boundary restore")
	var state := F.completed(1)
	state.shop_open = false
	state.auto_purchase = false
	for partner in state.contracts.PARTNERS: accept(state, partner.id)
	var events: Dictionary = state.advance(60.0)
	var starts: Array = events.get("batch_events", [])
	check(starts.size() >= 10, "Rich fake fixture produces multiple real scheduling cycles")
	for index in mini(15, starts.size()):
		check(starts[index].purpose == ("contract" if index % 5 == 4 else "ordinary"), "Actual start %d obeys ordinary4:contract1" % (index + 1))
	var missed := F.opened(1)
	missed.progression.owned = ["agility"]
	missed.herbs = 10
	missed.mushrooms = 0
	missed.progression.rare_herbs = 0
	missed.auto_purchase = false
	missed.shop_open = false
	accept(missed, "academy")
	missed.contracts.ordinary_batches = 4
	missed._start_batch()
	check(missed.brew_active and missed.progression.active_recipe == false and missed.contracts.batch.purpose == "ordinary" and missed.contracts.ordinary_batches == 0, "Unavailable fifth-slot contract falls back to a real ordinary start and resets phase without debt")
	missed.progression.batch_success = false
	missed.advance(missed.brew_duration())
	F.fill_materials(missed)
	missed._start_batch()
	check(missed.contracts.batch.purpose == "ordinary" and missed.contracts.ordinary_batches == 1, "Restored contract ingredients cannot collect a missed scheduling debt")
	var boundary := F.completed(1)
	boundary.shop_open = false
	boundary.auto_purchase = false
	accept(boundary, "caravan")
	boundary.contracts.ordinary_batches = 4
	var restored := clone(boundary)
	boundary._start_batch()
	restored._start_batch()
	check(boundary.contracts.batch == restored.contracts.batch and boundary.progression.active_recipe == restored.progression.active_recipe and boundary.progression.seed_value == restored.progression.seed_value, "Saving immediately before due boundary neither regrants nor skips a contract slot")
	var ordinary_fail := F.completed(1)
	ordinary_fail.shop_open = false
	ordinary_fail._start_batch()
	ordinary_fail.progression.batch_success = false
	ordinary_fail.advance(ordinary_fail.brew_duration())
	check(ordinary_fail.progression.totals.failed == 1 and ordinary_fail.contracts.ordinary_batches == 2 and ordinary_fail.brew_active, "Failed actual ordinary batch consumes its start slot; the following real ordinary start consumes the next slot")
	var coarse := F.completed(4444)
	for partner in coarse.contracts.PARTNERS: accept(coarse, partner.id)
	coarse = clone(coarse)
	var fine := clone(coarse)
	coarse.advance(180.0)
	for tick in 720: fine.advance(0.25)
	check(F.stable_equal(F.data(coarse), F.data(fine)), "Contract scheduling/failures/shipping/retail/growth/three RNG streams are independent of headless advance chunk size")


func direct_ship(state: RefCounted, partner: String, id: String) -> Dictionary:
	var round_data: Dictionary = state.contracts.partners[partner].round
	state.contracts.batch = {"purpose": "contract", "partner": partner, "round_id": round_data.id, "kind": false if id == "health" else true if id == "mana" else id}
	return state.contracts.complete(state, state.contracts.batch.kind)


func test_prices_rounds_and_stats() -> void:
	cases.append("mixed frozen units / one rounding and settlement / fresh next round / statistics")
	var state := F.opened(1)
	state.progression.owned = ["agility", "vigor"]
	F.fill_materials(state)
	accept(state, "caravan")
	var original: Dictionary = state.contracts.partners.caravan.round.duplicate(true)
	var actual_multiplier: float = state.contracts._multiplier(original.terms)
	check(original.allowed.health.unit == 6 and original.allowed.agility.unit == 28 and original.allowed.vigor.unit == 30, "First round snapshots actual low/high catalog unit prices")
	var gold: int = state.gold
	var base := 0
	var low_rounding := 0
	for index in 20:
		var id: String = ["health", "vigor"][index % 2] if index < 10 else "agility"
		base += int(original.allowed[id].unit)
		low_rounding += int(round(int(original.allowed[id].unit) * actual_multiplier))
		if index == 5:
			state.progression.expansion.stages.cauldron = 20
			state.progression.expansion.staff.append("brewing_assistant")
			state.progression.expansion.stages.brewing_assistant = 5
			state.progression.owned.append("fortune")
			state = clone(state)
			check(F.stable_equal(state.contracts.partners.caravan.round.allowed, original.allowed) and not state.contracts.partners.caravan.round.allowed.has("fortune"), "Mid-round quality upgrade/new recipe/save restore cannot change allowed kinds or unit snapshots")
		var result := direct_ship(state, "caravan", id)
		check(result.get("ok", false), "Mixed actual kind is eligible for its unfilled family")
		if index < 19:
			check(result.paid == 0 and state.gold == gold and state.contracts.partners.caravan.points == 0, "Partial family delivery never pays or grants completion performance")
	var partner: Dictionary = state.contracts.partners.caravan
	var payout := int(round(base * actual_multiplier))
	check(partner.last_round.base_total == base and partner.last_round.payout == payout and state.gold == gold + payout, "Mixed units sum first, then contract multiplier rounds once at completion")
	check(low_rounding != payout, "Mixed fixture distinguishes final-round rounding from per-bottle rounding")
	check(F.stable_equal(partner.last_round.shipped, {"vitality": 10, "craft": 10}) and partner.points == 20, "Both required families complete and grade1 basic grants actual20-bottle performance")
	check(partner.round.id != original.id and partner.round.allowed.has("fortune") and partner.round.allowed.health.unit == 7 and partner.round.allowed.vigor.unit == 36, "Automatic next round refreshes bought ordinary kinds and additive current quality only")
	check(partner.round.allowed.vigor.unit == int(round(30 * (1.0 + 0.12 + 0.07))), "New-recipe quality is additive, excluding customer preference and sales assistant flat")
	var summary := Status.lifetime_summary(state)
	check(summary.contract_paid == payout and summary.contract_shipped == 20 and summary.contract_rounds == 1 and summary.sales == 0 and summary.sold == 0 and summary.net == payout, "Lifetime summary includes contract income once and leaves ordinary sale totals separate")
	var paid := int(state.contracts.totals.paid)
	check(not state.contracts.complete(state, "agility").get("ok", true) and state.contracts.totals.paid == paid, "Completed round cannot be paid twice through duplicate completion")
	var restored := clone(state)
	check(F.stable_equal(restored.contracts.totals, state.contracts.totals) and restored.gold == state.gold and F.stable_equal(restored.contracts.partners.caravan.last_round, partner.last_round), "Paid boundary and next fresh round survive restore without duplicate gold")
	for rare in Rare.ROWS: check(not partner.round.allowed.has(rare.id), "Approved special potion excluded from contract allowed snapshot")


func test_rng_and_stale() -> void:
	cases.append("pure previews / separate RNG / negotiation one-shot / stale options")
	var state := F.completed(1)
	var before := F.data(state)
	for repeat in 10:
		state.contracts.training_view(state)
		for partner in state.contracts.PARTNERS:
			state.contracts.partner_view(state, partner.id)
		state.contracts.candidate(state)
		state.production_preview()
		Status.lifetime_summary(state)
	check(F.stable_equal(before, F.data(state)), "Contract and existing projections change neither state nor any RNG stream")
	var p_seed: int = state.progression.seed_value
	var rare_seed: int = state.progression.expansion.rare_seed
	var improved := option(state, "caravan", "payment")
	state.contracts.seed = 1
	check(state.contracts.negotiate(state, "caravan", improved).get("ok", false), "Current option can perform its one negotiation")
	var judged := F.data(state)
	check(state.progression.seed_value == p_seed and state.progression.expansion.rare_seed == rare_seed and state.contracts.seed != 1, "Negotiation consumes only its dedicated RNG")
	check(not state.contracts.negotiate(state, "caravan", option(state, "caravan", "relationship")).get("ok", true) and F.stable_equal(judged, F.data(state)), "Alternative option cannot reroll the same judged opportunity")
	var restored := clone(state)
	var judged_restored := F.data(restored)
	check(not restored.contracts.negotiate(restored, "caravan", improved).get("ok", true) and F.stable_equal(judged_restored, F.data(restored)), "Save restore preserves already judged opportunity")
	check(restored.contracts.accept(restored, "caravan", improved).get("ok", false), "Reserved successful proposal can be accepted once after restore")
	var accepted := F.data(restored)
	check(not restored.contracts.accept(restored, "caravan", option(restored, "caravan")).get("ok", true) and F.stable_equal(accepted, F.data(restored)), "Basic acceptance cannot replace already accepted improved agreement")
	var late := F.completed(1)
	var old := option(late, "academy", "payment")
	late.contracts.partners.academy.points = 60 # Isolated stale UI token, never saved.
	var unchanged := F.data(late)
	check(not late.contracts.negotiate(late, "academy", old).get("ok", true) and not late.contracts.accept(late, "academy", old).get("ok", true) and F.stable_equal(unchanged, F.data(late)), "Both negotiation and acceptance reject a stale lower-grade token atomically")
	var token := option(late, "academy")
	token.version += 1
	check(not late.contracts.accept(late, "academy", token).get("ok", true) and F.stable_equal(unchanged, F.data(late)), "Changed condition version is rejected without mutation")


func test_legacy_and_atomic() -> void:
	cases.append("save versions1..9 / malformed contract atomic rejection")
	for version in range(1, 10):
		var source := State.new()
		source.gold = 12345
		source.level = 2
		source.garden_level = 2
		source.total_sold = 7
		source.total_sales_gold = 50
		source.herbs = 12
		source.brew_active = true
		source.brew_elapsed = 1.5
		source.progression.active_recipe = false
		source.progression.reputation = 23
		source.progression.clock = 120.0
		source.inventory = [false, true]
		source.stock = 2
		source.mana_stock = 1
		var legacy := F.data(source)
		legacy.version = version
		legacy.erase("contracts")
		if version < 4: legacy.erase("inventory")
		if version < 5: legacy.erase("progression")
		var restored := State.new()
		check(restored.load_data(legacy), "Legacy v%d remains explicitly accepted" % version)
		check(restored.gold == 12345 and restored.level == 2 and restored.total_sold == 7 and restored.brew_active and is_equal_approx(restored.brew_elapsed, 1.5), "Legacy v%d preserves gold, basic upgrades, sales and already-paid current brew" % version)
		check(restored.contracts.training == 0 and restored.contracts.totals.shipped == 0 and restored.contracts.batch.purpose == "ordinary", "Legacy v%d migrates to unstarted contracts and an ordinary current batch" % version)
		if version >= 5:
			check(restored.progression.reputation == 23 and restored.progression.clock == 120.0 and restored.inventory == [false, true], "Legacy v%d preserves progression, inventory and accumulated clock" % version)
	var good := F.completed(1)
	accept(good, "caravan")
	good.contracts.ordinary_batches = 4
	good._start_batch()
	good.brew_elapsed = good.brew_duration() * 0.5
	var payload := F.data(good)
	var target := F.completed(4444)
	target.gold = 765432
	var before := F.data(target)
	var mutations: Array = []
	var changed := payload.duplicate(true)
	changed.contracts.batch.purpose = "auction"
	mutations.append(["unknown batch purpose", changed])
	changed = payload.duplicate(true)
	changed.contracts.batch.partner = "unknown"
	mutations.append(["unknown reserved partner", changed])
	changed = payload.duplicate(true)
	changed.contracts.batch.round_id = "caravan:999"
	mutations.append(["inconsistent reserved round", changed])
	changed = payload.duplicate(true)
	changed.contracts.partners.caravan.round.allowed.health.unit += 1
	mutations.append(["forged frozen unit price", changed])
	changed = payload.duplicate(true)
	changed.contracts.partners.caravan.round.shipped.vitality = -1
	mutations.append(["negative shipped count", changed])
	changed = payload.duplicate(true)
	changed.contracts.partners.caravan.round.shipped.craft = 999
	mutations.append(["overfilled family count", changed])
	changed = payload.duplicate(true)
	changed.contracts.partners.caravan.round.terms.option = "unknown"
	mutations.append(["unknown contract condition", changed])
	changed = payload.duplicate(true)
	changed.contracts.partners.caravan.round.id = "academy:1"
	mutations.append(["duplicate foreign round identifier", changed])
	changed = payload.duplicate(true)
	changed.contracts.partners.caravan.history["1"].success = true
	mutations.append(["unjudged success record inconsistency", changed])
	changed = payload.duplicate(true)
	changed.contracts.partners.caravan.round.allowed.rare_forest_breath = {"family": "vitality", "unit": 90}
	mutations.append(["special type in ordinary-only shipment", changed])
	changed = payload.duplicate(true)
	changed.progression.owned.erase("shadow_elixir")
	mutations.append(["no longer owned frozen allowed potion", changed])
	changed = payload.duplicate(true)
	changed.erase("contracts")
	mutations.append(["missing mandatory v10 contracts", changed])
	for item in mutations:
		check(not target.load_data(item[1]), "Malformed F18 save rejects " + item[0])
		check(F.stable_equal(before, F.data(target)), "Rejected F18 save is fully atomic: " + item[0])


func run() -> void:
	test_retail_baseline()
	test_batch_channels_and_reservation()
	test_phase_and_no_debt()
	test_prices_rounds_and_stats()
	test_rng_and_stale()
	test_legacy_and_atomic()
	F.write_json(OUT, {"checks": checks, "failures": failures, "cases": cases, "passed": failures.is_empty(), "safety": "Synthetic in-memory states only; workspace JSON; no GUI/current game/user save/registry/process action"})
	print("%s F18 integrated contracts: %d checks, %d failures" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
