extends SceneTree
## F21 keeper fatigue/sleep: schedule, cauldron pause, penalty at reservation,
## faint, policy unlock/change, frame independence and save validation.
## Workspace-only synthetic stores; never reads a player save.
const State = preload("res://scripts/shop_state.gd")
const Keeper = preload("res://scripts/shop_keeper.gd")
const F = preload("res://tests/late_investment_fixture.gd")
const M = preload("res://tests/contracts_fixture.gd")
const Compare = preload("res://tests/state_compare.gd")
const DAY := 240.0
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func fresh(policy: String = "regular") -> RefCounted:
	var s := State.new(); s.gold = 5000
	if policy != "regular":
		s.progression.reputation = Keeper.POLICY_REPUTATION
		check(s.set_keeper_policy(policy), "Select " + policy)
	return s
## Advance in 1s steps, recording fatigue extremes and states seen.
func run_for(s: RefCounted, seconds: float) -> Dictionary:
	var peak := 0.0; var states := {}; var faints := 0; var previous: String = s.keeper.state
	for i in int(seconds):
		s.advance(1.0)
		peak = maxf(peak, s.keeper.fatigue)
		states[s.keeper.state] = true
		if s.keeper.state == "fainted" and previous != "fainted": faints += 1
		previous = s.keeper.state
	return {"peak": peak, "states": states, "faints": faints}
func _initialize() -> void: call_deferred("run")
func run() -> void:
	check(DisplayServer.get_name() == "headless", "Only workspace headless fake stores")
	# Clock 0 is 10:48. Regular bed 22:00 = 112s, wake 06:00 = 192s.
	check(absf(Keeper.hour_of(0.0) - 10.8) < 0.0001 and absf(Keeper.until_hour(0.0, 22.0) - 112.0) < 0.0001, "Game starts at 10:48, first regular bedtime at 112s")
	var s := fresh()
	s.advance(111.0)
	check(s.keeper.state == "awake" and s.is_brewing(), "Awake and brewing before bedtime")
	s.advance(1.5)
	check(s.keeper.state == "asleep" and not s.is_brewing(), "Asleep after 22:00; cauldron paused")
	var elapsed: float = s.brew_elapsed; var sold: int = s.total_sold; var herbs_before: int = s.progression.totals.harvested
	s.advance(40.0)
	check(s.brew_elapsed == elapsed, "Paused batch keeps its elapsed time while asleep")
	check(s.total_sold >= sold and s.progression.totals.harvested > herbs_before, "Sales continue and herbs grow during sleep")
	s.advance(40.0)
	check(s.keeper.state == "awake" and absf(s.keeper.last_sleep_hours - 8.0) < 0.01, "Wakes at 06:00 after 8 hours")
	# Rested bonus: +30% main-cauldron progress below fatigue 40, none above it.
	var quick := fresh(); quick.advance(0.01)
	var e0: float = quick.brew_elapsed
	quick.advance(1.0)
	check(quick.keeper.fatigue < Keeper.FRESH_BELOW and absf(quick.brew_elapsed - e0 - Keeper.FRESH_SPEED) < 0.0001, "Rested keeper brews 1.3s of work per second")
	check(absf(quick.brew_remaining_seconds() - (quick.brew_duration() - quick.brew_elapsed) / Keeper.FRESH_SPEED) < 0.000001, "Displayed remaining time uses the rested speed")
	var normal := fresh(); normal.advance(0.01); normal.keeper.fatigue = 45.0
	e0 = normal.brew_elapsed
	normal.advance(1.0)
	check(absf(normal.brew_elapsed - e0 - 1.0) < 0.0001, "No bonus at fatigue 40+")
	var edge := fresh(); edge.advance(0.01); edge.keeper.fatigue = Keeper.FRESH_BELOW - 0.12 # 0.5s of brewing left in the band
	var split := State.new(); check(split.load_data(M.data(edge)), "Clone at the band edge")
	e0 = edge.brew_elapsed
	edge.advance(1.0)
	for i in 10: split.advance(0.1)
	check(absf(edge.brew_elapsed - e0 - (0.5 * Keeper.FRESH_SPEED + 0.5)) < 0.0001 and Compare.equivalent(M.data(edge), M.data(split)), "Crossing fatigue 40 mid-step changes speed exactly at the boundary")
	# Regular: three days stay under the first penalty band and fully recover.
	var regular := fresh()
	var r := run_for(regular, DAY * 3)
	check(r.peak < 40.0 and r.faints == 0, "Regular peaks below 40 (%.1f) and never faints" % r.peak)
	check(regular.progression.totals.failed == 0, "Regular policy causes no extra failures on basic potions")
	# Policies are locked until reputation.
	var locked := State.new()
	check(not locked.set_keeper_policy("busy") and locked.keeper_policy_reason("busy").contains("명성"), "Busy is locked before reputation %d" % Keeper.POLICY_REPUTATION)
	check(locked.set_keeper_policy("regular") == false and locked.keeper.policy == "regular", "Selecting the current policy is a no-op")
	# Busy accumulates and eventually faints; allnighter faints sooner.
	var busy := fresh("busy"); var b := run_for(busy, DAY * 6)
	var night := fresh("allnighter"); var n := run_for(night, DAY * 6)
	check(b.peak >= 80.0, "Busy accumulates into the exhaustion band within 6 days (peak %.1f, faints %d)" % [b.peak, b.faints])
	check(n.faints >= 1 and n.faints >= b.faints, "Allnighter faints within 6 days and at least as often as busy (%d vs %d)" % [n.faints, b.faints])
	# Faint: forced 10h, no brewing, then awake.
	var faint := fresh("allnighter")
	for i in int(DAY * 6):
		faint.advance(1.0)
		if faint.keeper.state == "fainted": break
	check(faint.keeper.state == "fainted" and not faint.is_brewing(), "Fainted keeper does not brew")
	var wake_at: float = faint.keeper.next_at
	check(absf(wake_at - faint.keeper.sleep_started - Keeper.FAINT_SECONDS) < 0.001, "Faint lasts exactly 10 game hours")
	faint.advance(wake_at - faint.progression.clock + 0.01)
	check(faint.keeper.state == "awake" and faint.keeper.fatigue <= 50.01, "Recovers 50 fatigue and wakes after fainting")
	# Penalty is applied once at reservation and saved with the batch.
	var tired := fresh(); tired.advance(1.0)
	tired.keeper.fatigue = 65.0
	tired.brew_active = false; tired.mushrooms = 1
	tired._start_batch()
	check(tired.progression.active_recipe is bool and absf(tired.progression.batch_chance - 0.95) < 0.000001, "Tired (60+) basic potion: 100% - half of 10%p = 95%")
	var special := fresh(); special.purchase("moon"); special.progression.rare_herbs = 4; special.advance(1.0)
	special.keeper.fatigue = 85.0; special.brew_active = false; special.stock = 6; special.inventory.clear()
	for i in 6: special.inventory.append(false)
	special._start_batch()
	if special.progression.active_recipe is String:
		var base: float = special.progression.success_chance(special.progression.active_recipe)
		check(absf(special.progression.batch_chance - maxf(minf(base, 0.3), base - 0.20)) < 0.000001, "Exhausted (80+) recipe batch takes the full 20%p")
	else: check(false, "Fixture reserved a recipe batch for the penalty check")
	# Policy change at night goes to bed immediately; leaving the window wakes.
	var change := fresh(); change.progression.reputation = Keeper.POLICY_REPUTATION
	change.advance(100.0) # 20:48, regular bed is 22:00
	check(change.keeper.state == "awake", "Awake at 20:48")
	check(change.set_keeper_policy("busy") and change.keeper.state == "awake" and absf(change.keeper.next_at - (change.progression.clock + Keeper.until_hour(change.progression.clock, 0.0))) < 0.0001, "Busy reschedules bed to 00:00")
	change.advance(30.0) # 23:48
	check(change.keeper.state == "awake" and change.set_keeper_policy("allnighter") and change.set_keeper_policy("regular") and change.keeper.state == "asleep", "Switching to regular inside 22-6 sleeps at once")
	check(change.set_keeper_policy("allnighter") and change.keeper.state == "awake", "Switching to allnighter before 02:00 wakes the keeper")
	# Auxiliary line keeps working while the keeper sleeps.
	var late := F.completed_store(73129, "final", "both3", "normal"); late.gold = 10000000; late.shop_open = false
	late.stock = 16; late.inventory.clear(); late.mana_stock = 0
	for i in 16: late.inventory.append(false)
	check(late.workshop.purchase(late, 1).ok, "Expansion for sleeping auxiliary check")
	late.keeper.fatigue = 0.0
	late.keeper.ensure(late.progression.clock)
	late.advance(late.keeper.next_at - late.progression.clock + 0.5 if late.keeper.state == "awake" else 0.5)
	check(late.keeper.resting(), "Late fixture keeper asleep")
	var shipped: int = late.contracts.totals.shipped; var aux_before: float = late.workshop.aux.get("elapsed", 0.0)
	late.advance(30.0)
	check(late.keeper.resting() and (late.contracts.totals.shipped > shipped or float(late.workshop.aux.get("elapsed", 0.0)) != aux_before), "Auxiliary keeps producing while the keeper sleeps")
	# Frame independence across sleep, wake and faint boundaries.
	for policy in ["regular", "busy", "allnighter"]:
		for chunk in [0.1, 0.7]:
			var coarse := fresh(policy); var fine := State.new()
			check(fine.load_data(M.data(coarse)), "Clone for frame comparison")
			coarse.advance(DAY * 4)
			var left := DAY * 4
			while left > 0.000001:
				var step := minf(chunk, left); fine.advance(step); left -= step
			check(Compare.equivalent(M.data(coarse), M.data(fine)), "Four %s days agree for one large step and %.1fs steps" % [policy, chunk])
	# Save roundtrip in every state; invalid keeper data is rejected atomically.
	for target in ["awake", "asleep", "fainted"]:
		var t := fresh("allnighter")
		for i in int(DAY * 6):
			if t.keeper.state == target: break
			t.advance(1.0)
		var restored := State.new()
		check(t.keeper.state == target and restored.load_data(M.data(t)) and Compare.equivalent(M.data(t), M.data(restored)), "Roundtrip while " + target)
	var base_save: Dictionary = M.data(fresh())
	for bad in [{"fatigue": 101.0}, {"state": "dreaming"}, {"policy": "nap"}, {"version": 3}, {"version": 1}, {"next_at": -5.0, "state": "asleep"}, {"next_at": 99999.0}]:
		var broken: Dictionary = base_save.duplicate(true)
		for key in bad: broken.keeper[key] = bad[key]
		var target := fresh(); var before: Dictionary = M.data(target)
		check(not target.load_data(broken) and Compare.equivalent(before, M.data(target)), "Reject keeper %s atomically" % str(bad))
	var legacy: Dictionary = base_save.duplicate(true); legacy.version = 12; legacy.erase("keeper")
	var migrated := State.new()
	check(migrated.load_data(legacy) and migrated.keeper.state == "awake" and migrated.keeper.fatigue == 0.0 and migrated.keeper.policy == "regular", "v12 save starts rested, awake and regular")
	var missing: Dictionary = base_save.duplicate(true); missing.erase("keeper")
	check(not State.new().load_data(missing), "v13 save without keeper is rejected")
	var result := {"checks": checks, "failures": failures, "passed": failures.is_empty(), "regular_peak": r.peak, "busy": b, "allnighter": n}
	M.write_json("res://.verification/f21-keeper-20261021/keeper.json", result)
	print("F21 KEEPER %s %d checks regular_peak=%.1f busy_peak=%.1f/%d faints allnighter=%d faints" % ["PASS" if failures.is_empty() else "FAIL", checks, r.peak, b.peak, b.faints, n.faints])
	quit(0 if failures.is_empty() else 1)
