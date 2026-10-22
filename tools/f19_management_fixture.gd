extends RefCounted
## Synthetic UI-only history. Real module completions establish valid ranks.
const State = preload("res://scripts/shop_state.gd")
const F18 = preload("res://tests/contracts_fixture.gd")

static func completed(rank: int = 1, training: int = 0, all_partners: bool = false) -> RefCounted:
	var state := F18.completed()
	state.contracts.training = training
	if rank > 1:
		for partner in state.contracts.PARTNERS:
			if not all_partners and partner.id != "caravan": continue
			accept_basic(state, partner.id)
			while state.contracts.grade(partner.id) < rank: finish_round(state, partner.id)
	state.gold = 10000000 # UI affordability fixture, never a measured growth balance.
	var normalized := State.new()
	assert(normalized.load_data(F18.data(state)), "F19 UI history passes strict current save validation")
	return normalized

static func accept_basic(state: RefCounted, partner: String) -> void:
	for item in state.contracts.partner_view(state, partner).options:
		if item.id == "basic":
			assert(state.contracts.accept(state, partner, item.token).ok)
			return

static func finish_round(state: RefCounted, partner: String) -> void:
	var original: String = state.contracts.partners[partner].round.id
	while state.contracts.partners[partner].round.id == original:
		var data: Dictionary = state.contracts.partners[partner].round
		var index := 0
		var shipped := false
		for family in data.requirements:
			if data.shipped[family] < data.requirements[family]:
				for id in data.allowed:
					if data.allowed[id].family != family: continue
					var kind: Variant = false if id == "health" else true if id == "mana" else id
					state.contracts.reserve({"partner": partner, "round_id": original, "kind": kind, "id": id, "family_index": index, "quantity": 1, "duration": state.brew_duration_for(kind)}, {"chance": 1.0, "success": true})
					assert(state.contracts.complete(state, kind).ok)
					shipped = true
					break
			if shipped: break
			index += 1
		assert(shipped, "Synthetic history always uses an allowed unfinished family")

static func buy_to(state: RefCounted, track: String, stage: int) -> void:
	while int(state.late_investments.stages[track]) < stage:
		assert(state.late_investments.purchase(state, track, int(state.late_investments.stages[track]) + 1).ok)
