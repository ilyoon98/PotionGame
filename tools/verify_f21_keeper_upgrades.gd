extends SceneTree
## F21 bed/herb-tea investments, keeper report counters and growth
## recommendation: gate, costs, exact rates and boundaries, frame independence
## with a mid-run purchase, fatigue-failure attribution, period report, v15 save
## validation and v14/v13 migration. Workspace-only synthetic stores.
const State = preload("res://scripts/shop_state.gd")
const Keeper = preload("res://scripts/shop_keeper.gd")
const Upgrades = preload("res://scripts/shop_keeper_upgrades.gd")
const Aging = preload("res://scripts/shop_aging.gd")
const Content = preload("res://scripts/shop_content.gd")
const Status = preload("res://scripts/management_status.gd")
const F = preload("res://tests/late_investment_fixture.gd")
const M = preload("res://tests/contracts_fixture.gd")
const Compare = preload("res://tests/state_compare.gd")
const DAY := 240.0
var checks := 0
var failures: Array[String] = []
## Scripted RNG so judge() attribution is checked roll by roll.
class FakeProgression extends RefCounted:
	var batch_chance := 1.0
	var batch_success := true
	var rolls: Array = []
	var draws := 0
	func random_value() -> float:
		draws += 1
		return float(rolls.pop_front())
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func near(a: float, b: float, tolerance: float = 0.000001) -> bool:
	return absf(a - b) <= tolerance
func fresh(policy: String = "regular", bed: int = 0, tea: int = 0) -> RefCounted:
	var s := State.new(); s.gold = 5000
	s.progression.reputation = Keeper.POLICY_REPUTATION
	if policy != "regular": check(s.set_keeper_policy(policy), "Select " + policy)
	s.keeper.upgrades.levels = {"bed": bed, "tea": tea}
	return s
func run_for(s: RefCounted, seconds: float) -> Dictionary:
	var peak := 0.0; var faints := 0; var previous: String = s.keeper.state
	for i in int(seconds):
		s.advance(1.0)
		peak = maxf(peak, s.keeper.fatigue)
		if s.keeper.state == "fainted" and previous != "fainted": faints += 1
		previous = s.keeper.state
	return {"peak": peak, "faints": faints}
func advance_in(s: RefCounted, seconds: float, chunk: float) -> void:
	var left := seconds
	while left > 0.000001:
		var step := minf(chunk, left); s.advance(step); left -= step
func _initialize() -> void: call_deferred("run")
func run() -> void:
	check(DisplayServer.get_name() == "headless", "Only workspace headless fake stores")
	# Gold sink outside Content: the 125-step growth and F19 checks never see these tracks.
	for entry in Content.DATA.upgrades: check(not str(entry.track) in Upgrades.TRACKS, "Content upgrades have no keeper track (%s)" % entry.track)
	# Gate, order, costs and gold accounting.
	var buy := State.new(); buy.gold = 1000000
	check(buy.keeper.upgrades.view(buy, "bed").reason == "명성 %d 필요" % Upgrades.UNLOCK_REPUTATION and not buy.keeper.upgrades.purchase(buy, "bed", 1).ok and buy.gold == 1000000, "Bed locked before reputation %d" % Upgrades.UNLOCK_REPUTATION)
	buy.progression.reputation = Upgrades.UNLOCK_REPUTATION
	check(not buy.keeper.upgrades.purchase(buy, "bed", 2).ok and buy.keeper.upgrades.levels.bed == 0, "Stale expected level is rejected")
	check(not buy.keeper.upgrades.purchase(buy, "nap", 1).ok, "Unknown track is rejected")
	var spent := 0
	for track in Upgrades.TRACKS:
		for level in range(1, Upgrades.COSTS[track].size() + 1):
			var item: Dictionary = buy.keeper.upgrades.view(buy, track)
			check(item.can_buy and item.next_level == level and item.cost == Upgrades.COSTS[track][level - 1], "%s stage %d buyable at %d G" % [track, level, item.cost])
			check(buy.keeper.upgrades.purchase(buy, track, level).ok, "Buy %s %d" % [track, level])
			spent += int(item.cost)
		check(buy.keeper.upgrades.view(buy, track).complete and not buy.keeper.upgrades.purchase(buy, track, Upgrades.COSTS[track].size() + 1).ok, "%s maxes out" % track)
	check(spent == 435000 and buy.gold == 1000000 - spent and buy.progression.totals.manual_spent == spent, "All seven stages cost 435,000 G and count as manual spend")
	var poor := fresh(); poor.gold = 9000
	check(poor.keeper.upgrades.view(poor, "bed").reason == "1000 G 부족", "Short gold reason")
	# Exact rates: bed recovery per game hour, tea cut while awake.
	for level in Upgrades.SLEEP_PER_HOUR.size():
		var k := Keeper.new(); k.state = "asleep"; k.next_at = 1000.0; k.fatigue = 60.0; k.upgrades.levels.bed = level
		k.advance(20.0, 20.0, false)
		check(near(k.fatigue, 60.0 - Upgrades.SLEEP_PER_HOUR[level] * 2.0), "Bed %d recovers %.0f per game hour" % [level, Upgrades.SLEEP_PER_HOUR[level]])
	for level in Upgrades.TEA_CUT.size():
		var k := Keeper.new(); k.ensure(0.0); k.upgrades.levels.tea = level
		k.advance(5.0, 5.0, true)
		var idle := Keeper.new(); idle.ensure(0.0); idle.upgrades.levels.tea = level
		idle.advance(5.0, 5.0, false)
		check(near(k.fatigue, 1.2 * (1.0 - Upgrades.TEA_CUT[level])) and near(idle.fatigue, 0.6 * (1.0 - Upgrades.TEA_CUT[level])), "Tea %d cuts awake gain by %.0f%%" % [level, Upgrades.TEA_CUT[level] * 100.0])
		k.fatigue = 39.0
		check(near(k.remaining(5.0, true), 1.0 / k.awake_rate(true)), "Rested-band boundary uses the tea rate (tea %d)" % level)
	# Daily balance per policy (worst case: brewing all day).
	var day := Keeper.new()
	check(day.daily("regular").fresh and not day.daily("busy").sustainable and not day.daily("allnighter").sustainable, "Unupgraded: only regular holds")
	day.upgrades.levels = {"bed": 3, "tea": 0}
	check(day.daily("busy").sustainable and not day.daily("busy").fresh, "Bed 3 alone sustains busy (43.2 / 48) without the rested bonus all day")
	day.upgrades.levels = {"bed": 2, "tea": 1}
	check(day.daily("busy").fresh and near(day.daily("busy").gain, 38.88, 0.0001), "Bed 2 + tea 1 keeps busy rested (38.9 / 42)")
	day.upgrades.levels = {"bed": 3, "tea": 3}
	check(not day.daily("allnighter").sustainable, "Allnighter needs the full bed")
	day.upgrades.levels = {"bed": 4, "tea": 3}
	check(day.daily("allnighter").fresh and near(day.daily("allnighter").gain, 33.6, 0.0001) and near(day.daily("allnighter").recovery, 36.0, 0.0001), "Full bed + tea keeps allnighter rested (33.6 / 36)")
	# Real 1s simulation: upgraded busy/allnighter never faint and stay rested.
	var busy := run_for(fresh("busy", 2, 1), DAY * 6)
	var night := run_for(fresh("allnighter", 4, 3), DAY * 6)
	var bed_only := run_for(fresh("busy", 3, 0), DAY * 6)
	check(busy.faints == 0 and busy.peak < Keeper.FRESH_BELOW, "Busy with bed 2 + tea 1: no faint, peak %.1f" % busy.peak)
	check(night.faints == 0 and night.peak < Keeper.FRESH_BELOW, "Allnighter fully upgraded: no faint, peak %.1f" % night.peak)
	check(bed_only.faints == 0 and bed_only.peak < 60.0, "Busy with bed 3: no faint, peak %.1f" % bed_only.peak)
	# Frame independence with upgrades and with a purchase between advances.
	for setup in [["busy", 2, 1], ["allnighter", 4, 3], ["allnighter", 1, 1]]:
		for chunk in [0.1, 0.7]:
			var coarse := fresh(setup[0], setup[1], setup[2]); var fine := State.new()
			check(fine.load_data(M.data(coarse)), "Clone with upgrades")
			coarse.advance(DAY * 1.3); advance_in(fine, DAY * 1.3, chunk)
			for s in [coarse, fine]:
				s.gold = 1000000
				var track := "bed" if int(s.keeper.upgrades.levels.bed) < 4 else "tea"
				if s.keeper.upgrades.view(s, track).can_buy: check(s.keeper.upgrades.purchase(s, track, int(s.keeper.upgrades.levels[track]) + 1).ok, "Mid-run %s purchase" % track)
			coarse.advance(DAY * 2.7); advance_in(fine, DAY * 2.7, chunk)
			check(Compare.equivalent(M.data(coarse), M.data(fine)), "%s bed%d tea%d: 4 days with a mid-run purchase agree for one step and %.1fs steps" % [setup[0], setup[1], setup[2], chunk])
	# Fatigue-failure attribution at reservation.
	var judge := Keeper.new(); var fake := FakeProgression.new()
	judge.fatigue = 85.0
	fake.rolls = [0.95, 0.5]
	judge.judge(fake, 1.0, true)
	check(near(fake.batch_chance, 0.9) and not fake.batch_success and judge.totals.fatigue_failed == 1, "Basic potion failure at 85 is a fatigue failure")
	judge.judge(fake, 1.0, true)
	check(fake.batch_success and judge.totals.fatigue_failed == 1, "Successful roll counts nothing")
	fake.rolls = [0.7, 0.85, 0.3]
	judge.judge(fake, 0.8, false, 3)
	check(near(fake.batch_chance, 0.6) and not fake.batch_success and judge.totals.fatigue_failed == 4, "Roll between penalised and base chance counts the whole batch quantity")
	judge.judge(fake, 0.8, false)
	check(not fake.batch_success and judge.totals.fatigue_failed == 4, "Roll above the base chance is an ordinary failure")
	judge.judge(fake, 0.8, false)
	check(fake.batch_success and fake.draws == 5, "One draw per uncertain batch")
	judge.fatigue = 0.0
	judge.judge(fake, 1.0, true)
	check(fake.batch_success and fake.draws == 5, "Certain batch draws nothing (RNG sequence unchanged)")
	var tired := fresh(); tired.advance(0.01)
	var fails := 0; var reservations := 0
	for i in 200:
		tired.keeper.fatigue = 85.0; tired.brew_active = false; tired.herbs = 10; tired.mushrooms = 0
		tired._start_batch()
		if tired.brew_active:
			reservations += 1
			if not tired.progression.batch_success: fails += 1
	check(reservations == 200 and fails > 0 and tired.keeper.totals.fatigue_failed == fails, "200 tired basic reservations: every failure (%d) is a fatigue failure" % fails)
	# Sleep and faint counters.
	var counted := fresh(); counted.advance(DAY * 3)
	check(counted.keeper.totals.sleeps == 3 and counted.keeper.totals.faints == 0, "Regular: 3 sleeps in 3 days (%s)" % str(counted.keeper.totals))
	var fainting := fresh("allnighter"); var seen := run_for(fainting, DAY * 6)
	check(seen.faints >= 1 and fainting.keeper.totals.faints == seen.faints, "Faint counter matches observed faints (%d)" % seen.faints)
	# Period report and summary.
	var report := fresh(); report.gold = 1000000; report.progression.reputation = Aging.UNLOCK_REPUTATION
	report.advance(1.0); report.start_report_period()
	check(report.report_text().contains("주인공 수면 0회 · 기절 0회") and report.report_text().contains("피로로 인한 제조 실패  0") and not report.report_text().contains("숙성품 판매"), "Fresh period shows zero keeper lines and no aging line")
	check(report.aging.purchase(report, "open", 1).ok, "Open aging for the report")
	report.inventory.clear()
	for i in 12: report.inventory.append(false)
	report.stock = 12; report.mana_stock = 0
	report._start_batch()
	report.advance(DAY * 3)
	var counts: Dictionary = report.report_f21_counts()
	check(counts.sleeps == 3 and counts.aged_sold > 0 and counts.aged_revenue == int(report.aging.totals.revenue), "Period counts sleeps and aged sales (%s)" % str(counts))
	var text: String = report.report_text()
	check(text.contains("주인공 수면 3회 · 기절 0회") and text.contains("숙성품 판매 %d병 · +%d G" % [counts.aged_sold, counts.aged_revenue]), "Report text lists sleeps and aged sales")
	check(Compare.equivalent(Status.report_summary(report).keeper_aging, counts), "Report summary carries the same F21 counts")
	var reloaded := State.new()
	check(reloaded.load_data(M.data(report)) and reloaded.report_text() == text and Compare.equivalent(M.data(reloaded), M.data(report)), "Period baseline survives a save roundtrip")
	report.start_report_period()
	check(report.report_f21_counts().values().all(func(value): return value == 0), "Restarting the period zeroes the F21 lines")
	# Save roundtrip with levels and counters; invalid data is rejected atomically.
	var saved := fresh("busy", 3, 2); saved.advance(DAY * 2)
	var restored := State.new()
	check(restored.load_data(M.data(saved)) and Compare.equivalent(M.data(saved), M.data(restored)) and restored.keeper.upgrades.levels == {"bed": 3, "tea": 2}, "Upgrades and counters roundtrip")
	var base_save: Dictionary = M.data(saved)
	var bad_cases := []
	for bad in [{"version": 2}, {"levels": {"bed": 5, "tea": 0}}, {"levels": {"bed": 0, "tea": 4}}, {"levels": {"bed": -1, "tea": 0}}, {"levels": {"bed": 1.5, "tea": 0}}, {"levels": {"bed": 1}}, {"levels": {"bed": 1, "tea": 0, "nap": 1}}, {"extra": 1}]:
		var broken: Dictionary = base_save.duplicate(true)
		for key in bad: broken.keeper_upgrades[key] = bad[key]
		bad_cases.append(broken)
	for bad in [{"sleeps": 99999}, {"faints": -1}, {"aged_sold": 0.5}]:
		var broken: Dictionary = base_save.duplicate(true)
		broken.report_f21 = report.report_f21.duplicate(); broken.report_f21.merge(bad, true)
		bad_cases.append(broken)
	var missing_key: Dictionary = base_save.duplicate(true); missing_key.report_f21 = {"sleeps": 0, "faints": 0, "fatigue_failed": 0, "aged_sold": 0, "aged": 0}; bad_cases.append(missing_key)
	var no_upgrades: Dictionary = base_save.duplicate(true); no_upgrades.erase("keeper_upgrades"); bad_cases.append(no_upgrades)
	var old_keeper: Dictionary = base_save.duplicate(true); old_keeper.keeper.erase("totals"); old_keeper.keeper.version = 1; bad_cases.append(old_keeper)
	var bad_totals: Dictionary = base_save.duplicate(true); bad_totals.keeper.totals.sleeps = -2; bad_cases.append(bad_totals)
	for broken in bad_cases:
		var target := fresh("busy", 1, 1); var before: Dictionary = M.data(target)
		check(not target.load_data(broken) and Compare.equivalent(before, M.data(target)), "Reject invalid v15 F21 data atomically")
	# v14 -> v15: levels 0, counters 0, period begins at the saved aged totals.
	var aged := F.completed_store(73129, "final", "both3", "normal"); aged.gold = 1000000; aged.progression.reputation = Aging.UNLOCK_REPUTATION
	check(aged.aging.purchase(aged, "open", 1).ok, "Aged fixture opens aging")
	aged.aging.totals = {"sold": 7, "revenue": 700}
	var v14: Dictionary = M.data(aged); v14.version = 14; v14.erase("keeper_upgrades"); v14.erase("report_f21"); v14.erase("regulars")
	v14.keeper.erase("totals"); v14.keeper.version = 1
	var migrated := State.new()
	check(migrated.load_data(v14) and migrated.keeper.upgrades.levels == {"bed": 0, "tea": 0} and migrated.keeper.totals == {"sleeps": 0, "faints": 0, "fatigue_failed": 0}, "v14 migrates with no upgrades and zero counters")
	check(migrated.report_f21.aged_sold == 7 and migrated.report_f21_counts().values().all(func(value): return value == 0), "v14 period begins at the saved aged totals")
	check(migrated.to_data().version == State.SAVE_VERSION and State.SAVE_VERSION >= 15, "Migrated state saves as the current version")
	var v13: Dictionary = M.data(State.new()); v13.version = 13; v13.erase("aging"); v13.erase("keeper_upgrades"); v13.erase("report_f21"); v13.erase("regulars"); v13.keeper.erase("totals"); v13.keeper.version = 1
	check(State.new().load_data(v13), "v13 still migrates")
	var v14_new_keeper: Dictionary = v14.duplicate(true); v14_new_keeper.keeper = M.data(aged).keeper
	check(not State.new().load_data(v14_new_keeper), "v14 save must carry the v14 keeper shape")
	# Growth recommendation: aging and useful keeper purchases.
	var rec := fresh(); rec.gold = 10000000
	check(not Status.growth_candidates(rec).any(func(item): return str(item.purchase_key).begins_with(Status.KEEPER_PREFIX)), "Regular policy gets no bed/tea recommendation")
	check(rec.set_keeper_policy("busy"), "Switch to busy")
	var keeper_items := Status.growth_candidates(rec).filter(func(item): return str(item.purchase_key).begins_with(Status.KEEPER_PREFIX))
	check(keeper_items.size() == 2 and keeper_items.all(func(item): return item.next_level == 1 and not Status.recommendation_purpose(item, rec).is_empty()), "Busy without upgrades recommends bed and tea")
	rec.keeper.upgrades.levels = {"bed": 2, "tea": 1}
	check(not Status.growth_candidates(rec).any(func(item): return str(item.purchase_key).begins_with(Status.KEEPER_PREFIX)), "No keeper recommendation once busy stays rested")
	check(not Status.growth_candidates(rec).any(func(item): return str(item.purchase_key).begins_with(Status.AGING_PREFIX)), "Aging not recommended before reputation %d" % Aging.UNLOCK_REPUTATION)
	rec.progression.reputation = Aging.UNLOCK_REPUTATION
	var aging_items := Status.growth_candidates(rec).filter(func(item): return str(item.purchase_key).begins_with(Status.AGING_PREFIX))
	check(aging_items.size() == 1 and aging_items[0].purchase_key == "aging:open" and aging_items[0].cost == 20000 and Status.recommendation_purpose(aging_items[0], rec) == "넘치는 재고를 비싸게 숙성", "Aging rack recommended at reputation %d" % Aging.UNLOCK_REPUTATION)
	check(rec.aging.purchase(rec, "open", 1).ok, "Buy rack")
	aging_items = Status.growth_candidates(rec).filter(func(item): return str(item.purchase_key).begins_with(Status.AGING_PREFIX))
	check(aging_items.size() == 3, "Barrels, cellar and shelf become recommendable after the rack")
	# Upgrades never change the content growth completion of a finished store.
	var done := F.completed_store(73129, "final", "both3", "normal"); done.gold = 10000000; done.progression.reputation = 5000
	var complete_before := F.complete_original(done)
	for track in Upgrades.TRACKS:
		while done.keeper.upgrades.view(done, track).can_buy: done.keeper.upgrades.purchase(done, track, int(done.keeper.upgrades.levels[track]) + 1)
	check(F.complete_original(done) == complete_before and Compare.equivalent(F.remaining(done), F.remaining(F.completed_store(73129, "final", "both3", "normal"))), "Keeper upgrades leave existing-growth completion unchanged")
	var result := {"checks": checks, "failures": failures, "passed": failures.is_empty(), "busy_bed2_tea1": busy, "allnighter_full": night, "busy_bed3": bed_only, "fatigue_basic_failures": fails}
	M.write_json("res://.verification/f21-keeper-upgrades-20261021/keeper-upgrades.json", result)
	print("F21 KEEPER UPGRADES %s %d checks busy_peak=%.1f allnighter_peak=%.1f" % ["PASS" if failures.is_empty() else "FAIL", checks, busy.peak, night.peak])
	quit(0 if failures.is_empty() else 1)
