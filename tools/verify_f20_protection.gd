extends SceneTree
const State = preload("res://scripts/shop_state.gd")
const F = preload("res://tests/late_investment_fixture.gd")
const M = preload("res://tests/contracts_fixture.gd")
const Compare = preload("res://tests/state_compare.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func stock(state: RefCounted, count: int) -> void:
	state.stock = count; state.mana_stock = 0; state.inventory.clear()
	for i in count: state.inventory.append(false)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	check(DisplayServer.get_name() == "headless", "Headless only")
	for c in [1, 12, 18, 128]:
		var expected: Dictionary = {1: {"low": 0, "high": 1}, 12: {"low": 3, "high": 5}, 18: {"low": 4, "high": 8}, 128: {"low": 6, "high": 12}}[c]
		check(State.StockProtection.thresholds(c) == expected, "Capacity thresholds %d" % c)
	check(State.StockProtection.thresholds(0).is_empty(), "Invalid zero capacity")
	var state := F.completed_store(73129, "final", "both3", "normal")
	var p = state.stock_protection
	stock(state, 6); state.contracts.ordinary_batches = 4; p.update(state)
	check(p.active and state.contracts.ordinary_batches == 0, "Low enters without contract debt")
	stock(state, 9); p.update(state); check(p.active, "Middle retains active")
	stock(state, 12); p.update(state); check(not p.active and state.contracts.ordinary_batches == 0, "High releases; requires four new ordinary starts")
	stock(state, 9); p.update(state); check(not p.active, "Middle retains inactive")
	var before: Dictionary = M.data(state)
	for i in 30:
		var allowance: Dictionary = p.reserve_materials(state)
		state.contracts.candidate(state, allowance, true)
	check(Compare.equivalent(before, M.data(state)), "Candidate and material preview are pure")
	stock(state, 0); state.contracts.ordinary_batches = 4; state._start_batch()
	check(state.brew_active and state.contracts.batch.purpose == "ordinary", "Low retail starts ordinary rather than due shipment")
	var reserved: Dictionary = M.data(state)
	state._start_batch()
	check(Compare.equivalent(reserved, M.data(state)), "Existing retail timer, judgement and resources unchanged")
	var old: Dictionary = M.data(state); old.version = 11; old.erase("stock_protection")
	var migrated := State.new(); check(migrated.load_data(old), "v11 paid ordinary migration")
	check(migrated.stock_protection.active and Compare.equivalent(migrated.contracts.to_data(), state.contracts.to_data()), "Legacy low stock protection with contract history preserved")
	var corrupt: Dictionary = M.data(state); corrupt.stock_protection = 3
	before = M.data(migrated); check(not migrated.load_data(corrupt) and Compare.equivalent(before, M.data(migrated)), "Malformed protection atomic rejection")
	state = F.completed_store(19337, "final", "both3", "inventory_full")
	state._start_batch(); check(state.contracts.batch.purpose == "contract", "Full stock uses contract capacity")
	var paid: Dictionary = state.contracts.batch.duplicate(true)
	var consumed: Dictionary = M.materials(state)
	stock(state, 0); state._start_batch()
	check(state.stock_protection.active and Compare.equivalent(paid, state.contracts.batch) and Compare.equivalent(consumed, M.materials(state)), "Protection never cancels/rerolls/reconsumes current contract")
	state.advance(state.brew_duration())
	check(state.contracts.batch.purpose == "ordinary", "Current shipment completes; next main batch restores retail")
	# Real refill, then real resumed shipments and all original partner rotations.
	state = F.completed_store(9973, "final", "both3", "normal")
	state.shop_open = false
	var partners := {}; var resume_time := -1
	for second in 300:
		var event: Dictionary = state.advance(1.0)
		for start in event.get("batch_events", []):
			if start.purpose == "contract":
				partners[start.partner] = true
				if resume_time < 0: resume_time = second + 1
	check(resume_time > 0 and state.stock >= 12, "Retail actually recovers and shipments automatically resume")
	check(partners.size() == 3, "All three partners receive actual production after recovery")
	# Restrict ingredients after the pure retail allowance: actual1..4 bottle sizes.
	for quantity in range(1, 5):
		state = F.completed_store(73129, "final", "both3", "inventory_full")
		var choice: Dictionary = state.contracts.candidate(state, {}, true)
		var recipe: Dictionary = State.Content.lookup("potions", choice.id).ingredients
		M.clear_materials(state)
		for material in recipe:
			var amount: int = int(recipe[material]) * (quantity + 1)
			if material == "herb": state.herbs = amount
			elif material == "moon_mushroom": state.mushrooms = amount
			elif material == "starleaf": state.progression.rare_herbs = amount
			else: state.progression.expansion.materials[material] = amount
		state.contracts.partner_cursor = int(choice.partner_index)
		var hold := recipe.duplicate()
		var limited: Dictionary = state.contracts.candidate(state, hold, true)
		check(not limited.is_empty() and limited.quantity == quantity, "Actual quantity%d after allowance" % quantity)
		for material in limited.ingredients: check(int(limited.ingredients[material]) + int(hold.get(material, 0)) <= state.material_count(material), "No negative or double reservation")
	M.write_json("res://.verification/f20-20261020/A/functional.json", {"checks": checks, "failures": failures, "passed": failures.is_empty(), "actual_resume_seconds": resume_time, "partners": partners})
	print("F20-A %s %d checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)
