extends SceneTree
const State = preload("res://scripts/shop_state.gd")
const F = preload("res://tests/late_investment_fixture.gd")
const M = preload("res://tests/contracts_fixture.gd")
const Compare = preload("res://tests/state_compare.gd")
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1; assert(ok,label)
func fill(state: RefCounted, count: int) -> void:
	state.stock = count; state.mana_stock = 0; state.inventory.clear()
	for i in count: state.inventory.append(false)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var s := M.completed(73129)
	# F20-A applies from the first accepted contract (spec fix 2026-10-21).
	var first: Dictionary = s.contracts.PARTNERS[0]
	assert(s.contracts.accept(s, first.id, F.option(s, first.id, "basic").token).get("ok", false))
	s.progression.expansion.stages.potion_cabinet = 0
	fill(s,4); s._start_batch(); s.brew_elapsed = 0.25
	check(s.capacity() == 12 and not s.stock_protection.active,"Old capacity middle starts inactive")
	var seed_value: int = s.progression.seed_value; var kind: Variant = s.progression.active_recipe
	var materials: Dictionary = M.materials(s); var chance: float = s.progression.batch_chance
	var success: bool = s.progression.batch_success
	check(s.buy_investment("potion_cabinet") and s.capacity() == 18,"Real warehouse purchase recalculates capacity12 to18")
	s._start_batch()
	check(s.stock_protection.active,"Stock4 now enters low threshold4")
	check(s.brew_active and s.brew_elapsed == 0.25 and s.progression.active_recipe == kind and s.progression.seed_value == seed_value and s.progression.batch_chance == chance and s.progression.batch_success == success and Compare.equivalent(materials,M.materials(s)),"Warehouse transition cannot reconsume/reroll/reset active production")
	s = F.completed_store(73129,"final","both3","normal"); s.gold = 10000000; s.shop_open = false
	fill(s,16); check(s.workshop.purchase(s,1).ok,"Expansion for simultaneous boundary")
	s.workshop.seed = 1; s._start_batch()
	check(s.progression.batch_success and s.workshop.aux.batch.success,"Two genuinely successful reserved judgements")
	var n: int = s.workshop.aux.batch.quantity; var shipped: int = s.contracts.totals.shipped
	s.brew_elapsed = s.brew_duration()-0.5; s.workshop.aux.elapsed = float(s.workshop.aux.batch.duration)-0.5
	var event: Dictionary = s.advance(0.5)
	check(s.stock == 17 and s.contracts.totals.shipped == shipped+n,"Same-time completions add one retail and dispatch only actual auxiliary quantity")
	check(event.potion_events.size() == 1 and event.potion_events[0].kind == "brew" and event.contract_events.size() == 1 and event.contract_events[0].shipped == n,"Exactly one event per line without retail leakage")
	var before: Dictionary = M.data(s)
	check(s.workshop.finish(s).is_empty() and Compare.equivalent(before,M.data(s)),"Repeated boundary cannot settle or advance a new reservation")
	var rounds := {}; var payments := 0; var total_paid: int = s.contracts.totals.paid
	for i in 600:
		# Plenty of actual material, so all partners can finish repeated rounds.
		M.fill_materials(s)
		event = s.advance(1)
		for item in event.contract_events:
			if item.paid > 0:
				check(not rounds.has(item.completed_round),"A partner round pays once")
				rounds[item.completed_round] = true; payments += int(item.paid)
	check(rounds.size() >= 3 and payments == int(s.contracts.totals.paid)-total_paid,"Actual repeated settlements and aggregate cash agree")
	M.write_json("res://.verification/f20-20261020/B/edges.json",{"passed":true,"checks":checks,"paid_rounds":rounds.size(),"actual_paid":payments})
	print("F20 EDGES PASS ",checks," checks and ",rounds.size()," unique paid rounds");quit()
