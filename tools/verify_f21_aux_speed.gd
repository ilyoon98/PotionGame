extends SceneTree
## F21 auxiliary slowdown: new reservations use 6.0/4.5/3.0 with 8/6/4s floors,
## while F20 reservations already saved at 2.0/1.5/1.0 keep their frozen time.
## Workspace-only synthetic stores; never reads a player save.
const State = preload("res://scripts/shop_state.gd")
const Workshop = preload("res://scripts/shop_workshop_operations.gd")
const F = preload("res://tests/late_investment_fixture.gd")
const M = preload("res://tests/contracts_fixture.gd")
const Compare = preload("res://tests/state_compare.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func fixture(seed_value: int, scenario: String) -> RefCounted:
	var s := F.completed_store(seed_value, "final", "both3", scenario)
	s.gold = 20000000; s.shop_open = false
	s.stock = 16; s.inventory.clear(); s.mana_stock = 0
	for i in s.stock: s.inventory.append(false)
	return s
func clone(s: RefCounted) -> RefCounted:
	var restored := State.new()
	check(restored.load_data(M.data(s)), "Save roundtrip")
	restored.shop_open = s.shop_open
	return restored
## Count auxiliary batches over a fixed window with every upgrade level.
func throughput(seed_value: int, scenario: String, target_level: int, seconds: float) -> Dictionary:
	var s := fixture(seed_value, scenario)
	for stage in range(1, target_level + 1): check(s.workshop.purchase(s, stage).ok, "Purchase level %d" % stage)
	var starts := 0; var durations: Array = []
	var last_id := -1
	var elapsed := 0.0
	while elapsed < seconds - 0.000001:
		s.advance(0.5); elapsed += 0.5
		if not s.workshop.aux.is_empty() and int(s.workshop.aux.rng_before) != last_id:
			last_id = int(s.workshop.aux.rng_before); starts += 1; durations.append(float(s.workshop.aux.batch.duration))
	return {"level": target_level, "starts": starts, "durations": durations, "shipped": s.contracts.totals.shipped}
func _initialize() -> void: call_deferred("run")
func run() -> void:
	check(DisplayServer.get_name() == "headless", "Only workspace headless fake stores")
	# Pure formula
	check(Workshop.aux_duration(0.8, 6.0) == 8.0 and Workshop.aux_duration(0.8, 4.5) == 6.0 and Workshop.aux_duration(0.8, 3.0) == 4.0, "Floors apply at late-game cauldron speed")
	check(absf(Workshop.aux_duration(3.0, 6.0) - 18.0) < 0.000001 and absf(Workshop.aux_duration(3.0, 3.0) - 9.0) < 0.000001, "Slow recipes use the multiplier above the floor")
	check(Workshop.aux_duration(0.8, 2.0) == 1.6 and Workshop.aux_duration(0.8, 1.0) == 0.8, "Legacy factors keep the old floorless formula")
	# Each level reserves with its own factor and floor.
	var rows: Array = []
	for target_level in range(1, 4):
		var s := fixture(73129, "normal")
		for stage in range(1, target_level + 1): check(s.workshop.purchase(s, stage).ok, "Purchase level %d" % stage)
		s._start_batch()
		check(not s.workshop.aux.is_empty(), "Level %d reserves an auxiliary batch" % target_level)
		var a: Dictionary = s.workshop.aux
		var expected := maxf(float(Workshop.MIN_SECONDS[target_level - 1]), float(a.base_duration) * float(Workshop.FACTORS[target_level - 1]))
		check(float(a.factor) == float(Workshop.FACTORS[target_level - 1]) and absf(float(a.batch.duration) - expected) < 0.000001, "Level %d duration = max(floor, base x factor)" % target_level)
		check(float(a.batch.duration) >= float(Workshop.MIN_SECONDS[target_level - 1]) - 0.000001, "Level %d never faster than its floor" % target_level)
		check(int(a.batch.quantity) == s.late_investments.batch_max() * Workshop.AUX_BOTTLES and int(a.batch.quantity) == 12, "Level %d auxiliary carries F19 limit x3 bottles" % target_level)
		var over: Dictionary = M.data(s); over.workshop.aux.batch.quantity = 13
		check(not State.new().load_data(over), "Level %d rejects more than 12 auxiliary bottles" % target_level)
		var restored := clone(s)
		check(Compare.equivalent(M.data(restored), M.data(s)), "Level %d reservation roundtrips exactly" % target_level)
		rows.append({"level": target_level, "base": a.base_duration, "duration": a.batch.duration})
		# A tampered faster time or floorless new factor must be rejected atomically.
		var bad: Dictionary = M.data(s); bad.workshop.aux.batch.duration = float(a.base_duration) * float(a.factor) - 0.5
		var target := clone(s); var before: Dictionary = M.data(target)
		check(not target.load_data(bad), "Level %d rejects time faster than the floor" % target_level)
		check(Compare.equivalent(before, M.data(target)), "Level %d rejection is atomic" % target_level)
	# F20 saves: a reservation frozen at the old factor keeps loading and its old time.
	for pair in [[1, 2.0], [3, 2.0], [3, 1.0]]:
		var s := fixture(19337, "normal")
		for stage in range(1, int(pair[0]) + 1): check(s.workshop.purchase(s, stage).ok, "Legacy purchase")
		s._start_batch()
		var legacy: Dictionary = M.data(s)
		var a: Dictionary = legacy.workshop.aux
		a.factor = pair[1]; a.batch.duration = float(a.base_duration) * float(pair[1])
		var too_many: Dictionary = legacy.duplicate(true)
		check(not State.new().load_data(too_many), "F20 reservation cannot carry F21 twelve bottles")
		var recipe: Dictionary = a.batch.ingredients
		for material in recipe: recipe[material] = int(recipe[material]) / int(a.batch.quantity) * 4
		a.batch.quantity = 4
		var target := State.new()
		check(target.load_data(legacy), "F20 reservation at level %d factor %.1f still loads" % pair)
		check(absf(float(target.workshop.aux.batch.duration) - float(a.base_duration) * float(pair[1])) < 0.000001, "F20 reservation keeps its frozen old time")
		target.shop_open = false
		target.advance(float(a.batch.duration) + 0.001)
		check(target.workshop.aux.is_empty() or float(target.workshop.aux.factor) == float(Workshop.FACTORS[int(pair[0]) - 1]), "Next reservation after a legacy batch uses the F21 factor")
	# Before expansion the main cauldron still ships at the F19 limit.
	var main := F.completed_store(19337, "final", "both3", "inventory_full"); main.gold = 10000000; main.shop_open = false
	main._start_batch()
	check(main.contracts.batch.get("purpose") == "contract" and int(main.contracts.batch.quantity) <= main.late_investments.batch_max(), "Main cauldron contract stays at the F19 four-bottle limit")
	var main_over: Dictionary = M.data(main); main_over.contracts.batch.quantity = 5
	check(not State.new().load_data(main_over), "Main cauldron contract above four bottles is rejected")
	# Old factor below the purchased level's legacy factor stays invalid.
	var s3 := fixture(19337, "normal")
	for stage in range(1, 2): s3.workshop.purchase(s3, stage)
	s3._start_batch()
	var bad_legacy: Dictionary = M.data(s3); bad_legacy.workshop.aux.factor = 1.0; bad_legacy.workshop.aux.batch.duration = float(bad_legacy.workshop.aux.base_duration)
	check(not State.new().load_data(bad_legacy), "Level1 cannot hold an improvement2 legacy reservation")
	# Fixed 10-minute window: how many auxiliary batches start per level.
	var windows: Array = []
	for scenario in ["normal", "inventory_full"]:
		for target_level in range(1, 4): windows.append(throughput(73129, scenario, target_level, 600.0).merged({"scenario": scenario}))
	for row in windows: check(row.starts > 0, "Auxiliary still produces in %s level %d" % [row.scenario, row.level])
	var result := {"checks": checks, "failures": failures, "passed": failures.is_empty(), "reservations": rows, "ten_minute_windows": windows}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.verification/f21-aux-speed-20261020"))
	M.write_json("res://.verification/f21-aux-speed-20261020/functional.json", result)
	for row in windows: print("F21 %s level%d starts=%d shipped=%d first=%s" % [row.scenario, row.level, row.starts, row.shipped, str(row.durations.slice(0, 3))])
	print("F21-AUX %s %d checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)
