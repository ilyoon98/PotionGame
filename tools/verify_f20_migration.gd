extends SceneTree
const State = preload("res://scripts/shop_state.gd")
const Old = preload("res://.verification/f20-20261020/baseline/scripts/shop_state.gd")
const F = preload("res://tests/late_investment_fixture.gd")
const M = preload("res://tests/contracts_fixture.gd")
const Compare = preload("res://tests/state_compare.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	for version in range(1, 12):
		var old := Old.new(); old.gold = 23456; old.level = 2
		old.brew_active = true; old.brew_elapsed = 1.25; old.progression.active_recipe = false
		var saved: Dictionary = M.data(old); saved.version = version
		if version < 11: saved.erase("late_investments"); saved.erase("report_supply")
		if version < 10: saved.erase("contracts")
		if version < 5: saved.erase("progression")
		if version < 4: saved.erase("inventory")
		var current := State.new()
		check(current.load_data(saved), "Load real v11-format downgraded compatibility fixture%d" % version)
		check(current.gold == old.gold and current.brew_active and is_equal_approx(current.brew_elapsed, 1.25), "Version%d preserves cash and already-paid ordinary timer" % version)
		check(current.workshop.level == 0 and current.workshop.aux.is_empty() and not current.stock_protection.active, "Version%d no unpaid auxiliary; free protection starts off before the first contract" % version)
	var source := F.completed_store(73129, "final", "both3", "inventory_full")
	var saved: Dictionary = M.data(source); saved.version = 11; saved.erase("stock_protection"); saved.erase("workshop")
	var old := Old.new(); check(old.load_data(saved), "Actual old contract store loads in frozen v11")
	old._start_batch(); old.brew_elapsed = old.brew_duration() * 0.33
	var restored := State.new(); check(restored.load_data(M.data(old)), "Migration of paid main contract with all old F19 ownership")
	check(Compare.equivalent(old.contracts.to_data(), restored.contracts.to_data()) and Compare.equivalent(M.materials(old), M.materials(restored)) and restored.progression.seed_value == old.progression.seed_value and restored.gold == old.gold and restored.brew_elapsed == old.brew_elapsed, "No contract history, resources, judgement, RNG or elapsed changes")
	check(restored.workshop.aux.is_empty() and restored.workshop.main_duration == 0, "No new line before purchase")
	# All one-to-four actual auxiliary quantities; verify successful and failed
	# real RNG judgements without editing an already reserved outcome.
	for quantity in range(1, 5):
		for failure in [false, true]:
			var s := F.completed_store(73129, "final", "both3", "inventory_full")
			s.gold = 10000000; s.shop_open = false
			check(s.workshop.purchase(s, 1).ok, "Actual expansion purchase")
			var choice: Dictionary = s.contracts.candidate(s, s.stock_protection.reserve_materials(s), true)
			var recipe: Dictionary = State.Content.lookup("potions", choice.id).ingredients
			M.clear_materials(s)
			for material in recipe:
				var amount: int = int(recipe[material]) * (quantity + 1)
				if material == "herb": s.herbs = amount
				elif material == "moon_mushroom": s.mushrooms = amount
				elif material == "starleaf": s.progression.rare_herbs = amount
				else: s.progression.expansion.materials[material] = amount
			s.workshop.seed = 44488 if failure else 1
			var inventory: Array = s.inventory.duplicate()
			var materials: Dictionary = M.materials(s)
			var main_seed: int = s.progression.seed_value
			s._start_batch()
			var batch: Dictionary = s.workshop.aux.batch.duplicate(true)
			check(int(batch.quantity) == quantity and bool(batch.success) != failure, "Actual quantity%d independent success=%s" % [quantity, not failure])
			check(s.progression.seed_value == main_seed, "Auxiliary RNG does not advance existing normal stream")
			for material in materials: check(int(materials[material])-s.material_count(material) == int(batch.ingredients.get(material, 0)), "Every consumed ingredient exactly once")
			var reloaded := State.new(); check(reloaded.load_data(M.data(s)), "Valid success or failure judgement restores without reroll")
			var old_shipped: int = s.contracts.totals.shipped
			var event: Dictionary = s.advance(float(batch.duration))
			check(int(s.contracts.totals.shipped)-old_shipped == (0 if failure else quantity), "Only real successful auxiliary bottles dispatch")
			check(event.potion_events.is_empty() and s.inventory == inventory and s.total_sold == 0, "No auxiliary bottle leaks into shelf or normal animation")
			var bad: Dictionary = M.data(reloaded); bad.workshop.aux.batch.chance = 0
			check(not State.new().load_data(bad), "Impossible zero auxiliary chance rejected even with forged false judgement")
	M.write_json("res://.verification/f20-20261020/B/migration.json", {"checks": checks, "failures": failures, "passed": failures.is_empty()})
	print("F20 MIGRATION %s %d checks" % ["PASS" if failures.is_empty() else "FAIL", checks]); quit(0 if failures.is_empty() else 1)
