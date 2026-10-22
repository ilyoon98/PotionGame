extends SceneTree
## F20-A spec gate (fixed 2026-10-21): free stock protection applies only from the
## first accepted contract. Before that, a fresh shop sells about as fast as it
## brews, so an always-on protection blocked every purchased recipe and mana.
## Workspace-only synthetic stores; never reads a player save.
const State = preload("res://scripts/shop_state.gd")
const F = preload("res://tests/late_investment_fixture.gd")
const M = preload("res://tests/contracts_fixture.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	check(DisplayServer.get_name() == "headless", "Only workspace headless fake stores")
	# Fresh shop: recipe and mana join production while stock stays near zero.
	var fresh := State.new(); fresh.gold = 5000
	check(fresh.purchase("moon"), "Buy moon recipe")
	var ever_active := false
	for i in 600:
		fresh.advance(1.0)
		ever_active = ever_active or fresh.stock_protection.active
	var moon: int = int(fresh.progression.by_potion.get("달빛 물약", 0))
	var mana: int = int(fresh.progression.by_potion.get("마나", 0))
	check(not ever_active, "No contract: protection never activates in 10 minutes")
	check(moon > 0, "Purchased moon recipe is actually brewed and sold (%d moon)" % moon)
	check(mana > 0, "Delivered mushrooms are brewed and sold as mana (%d mana)" % mana)
	# Late shop before its first contract: still off even at stock 0.
	var late := M.completed(73129)
	late.stock = 0; late.mana_stock = 0; late.inventory.clear()
	check(late.contracts.unlocked(late) and not late.contracts.in_use(), "Fixture has contracts unlocked but none accepted")
	late._start_batch()
	check(not late.stock_protection.active, "Unlocked but unused contracts keep protection off")
	# The first accepted contract turns the F20-A hysteresis on.
	var first: Dictionary = late.contracts.PARTNERS[0]
	check(late.contracts.accept(late, first.id, F.option(late, first.id, "basic").token).get("ok", false), "Accept first basic contract")
	check(late.contracts.in_use(), "Accepted agreement counts as contract use")
	late.brew_active = false
	late._start_batch()
	check(late.stock_protection.active and late.progression.active_recipe is bool and not late.progression.active_recipe, "After the first contract, stock 0 recovers with basic potions first")
	# Saves: a pre-contract v11 save initializes off; a v12 flag is kept until the next boundary.
	var legacy: Dictionary = M.data(State.new()); legacy.version = 11; legacy.erase("stock_protection"); legacy.erase("workshop")
	var migrated := State.new()
	check(migrated.load_data(legacy) and not migrated.stock_protection.active, "Pre-contract v11 save starts with protection off")
	var stale: Dictionary = M.data(State.new()); stale.stock_protection = true
	var resumed := State.new()
	check(resumed.load_data(stale) and resumed.stock_protection.active, "Saved v12 flag loads unchanged")
	resumed._start_batch()
	check(not resumed.stock_protection.active, "Next scheduling boundary clears a pre-contract saved flag")
	var result := {"checks": checks, "failures": failures, "passed": failures.is_empty(), "fresh_moon": moon, "fresh_mana": mana, "fresh_brewed": fresh.progression.totals.brewed}
	M.write_json("res://.verification/f21-stale-tests-20261021/protection-gate.json", result)
	print("F21 PROTECTION GATE %s %d checks moon=%d mana=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, moon, mana])
	quit(0 if failures.is_empty() else 1)
