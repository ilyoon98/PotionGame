extends SceneTree
const State = preload("res://scripts/shop_state.gd")
const SaveStore = preload("res://scripts/save_store.gd")
## F21: a rested keeper brews FRESH_SPEED work-seconds per real second.
const SPEED: float = preload("res://scripts/shop_keeper.gd").FRESH_SPEED
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		push_error("FAIL: " + description)
		failures += 1


func equivalent(a: RefCounted, b: RefCounted) -> bool:
	return preload("res://tests/state_compare.gd").equivalent(a.to_data(), b.to_data())


func _run() -> void:
	var supply := State.new()
	supply.gold = 100
	supply.herbs = 0
	supply.harvest_elapsed = 0
	supply.advance(11.9)
	check(supply.mushrooms == 0 and supply.total_spent_materials == 0, "No purchase before the scheduled delivery")
	var events: Dictionary = supply.advance(0.1)
	check(events["bought"] == 2 and supply.total_spent_materials == 8, "Delivery automatically pays for two mushrooms")
	check(supply.gold == 100 + supply.total_sales_gold - supply.total_spent_materials, "Purchases and real sales reconcile with the gold balance")
	var poor := State.new()
	poor.gold = 37
	poor.herbs = 0
	poor.delivery_elapsed = 11.99
	events = poor.advance(0.01)
	check(events["bought"] == 0 and poor.gold == 37 and poor.purchase_status().contains("자금 대기"), "Unaffordable delivery never spends the thirty-gold reserve")
	check(is_equal_approx(poor.delivery_elapsed, State.DELIVERY_INTERVAL), "An unfunded order retains completed progress")
	poor.gold = 38
	events = poor.advance(0.01)
	check(events["bought"] == 2 and poor.gold == 30, "Exact delivery budget leaves the full reserve")
	var capped := State.new()
	capped.gold = 100
	capped.herbs = 0
	capped.mushrooms = 5
	capped.delivery_elapsed = 11.99
	events = capped.advance(0.01)
	check(events["bought"] == 1 and capped.mushrooms == 6 and capped.gold == 96, "Only the remaining storage slot is purchased and charged")
	capped.delivery_elapsed = 11.99
	events = capped.advance(0.01)
	check(events["bought"] == 0 and capped.gold == 96, "Full mushroom stock prevents further spending")
	capped.advance(1.0)
	check(is_equal_approx(capped.delivery_elapsed, State.DELIVERY_INTERVAL), "Full material storage keeps the order ready without looping or resetting")
	var ready_restored := State.new()
	check(ready_restored.load_data(JSON.parse_string(JSON.stringify(capped.to_data()))) and is_equal_approx(ready_restored.delivery_elapsed, State.DELIVERY_INTERVAL), "A ready order survives save/load without restarting its timer")
	capped.mushrooms -= 1
	events = capped.advance(0.01)
	check(events["bought"] == 1 and capped.mushrooms == 6 and capped.gold == 92, "A ready order fills newly freed material space immediately")
	var closed := State.new()
	closed.gold = 1000
	closed.set_shop_open(false)
	closed.advance(3600.0)
	check(closed.gold == 1000 and closed.total_spent_materials == 0 and closed.delivery_elapsed == 0, "Closed shop never pays for deliveries")
	closed.set_shop_open(true)
	closed.advance(0.1)
	check(closed.mushrooms == 0, "Reopening does not trigger an accumulated delivery")
	var shelves := State.new()
	shelves.gold = 100
	shelves.stock = State.CAPACITY
	shelves.delivery_elapsed = 11.99
	events = shelves.advance(0.01)
	check(events["bought"] == 2 and shelves.gold == 92 and shelves.stock == State.CAPACITY, "Full potion shelves do not block separate material procurement")
	var held := State.new()
	held.auto_purchase = false
	held.advance(2.0)
	var held_work: float = 2.0 * SPEED
	held.stock = State.CAPACITY
	held.customer_elapsed = 0.0
	held.advance(2.0)
	check(held.brew_active and is_equal_approx(held.brew_elapsed, held_work), "An in-flight batch holds its progress while the shelf is full")
	held.advance(1.3)
	check(held.brew_elapsed > held_work and held.brew_elapsed < held_work + 0.2 * SPEED, "The same batch resumes as soon as a shelf slot opens")
	var toggle := State.new()
	toggle.delivery_elapsed = 7.0
	toggle.set_auto_purchase(false)
	toggle.advance(1.0)
	toggle.set_auto_purchase(true)
	check(toggle.delivery_elapsed == 7.0, "Turning procurement off and on preserves accumulated progress")
	var disabled := State.new()
	disabled.gold = 1000
	disabled.set_auto_purchase(false)
	disabled.advance(60.0)
	check(disabled.mushrooms == 0 and disabled.total_spent_materials == 0, "The automatic-purchase switch stops all material spending")
	check(disabled.level == 1 and disabled.garden_level == 1, "Neither upgrade is purchased automatically")
	var recipe := State.new()
	recipe.auto_purchase = false
	recipe.mushrooms = 1
	recipe.advance(0.1)
	check(recipe.active_mana and recipe.mushrooms == 0 and recipe.herbs == 4, "Available ingredients prioritize mana and reserve both ingredients once")
	check(is_equal_approx(recipe.brew_duration(), 6.25), "Mana takes one quarter longer than a health potion")
	var batch := State.new()
	batch.auto_purchase = false
	batch.advance(2.0 / SPEED)
	batch.mushrooms = 1
	batch.advance(2.0 / SPEED)
	check(not batch.active_mana and batch.mushrooms == 1 and is_equal_approx(batch.brew_elapsed, 4.0), "New ingredients never replace a batch already in progress")
	events = batch.advance(1.0 / SPEED)
	check(events["brewed"] == 1 and not events["last_brewed_mana"] and batch.active_mana, "Premium priority starts at the next batch boundary")
	var fallback := State.new()
	fallback.auto_purchase = false
	fallback.mushrooms = 1
	fallback.advance(6.25)
	check(fallback.mana_stock == 1 and not fallback.active_mana and fallback.is_brewing(), "Running out of mushrooms falls back to free-ingredient health potions")
	events = fallback.advance(0.15)
	check(events["earned"] == 18 and events["last_sold_mana"] and fallback.gold == 18, "Mana earns its actual eighteen-gold price")
	var mixed := State.new()
	mixed.auto_purchase = false
	mixed.stock = 2
	mixed.mana_stock = 1
	mixed.inventory.assign([false, true])
	mixed.progression.customer = 3 # No unlocked preference: preserves global FIFO.
	mixed.progression.customer_selected = true
	mixed.herbs = 0
	events = mixed.advance(3.2)
	check(events["earned"] == 6 and mixed.stock == 1 and mixed.mana_stock == 1, "Older health potion sells before newly stocked mana")
	mixed.progression.customer = 3
	mixed.progression.customer_selected = true
	events = mixed.advance(3.2)
	check(events["earned"] == 18 and mixed.stock == 0, "Newer mana potion waits its turn and sells at eighteen gold")
	var rich := State.new()
	rich.gold = 1000
	rich.level = 9
	rich.garden_level = 3
	var fine := State.new()
	fine.load_data(rich.to_data())
	rich.advance(1800.0)
	for index in range(54000):
		fine.advance(1.0 / 30.0)
	check(equivalent(rich, fine), "Thirty-minute automation matches across frame sizes and simultaneous events")
	check(rich.gold == 1000 + rich.total_sales_gold - rich.total_spent_materials, "Thirty-minute ledger balances without hidden spending")
	check(rich.mushrooms <= State.MUSHROOM_CAPACITY and rich.mana_stock <= rich.stock and rich.stock <= State.CAPACITY, "All ingredient and potion capacities hold during automation")
	var old: Dictionary = batch.to_data()
	old["version"] = 2
	for key in ["mana_stock", "mushrooms", "active_mana", "auto_purchase", "delivery_elapsed", "total_spent_materials", "total_sales_gold"]:
		old.erase(key)
	var migration := State.new()
	check(migration.load_data(old) and migration.gold == batch.gold and migration.herbs == batch.herbs and migration.garden_level == batch.garden_level, "Version-two migration preserves the garden and economy")
	check(migration.mana_stock == 0 and migration.mushrooms == 0 and migration.auto_purchase and not migration.active_mana, "Old potions remain health potions and new procurement starts on a fresh timer")
	var resume := State.new()
	recipe.auto_purchase = true
	check(resume.load_data(JSON.parse_string(JSON.stringify(recipe.to_data()))) and equivalent(recipe, resume), "Mana batch reservations survive JSON without double charging")
	recipe.advance(17.25)
	resume.advance(17.25)
	check(equivalent(recipe, resume), "Resumed premium production remains deterministic")
	var invalid: Dictionary = recipe.to_data()
	invalid["mushrooms"] = NAN
	var snapshot: Dictionary = resume.to_data()
	check(not resume.load_data(invalid) and resume.to_data() == snapshot, "Invalid ingredient payload is rejected before changing progress")
	invalid = recipe.to_data()
	invalid["auto_purchase"] = "on"
	check(not resume.load_data(invalid), "Malformed automatic-purchase setting is rejected")
	invalid = recipe.to_data()
	invalid["mana_stock"] = 999
	invalid["mushrooms"] = 999
	invalid["version"] = 3
	resume.load_data(invalid)
	check(resume.mana_stock <= resume.stock and resume.mushrooms == State.MUSHROOM_CAPACITY, "Malformed stock quantities cannot exceed real capacity")
	var path := "res://.verification/supply-save.json"
	DirAccess.make_dir_recursive_absolute("res://.verification")
	recipe.set_auto_purchase(false)
	var automatic_expected := recipe.to_data().duplicate(true)
	automatic_expected["auto_purchase"] = true
	check(SaveStore.write_from(recipe, path) == OK and SaveStore.read_into(resume, path) == "loaded" and preload("res://tests/state_compare.gd").equivalent(automatic_expected, resume.to_data()), "Legacy opt-out resumes procurement while retaining supply progress and balances")
	print("SUPPLY RESULT: ", failures, " failures")
	quit(0 if failures == 0 else 1)
