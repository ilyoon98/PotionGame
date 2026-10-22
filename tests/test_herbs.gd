extends SceneTree

const State = preload("res://scripts/shop_state.gd")
const SaveStore = preload("res://scripts/save_store.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		push_error("FAIL: " + description)
		failures += 1


func equivalent(first: RefCounted, second: RefCounted) -> bool:
	return preload("res://tests/state_compare.gd").equivalent(first.to_data(), second.to_data())


func _run() -> void:
	var fresh := State.new()
	fresh.advance(0.01)
	check(fresh.herbs == 4 and fresh.brew_active, "A batch reserves exactly two herbs when it starts")
	fresh.advance(0.99)
	check(fresh.herbs == 4, "Repeated frames do not charge ingredients twice")
	var empty := State.new()
	empty.herbs = 0
	var events: Dictionary = empty.advance(3.9)
	check(empty.waiting_for_herbs() and empty.brew_elapsed == 0.0 and events["brewed"] == 0, "No herbs means no fake production or brewing progress")
	events = empty.advance(0.1)
	check(events["harvested"] == 2 and empty.brew_active and empty.herbs == 0, "Free harvest starts a waiting batch automatically")
	empty.advance(5.0)
	check(empty.stock == 1 and empty.gold == 0, "A harvested batch still takes its full brewing duration")
	empty.advance(0.6)
	check(empty.gold == 6, "Zero money and zero herbs can recover into a real sale")
	var all_empty := State.new()
	all_empty.herbs = 0
	all_empty.advance(1800.0)
	check(all_empty.gold > 0 and all_empty.total_sold > 0, "Thirty minutes unattended never deadlocks at zero resources")
	var closed := State.new()
	closed.shop_open = false
	closed.advance(86400.0)
	check(closed.stock == State.CAPACITY and closed.herbs == closed.herb_capacity() and closed.gold == 0, "Closed shop fills both stores without selling or overflowing")
	var stable: Dictionary = closed.to_data()
	closed.advance(300.0)
	check(closed.brew_elapsed == stable["brew_elapsed"] and closed.harvest_elapsed == stable["harvest_elapsed"] and closed.stock == stable["stock"] and closed.herbs == stable["herbs"], "Full stores pause both production timers while the world clock continues")
	closed.set_shop_open(true)
	closed.advance(3.2)
	check(closed.herbs == closed.herb_capacity() - 2 and closed.brew_active, "A freed shelf slot reserves the next recipe exactly once")
	closed.advance(0.5)
	check(closed.harvest_elapsed > 0.0 and closed.brew_elapsed > 0.0, "Growth and brewing both resume after storage frees up")
	var garden := State.new()
	garden.gold = 23
	check(not garden.upgrade_garden() and garden.gold == 23 and garden.garden_level == 1, "Insufficient gold cannot upgrade the garden")
	garden.gold = 24
	garden.harvest_elapsed = 2.0
	check(garden.upgrade_garden() and garden.gold == 0 and garden.garden_level == 2, "Garden upgrade charges the displayed price")
	check(garden.herb_capacity() == 32 and is_equal_approx(garden.harvest_duration(), 3.44), "Garden upgrade improves storage and free-harvest speed")
	check(is_equal_approx(garden.harvest_elapsed / garden.harvest_duration(), 0.5), "Garden upgrade preserves partial growth")
	garden.garden_level = State.MAX_GARDEN_LEVEL
	garden.gold = 1000000
	check(not garden.upgrade_garden() and garden.gold == 1000000, "Maximum garden level cannot consume money")
	var limited := State.new()
	limited.herbs = 0
	limited.level = State.MAX_LEVEL
	limited.advance(60.0)
	check(limited.total_sold <= 15, "A fast cauldron cannot bypass ingredient supply")
	var conservation := State.new()
	conservation.level = State.MAX_LEVEL
	events = conservation.advance(1800.0)
	check(State.STARTING_HERBS + events["harvested"] == conservation.herbs + State.HERBS_PER_POTION * (events["brewed"] + int(conservation.brew_active)), "Every harvested herb is stored or committed to exactly one potion")
	for pair in [Vector2i(1, 1), Vector2i(8, 1), Vector2i(2, 8), Vector2i(15, 12)]:
		var coarse := State.new()
		coarse.level = pair.x
		coarse.garden_level = pair.y
		coarse.herbs = 0
		var fine := State.new()
		fine.load_data(coarse.to_data())
		coarse.advance(1800.0)
		for frame in range(54000):
			fine.advance(1.0 / 30.0)
		check(equivalent(coarse, fine), "Thirty-minute coarse/fine simulation matches at cauldron %d, garden %d" % [pair.x, pair.y])
	var resumed := State.new()
	resumed.load_data(fresh.to_data())
	fresh.advance(17.123)
	resumed.advance(17.123)
	check(equivalent(fresh, resumed), "Saving mid-batch does not charge ingredients again on resume")
	var legacy: Dictionary = fresh.to_data()
	legacy["version"] = 1
	for key in ["herbs", "garden_level", "harvest_elapsed", "brew_active"]:
		legacy.erase(key)
	var migrated := State.new()
	check(migrated.load_data(legacy) and migrated.gold == fresh.gold and migrated.level == fresh.level and migrated.stock == fresh.stock, "Version-one migration preserves existing economy")
	check(migrated.herbs == State.STARTING_HERBS and migrated.garden_level == 1 and migrated.brew_elapsed == fresh.brew_elapsed and migrated.brew_active, "Migration supplies a starter garden and honors the current batch")
	var invalid: Dictionary = fresh.to_data()
	invalid.erase("herbs")
	var before: Dictionary = migrated.to_data()
	check(not migrated.load_data(invalid) and migrated.to_data() == before, "Incomplete version-two payload is rejected atomically")
	invalid = fresh.to_data()
	invalid["harvest_elapsed"] = NAN
	check(not migrated.load_data(invalid) and migrated.to_data() == before, "Invalid growth timer cannot partially overwrite a save")
	invalid = fresh.to_data()
	invalid["brew_active"] = "yes"
	check(not migrated.load_data(invalid), "Invalid reserved-batch flag is rejected")
	invalid = fresh.to_data()
	invalid["herbs"] = 999999
	invalid["garden_level"] = 999
	check(migrated.load_data(invalid) and migrated.herbs == migrated.herb_capacity() and migrated.garden_level == State.MAX_GARDEN_LEVEL, "Saved herb stock and garden levels clamp to supported limits")
	var path := "res://.verification/herb-save.json"
	DirAccess.make_dir_recursive_absolute("res://.verification")
	check(SaveStore.write_from(resumed, path) == OK, "Ingredient progress writes to disk")
	var disk := State.new()
	check(SaveStore.read_into(disk, path) == "loaded" and equivalent(resumed, disk), "Ingredients, reservations and growth survive a file round trip")
	print("HERB RESULT: ", failures, " failures")
	quit(0 if failures == 0 else 1)
