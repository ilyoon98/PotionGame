extends SceneTree
const State = preload("res://scripts/shop_state.gd")
const Compare = preload("res://tests/state_compare.gd")
const Display = preload("res://scripts/potion_display.gd")
var failures := 0


func check(value: bool, description: String) -> void:
	if value: print("PASS: ", description)
	else:
		failures += 1
		push_error(description)


func _initialize() -> void:
	var roster := State.Progression.new()
	var seen := {}
	for moment in [0.0, 80.0, 100.0, 170.0, 190.0, 240.0]:
		roster.clock = moment
		for visit in range(1000):
			roster.select_customer()
			seen[roster.customer] = true
	check(seen.size() == 4 and not seen.has(1), "Only four active customers appear across day/night and all weather")
	var legacy := State.new()
	legacy.gold = 123
	legacy.progression.customer = 1
	legacy.progression.customer_selected = true
	legacy.progression.by_customer = {"knight": 7}
	var legacy_data := legacy.to_data()
	var migrated := State.new()
	check(migrated.load_data(legacy_data) and migrated.progression.customer == 0 and migrated.progression.customer_selected, "Saved knight visitor resumes as traveler without restarting the visit")
	var expected := legacy_data.duplicate(true)
	expected["progression"]["customer"] = 0
	check(Compare.equivalent(expected, migrated.to_data()), "Roster change preserves money, inventory, historical counts, seed and progress")
	var state := State.new()
	check(not state.purchase("moon") and state.gold == 0, "Unaffordable recipe does not charge or unlock")
	state.gold = 2000
	check(state.purchase("moon") and state.gold == 1880, "Recipe purchase charges once")
	check(not state.purchase("moon") and state.gold == 1880, "Owned recipe cannot be purchased again")
	check(not state.purchase("employee") and not state.purchase("expedition"), "Reputation gates do not spend money")
	state.progression.reputation = 30
	check(state.purchase("purify") and state.purchase("agility") and state.purchase("employee") and state.purchase("filter") and state.purchase("expedition"), "Manual unlocks and employee apply their saved effects")
	var night := State.Progression.new()
	night.clock = 80
	var day := State.Progression.new()
	check(night.growth_rate() > day.growth_rate() and night.success_chance("moon") > day.success_chance("moon"), "Night affects rare herb growth and special brewing success")
	day.clock = 240
	check(day.weather() == 2 and not day.is_night() and day.growth_rate() == 1.5, "Rain and day/night are independent")
	check(day.customer_weights()[3] > night.customer_weights()[3] and night.customer_weights()[4] > day.customer_weights()[4], "Rain favors elves; night favors rogues")
	var preference := State.new()
	preference.inventory = [false, "purify", "purify", true]
	preference.stock = 4
	preference.mana_stock = 1
	preference.progression.customer = 3
	preference.progression.customer_selected = true
	preference.customer_elapsed = 3.1
	var event: Dictionary = preference.advance(0.1)
	check(event["potion_events"][0]["index"] == 1 and event["earned"] == 24 and preference.inventory == [false, "purify", true], "Preference takes the oldest matching bottle; all other inventory stays ordered")
	check(preference.progression.totals["preferred"] == 1 and preference.progression.reputation == 2, "Preferred trade records reputation and actual price")
	preference.progression.customer = 4
	preference.progression.customer_selected = true
	preference.customer_elapsed = 3.1
	event = preference.advance(0.1)
	check(event["earned"] == 6 and event["potion_events"][0]["index"] == 0, "Missing preference falls back to oldest available potion")
	var journey := State.new()
	journey.gold = 1000
	journey.progression.reputation = 30
	check(journey.purchase("expedition") and journey.total_spent_expeditions == 8, "Opening a region starts a separately paid automatic leg")
	journey.advance(70)
	check(journey.progression.expedition_count == 1 and journey.progression.rare_herbs == 2 and journey.material_count("dewgrass") == 2 and journey.total_sold > 0, "Expedition returns both materials while shop sells")
	check(journey.total_spent_expeditions == 16, "Each actual departure is charged exactly once")
	state.progression.expedition_active = true
	state.advance(37.25)
	var saved := state.to_data()
	var restored := State.new()
	check(restored.load_data(JSON.parse_string(JSON.stringify(saved))) and Compare.equivalent(saved, restored.to_data()), "Recipes, employees, seed, batch result, environment and expedition restore exactly")
	state.advance(200)
	for index in range(6000): restored.advance(1.0 / 30.0)
	check(Compare.equivalent(state.to_data(), restored.to_data()), "Expanded simulation is frame independent across weather boundaries and failures")
	var failure := State.new()
	failure.progression.owned = ["moon"]
	failure.progression.rare_herbs = 1
	failure.progression.seed_value = 40000
	failure.set_shop_open(false)
	failure.advance(0.1)
	check(not failure.progression.batch_success, "Failed batch result is fixed when ingredients are reserved")
	var failure_resume := State.new()
	check(failure_resume.load_data(JSON.parse_string(JSON.stringify(failure.to_data()))), "In-progress failed batch restores")
	failure_resume.advance(7.4)
	check(failure_resume.progression.totals["failed"] == 1 and failure_resume.stock == 0 and failure_resume.is_brewing(), "Failed special batch charges once, creates no potion, and automatically falls back to basic production")
	var snapshot := state.to_data()
	for index in range(3): state.report_text()
	check(state.to_data() == snapshot, "Opening results is read-only and cannot pay twice")
	state.start_report_period()
	check(state.gold == snapshot["gold"] and state.progression.report_baseline == state.progression.totals, "New reporting period only resets the comparison baseline")
	var corrupted := snapshot.duplicate(true)
	corrupted["progression"]["owned"] = ["moon", "moon"]
	var before := restored.to_data()
	check(not restored.load_data(corrupted) and restored.to_data() == before, "Invalid expansion data is rejected atomically")
	print("PROGRESSION RESULT: ", failures, " failures")
	quit(1 if failures else 0)
