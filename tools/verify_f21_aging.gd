extends SceneTree
## F21 aging: unlock/purchases, barrel fill from a full shelf, maturity, aged-first
## premium sales, cellar retarget, shelf limit, frame independence, saves.
## Workspace-only synthetic stores; never reads a player save.
const State = preload("res://scripts/shop_state.gd")
const Aging = preload("res://scripts/shop_aging.gd")
const M = preload("res://tests/contracts_fixture.gd")
const Compare = preload("res://tests/state_compare.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
## Closed shop with a full 12-bottle shelf: 8 health then 4 mana.
func full_shop(open_aging: bool = true) -> RefCounted:
	var s := State.new(); s.gold = 1000000; s.set_shop_open(false)
	s.progression.reputation = Aging.UNLOCK_REPUTATION
	if open_aging: check(s.aging.purchase(s, "open", 1).ok, "Open aging")
	s.stock = 0; s.mana_stock = 0; s.inventory.clear()
	for i in 8: s.inventory.append(false)
	for i in 4: s.inventory.append(true)
	s.stock = 12; s.mana_stock = 4
	return s
func _initialize() -> void: call_deferred("run")
func run() -> void:
	check(DisplayServer.get_name() == "headless", "Only workspace headless fake stores")
	# Unlock and purchase order.
	var locked := State.new(); locked.gold = 1000000
	check(not locked.aging.purchase(locked, "open", 1).ok and locked.aging.view(locked, "open").reason.contains("명성"), "Aging locked before reputation %d" % Aging.UNLOCK_REPUTATION)
	locked.progression.reputation = Aging.UNLOCK_REPUTATION
	check(not locked.aging.purchase(locked, "barrels", 1).ok, "Barrels need the aging rack first")
	var gold: int = locked.gold
	check(locked.aging.purchase(locked, "open", 1).ok and locked.gold == gold - 20000 and locked.progression.totals.manual_spent == 20000, "Opening charges once")
	check(not locked.aging.purchase(locked, "open", 2).ok and not locked.aging.purchase(locked, "barrels", 2).ok, "Stale or skipped stages are refused")
	# Fill: a barrel takes the 12 most valuable bottles; equal prices take the oldest.
	var s := full_shop()
	s._start_batch()
	check(s.aging.barrels.size() == 1 and s.aging.barrels[0].bottles.size() == Aging.BATCH and s.stock == 0 and s.inventory.is_empty() and s.mana_stock == 0, "Full 12-bottle shelf fills one 12-bottle barrel")
	var pick := full_shop(); pick.progression.expansion.stages["potion_cabinet"] = 2
	pick.inventory.clear()
	for i in 6: pick.inventory.append(false)
	for i in 2: pick.inventory.append("moon")
	for i in 6: pick.inventory.append(true)
	for i in 2: pick.inventory.append(false)
	pick.stock = 16; pick.mana_stock = 6
	pick._start_batch()
	var barrel_bottles: Array = pick.aging.barrels[0].bottles if not pick.aging.barrels.is_empty() else []
	check(pick.capacity() >= 16 and barrel_bottles == [false, false, false, false, "moon", "moon", true, true, true, true, true, true], "Moon x2, mana x6 and the 4 oldest health in shelf order (%s)" % str(barrel_bottles))
	check(pick.inventory == [false, false, false, false] and pick.stock == 4 and pick.mana_stock == 0 and pick.inventory_order() == pick.inventory, "The 4 newest health stay on the shelf")
	var partial := full_shop(); partial.stock = 11; partial.inventory.pop_back(); partial.mana_stock = 3
	partial._start_batch()
	check(partial.aging.barrels.is_empty(), "No fill below 12 bottles")
	# Maturity at 10 minutes moves bottles to the aged shelf; barrel refills.
	s.advance(599.0)
	check(s.aging.shelf.is_empty() and s.aging.barrels.size() == 1 and absf(float(s.aging.barrels[0].elapsed) - 599.0) < 0.001, "Not matured at 599s")
	s.advance(2.0)
	check(s.aging.shelf.size() == 12 and int(s.aging.shelf[0].stage) == 1, "Matured into twelve stage-1 bottles at 600s")
	# Aged bottles sell first at x3 of the normal retail price.
	var normal_price: int = s._retail_price(false, false)
	s.set_shop_open(true)
	s.progression.customer = 0; s.progression.customer_selected = true
	var before_gold: int = s.gold
	var events: Dictionary = s.advance(s.customer_interval() + 0.01)
	var aged_events: Array = events.potion_events.filter(func(e): return e.kind == "aged_sale")
	check(aged_events.size() >= 1 and s.aging.totals.sold >= 1, "Customer buys an aged bottle first")
	check(int(aged_events[0].gold) == int(round(s._retail_price(false, bool(aged_events[0].preferred)) * 3.0)), "Aged price = retail x3 (%d, normal %d)" % [int(aged_events[0].gold), normal_price])
	check(events.potion_events.filter(func(e): return e.kind == "sale").is_empty() and s.gold > before_gold, "That customer took no retail-shelf bottle")
	# Cellar raises the target; in-progress barrels keep their elapsed time.
	var c := full_shop(); c._start_batch(); c.advance(300.0)
	check(c.aging.purchase(c, "cellar", 1).ok and c.aging.max_stage() == 2, "Cellar unlocks stage 2")
	c.advance(400.0)
	check(c.aging.shelf.is_empty() and absf(float(c.aging.barrels[0].elapsed) - 700.0) < 0.001, "Barrel keeps aging past 10 minutes toward 30")
	c.advance(1100.5)
	check(c.aging.shelf.size() == 12 and int(c.aging.shelf[0].stage) == 2 and absf(Aging.multiplier(2) - 7.0) < 0.0001, "Stage 2 at 30 minutes (x7)")
	# Shelf full: a matured barrel waits; remaining() reports no boundary.
	var w := full_shop()
	for i in 12: w.aging.shelf.append({"kind": false, "stage": 1})
	w._start_batch(); w.advance(610.0)
	check(w.aging.barrels.size() == 1 and float(w.aging.barrels[0].elapsed) == Aging.STAGES[0] and w.aging.remaining() == INF, "Matured barrel waits while the aged shelf is full")
	# Extra barrels and shelf purchases.
	var b := full_shop()
	check(b.aging.purchase(b, "barrels", 1).ok and b.aging.barrel_count() == 2 and b.aging.purchase(b, "shelf", 1).ok and b.aging.shelf_capacity() == 18, "Barrel and shelf upgrades apply")
	# Every track to its last stage; every view must render at every combination.
	var all := full_shop(); all.gold = 10000000
	var spent := 20000
	for track in Aging.TRACKS:
		while not all.aging.view(all, track).complete:
			for other in Aging.TRACKS: check(all.aging.view(all, other).has("next_effect"), "View %s renders at %s" % [other, str(all.aging.levels)])
			var item: Dictionary = all.aging.view(all, track)
			check(all.aging.purchase(all, track, int(item.next_level)).ok, "Buy %s %d" % [track, int(item.next_level)])
			spent += int(item.cost)
	check(all.aging.barrel_count() == 4 and all.aging.max_stage() == 3 and all.aging.shelf_capacity() == 24 and all.progression.totals.manual_spent == 570000 and spent == 570000, "All eight stages cost 570,000 G and reach 4 barrels / stage 3 / 24 slots")
	# Frame independence with sales, sleep, aging and refills.
	var coarse := full_shop(); coarse.aging.purchase(coarse, "barrels", 1); coarse.set_shop_open(true)
	var fine := State.new(); check(fine.load_data(M.data(coarse)), "Clone for frame comparison")
	fine.set_shop_open(true); fine.customer_elapsed = coarse.customer_elapsed
	coarse.advance(3600.0)
	var left := 3600.0
	while left > 0.000001:
		var step := minf(0.7, left); fine.advance(step); left -= step
	check(Compare.equivalent(M.data(coarse), M.data(fine)), "One hour with aging agrees for one step and 0.7s steps")
	check(coarse.aging.totals.sold > 0, "The hour actually sold aged bottles (%d)" % coarse.aging.totals.sold)
	check(coarse.gold == 1000000 - 20000 - 30000 + coarse.total_sales_gold - coarse.total_spent_materials - coarse.total_spent_expeditions, "Gold ledger includes aged revenue exactly")
	# Saves.
	var restored := State.new()
	check(restored.load_data(M.data(coarse)) and Compare.equivalent(M.data(coarse), M.data(restored)), "Roundtrip with barrels and aged shelf")
	var base: Dictionary = M.data(coarse)
	var bad_cases := [
		func(d): for i in 3: d.aging.barrels.append({"bottles": [false], "elapsed": 0.0}),
		func(d): d.aging.barrels = [{"bottles": [], "elapsed": 0.0}],
		func(d): d.aging.barrels = [{"bottles": [false, false, false, false, false, false, false, false, false, false, false, false, false], "elapsed": 0.0}],
		func(d): d.aging.shelf = [{"kind": false, "stage": 3}],
		func(d): d.aging.levels.open = 0,
		func(d): d.aging.totals.sold = -1,
		func(d): d.aging.shelf = [{"kind": "not_a_potion", "stage": 1}],
	]
	for i in bad_cases.size():
		var broken: Dictionary = base.duplicate(true); bad_cases[i].call(broken)
		var target := State.new(); check(target.load_data(base), "Load base"); var before: Dictionary = M.data(target)
		check(not target.load_data(broken) and Compare.equivalent(before, M.data(target)), "Reject invalid aging case %d atomically" % i)
	var legacy: Dictionary = M.data(State.new()); legacy.version = 13; legacy.erase("aging")
	# v15 keeper fields postdate v13: write the v13 keeper shape (no counters, no bed/tea).
	legacy.erase("keeper_upgrades"); legacy.erase("report_f21"); legacy.keeper.erase("totals"); legacy.keeper.version = 1
	var migrated := State.new()
	check(migrated.load_data(legacy) and not migrated.aging.opened() and migrated.aging.barrels.is_empty(), "v13 save starts without aging")
	var result := {"checks": checks, "failures": failures, "passed": failures.is_empty(), "hour_aged_sold": coarse.aging.totals.sold, "hour_aged_revenue": coarse.aging.totals.revenue}
	M.write_json("res://.verification/f21-aging-20261021/aging.json", result)
	print("F21 AGING %s %d checks aged_sold=%d revenue=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, coarse.aging.totals.sold, coarse.aging.totals.revenue])
	quit(0 if failures.is_empty() else 1)
