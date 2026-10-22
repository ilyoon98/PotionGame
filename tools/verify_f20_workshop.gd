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
func fixture() -> RefCounted:
	var s := F.completed_store(73129, "final", "both3", "normal")
	s.gold = 10000000; s.shop_open = false
	s.stock = 16; s.inventory.clear(); s.mana_stock = 0
	for i in s.stock: s.inventory.append(false)
	return s
func clone(s: RefCounted) -> RefCounted:
	var restored := State.new()
	check(restored.load_data(M.data(s)), "Both production lines pass transactional save roundtrip")
	# Existing load policy always reopens the shop; restore the synthetic pause
	# only in the test, so production timing can be compared on identical inputs.
	restored.shop_open = s.shop_open
	return restored
func invalid(s: RefCounted, bad: Dictionary, label: String) -> void:
	var target := clone(s); var before: Dictionary = M.data(target)
	check(not target.load_data(bad), "Reject " + label)
	check(Compare.equivalent(before, M.data(target)), "Atomic " + label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	check(DisplayServer.get_name() == "headless", "Only workspace headless fake stores")
	var s := fixture()
	var old: int = s.gold; var spent: int = s.progression.totals.manual_spent
	check(not s.workshop.purchase(s, 2).ok and s.gold == old, "Skipped purchase refuses without debit")
	s.gold = 499999; check(not s.workshop.purchase(s, 1).ok and s.gold == 499999, "One gold short of the 50万 expansion is refused")
	s.gold = old
	check(s.workshop.purchase(s, 1).ok and s.gold == old - 500000 and s.progression.totals.manual_spent == spent + 500000, "Expansion contains actual basic auxiliary line for one debit")
	var paid: Dictionary = M.data(s)
	check(not s.workshop.purchase(s, 1).ok and Compare.equivalent(paid, M.data(s)), "Duplicate/stale stage atomic rejection")
	var rng: int = s.progression.seed_value
	s._start_batch()
	check(s.brew_active and s.contracts.batch.purpose == "ordinary" and not s.workshop.aux.is_empty(), "Main retail and auxiliary shipment actually run simultaneously")
	var after_main_rng: int = s.progression.seed_value
	var reservation: Dictionary = s.workshop.aux.duplicate(true)
	check(absf(float(reservation.batch.duration) - maxf(8.0, float(reservation.base_duration) * 6.0)) < 0.000001 and reservation.batch.quantity == 12, "Base time frozen at F21 6x with 8s floor and F21 twelve-bottle auxiliary limit")
	var before: Dictionary = M.data(s)
	for i in 100:
		s.workshop.view(s); s.workshop.status(s); s.production_preview()
	check(Compare.equivalent(before, M.data(s)), "Views do not consume RNG, materials, time or cursors")
	check(s.workshop.purchase(s, 2).ok and Compare.equivalent(reservation, s.workshop.aux), "Improvement1 applies to future batches, existing batch preserved")
	check(s.workshop.purchase(s, 3).ok and Compare.equivalent(reservation, s.workshop.aux), "Improvement2 preserves frozen basic reservation")
	var live := clone(s)
	check(Compare.equivalent(M.data(live), M.data(s)), "All reservation fields roundtrip exactly")
	# Compare two restored states, excluding transient unflushed start events.
	var chunks := clone(s); var large := clone(s)
	large.advance(120)
	for i in 1200: chunks.advance(0.1)
	check(Compare.equivalent(M.data(large), M.data(chunks)), "Large and fractional time chunks agree including independent RNG")
	check(large.contracts.totals.shipped > s.contracts.totals.shipped, "Auxiliary completes actual contracts")
	var event: Dictionary = live.advance(float(reservation.batch.duration))
	check(live.progression.seed_value != rng or after_main_rng == rng, "Normal main stream remains owned by ordinary reservations")
	for item in event.potion_events: check(item.kind in ["brew", "sale"], "No auxiliary event on retail animation channel")
	check(not live.workshop.aux.is_empty() and live.workshop.aux.factor == 3.0, "New batch uses purchased improvement2")
	var snapshot: Dictionary = M.data(s)
	for key in ["version", "level", "seed", "main_duration"]:
		var bad: Dictionary = snapshot.duplicate(true); bad.workshop[key] = -1
		invalid(s, bad, "workshop " + key)
	for key in ["quantity", "round_id", "kind", "duration", "chance", "success", "ingredients"]:
		var bad: Dictionary = snapshot.duplicate(true)
		bad.workshop.aux.batch[key] = {"quantity": 5, "round_id": "caravan:bad", "kind": "invalid", "duration": 0, "chance": -1, "success": not bool(snapshot.workshop.aux.batch.success), "ingredients": {}}[key]
		invalid(s, bad, "reservation " + key)
	for key in ["elapsed", "factor", "base_duration", "rng_before"]:
		var bad: Dictionary = snapshot.duplicate(true); bad.workshop.aux[key] = -1
		invalid(s, bad, "aux " + key)
	var legacy: Dictionary = snapshot.duplicate(true); legacy.version = 11; legacy.erase("stock_protection"); legacy.erase("workshop")
	var migrated := State.new(); check(migrated.load_data(legacy), "v11 migration preserves paid main ordinary")
	check(migrated.workshop.level == 0 and migrated.workshop.aux.is_empty() and migrated.brew_active and migrated.brew_elapsed == s.brew_elapsed and migrated.progression.seed_value == s.progression.seed_value, "No invented auxiliary, consume or reroll on migration")
	# Expansion purchased during a real main-cauldron contract: never duplicate.
	s = F.completed_store(19337, "final", "both3", "inventory_full"); s.gold = 10000000; s.shop_open = false
	s._start_batch(); reservation = s.contracts.batch.duplicate(true)
	check(s.workshop.purchase(s, 1).ok, "Expansion may be bought during an old main shipment")
	s._start_batch(); check(s.workshop.aux.is_empty() and Compare.equivalent(reservation, s.contracts.batch), "Wait for existing main contract; no copied batch")
	var main_restore := clone(s)
	main_restore.advance(float(reservation.duration))
	check(main_restore.contracts.batch.purpose == "ordinary" and not main_restore.workshop.aux.is_empty(), "Role transfers only after original shipment completes")
	# Pending auxiliary still finishes under low stock, then waits with no costs.
	s = fixture(); check(s.workshop.purchase(s, 1).ok, "Second expansion fixture")
	s._start_batch(); reservation = s.workshop.aux.duplicate(true)
	s.stock = 0; s.inventory.clear(); s._start_batch()
	check(s.stock_protection.active and Compare.equivalent(reservation, s.workshop.aux), "Protection preserves active auxiliary")
	s.advance(float(reservation.batch.duration))
	# F21: the slower batch lets the main cauldron refill past protection, so a
	# next batch may legitimately start, but never while protection is active.
	check(s.workshop.aux.is_empty() or (int(s.workshop.aux.rng_before) != int(reservation.rng_before) and not s.stock_protection.active), "Auxiliary finishes once; low stock blocks the next batch")
	M.write_json("res://.verification/f20-20261020/B/functional.json", {"checks": checks, "failures": failures, "passed": failures.is_empty(), "main_stream_before": rng, "after_main": after_main_rng})
	print("F20-BC %s %d checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)
