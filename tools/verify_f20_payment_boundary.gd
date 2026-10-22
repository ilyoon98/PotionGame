extends SceneTree
const State = preload("res://scripts/shop_state.gd")
const F = preload("res://tests/late_investment_fixture.gd")
const M = preload("res://tests/contracts_fixture.gd")
const Compare = preload("res://tests/state_compare.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var s := F.completed_store(73129,"final","both3","inventory_full")
	s.gold = 10000000; assert(s.workshop.purchase(s,1).ok)
	var round_data: Dictionary = s.contracts.partners.caravan.round
	while int(round_data.requirements.values().reduce(func(a,b):return a+b,0))-int(round_data.shipped.values().reduce(func(a,b):return a+b,0)) > 4:
		var chosen := ""
		for id in round_data.allowed:
			var family: String = round_data.allowed[id].family
			if round_data.shipped[family] < round_data.requirements[family]: chosen = id; break
		assert(not chosen.is_empty())
		var kind: Variant = false if chosen == "health" else true if chosen == "mana" else chosen
		s.contracts.batch = {"purpose":"contract","partner":"caravan","round_id":round_data.id,"kind":kind,"quantity":1}
		assert(s.contracts.complete(s,kind).ok)
	s.workshop.seed = 1; s.contracts.partner_cursor = 0; s._start_batch()
	assert(s.workshop.aux.batch.partner == "caravan" and s.workshop.aux.batch.quantity == 4 and s.workshop.aux.batch.success)
	M.clear_materials(s); s.stock=0; s.mana_stock=0; s.inventory.clear(); s.gold=0
	s.harvest_elapsed = s.harvest_duration()-0.1
	s.workshop.aux.elapsed = float(s.workshop.aux.batch.duration)-0.1
	s.delivery_elapsed = s.DELIVERY_INTERVAL
	var coarse := State.new(); var fine := State.new()
	assert(coarse.load_data(M.data(s)) and fine.load_data(M.data(s)))
	coarse.advance(0.2); fine.advance(0.1); fine.advance(0.1)
	var identical := Compare.equivalent(M.data(coarse),M.data(fine))
	var report := {"passed":identical,"coarse_kind":coarse.progression.active_recipe,"fine_kind":fine.progression.active_recipe,"coarse_cash":coarse.gold,"fine_cash":fine.gold,"checks":1,"case":"Harvest and auxiliary payout at0.1s must fund the same ready delivery before next retail reservation under0.2 versus0.1+0.1 advancement"}
	var name := "payment-boundary-pass.json" if identical else "payment-boundary-before.json"
	M.write_json("res://.verification/f20-20261020/B/"+name,report)
	print("F20 PAYMENT BOUNDARY ","PASS" if identical else "FAIL"," coarse=",coarse.progression.active_recipe," fine=",fine.progression.active_recipe)
	quit(0 if identical else 1)
