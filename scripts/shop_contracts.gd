extends RefCounted
## F18 initial balance. This module owns contracts, never the cauldron or retail stock.
const Content = preload("res://scripts/shop_content.gd")
const VERSION := 1
const INITIAL_SEED := 18273129
const PARTNERS := [
	{"id": "caravan", "name": "여행자 상단", "customer": "traveler", "families": ["vitality", "craft"]},
	{"id": "academy", "name": "마법 연구회", "customer": "mage", "families": ["arcane", "craft"]},
	{"id": "grove", "name": "숲 조합", "customer": "elf", "families": ["nature", "vitality"]},
]
const OPTIONS := ["basic", "payment", "relationship"]
const OPTION_NAMES := {"basic": "기본 제안", "payment": "대금 중심", "relationship": "거래 관계 중심"}
const THRESHOLDS := [0, 60, 240, 600]
const QUANTITIES := [20, 40, 60, 80]
## F21 auxiliary batches: F19 limit 4 x auxiliary multiplier 3.
const MAX_BATCH_BOTTLES := 12
const TRAINING_COSTS := [8000, 20000, 50000]
const LIMIT := 1000000000000

var training := 0
var seed := INITIAL_SEED
var ordinary_batches := 0 # Five start slots: ordinary 0..3, contract-or-ordinary 4.
var partner_cursor := 0
var batch := {"purpose": "ordinary"}
var totals := {"shipped": 0, "paid": 0, "rounds": 0, "points": 0}
var report_paid := 0
var partners := {}

func _init() -> void:
	for item in PARTNERS:
		partners[item.id] = {"points": 0, "family_cursor": 0, "serial": 0, "agreement": {}, "pending": {}, "round": {}, "last_round": {}, "history": {}, "totals": {"shipped": 0, "paid": 0, "rounds": 0}}

func unlocked(state: RefCounted) -> bool:
	return state.progression.expansion.regions.has("star_garden")

## A first contract was accepted; agreements persist across automatic rounds.
func in_use() -> bool:
	for id in partners:
		if not partners[id].agreement.is_empty(): return true
	return false

func _partner(id: String) -> Dictionary:
	for item in PARTNERS:
		if item.id == id: return item
	return {}

func grade(id: String) -> int:
	if not partners.has(id): return 0
	return _grade(int(partners[id].points))

func _grade(points: int) -> int:
	var result := 1
	for index in THRESHOLDS.size():
		if points >= THRESHOLDS[index]: result = index + 1
	return result

func chance(rank: int, stage: int = -1) -> float:
	return 1.0 if rank == 4 else minf(0.9, 0.6 + 0.1 * (training if stage < 0 else stage))

func _opportunity(id: String, rank: int) -> String:
	return "%s:%d:v%d" % [id, rank, VERSION]

func _record(id: String, rank: int) -> Dictionary:
	return partners[id].history.get(str(rank), {"opportunity": _opportunity(id, rank), "grade": rank, "version": VERSION, "tried": false, "choice": "", "chance": 0.0, "training": 0, "success": false, "accepted": false, "final": ""}).duplicate(true)

func _terms(rank: int, option: String) -> Dictionary:
	return {"grade": rank, "option": option, "version": VERSION}

func _requirements(id: String, terms: Dictionary) -> Dictionary:
	var result := {}
	var amount := int(QUANTITIES[int(terms.grade) - 1]) / 2
	if terms.option != "basic": amount = int(ceil(amount * 1.2))
	for family in _partner(id).families: result[family] = amount
	return result

func _multiplier(terms: Dictionary) -> float:
	return (1.80 if terms.get("option", "basic") == "payment" else 1.60) + 0.1 * (int(terms.get("grade", 1)) - 1)

func _points(terms: Dictionary) -> int:
	var quantity: int = QUANTITIES[int(terms.grade) - 1]
	if terms.option != "basic": quantity = int(ceil(quantity / 2.0 * 1.2)) * 2
	return quantity * (2 if terms.option == "relationship" else 1)

func _owned(row: Dictionary, p: RefCounted) -> bool:
	return row.id in ["health", "mana"] or p.owned.has(row.id)

func _kind(id: String) -> Variant:
	return false if id == "health" else true if id == "mana" else id

func _id(kind: Variant) -> String:
	return ("mana" if kind else "health") if kind is bool else str(kind)

func _allowed(state: RefCounted, id: String) -> Dictionary:
	var result := {}
	var p: RefCounted = state.progression
	var cauldron: float = p.expansion.effect("cauldron", "quality_sale_bonus")
	var assistant: float = p.expansion.effect("brewing_assistant", "new_recipe_quality_bonus")
	for row in Content.DATA.potions:
		if _partner(id).families.has(row.family) and _owned(row, p):
			result[row.id] = {"family": row.family, "unit": int(round(int(row.sale_price) * (1.0 + cauldron + (assistant if not row.existing else 0.0))))}
	return result

func _missing_family(id: String, allowed: Dictionary) -> String:
	for family in _partner(id).families:
		var found := false
		for item in allowed.values():
			if item.family == family: found = true
		if not found: return "%s 계열 레시피 필요" % Content.lookup("families", family).name
	return ""

func remaining_opportunities() -> int:
	var count := 0
	for item in PARTNERS:
		for rank in range(grade(item.id), 4):
			var record: Dictionary = partners[item.id].history.get(str(rank), {})
			if not record.get("tried", false) and not record.get("accepted", false): count += 1
	return count

func training_view(state: RefCounted) -> Dictionary:
	var cost: int = TRAINING_COSTS[training] if training < 3 else 0
	var remaining := remaining_opportunities()
	var reason := "별의 정원 개방 필요" if not unlocked(state) else "최대 단계" if training == 3 else "적용할 흥정 없음" if remaining == 0 else "%d G 부족" % maxi(0, cost - state.gold) if state.gold < cost else ""
	return {"level": training, "max_level": 3, "next_level": training + 1 if training < 3 else 0, "remaining_opportunities": remaining, "cost": cost, "chance": chance(1), "next_chance": chance(1, mini(3, training + 1)), "bonus": training * 0.1, "next_bonus": mini(3, training + 1) * 0.1, "final_chance": 1.0, "reason": reason, "can_buy": reason.is_empty(), "unlocked": unlocked(state)}

func partner_view(state: RefCounted, id: String) -> Dictionary:
	if not partners.has(id): return {"exists": false}
	var item := _partner(id)
	var p: Dictionary = partners[id]
	var rank := grade(id)
	var record := _record(id, rank)
	var allowed := _allowed(state, id)
	var reason := "별의 정원 개방 필요" if not unlocked(state) else _missing_family(id, allowed)
	var round_data: Dictionary = p.round
	var counts := []
	var shipped := 0
	var required := 0
	for family in item.families:
		var need: int = int(round_data.get("requirements", {}).get(family, 0))
		var sent: int = int(round_data.get("shipped", {}).get(family, 0))
		counts.append({"family": family, "name": Content.lookup("families", family).name, "required": need, "shipped": sent})
		required += need
		shipped += sent
	var options := []
	var actual_chance: float = float(record.chance) if record.tried else chance(rank)
	for option in OPTIONS:
		if rank == 4 and option == "relationship": continue
		var terms := _terms(rank, option)
		var token := {"option": option, "grade": rank, "opportunity": record.opportunity, "version": VERSION}
		var can_accept: bool = reason.is_empty() and not record.accepted and ((option == "basic" and not (record.tried and record.success)) or (record.tried and record.success and record.choice == option))
		var can_negotiate: bool = reason.is_empty() and option != "basic" and not record.tried and not record.accepted
		options.append({"id": option, "kind": option, "label": OPTION_NAMES[option], "token": token, "requirements": _requirements(id, terms), "multiplier": _multiplier(terms), "points": _points(terms), "chance": actual_chance, "can_accept": can_accept, "can_negotiate": can_negotiate, "reason": reason if not reason.is_empty() else "협의 완료" if record.accepted else "이미 판정한 협의" if record.tried and not can_accept else ""})
	var items := []
	var proposal_items := []
	for potion in allowed:
		proposal_items.append({"id": potion, "kind": _kind(potion), "name": Content.lookup("potions", potion).name, "family": allowed[potion].family, "price": allowed[potion].unit})
	var visible_allowed: Dictionary = allowed if round_data.is_empty() else round_data.allowed
	for potion in visible_allowed:
		items.append({"id": potion, "kind": _kind(potion), "name": Content.lookup("potions", potion).name, "family": visible_allowed[potion].family, "price": visible_allowed[potion].unit})
	var status := reason
	if status.is_empty():
		if round_data.is_empty(): status = "첫 계약" if not record.tried else "흥정 성공 · 수락 대기" if record.success else "흥정 실패 · 기본 계약 가능"
		elif not p.pending.is_empty(): status = "새 조건 적용 대기"
		elif not record.accepted: status = "새 조건 협의 가능" if not record.tried else "흥정 성공 · 수락 대기" if record.success else "흥정 실패 · 기존 납품 중"
		else: status = "최고 등급 · 자동 납품" if rank == 4 else "납품 중"
	if not round_data.is_empty() and _ready_for(id, state).is_empty() and not status.contains("협의") and not status.contains("수락") and not status.contains("조건"): status = "재료 대기"
	return {"exists": true, "id": id, "name": item.name, "customer": item.customer, "families": item.families.duplicate(), "unlocked": unlocked(state), "grade": rank, "points": p.points, "next_points": THRESHOLDS[rank] if rank < 4 else 0, "status": status, "active": not round_data.is_empty(), "round": round_data.duplicate(true), "current_round": round_data.duplicate(true), "agreement": p.agreement.duplicate(true), "pending": p.pending.duplicate(true), "pending_contract": p.pending.duplicate(true), "counts": counts, "shipped": shipped, "required": required, "progress": float(shipped) / required if required > 0 else 0.0, "paid": p.totals.paid, "estimate": int(round(int(round_data.get("base_total", 0)) * _multiplier(round_data.get("terms", {})))), "multiplier": _multiplier(round_data.get("terms", {})), "negotiation": record, "opportunity": record.opportunity, "chance": actual_chance, "options": options, "allowed_items": items, "proposal_items": proposal_items, "totals": p.totals.duplicate(true)}

func _token_error(state: RefCounted, id: String, token: Variant) -> String:
	if not partners.has(id): return "알 수 없는 거래처"
	if not unlocked(state): return "별의 정원 개방 필요"
	if not token is Dictionary or not _keys(token, ["option", "grade", "opportunity", "version"]): return "오래된 계약 화면이에요"
	if not token.option is String or not OPTIONS.has(token.option) or not _integer(token.grade, 1, 4) or not _integer(token.version, VERSION, VERSION) or not token.opportunity is String: return "알 수 없는 계약 조건"
	if int(token.grade) != grade(id) or token.opportunity != _opportunity(id, grade(id)): return "새 등급의 조건을 다시 확인해 주세요"
	if grade(id) == 4 and token.option == "relationship": return "최고 등급은 대금 중심 조건을 선택해 주세요"
	if _record(id, grade(id)).accepted: return "이미 수락한 협의예요"
	return _missing_family(id, _allowed(state, id))

func negotiate(state: RefCounted, id: String, option: Variant) -> Dictionary:
	var error := _token_error(state, id, option)
	if not error.is_empty(): return {"ok": false, "error": error}
	if option.option == "basic": return {"ok": false, "error": "기본 제안은 바로 수락할 수 있어요"}
	var record := _record(id, grade(id))
	if record.tried: return {"ok": false, "error": "이미 판정한 협의예요"}
	record.tried = true
	record.choice = option.option
	record.chance = chance(grade(id))
	record.training = training
	if record.chance >= 1.0: record.success = true
	else:
		seed = (seed * 48271) % 2147483647
		record.success = float(seed) / 2147483647.0 < float(record.chance)
	record.final = option.option if record.success else "basic"
	partners[id].history[str(grade(id))] = record
	return {"ok": true, "error": "", "success": record.success, "chance": record.chance, "option": record.final, "opportunity": record.opportunity}

func accept(state: RefCounted, id: String, option: Variant) -> Dictionary:
	var error := _token_error(state, id, option)
	if not error.is_empty(): return {"ok": false, "error": error}
	var rank := grade(id)
	var record := _record(id, rank)
	if option.option == "basic" and record.tried and record.success: return {"ok": false, "error": "성공한 개선 조건을 수락해 주세요"}
	if option.option != "basic" and (not record.tried or not record.success or record.choice != option.option): return {"ok": false, "error": "흥정 결과를 먼저 확인해 주세요"}
	record.accepted = true
	record.final = option.option
	partners[id].history[str(rank)] = record
	var terms := _terms(rank, option.option)
	if partners[id].round.is_empty():
		partners[id].agreement = terms
		_start_round(state, id)
	else: partners[id].pending = terms
	return {"ok": true, "error": "", "pending": not partners[id].pending.is_empty()}

func train(state: RefCounted, expected_next_level: int = -1) -> Dictionary:
	if expected_next_level != -1 and expected_next_level != training + 1: return {"ok": false, "error": "훈련 단계가 변경되었어요"}
	var view := training_view(state)
	if not view.can_buy: return {"ok": false, "error": view.reason}
	state.gold -= int(view.cost)
	state.progression.totals.manual_spent += int(view.cost)
	training += 1
	return {"ok": true, "error": "", "cost": view.cost, "level": training}

func _start_round(state: RefCounted, id: String) -> void:
	var p: Dictionary = partners[id]
	if not p.pending.is_empty():
		p.agreement = p.pending.duplicate(true)
		p.pending = {}
	p.serial += 1
	var requirements := _requirements(id, p.agreement)
	var shipped := {}
	for family in requirements: shipped[family] = 0
	p.round = {"id": "%s:%d" % [id, int(p.serial)], "serial": p.serial, "terms": p.agreement.duplicate(true), "requirements": requirements, "shipped": shipped, "allowed": _allowed(state, id), "shipped_by_kind": {}, "base_total": 0, "paid": false, "payout": 0, "cauldron_quality": state.progression.expansion.effect("cauldron", "quality_sale_bonus"), "assistant_quality": state.progression.expansion.effect("brewing_assistant", "new_recipe_quality_bonus")}

func _ready_for(id: String, state: RefCounted, retail_reserve: Dictionary = {}, max_quantity: int = 0) -> Dictionary:
	var limit: int = max_quantity if max_quantity > 0 else int(state.late_investments.batch_max())
	var p: Dictionary = partners[id]
	if p.round.is_empty(): return {}
	var item := _partner(id)
	for offset in item.families.size():
		var family_index: int = (int(p.family_cursor) + offset) % item.families.size()
		var family: String = item.families[family_index]
		if p.round.shipped[family] >= p.round.requirements[family]: continue
		var chosen := ""
		var best := -1
		var best_value := 0
		for potion in p.round.allowed:
			var row := Content.lookup("potions", potion)
			if row.family != family: continue
			var fits: int = mini(limit, int(p.round.requirements[family]) - int(p.round.shipped[family]))
			for material in row.ingredients:
				fits = mini(fits, (state.material_count(material) - int(retail_reserve.get(material, 0))) / int(row.ingredients[material]))
			if fits < 1: continue
			# The main cauldron keeps the highest tier. The slow F21 auxiliary line
			# fills its batch with the most valuable bottles that actually fit.
			var value: int = int(p.round.allowed[potion].unit) * fits if max_quantity > 0 else 0
			if value > best_value or (value == best_value and int(row.order) > best):
				chosen = potion
				best = int(row.order)
				best_value = value
		if not chosen.is_empty():
			var quantity: int = mini(limit, int(p.round.requirements[family]) - int(p.round.shipped[family]))
			var recipe: Dictionary = Content.lookup("potions", chosen).ingredients
			for material in recipe: quantity = mini(quantity, (state.material_count(material) - int(retail_reserve.get(material, 0))) / int(recipe[material]))
			if quantity < 1: continue
			var ingredients := {}
			for material in recipe: ingredients[material] = int(recipe[material]) * quantity
			return {"partner": id, "round_id": p.round.id, "kind": _kind(chosen), "id": chosen, "family": family, "family_index": family_index, "quantity": quantity, "max_quantity": limit, "ingredients": ingredients, "duration": state.brew_duration_for(_kind(chosen)), "chance": state.progression.success_chance(_kind(chosen))}
	return {}

## max_quantity 0 means the main cauldron's F19 batch limit.
func candidate(state: RefCounted, retail_reserve: Dictionary = {}, ignore_ratio: bool = false, max_quantity: int = 0) -> Dictionary:
	if batch.get("purpose", "ordinary") == "contract" or (not ignore_ratio and ordinary_batches < 4 and state.stock < state.capacity()) or not unlocked(state): return {}
	for offset in PARTNERS.size():
		var index := (partner_cursor + offset) % PARTNERS.size()
		var result := _ready_for(PARTNERS[index].id, state, retail_reserve, max_quantity)
		if not result.is_empty():
			result["partner_index"] = index
			return result
	return {}

func reserve(choice: Dictionary, judgement: Dictionary = {}) -> void:
	if choice.is_empty() or batch.get("purpose", "ordinary") == "contract" or not partners.has(choice.get("partner", "")): return
	var p: Dictionary = partners[choice.partner]
	if p.round.is_empty() or p.round.id != choice.get("round_id", "") or not p.round.allowed.has(choice.get("id", "")): return
	if not choice.has("kind") or typeof(choice.kind) != typeof(_kind(choice.id)) or choice.kind != _kind(choice.id) or not _integer(choice.get("family_index"), 0, 1): return
	var family: String = p.round.allowed[choice.id].family
	if _partner(choice.partner).families[int(choice.family_index)] != family or p.round.shipped[family] >= p.round.requirements[family]: return
	var quantity := int(choice.get("quantity", 1))
	if quantity < 1 or quantity > mini(MAX_BATCH_BOTTLES, int(choice.get("max_quantity", 4))) or quantity > int(p.round.requirements[family]) - int(p.round.shipped[family]): return
	var ingredients := {}
	for material in Content.lookup("potions", choice.id).ingredients: ingredients[material] = int(Content.lookup("potions", choice.id).ingredients[material]) * quantity
	batch = {"purpose": "contract", "partner": choice.partner, "round_id": choice.round_id, "kind": choice.kind, "quantity": quantity, "ingredients": ingredients, "duration": float(choice.get("duration", 1.0)), "chance": float(judgement.get("chance", 1.0)), "success": bool(judgement.get("success", true))}
	ordinary_batches = 0
	partner_cursor = (PARTNERS.find(_partner(choice.partner)) + 1) % PARTNERS.size()
	p.family_cursor = (int(choice.family_index) + 1) % 2

func note_ordinary_start() -> void:
	ordinary_batches = ordinary_batches + 1 if ordinary_batches < 4 else 0
	clear_batch()

func clear_batch() -> void:
	batch = {"purpose": "ordinary"}

func complete(state: RefCounted, kind: Variant) -> Dictionary:
	if batch.get("purpose", "ordinary") != "contract" or typeof(batch.kind) != typeof(kind) or batch.kind != kind: return {"ok": false, "error": "납품 배치가 아니에요"}
	var reserved := batch.duplicate(true)
	var p: Dictionary = partners[reserved.partner]
	var id := _id(kind)
	if p.round.is_empty() or p.round.id != reserved.round_id or not p.round.allowed.has(id): return {"ok": false, "error": "납품 회차가 일치하지 않아요"}
	var family: String = p.round.allowed[id].family
	var quantity := int(reserved.get("quantity", 1))
	if not reserved.get("success", true): return {"ok": false, "error": "실패한 납품 배치예요"}
	if quantity < 1 or p.round.shipped[family] + quantity > p.round.requirements[family]: return {"ok": false, "error": "이미 채운 납품 품목이에요"}
	clear_batch() # Consume the reservation before any payment or next-round transition.
	p.round.shipped[family] += quantity
	p.round.shipped_by_kind[id] = int(p.round.shipped_by_kind.get(id, 0)) + quantity
	p.round.base_total += int(p.round.allowed[id].unit) * quantity
	p.totals.shipped += quantity
	totals.shipped += quantity
	var result := {"ok": true, "error": "", "partner": reserved.partner, "kind": kind, "shipped": quantity, "paid": 0, "rounds": 0, "points": 0, "completed_round": "", "next_round": ""}
	for required in p.round.requirements:
		if p.round.shipped[required] < p.round.requirements[required]: return result
	var payout := int(round(int(p.round.base_total) * _multiplier(p.round.terms)))
	var points := _points(p.round.terms)
	p.round.paid = true
	p.round.payout = payout
	p.last_round = p.round.duplicate(true)
	p.points += points
	p.totals.paid += payout
	p.totals.rounds += 1
	totals.paid += payout
	totals.rounds += 1
	totals.points += points
	state.gold += payout
	result.paid = payout
	result.rounds = 1
	result.points = points
	result.completed_round = p.round.id
	_start_round(state, reserved.partner)
	result.next_round = p.round.id
	return result

func to_data() -> Dictionary:
	return {"version": VERSION, "training": training, "seed": seed, "ordinary_batches": ordinary_batches, "partner_cursor": partner_cursor, "batch": batch.duplicate(true), "totals": totals.duplicate(true), "report_paid": report_paid, "partners": partners.duplicate(true)}

func _integer(value: Variant, low: int = 0, high: int = LIMIT) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == int(value) and value >= low and value <= high

func _keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size(): return false
	for key in expected:
		if not value.has(key): return false
	return true

func _valid_terms(value: Variant, rank: int) -> bool:
	return value is Dictionary and _keys(value, ["grade", "option", "version"]) and _integer(value.grade, 1, rank) and value.option is String and OPTIONS.has(value.option) and not (int(value.grade) == 4 and value.option == "relationship") and _integer(value.version, VERSION, VERSION)

func _valid_history(id: String, history: Dictionary, rank: int) -> bool:
	if history.size() > 4: return false
	for key in history:
		if not key is String or key not in ["1", "2", "3", "4"] or int(key) > rank: return false
		var h: Variant = history[key]
		if not h is Dictionary or not _keys(h, ["opportunity", "grade", "version", "tried", "choice", "chance", "training", "success", "accepted", "final"]): return false
		if not _integer(h.grade, int(key), int(key)) or not _integer(h.version, VERSION, VERSION) or h.opportunity != _opportunity(id, int(key)): return false
		for flag in ["tried", "success", "accepted"]:
			if not h[flag] is bool: return false
		if not h.choice is String or not h.final is String or not _integer(h.training, 0, training) or not (h.chance is int or h.chance is float) or not is_finite(float(h.chance)): return false
		if not h.tried and not h.accepted: return false
		if not h.tried:
			if h.choice != "" or h.success or h.training != 0 or h.chance != 0.0 or (h.final != "basic" if h.accepted else h.final != ""): return false
		else:
			if h.choice not in ["payment", "relationship"] or absf(float(h.chance) - chance(int(key), int(h.training))) > 0.0000001 or (int(key) == 4 and (not h.success or h.choice != "payment")): return false
			if h.final != (h.choice if h.success else "basic"): return false
	return true

func _valid_round(id: String, value: Variant, serial: int, p: RefCounted, completed: bool) -> bool:
	if not value is Dictionary or not _keys(value, ["id", "serial", "terms", "requirements", "shipped", "allowed", "shipped_by_kind", "base_total", "paid", "payout", "cauldron_quality", "assistant_quality"]): return false
	if not _integer(value.serial, serial, serial) or value.id != "%s:%d" % [id, serial] or not _valid_terms(value.terms, grade(id)): return false
	var acceptance: Dictionary = partners[id].history.get(str(int(value.terms.grade)), {})
	if not acceptance.get("accepted", false) or acceptance.get("final", "") != value.terms.option: return false
	if not value.paid is bool or value.paid != completed or not _integer(value.base_total) or not _integer(value.payout): return false
	if not value.requirements is Dictionary or not _keys(value.requirements, _partner(id).families) or not value.shipped is Dictionary or not _keys(value.shipped, _partner(id).families): return false
	var expected_requirements := _requirements(id, value.terms)
	for family in expected_requirements:
		if not _integer(value.requirements[family], int(expected_requirements[family]), int(expected_requirements[family])): return false
	for quality in ["cauldron_quality", "assistant_quality"]:
		if not (value[quality] is int or value[quality] is float) or not is_finite(float(value[quality])) or value[quality] < 0 or value[quality] > (0.12 if quality == "cauldron_quality" else 0.07): return false
		var owned_quality: float = p.expansion.effect("cauldron", "quality_sale_bonus") if quality == "cauldron_quality" else p.expansion.effect("brewing_assistant", "new_recipe_quality_bonus")
		if float(value[quality]) > owned_quality + 0.00000001: return false
	if not value.allowed is Dictionary or value.allowed.is_empty() or not value.shipped_by_kind is Dictionary: return false
	var by_family := {}
	for family in _partner(id).families: by_family[family] = 0
	for potion in value.allowed:
		if not potion is String: return false
		var row: Dictionary = {}
		for general in Content.DATA.potions:
			if general.id == potion: row = general
		if row.is_empty() or not _owned(row, p) or not _partner(id).families.has(row.family): return false
		var entry: Variant = value.allowed[potion]
		if not entry is Dictionary or not _keys(entry, ["family", "unit"]) or entry.family != row.family or not _integer(entry.unit, 1): return false
		var price := int(round(int(row.sale_price) * (1.0 + float(value.cauldron_quality) + (float(value.assistant_quality) if not row.existing else 0.0))))
		if entry.unit != price: return false
	if not _missing_family(id, value.allowed).is_empty(): return false
	var base := 0
	for potion in value.shipped_by_kind:
		if not value.allowed.has(potion) or not _integer(value.shipped_by_kind[potion], 1, 96): return false
		by_family[value.allowed[potion].family] += int(value.shipped_by_kind[potion])
		base += int(value.shipped_by_kind[potion]) * int(value.allowed[potion].unit)
	if base != value.base_total: return false
	var full := true
	for family in by_family:
		if not _integer(value.shipped[family], 0, int(value.requirements[family])) or value.shipped[family] != by_family[family]: return false
		full = full and value.shipped[family] == value.requirements[family]
	if completed != full: return false
	return value.payout == (int(round(base * _multiplier(value.terms))) if completed else 0)

func _validate(data: Variant, p: RefCounted, brew_active: bool, active_kind: Variant, expected_batch: Dictionary = {}, legacy: bool = false) -> bool:
	if not data is Dictionary or not _keys(data, ["version", "training", "seed", "ordinary_batches", "partner_cursor", "batch", "totals", "report_paid", "partners"]): return false
	if not _integer(data.version, VERSION, VERSION) or not _integer(data.training, 0, 3) or not _integer(data.seed, 1, 2147483646) or not _integer(data.ordinary_batches, 0, 4) or not _integer(data.partner_cursor, 0, 2): return false
	if not data.totals is Dictionary or not _keys(data.totals, ["shipped", "paid", "rounds", "points"]) or not data.partners is Dictionary or not _keys(data.partners, ["caravan", "academy", "grove"]): return false
	training = int(data.training)
	partners = data.partners.duplicate(true)
	var has_progress := training > 0
	var sums := {"shipped": 0, "paid": 0, "rounds": 0, "points": 0}
	for id in partners:
		var item: Variant = partners[id]
		if not item is Dictionary or not _keys(item, ["points", "family_cursor", "serial", "agreement", "pending", "round", "last_round", "history", "totals"]): return false
		if not _integer(item.points, 0, 1000000000) or not _integer(item.family_cursor, 0, 1) or not _integer(item.serial, 0, 1000000000): return false
		if not item.history is Dictionary or not _valid_history(id, item.history, grade(id)): return false
		has_progress = has_progress or not item.history.is_empty() or item.points > 0
		var highest_accepted := 0
		for record in item.history.values():
			if record.accepted: highest_accepted = maxi(highest_accepted, int(record.grade))
		if not item.totals is Dictionary or not _keys(item.totals, ["shipped", "paid", "rounds"]): return false
		for key in item.totals:
			if not _integer(item.totals[key]): return false
			item.totals[key] = int(item.totals[key])
		for key in ["agreement", "pending", "round", "last_round"]:
			if not item[key] is Dictionary: return false
		if item.agreement.is_empty():
			if highest_accepted != 0 or item.points != 0 or item.serial != 0 or not item.pending.is_empty() or not item.round.is_empty() or not item.last_round.is_empty() or item.totals != {"shipped": 0, "paid": 0, "rounds": 0}: return false
		else:
			if not _valid_terms(item.agreement, grade(id)) or item.serial != item.totals.rounds + 1: return false
			if not _valid_round(id, item.round, int(item.serial), p, false) or item.round.terms != item.agreement: return false
			for terms in [item.agreement, item.pending]:
				if terms.is_empty(): continue
				if not _valid_terms(terms, grade(id)): return false
				var history: Dictionary = item.history.get(str(int(terms.grade)), {})
				if not history.get("accepted", false) or history.get("final", "") != terms.option: return false
			if not item.pending.is_empty() and item.pending.grade <= item.agreement.grade: return false
			if highest_accepted != maxi(int(item.agreement.grade), int(item.pending.get("grade", 0))): return false
			if item.totals.rounds == 0:
				if not item.last_round.is_empty() or item.totals.paid != 0 or item.points != 0: return false
			elif not _valid_round(id, item.last_round, int(item.serial) - 1, p, true): return false
			var current_sent := 0
			for sent in item.round.shipped.values(): current_sent += int(sent)
			if item.totals.shipped < item.totals.rounds * 20 + current_sent or item.totals.shipped > item.totals.rounds * 96 + current_sent: return false
			var completed_sent: int = int(item.totals.shipped) - current_sent
			if item.points < completed_sent or item.points > completed_sent * 2: return false
			if not item.last_round.is_empty() and item.totals.paid < item.last_round.payout: return false
		for key in item.totals: sums[key] += int(item.totals[key])
		sums.points += int(item.points)
		for key in ["points", "serial", "family_cursor"]: item[key] = int(item[key])
	for key in sums:
		if not _integer(data.totals[key]) or data.totals[key] != sums[key]: return false
	if has_progress and not p.expansion.regions.has("star_garden"): return false
	if not _integer(data.report_paid, 0, int(sums.paid)): return false
	if not data.batch is Dictionary or not data.batch.get("purpose") is String: return false
	if data.batch.purpose == "ordinary":
		if not _keys(data.batch, ["purpose"]): return false
	elif data.batch.purpose == "contract":
		if legacy:
			if not _keys(data.batch, ["purpose", "partner", "round_id", "kind"]): return false
			var ingredients := {}
			var row := Content.lookup("potions", _id(active_kind))
			if row.is_empty(): return false
			for material in row.ingredients: ingredients[material] = int(row.ingredients[material])
			data = data.duplicate(true)
			data.batch.merge({"quantity": 1, "ingredients": ingredients, "duration": expected_batch.get("duration", 0.0), "chance": p.batch_chance, "success": p.batch_success})
		if not _keys(data.batch, ["purpose", "partner", "round_id", "kind", "quantity", "ingredients", "duration", "chance", "success"]) or not data.batch.partner is String or not partners.has(data.batch.partner) or not brew_active or typeof(data.batch.kind) != typeof(active_kind) or data.batch.kind != active_kind or int(data.ordinary_batches) != 0: return false
		var round_data: Dictionary = partners[data.batch.partner].round
		var potion := _id(data.batch.kind)
		if round_data.is_empty() or round_data.id != data.batch.round_id or not round_data.allowed.has(potion): return false
		var family: String = round_data.allowed[potion].family
		if not _integer(data.batch.quantity, 1, mini(MAX_BATCH_BOTTLES, int(expected_batch.get("max_quantity", 4)))) or round_data.shipped[family] + data.batch.quantity > round_data.requirements[family]: return false
		var recipe: Dictionary = Content.lookup("potions", potion).ingredients
		if not data.batch.ingredients is Dictionary or not _keys(data.batch.ingredients, recipe.keys()): return false
		for material in recipe:
			if not _integer(data.batch.ingredients[material], int(recipe[material]) * int(data.batch.quantity), int(recipe[material]) * int(data.batch.quantity)): return false
		var ceiling: float = 5.0 * (1.25 if active_kind is bool and active_kind else 1.0 if active_kind is bool else float(Content.RECIPES[active_kind].duration))
		ceiling *= float(expected_batch.get("duration_ceiling_factor", 1.0))
		if not (data.batch.duration is int or data.batch.duration is float) or not is_finite(float(data.batch.duration)) or data.batch.duration < 0.8 or data.batch.duration > ceiling + 0.0000001: return false
		# Upgrades only shorten future batches; an older reserved duration can be
		# longer than today's duration, but cannot have been faster than it.
		if expected_batch.has("duration") and float(data.batch.duration) + 0.0000001 < float(expected_batch.duration): return false
		if not (data.batch.chance is int or data.batch.chance is float) or not is_finite(float(data.batch.chance)) or data.batch.chance < 0 or data.batch.chance > 1 or absf(float(data.batch.chance) - float(expected_batch.get("chance", p.batch_chance))) > 0.0000001: return false
		var maximum_chance := 1.0
		if active_kind is String:
			var environment_cap: float = 0.10 if Content.LEGACY_RECIPES.has(active_kind) else float(Content.lookup("potions", active_kind).environment_bonus)
			maximum_chance = minf(1.0, float(Content.RECIPES[active_kind].success) + environment_cap + p.expansion.effect("precision_filter", "success_bonus", 0.05 if p.filter_owned else 0.0))
		if float(data.batch.chance) > maximum_chance + 0.0000001: return false
		if not data.batch.success is bool or data.batch.success != expected_batch.get("success", p.batch_success): return false
		if data.batch.chance >= 1.0 and not data.batch.success: return false
	else: return false
	seed = int(data.seed)
	ordinary_batches = int(data.ordinary_batches)
	partner_cursor = int(data.partner_cursor)
	batch = data.batch.duplicate(true)
	totals = sums
	report_paid = int(data.report_paid)
	return true

func load_data(data: Variant, progression: RefCounted, brew_active: bool, active_kind: Variant, expected_batch: Dictionary = {}, legacy: bool = false) -> bool:
	var candidate_module = get_script().new()
	if not candidate_module._validate(data, progression, brew_active, active_kind, expected_batch, legacy): return false
	training = candidate_module.training
	seed = candidate_module.seed
	ordinary_batches = candidate_module.ordinary_batches
	partner_cursor = candidate_module.partner_cursor
	batch = candidate_module.batch.duplicate(true)
	totals = candidate_module.totals.duplicate(true)
	report_paid = candidate_module.report_paid
	partners = candidate_module.partners.duplicate(true)
	return true
