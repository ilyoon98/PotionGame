extends SceneTree

const State = preload("res://scripts/shop_state.gd")
const SaveStore = preload("res://scripts/save_store.gd")
const RecentIncome = preload("res://scripts/recent_income.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		push_error("FAIL: " + description)
		failures += 1


func same_progress(first: RefCounted, second: RefCounted) -> bool:
	return preload("res://tests/state_compare.gd").equivalent(first.to_data(), second.to_data())


func _run() -> void:
	var state := State.new()
	state.advance(5.0)
	check(state.stock == 1 and state.gold == 0, "First potion completes at five seconds")
	state.advance(1.4)
	check(state.stock == 0 and state.gold == 6 and state.total_sold == 1, "Customer purchases stock for six gold")
	var coarse := State.new()
	var fine := State.new()
	coarse.advance(180.0)
	for index in range(5400):
		fine.advance(1.0 / 30.0)
	check(coarse.gold == fine.gold and coarse.stock == fine.stock and coarse.total_sold == fine.total_sold, "Economy is consistent across frame rates")
	check(not state.upgrade() and state.level == 1 and state.gold == 6, "Insufficient funds cannot buy an upgrade")
	state.gold = 30
	var progress := state.brew_elapsed / state.brew_duration()
	check(state.upgrade() and state.level == 2 and state.gold == 0, "Upgrade deducts exactly its displayed cost")
	check(is_equal_approx(state.brew_duration(), 4.4), "Upgrade reduces brew duration by twelve percent")
	check(is_equal_approx(progress, state.brew_elapsed / state.brew_duration()), "Upgrade preserves partial brewing progress")
	state.level = State.MAX_LEVEL
	state.gold = 1000000
	check(not state.upgrade(), "Maximum upgrade level is enforced")
	state.stock = State.CAPACITY
	state.customer_elapsed = 0.0
	state.brew_elapsed = 0.0
	state.advance(2.0)
	check(state.stock == State.CAPACITY and state.brew_elapsed == 0.0, "Brewing pauses at shelf capacity")
	state.advance(1.5)
	check(state.stock == State.CAPACITY - 1 and state.brew_elapsed > 0.0, "Production resumes when a customer frees space")
	var before: Dictionary = state.to_data().duplicate()
	state.advance(-1.0)
	state.advance(NAN)
	check(state.to_data() == before, "Invalid time steps do not change the economy")
	state.pinned = false
	var loaded := State.new()
	check(loaded.load_data(JSON.parse_string(JSON.stringify(state.to_data()))), "JSON round trip loads")
	check(same_progress(loaded, state), "Progress and pin preference survive save/load")
	check(not loaded.load_data({"gold": "broken"}) and loaded.gold == state.gold, "Malformed data is rejected without mutating state")
	var invalid: Dictionary = state.to_data()
	invalid["version"] = 99
	check(not loaded.load_data(invalid), "Unsupported save version is rejected")
	invalid = state.to_data()
	invalid["stock"] = 999
	invalid["version"] = 3 # Count-only legacy saves retain their clamping migration.
	invalid["level"] = -100
	invalid["gold"] = -100
	loaded.load_data(invalid)
	check(loaded.stock == State.CAPACITY and loaded.level == 1 and loaded.gold == 0, "Out-of-range save values are clamped")
	DirAccess.make_dir_recursive_absolute("res://.verification")
	var path := "res://.verification/test-save.json"
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)
	check(SaveStore.write_from(state, path) == OK, "Save writes successfully")
	var restored := State.new()
	check(SaveStore.read_into(restored, path) == "loaded" and same_progress(restored, state), "File save restores all game progress")
	state.gold += 6
	check(SaveStore.write_from(state, path) == OK, "Existing save is replaced successfully")
	var broken := FileAccess.open(path, FileAccess.WRITE)
	broken.store_string("{interrupted write")
	broken.close()
	check(SaveStore.read_into(restored, path) == "recovered" and restored.gold == state.gold - 6, "Corrupt primary save recovers last valid backup")
	check(SaveStore.write_from(state, path) == OK, "Recovered progress can be saved again")
	var missing_dir := "res://.verification/nonexistent-directory/save.json"
	check(SaveStore.write_from(state, missing_dir) != OK, "Write failure is reported to the caller")
	var closed := State.new()
	closed.set_shop_open(false)
	closed.advance(3600.0)
	check(closed.stock == State.CAPACITY and closed.gold == 0 and closed.total_sold == 0, "Closed shop brews to capacity without selling")
	check(closed.customer_elapsed == 0.0, "Closed shop does not queue visitor time")
	closed.set_shop_open(true)
	closed.advance(3.0)
	check(closed.total_sold == 0, "Reopening does not cause an instant accumulated sale")
	closed.advance(0.2)
	check(closed.total_sold == 1 and closed.gold == 6, "Customers resume after reopening")
	closed.set_shop_open(false)
	closed.mini_mode = true
	closed.opacity = 0.55
	closed.pinned = false
	var settings := State.new()
	var automatic_expected := closed.to_data().duplicate(true)
	automatic_expected["shop_open"] = true
	check(settings.load_data(closed.to_data()) and preload("res://tests/state_compare.gd").equivalent(automatic_expected, settings.to_data()), "Closed legacy save resumes automatically while preserving progress, window mode and opacity")
	var legacy := state.to_data()
	for key in ["shop_open", "mini_mode", "window_mode", "opacity"]:
		legacy.erase(key)
	check(settings.load_data(legacy) and settings.shop_open and not settings.mini_mode and settings.opacity == 1.0 and settings.gold == state.gold, "Existing saves migrate without losing gold")
	var bad_settings := closed.to_data()
	bad_settings["opacity"] = "bad"
	check(not settings.load_data(bad_settings), "Malformed opacity is rejected")
	bad_settings["opacity"] = 0.0
	settings.load_data(bad_settings)
	check(settings.opacity == 0.3, "Opacity cannot make the window invisible")
	closed.window_mode = State.WindowMode.MINIMAL
	check(settings.load_data(JSON.parse_string(JSON.stringify(closed.to_data()))) and settings.window_mode == State.WindowMode.MINIMAL, "Minimal mode survives a JSON save/load")
	var old_mini := closed.to_data()
	old_mini.erase("window_mode")
	check(settings.load_data(old_mini) and settings.window_mode == State.WindowMode.SMALL, "Legacy mini mode migrates to small mode")
	var bad_mode := closed.to_data()
	bad_mode["window_mode"] = 1.5
	check(not settings.load_data(bad_mode), "Fractional window modes are rejected")
	bad_mode["window_mode"] = 5
	check(not settings.load_data(bad_mode), "Unknown window modes are rejected")
	var income := RecentIncome.new()
	income.advance(1.0, 6)
	income.advance(30.0, 12)
	check(income.gold == 18, "Recent income totals actual sales without extrapolating")
	income.advance(30.0)
	check(income.gold == 12, "Sales expire individually after sixty seconds")
	income.advance(30.0)
	check(income.gold == 0, "Recent income reaches zero after no sales for sixty seconds")
	print("RESULT: ", "ALL TESTS PASSED" if failures == 0 else str(failures) + " FAILURES")
	quit(0 if failures == 0 else 1)
