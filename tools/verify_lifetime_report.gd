extends SceneTree
const State = preload("res://scripts/shop_state.gd")
const Status = preload("res://scripts/management_status.gd")
const Compare = preload("res://tests/state_compare.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func summary(state: RefCounted) -> Dictionary:
	var before: Dictionary = state.to_data()
	var seed_before: int = state.progression.seed_value
	var result := Status.lifetime_summary(state)
	check(Compare.equivalent(before, state.to_data()), "Lifetime projection preserves complete economy/progress/save data")
	check(state.progression.seed_value == seed_before, "Lifetime projection never advances RNG")
	return result

func _initialize() -> void:
	assert(DisplayServer.get_name() == "headless")
	set_meta("isolated_preview", true)
	var fresh := State.new()
	# Original nine lifetime values, the contract (F18) aggregates and the F21
	# keeper/aging section. F22 regulars are cards, not lifetime-summary values.
	check(summary(fresh) == {"seconds": 0, "time": "0시간 0분 0초", "net": 0, "sales": 0, "materials_cost": 0, "fees": 0, "brewed": 0, "sold": 0, "expeditions": 0, "reputation_gain": 0, "contract_paid": 0, "contract_shipped": 0, "contract_rounds": 0, "keeper_sleeps": 0, "keeper_faints": 0, "fatigue_failed": 0, "aged_sold": 0, "aged_revenue": 0}, "New save has zero lifetime totals")
	# Advance actual model time while production and trade are fully blocked.
	var waiting := State.new()
	waiting.set_shop_open(false)
	waiting.stock = waiting.capacity()
	for i in waiting.stock: waiting.inventory.append(false)
	waiting.herbs = waiting.herb_capacity()
	var gold_before: int = waiting.gold
	var seed_before: int = waiting.progression.seed_value
	waiting.advance(17.25)
	check(is_equal_approx(waiting.progression.clock, 17.25), "Closed/full shop still accumulates actual advance time")
	check(summary(waiting).seconds == 17 and waiting.gold == gold_before and waiting.progression.seed_value == seed_before, "Waiting play time does not invent sales or RNG")
	for mode in [State.WindowMode.FULL, State.WindowMode.WORKSHOP, State.WindowMode.COMPANION, State.WindowMode.MINIMAL, State.WindowMode.SMALL]:
		waiting.window_mode = mode
		var before: float = waiting.progression.clock
		waiting.advance(0.25)
		check(is_equal_approx(waiting.progression.clock, before + 0.25), "Every window mode uses the same actual play clock")
	waiting.set_shop_open(true)
	var reopened: float = waiting.progression.clock
	waiting.advance(0.25)
	check(is_equal_approx(waiting.progression.clock, reopened + 0.25), "Open shop uses the same play clock")
	for item in [{"clock": 59.99, "seconds": 59, "text": "0시간 0분 59초"}, {"clock": 60.0, "seconds": 60, "text": "0시간 1분 0초"}, {"clock": 3600.0, "seconds": 3600, "text": "1시간 0분 0초"}, {"clock": 93784.99, "seconds": 93784, "text": "26시간 3분 4초"}]:
		fresh.progression.clock = item.clock
		var display := summary(fresh)
		check(display.seconds == item.seconds and display.time == item.text, "Seconds floor and long-session formatting")
	var state := State.new()
	state.progression.clock = 93784.99
	state.total_sales_gold = 120000
	state.total_spent_materials = 12000
	state.total_spent_expeditions = 80
	state.progression.totals.merge({"brewed": 700, "sold": 680, "expeditions": 25, "reputation": 777, "manual_spent": 30000}, true)
	state.progression.last_report_clock = 93700.0
	state.progression.report_sales = 110000
	state.progression.report_materials = 10000
	state.progression.report_expeditions = 70
	state.progression.report_baseline.merge({"brewed": 690, "sold": 675, "expeditions": 24, "reputation": 750, "manual_spent": 29000}, true)
	var lifetime := summary(state)
	check(lifetime.net == 107920 and lifetime.sales == 120000 and lifetime.materials_cost == 12000 and lifetime.fees == 80, "Operating net includes all sales/material/departure costs")
	check(lifetime.brewed == 700 and lifetime.sold == 680 and lifetime.expeditions == 25 and lifetime.reputation_gain == 777, "All activity counts use lifetime totals")
	check(Status.report_summary(state).net == 7990 and Status.report_summary(state).period == "0시간 1분 24초", "Existing period projection is unchanged")
	state.progression.totals.manual_spent = 999999
	check(summary(state) == lifetime, "Manual purchases/investments are excluded from operating net")
	state.start_report_period()
	check(summary(state) == lifetime and state.progression.clock == 93784.99, "Old report reset never changes lifetime play time or totals")
	check(Status.report_summary(state).net == 0 and Status.report_summary(state).period == "0시간 0분 0초", "Old baseline reset retains its original meaning")
	state.progression.report_started = "1900-01-01T00:00:00"
	var data: Dictionary = JSON.parse_string(JSON.stringify(state.to_data()))
	var restored := State.new()
	check(restored.load_data(data), "Current save roundtrip succeeds")
	check(summary(restored) == lifetime and restored.progression.seed_value == state.progression.seed_value, "Resume keeps lifetime totals and seed without adding closed wall time")
	check(data.progression.report_started == "1900-01-01T00:00:00", "Read-only load fixture preserves historical baseline timestamp")
	var legacy_data: Dictionary = State.new().to_data()
	legacy_data.version = 4
	legacy_data.erase("progression")
	var legacy := State.new()
	check(legacy.load_data(legacy_data) and summary(legacy).seconds == 0, "Pre-clock legacy save retains existing zero-time fallback")
	for item in [{"sales": 19800, "materials": 0, "fees": 0, "net": 19800}, {"sales": 0, "materials": 19800, "fees": 12, "net": -19812}, {"sales": 20, "materials": 8, "fees": 12, "net": 0}, {"sales": 1000000000000, "materials": 19800, "fees": 200, "net": 999999980000}]:
		state.total_sales_gold = item.sales
		state.total_spent_materials = item.materials
		state.total_spent_expeditions = item.fees
		check(summary(state).net == item.net, "Signed/zero/large operating net stays exact for UI formatting")
	print("LIFETIME REPORT %s: %d checks; real advance clock including closed/full/all modes, cumulative operating costs/counts, independent old baselines, signed net, save roundtrip/legacy fallback, readonly economy/RNG; isolated headless without player files or desktop" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
