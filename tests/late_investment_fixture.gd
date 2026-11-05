extends RefCounted
## F19 synthetic fixtures and simulated return-time decisions. No user save I/O.
const State = preload("res://scripts/shop_state.gd")
const Content = preload("res://scripts/shop_content.gd")
const F18 = preload("res://tests/contracts_fixture.gd")
const ORIGINAL_TRACKS := {"cauldron": 20, "herb_pot": 15, "sales_counter": 10, "potion_cabinet": 8, "herb_storage": 10, "drying_rack": 8, "expedition_path": 8, "precision_filter": 6, "family_vitality": 5, "family_arcane": 5, "family_nature": 5, "family_craft": 5, "sales_assistant": 5, "cultivation_assistant": 5, "brewing_assistant": 5, "expedition_guide": 5}
const TRACKS := ["supply_support", "contract_batch"]


static func data(state: RefCounted) -> Dictionary:
	return F18.data(state)


static func clone(state: RefCounted) -> RefCounted:
	var restored := State.new()
	assert(restored.load_data(data(state)), "Synthetic F19 fixture must pass actual save validation")
	return restored


static func remaining(state: RefCounted) -> Dictionary:
	# Original growth only: F26 post-growth rows (content_set) are not part of it.
	var recipes := 0
	for row in Content.DATA.potions:
		if F18.original(row) and not row.owned_at_start and not state.progression.owned.has(row.id): recipes += 1
	var regions := 0
	for row in Content.DATA.regions:
		if F18.original(row) and state.progression.expansion.region_returns(row.id, state.progression) < int(row.complete_returns): regions += 1
	var investments := 0
	for track in ORIGINAL_TRACKS:
		investments += maxi(0, int(ORIGINAL_TRACKS[track]) - state.track_level(track))
	var staff := 0
	for row in Content.DATA.employees:
		if not state.progression.expansion.staff.has(row.id) and not (row.id == "sales_assistant" and state.progression.employee): staff += 1
	return {"recipes": recipes, "regions": regions, "investments": investments, "employees": staff}


static func complete_original(state: RefCounted) -> bool:
	return remaining(state).values().all(func(value): return value == 0)


static func option(state: RefCounted, partner: String, kind: String) -> Dictionary:
	for row in state.contracts.partner_view(state, partner).options:
		if row.id == kind: return row
	return {}


static func synthetic_round(state: RefCounted, partner: String) -> void:
	# This creates valid past contract history for effect-only comparisons.
	# It is never used by the fresh zero-gold growth measurement.
	var round_id: String = state.contracts.partners[partner].round.id
	while state.contracts.partners[partner].round.id == round_id:
		var current: Dictionary = state.contracts.partners[partner].round
		var chosen := ""
		var order := -1
		for id in current.allowed:
			var family: String = current.allowed[id].family
			var rank: int = Content.lookup("potions", id).order
			if current.shipped[family] < current.requirements[family] and rank > order:
				chosen = id
				order = rank
		assert(not chosen.is_empty())
		state.contracts.batch = {"purpose": "contract", "partner": partner, "round_id": round_id, "kind": false if chosen == "health" else true if chosen == "mana" else chosen, "quantity": 1}
		assert(state.contracts.complete(state, state.contracts.batch.kind).get("ok", false))


static func completed_store(seed_value: int, terms: String, combo: String, scenario: String) -> RefCounted:
	var source := F18.completed(seed_value)
	source.contracts.seed = seed_value
	for partner in source.contracts.PARTNERS:
		assert(source.contracts.accept(source, partner.id, option(source, partner.id, "basic").token).get("ok", false))
		while source.contracts.grade(partner.id) < 4: synthetic_round(source, partner.id)
	if terms == "final":
		var log: Array = []
		negotiate_returns(source, "payment", log)
		for partner in source.contracts.PARTNERS: synthetic_round(source, partner.id)
	assert(complete_original(source))
	# Real setup purchases initialize the reserved60-second supply cycle. Setup
	# money is explicitly synthetic and excluded from the measured ledger.
	source.gold = 3000000
	var support := int(combo.trim_prefix("support")) if combo.begins_with("support") else int(combo.trim_prefix("both")) if combo.begins_with("both") else 0
	var bulk := int(combo.trim_prefix("bulk")) if combo.begins_with("bulk") else int(combo.trim_prefix("both")) if combo.begins_with("both") else 0
	for level in range(1, support + 1): assert(source.late_investments.purchase(source, "supply_support", level).get("ok", false))
	for level in range(1, bulk + 1): assert(source.late_investments.purchase(source, "contract_batch", level).get("ok", false))
	source.gold = 1000000
	if scenario == "scarce_upper":
		for id in ["star_seed", "moonflower", "ash_sage", "crystal_herb"]: source.progression.expansion.materials[id] = 0
	if scenario == "inventory_full":
		for index in source.capacity(): source.inventory.append(["eternity", "sage_elixir", "worldtree_elixir", "shadow_elixir", "rare_nebula_distillate"][index % 5])
		source.stock = source.inventory.size()
	return clone(source)


static func negotiate_returns(state: RefCounted, strategy: String, log: Array) -> void:
	if not state.contracts.unlocked(state): return
	for partner in state.contracts.PARTNERS:
		var view: Dictionary = state.contracts.partner_view(state, partner.id)
		if view.negotiation.accepted: continue
		var chosen := "payment" if view.grade == 4 or strategy == "payment" else "relationship"
		var row := option(state, partner.id, chosen)
		if row.get("can_negotiate", false):
			var result: Dictionary = state.contracts.negotiate(state, partner.id, row.token)
			assert(result.get("ok", false), "Only current offered negotiations are used")
			log.append({"action": "negotiate", "time": state.progression.clock, "partner": partner.id, "grade": view.grade, "choice": chosen, "training": state.contracts.training, "result": result.duplicate(true)})
		row = option(state, partner.id, chosen)
		if not row.get("can_accept", false): row = option(state, partner.id, "basic")
		if row.get("can_accept", false):
			var result: Dictionary = state.contracts.accept(state, partner.id, row.token)
			assert(result.get("ok", false), "Current valid final proposal is accepted once")
			log.append({"action": "accept", "time": state.progression.clock, "partner": partner.id, "grade": view.grade, "choice": row.id, "result": result.duplicate(true)})


static func purchase_original(state: RefCounted, policy: String, log: Array) -> void:
	# Same original-content ranking as measure_full_expansion; only runs at a
	# simulated human return, never installs automatic shopping in production.
	for decision in 160:
		var candidates := []
		var completed: int = state.progression.completed_regions()
		var reserve := 0
		for potion in Content.DATA.potions:
			var id: String = potion.id
			if potion.owned_at_start or state.purchase_reason(id) != "": continue
			var rank := 5.0 if potion.existing else 20.0 - float(potion.order) / 100.0
			candidates.append({"kind": id, "cost": state.purchase_cost(id), "rank": rank})
			if not potion.existing: reserve = state.purchase_cost(id) if reserve == 0 else mini(reserve, state.purchase_cost(id))
		for region in Content.DATA.regions:
			var kind: String = "expedition" if region.id == "forest_edge" else "region:" + str(region.id)
			if state.purchase_reason(kind) != "": continue
			candidates.append({"kind": kind, "cost": state.purchase_cost(kind), "rank": 25.0 if policy == "equipment_first" else 8.0})
			reserve = state.purchase_cost(kind) if reserve == 0 else mini(reserve, state.purchase_cost(kind))
		for employee in Content.DATA.employees:
			var kind := "staff:" + str(employee.id)
			if state.purchase_reason(kind) == "": candidates.append({"kind": kind, "cost": state.purchase_cost(kind), "rank": 23.0 if employee.id == "sales_assistant" else 34.0})
		for track in ORIGINAL_TRACKS:
			var kind: String = "upgrade:" + track
			if state.purchase_reason(kind) != "": continue
			var next: Dictionary = state.next_investment(track)
			var essential: bool = (track == "cauldron" and int(next.stage) <= mini(14, 4 + completed * 2)) or (track == "herb_pot" and int(next.stage) <= mini(11, 2 + completed))
			var rank := (2.0 if int(next.stage) <= 2 else 15.0) if essential else (27.0 if track == "sales_counter" and int(next.stage) <= 2 + completed else 40.0)
			if policy == "equipment_first": rank -= 12.0
			if not essential and state.gold - state.purchase_cost(kind) < reserve and policy != "equipment_first": continue
			candidates.append({"kind": kind, "cost": state.purchase_cost(kind), "rank": rank})
		if candidates.is_empty(): break
		candidates.sort_custom(func(a, b): return a.rank < b.rank or (is_equal_approx(a.rank, b.rank) and a.cost < b.cost))
		var before: int = state.gold
		var chosen: Dictionary = candidates[0]
		assert(state.purchase(chosen.kind), "Affordability and original purchase gateway agree")
		log.append({"action": "original_purchase", "time": state.progression.clock, "kind": chosen.kind, "cost": chosen.cost, "gold_before": before, "gold_after": state.gold})


static func train_to(state: RefCounted, target: int, log: Array) -> void:
	while state.contracts.training < target:
		var view: Dictionary = state.contracts.training_view(state)
		if not view.can_buy: return
		var before: int = state.gold
		var result: Dictionary = state.contracts.train(state, state.contracts.training + 1)
		assert(result.get("ok", false), "Training uses a fresh next-stage token")
		log.append({"action": "training", "time": state.progression.clock, "cost": before - state.gold, "gold_before": before, "gold_after": state.gold, "stage": state.contracts.training, "view_before": view.duplicate(true)})


static func purchase_late(state: RefCounted, log: Array) -> void:
	for attempt in 6:
		var candidates := []
		for track in TRACKS:
			var view: Dictionary = state.late_investments.view(state, track)
			if view.get("can_buy", false): candidates.append({"track": track, "stage": int(state.late_investments.stages[track]), "cost": int(view.cost)})
		if candidates.is_empty(): return
		candidates.sort_custom(func(a, b): return a.stage < b.stage or (a.stage == b.stage and a.track == "supply_support"))
		var chosen: Dictionary = candidates[0]
		var before: int = state.gold
		var result: Dictionary = state.late_investments.purchase(state, chosen.track, chosen.stage + 1)
		assert(result.get("ok", false), "Late investment uses a fresh next-stage token and actual cash")
		log.append({"action": "late_purchase", "time": state.progression.clock, "track": chosen.track, "stage": chosen.stage + 1, "cost": chosen.cost, "gold_before": before, "gold_after": state.gold})


static func cash_identity(state: RefCounted, starting_gold: int = 0, initial: Dictionary = {}) -> int:
	return starting_gold + state.total_sales_gold - int(initial.get("sales", 0)) + int(state.contracts.totals.paid) - int(initial.get("contracts", 0)) - state.total_spent_materials + int(initial.get("materials", 0)) - state.total_spent_expeditions + int(initial.get("fees", 0)) - int(state.progression.totals.manual_spent) + int(initial.get("manual", 0))


static func unpaid_value(state: RefCounted) -> float:
	var total := 0.0
	for partner in state.contracts.PARTNERS:
		var round_data: Dictionary = state.contracts.partners[partner.id].round
		if not round_data.is_empty(): total += int(round_data.base_total) * state.contracts._multiplier(round_data.terms)
	return total


static func write_json(path: String, payload: Dictionary) -> void:
	F18.write_json(path, payload)
