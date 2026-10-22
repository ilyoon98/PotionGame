extends SceneTree
const State = preload("res://scripts/shop_state.gd")
const Late = preload("res://scripts/shop_late_investments.gd")
const Baseline = preload("res://.verification/f19-20261019/baseline/scripts/shop_state.gd")
const F = preload("res://tests/late_investment_fixture.gd")
const M = preload("res://tests/contracts_fixture.gd")
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func normalized_old(state: RefCounted) -> Dictionary:
	var saved := F.data(state)
	saved.version = 10
	saved.erase("late_investments")
	saved.erase("report_supply")
	for field in ["quantity", "ingredients", "duration", "chance", "success"]: saved.contracts.batch.erase(field)
	return saved


func fill_stock(state: RefCounted) -> void:
	state.inventory.clear()
	for index in state.capacity(): state.inventory.append(false)
	state.stock = state.inventory.size()
	state.mana_stock = 0


func pause_ordinary(state: RefCounted) -> void:
	state.shop_open = false
	state.auto_purchase = false
	fill_stock(state)
	state.brew_active = true
	state.progression.active_recipe = false
	state.active_mana = false
	state.contracts.clear_batch()
	state.progression.batch_success = true
	state.progression.batch_chance = 1.0


func test_baseline() -> void:
	for terms in ["standard", "final"]:
		var state := F.completed_store(73129, terms, "none", "normal")
		var old := Baseline.new()
		check(old.load_data(normalized_old(state)), "Frozen F18 baseline accepts equivalent stage0 fake store")
		for seconds in [59.999, 0.001, 60.0, 300.0]:
			var now_event: Dictionary = state.advance(seconds)
			var old_event: Dictionary = old.advance(seconds)
			check(M.stable_equal(now_event.potion_events, old_event.potion_events) and M.stable_equal(now_event.contract_events, old_event.contract_events), "Stage0 retains actual retail/contract bottles, prices, and completion order")
			check(M.stable_equal(normalized_old(state), F.data(old)), "Stage0 preserves F18 currencies, FIFO, all RNG streams, growth, trips, and statistics")
		check(state.late_investments.supply.is_empty() and state.late_investments.totals.is_empty(), "Unpurchased supply never creates a clock or deferred debt")
		check(state.late_investments.supply_view(state).status == "미구매", "Unpurchased public supply view is valid and typed")


func test_supply_order_and_split() -> void:
	var state := F.completed_store(73129, "final", "support1", "normal")
	pause_ordinary(state)
	state.progression.rare_herbs = state.progression.expansion.special_capacity() - 1
	state.progression.expansion.materials.dewgrass = state.progression.expansion.special_capacity() - 2
	state.late_investments.supply.elapsed = 59.0
	var cycle: Dictionary = state.progression.expansion.cycles.forest_edge
	cycle.merge({"id": 1, "fee": 0, "paid": false, "running": true, "elapsed": 59.0, "duration": 60.0, "rewards": {"dewgrass": 5}, "mode": "normal", "rare_valid": false, "rare_recipe": "", "rare_success": false, "rare_attempt": 0}, true)
	var seed_before: int = state.progression.seed_value
	var rare_seed: int = state.progression.expansion.rare_seed
	var trips_before: int = state.progression.totals.expeditions
	var event: Dictionary = state.advance(1.0)
	check(event.supply_events.size() == 1 and event.supply_events[0].material == "starleaf" and event.supply_events[0].quantity == 1, "Existing same-time expedition delivery precedes low-stock support selection and partial capacity clipping")
	check(state.progression.expansion.materials.dewgrass == state.progression.expansion.special_capacity() and state.progression.rare_herbs == state.progression.expansion.special_capacity(), "Simultaneous ordinary and support deliveries fill their actual separate spaces")
	check(state.progression.expansion.pending.get("dewgrass", 0) == 3 and state.progression.expansion.reward_totals.get("dewgrass", 0) == 5, "Five existing expedition units remain two deposited plus three pending, never overwritten or reclassified as support")
	check(state.progression.seed_value == seed_before and state.progression.expansion.rare_seed == rare_seed and state.progression.totals.expeditions == trips_before + 1, "Support itself consumes no RNG and invents no expedition/discovery return")
	var before := F.data(state)
	state.late_investments.supply_view(state)
	check(M.stable_equal(before, F.data(state)), "Supply progress projection is read-only")
	var coarse := F.completed_store(19337, "final", "both3", "scarce_upper")
	var fine := F.clone(coarse)
	coarse.advance(180.0)
	for tick in 720: fine.advance(0.25)
	check(M.stable_equal(F.data(coarse), F.data(fine)), "60-second support boundaries preserve full state under180-second versus quarter-second advance splitting")
	var restored := F.clone(fine)
	check(M.stable_equal(restored.late_investments.to_data(), fine.late_investments.to_data()), "Saved elapsed/reserved supply quantity/actual receipts restore exactly")
	var full := F.completed_store(73129, "final", "support1", "normal")
	pause_ordinary(full)
	var no_payment: Dictionary = full.advance(120.0)
	check(no_payment.supplied == 0 and full.late_investments.totals.is_empty() and is_zero_approx(full.late_investments.supply.elapsed), "Two full-storage periods expire without producing or accumulating support")
	full.progression.rare_herbs = 0
	full.late_investments.supply_tick(60.0)
	var supplied: Dictionary = full.late_investments.supply_boundary(full)
	check(supplied.quantity == int(Late.SUPPLY_QUANTITIES[1]), "After storage frees, only one newly due period is granted")


func test_actual_quantities() -> void:
	for quantity in range(1, 5):
		for succeeded in [true, false]:
			var state := F.completed_store(73129, "final", "bulk3", "normal")
			state.shop_open = false
			state.auto_purchase = false
			state.contracts.ordinary_batches = 4
			state.progression.expansion.materials.star_seed = quantity
			var before := M.materials(state)
			var shipped_before: int = state.contracts.totals.shipped
			var seed_before: int = state.progression.seed_value
			state._start_batch()
			var batch: Dictionary = state.contracts.batch.duplicate(true)
			check(batch.purpose == "contract" and batch.kind == "eternity" and batch.quantity == quantity, "Actual highest-kind contract batch sizes down to available1/2/3/4-bottle ingredients")
			for material in before:
				check(int(before[material]) - state.material_count(material) == int(M.ingredients(batch.kind).get(material, 0)) * quantity, "Every actual blend input is reserved once times the actual bottle count: " + material)
			var expected_seed: int = (seed_before * 48271) % 2147483647 if state.progression.batch_chance < 1.0 else seed_before
			check(state.progression.seed_value == expected_seed, "Multi-bottle reservation consumes exactly the old one batch RNG judgement")
			check(is_equal_approx(batch.duration, state.brew_duration_for(batch.kind)) and batch.chance == state.progression.batch_chance and batch.success == state.progression.batch_success, "Batch freezes actual kind time/chance/judgement without multiplying time by bottles")
			var reserved := M.materials(state)
			state._start_batch()
			check(M.materials(state) == reserved, "Repeated start cannot spend another multi-bottle blend")
			state.progression.batch_success = succeeded
			state.contracts.batch.success = succeeded
			state.brew_elapsed = state.brew_duration() * 0.4
			state = F.clone(state)
			state.shop_open = false
			state.auto_purchase = false
			check(state.contracts.batch.quantity == quantity and is_equal_approx(state.brew_elapsed / state.brew_duration(), 0.4), "Frozen bottle count and partial manufacture survive strict save restore")
			fill_stock(state)
			var stock_before: int = state.stock
			var event: Dictionary = state.advance(state.brew_duration() - state.brew_elapsed)
			check(event.potion_events.is_empty() and state.stock == stock_before and state.total_sold == 0, "Bulk success/failure never enters shelf inventory, retail customer events, or sale statistics")
			check(state.progression.totals.brewed == (quantity if succeeded else 0) and state.progression.totals.failed == (0 if succeeded else quantity), "Manufacture and failure statistics count actual bottles rather than start slots")
			check(int(state.contracts.totals.shipped) - shipped_before == (quantity if succeeded else 0), "Only successful reserved bottles directly enter actual contract shipments")
			if succeeded: check(event.contract_events.size() == 1 and event.contract_events[0].shipped == quantity, "One batch emits one dispatch carrying its actual quantity")
			else: check(event.contract_events.is_empty(), "A failed multi-bottle batch never dispatches a partial success")
			check(state.contracts.ordinary_batches == 0, "A multi-bottle batch consumes one contract start slot")
	# Isolated functional routes: these deliberately incomplete stores are not
	# loaded or used as eligibility/economy evidence; only the base blend path.
	for mana in [false, true]:
		var state := State.new()
		state.gold = 30
		state.shop_open = false
		state.auto_purchase = false
		state.herbs = 8
		state.mushrooms = 4
		state.progression.owned = ["agility"]
		state.progression.expansion.regions.append("star_garden")
		state.late_investments.stages.contract_batch = 3
		var partner := "academy" if mana else "caravan"
		check(state.contracts.accept(state, partner, F.option(state, partner, "basic").token).ok, "Basic health/mana functional contract has a real accepted ordinary family")
		state.contracts.ordinary_batches = 4
		var seed_before: int = state.progression.seed_value
		state._start_batch()
		check(state.contracts.batch.kind == mana and state.contracts.batch.quantity == 4 and state.herbs == 0 and state.mushrooms == (0 if mana else 4), "State reserves all eight herbs and all four mana mushrooms exactly once for four base bottles")
		check(state.progression.seed_value == seed_before and state.progression.batch_chance == 1.0, "Guaranteed base four-bottle batch adds no manufacture RNG draws")
		fill_stock(state)
		var event: Dictionary = state.advance(state.brew_duration())
		check(state.progression.totals.brewed == 4 and event.contract_events.size() == 1 and event.contract_events[0].shipped == 4 and state.mana_stock == 0 and event.potion_events.is_empty(), "Actual base bulk completion counts four manufactured/shipped bottles with no mana/common shelf duplicate")


func test_legacy_and_atomic() -> void:
	for version in range(1, 11):
		var source := State.new()
		source.gold = 23456
		source.level = 2
		source.brew_active = true
		source.brew_elapsed = 1.25
		source.progression.active_recipe = false
		var payload := F.data(source)
		payload.version = version
		payload.erase("late_investments")
		if version < 10: payload.erase("contracts")
		if version < 5: payload.erase("progression")
		if version < 4: payload.erase("inventory")
		var restored := State.new()
		check(restored.load_data(payload) and restored.gold == source.gold and restored.brew_active and is_equal_approx(restored.brew_elapsed, 1.25), "Version%d migrates without losing cash/current ordinary brew" % version)
		check(restored.late_investments.stages == {"supply_support": 0, "contract_batch": 0} and restored.late_investments.supply.is_empty(), "Version%d starts both late investments at zero without retroactive supply" % version)
	var modern := F.completed_store(73129, "final", "none", "normal")
	var old := Baseline.new()
	check(old.load_data(normalized_old(modern)), "Old contract fixture is valid in the frozen v10 model")
	old.contracts.ordinary_batches = 4
	old._start_batch()
	old.brew_elapsed = old.brew_duration() * 0.33
	var before_materials := M.materials(old)
	var restored := State.new()
	check(restored.load_data(F.data(old)), "Legacy v10 currently manufacturing contract migrates")
	check(restored.contracts.batch.quantity == 1 and restored.progression.seed_value == old.progression.seed_value and M.materials(restored) == before_materials and is_equal_approx(restored.brew_elapsed, old.brew_elapsed), "Legacy current contract reconstructs one already-paid bottle without reroll, reconsumption or timer loss")
	var target := F.completed_store(19337, "final", "both3", "normal")
	target.contracts.ordinary_batches = 4
	target._start_batch()
	var valid := F.data(target)
	var original := F.data(target)
	var malformed: Array = []
	var changed := valid.duplicate(true)
	changed.late_investments.stages.supply_support = 4
	malformed.append(changed)
	changed = valid.duplicate(true)
	changed.late_investments.supply.elapsed = -1
	malformed.append(changed)
	changed = valid.duplicate(true)
	changed.contracts.batch.quantity = 5
	malformed.append(changed)
	changed = valid.duplicate(true)
	changed.contracts.batch.ingredients.herb = 1
	malformed.append(changed)
	changed = valid.duplicate(true)
	changed.contracts.batch.success = not changed.progression.batch_success
	malformed.append(changed)
	changed = valid.duplicate(true)
	changed.erase("late_investments")
	malformed.append(changed)
	for payload in malformed:
		check(not target.load_data(payload) and M.stable_equal(original, F.data(target)), "Malformed quantity/supply/reservation/stage save is rejected atomically")


func run() -> void:
	test_baseline()
	test_supply_order_and_split()
	test_actual_quantities()
	test_legacy_and_atomic()
	var report := {"checks": checks, "failures": failures, "passed": failures.is_empty(), "source_sha256": {"shop_state": FileAccess.get_sha256("res://scripts/shop_state.gd"), "shop_contracts": FileAccess.get_sha256("res://scripts/shop_contracts.gd"), "shop_late_investments": FileAccess.get_sha256("res://scripts/shop_late_investments.gd")}, "actual_supply_quantities": Late.SUPPLY_QUANTITIES, "safety": "In-memory fake fixtures; isolated headless; no GUI/user saves/process actions"}
	F.write_json("res://.verification/late-investment-f19-20261019/integration.json", report)
	print("%s F19 integration %d checks %d failures" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
