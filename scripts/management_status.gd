extends RefCounted
## Read-only projections: never start work, reserve ingredients, pay or award here.
const Content = preload("res://scripts/shop_content.gd")
const Trips = preload("res://scripts/parallel_expeditions.gd")
const ExpeditionRewards = preload("res://scripts/expedition_rewards.gd")
const Rare = preload("res://scripts/rare_recipes.gd")
const CONTRACT_TRAINING_KEY := "contract:train"
const LATE_INVESTMENT_PREFIX := "late:"
const LATE_TRACKS := ["supply_support", "contract_batch"]
const AGING_PREFIX := "aging:"
const KEEPER_PREFIX := "keeper:"
const TRACK_NAMES := {"cauldron": "솥", "herb_pot": "약초 화분", "sales_counter": "판매대", "herb_storage": "약초 보관함", "potion_cabinet": "물약 보관장", "precision_filter": "정밀 여과기", "drying_rack": "약초 건조대", "expedition_path": "원정 길", "family_vitality": "활력 계열", "family_arcane": "비술 계열", "family_nature": "자연 계열", "family_craft": "기교 계열"}
const EFFECTS := {"base_brew_seconds": "제조 %.2f초", "customer_seconds": "거래 %.2f초", "harvest_seconds": "수확 %.2f초", "herb_capacity": "약초 %d", "special_capacity": "특수 재료 %d", "total_potion_capacity": "물약 %d", "harvest_quantity": "수확 %d개", "quality_sale_bonus": "품질 +%.0f%%", "success_bonus": "성공 +%.0f%%p", "preferred_sale_bonus": "선호 +%.0f%%", "preferred_sale_flat": "선호 +%d G", "trip_time_reduction": "원정 시간 %.0f%% 단축", "new_material_growth_multiplier": "재배 ×%.2f", "new_recipe_time_multiplier": "제조 ×%.2f", "new_recipe_quality_bonus": "품질 +%.0f%%"}

static func ratio(amount: float, capacity: float) -> float:
	return clampf(amount / maxf(0.0001, capacity), 0.0, 1.0)

static func kind_id(kind: Variant) -> String:
	return kind if kind is String else ("mana" if kind else "health")

static func known_potion(state: RefCounted, kind: Variant) -> bool:
	var id := kind_id(kind)
	return not Rare.is_special(id) or Rare.is_discovered(id, state.progression)

static func ingredients(state: RefCounted, kind: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if state == null or not known_potion(state, kind): return result
	var source := Content.lookup("potions", kind_id(kind))
	var reserved: bool = state.brew_active and kind_id(state.progression.active_recipe) == kind_id(kind)
	for id in source.get("ingredients", {}):
		var required: int = int(source.ingredients[id])
		var owned: int = state.material_count(id)
		var missing := maxi(0, required - owned)
		result.append({"id": id, "name": Content.lookup("materials", id).name, "required": required, "owned": owned, "missing": 0 if reserved else missing, "next_missing": missing, "reserved": reserved})
	return result

static func potion_priority(state: RefCounted, kind: Variant) -> Dictionary:
	var result := {"higher_id": "", "first_batch": false, "status": ""}
	var id := kind_id(kind)
	if not known_potion(state, kind): return result
	if state.progression.expansion.first_batches.has(id):
		result.first_batch = true
		result.status = "첫 제조 우선 · 자동 제작 대기"
		return result
	# Special recipes alternate with ordinary production; their higher catalog
	# order must never imply they permanently replace an ordinary family.
	if Rare.is_special(id): return result
	var source := Content.lookup("potions", id)
	var legacy: bool = kind is bool or Content.LEGACY_RECIPES.has(id)
	for candidate in state.production_candidates():
		if candidate.is_rare: continue
		if legacy:
			# Basic/legacy selection is the global fallback only when no ordinary
			# expansion family can produce, rather than a same-family contest.
			if candidate.kind is bool or Content.LEGACY_RECIPES.has(candidate.id): continue
			result.higher_id = candidate.id
			result.status = "신규 일반품 우선 · 부족 시 자동 대체"
			return result
		if candidate.family != source.get("family", "") or int(candidate.order) <= int(source.get("order", -1)): continue
		result.higher_id = candidate.id
		result.status = "상위 물약 우선 · 부족 시 자동 대체"
		return result
	return result

static func crafting(state: RefCounted) -> Dictionary:
	return production_current(state)

static func is_contract_batch(state: RefCounted) -> bool:
	var contracts: Variant = state.get("contracts")
	return contracts != null and contracts.batch.get("purpose", "ordinary") == "contract"

static func contract_totals(state: RefCounted) -> Dictionary:
	var contracts: Variant = state.get("contracts")
	return contracts.totals if contracts != null else {}

static func contract_batch_quantity(state: RefCounted) -> int:
	return maxi(1, int(state.contracts.batch.get("quantity", 1))) if state.brew_active and is_contract_batch(state) else 1

static func production_current(state: RefCounted) -> Dictionary:
	# active_recipe is retained after a batch completes or waits. Reading it
	# never chooses the next batch or consumes its ingredients.
	var kind: Variant = state.progression.active_recipe
	var duration: float = state.brew_duration()
	var running: bool = state.is_brewing()
	var contract: bool = state.brew_active and is_contract_batch(state)
	var keeper: Variant = state.get("keeper")
	# Short enough for the 66px workshop caption.
	var status := ("기절" if keeper.state == "fainted" else "수면 중") if keeper != null and keeper.resting() else "납품 제조 중" if contract and running else "보관 가득" if state.stock >= state.capacity() else "제작 중" if running else "재료 부족" if state.waiting_for_herbs() else "제작 대기"
	var known := known_potion(state, kind)
	var contracts: Variant = state.get("contracts")
	var batch: Dictionary = contracts.batch if contracts != null else {}
	return {"icon": kind_id(kind) if known else "", "kind": kind if known else null, "name": Content.potion_name(kind) if known else "특별 물약 · 미발견", "known": known, "elapsed": state.brew_elapsed, "duration": duration, "remaining": state.brew_remaining_seconds(), "progress": ratio(state.brew_elapsed, duration) if state.brew_active else 0.0, "running": running, "status": status, "purpose": "contract" if contract else "ordinary", "quantity": contract_batch_quantity(state), "partner": str(batch.get("partner", "")) if contract else "", "round_id": str(batch.get("round_id", "")) if contract else ""}

static func activity_counts(state: RefCounted) -> Dictionary:
	var herbs := 0
	for source in Content.DATA.materials:
		if source.id == "moon_mushroom": continue
		var data := material(state, source.id)
		if data.supplied and data.running: herbs += 1
	return {"herbs": herbs, "regions": Trips.active_count(state.progression)}

static func purchase_condition(state: RefCounted, key: String) -> String:
	var reason: String = state.purchase_reason(key)
	if reason == "직원 고용 필요":
		reason = str(Content.lookup("employees", key.trim_prefix("upgrade:")).name) + " 고용 필요"
	return condition_text(reason)

static func potion_condition(state: RefCounted, kind: Variant, available: bool, active: bool) -> Dictionary:
	var id := kind_id(kind)
	if not known_potion(state, kind):
		var region: String = Rare.recipe_info(id, state.progression).region
		return {"status": "특별 레시피 미발견", "condition": "%s · 특별 레시피 발견 필요" % Content.lookup("regions", region).name}
	if not available:
		var reason := purchase_condition(state, id)
		return {"status": "레시피 필요", "condition": "레시피 구매 필요 · " + (reason if not reason.is_empty() else "레시피 탭에서 구매 가능")}
	var contract := active and is_contract_batch(state)
	if state.stock >= state.capacity() and not contract: return {"status": "재고 가득", "condition": "물약 보관 공간 필요 · 판매 후 자동 재개" + ("\n현재 배치 재료 예약 완료" if active else "")}
	# The active batch has already paid its ingredients. Do not count them twice.
	var batch := ingredients(state, kind)
	var missing := PackedStringArray()
	for item in batch:
		if item.next_missing > 0: missing.append("%s %d개" % [item.name, item.next_missing])
	if active:
		var quantity := contract_batch_quantity(state)
		var action := "납품용 %d병 자동 제작 중" % quantity if contract and quantity > 1 else "납품용 자동 제작 중" if contract else "자동 제작 중"
		return {"status": "납품 제조 중" if contract else "제작 중", "condition": "재료 예약 완료 · " + action + ("\n다음 병 필요 · " + " · ".join(missing) if not missing.is_empty() else "")}
	if not missing.is_empty(): return {"status": "재료 부족", "condition": "필요 · " + " · ".join(missing)}
	var priority := potion_priority(state, kind)
	if not priority.status.is_empty(): return {"status": priority.status, "condition": "재료 준비 완료 · " + priority.status}
	return {"status": "제작 대기", "condition": "재료 준비 완료 · 자동 제조 순서 대기"}

static func material_condition(state: RefCounted, id: String, data: Dictionary) -> String:
	if data.pending > 0: return ("보관 공간 필요" if data.count >= data.capacity else "자동 입고 대기") + " · 대기 재료 %d개" % data.pending
	if data.count >= data.capacity: return "보관 공간 필요 · 재료 사용 후 자동 재개"
	if id == "moon_mushroom":
		if not state.shop_open: return "영업 재개 필요 · 자동 발주 대기"
		if not state.auto_purchase: return "자동 구매 활성화 필요"
		var quantity: int = mini(state.DELIVERY_QUANTITY, data.capacity - data.count)
		var required: int = state.GOLD_RESERVE + quantity * state.MUSHROOM_COST
		if state.gold < required: return "%d G 부족 · 발주 %d G + 예비금 %d G 필요" % [required - state.gold, quantity * state.MUSHROOM_COST, state.GOLD_RESERVE]
		return "자동 발주 · %d개 / %d G · 예비금 %d G 유지" % [quantity, quantity * state.MUSHROOM_COST, state.GOLD_RESERVE]
	if data.supplied: return "자동 채집 중" if id == "herb" else "자동 재배 중"
	# Inventory received on a trip does not grant an automatic cultivation source.
	for source in Content.DATA.potions:
		if not source.get("grant_sources", []).has(id) and not (id == "starleaf" and Content.LEGACY_RECIPES.has(source.id)): continue
		var reason := purchase_condition(state, source.id)
		return "재배 · %s 레시피 구매 필요\n%s" % [source.name, reason if not reason.is_empty() else "레시피 탭에서 구매 가능"]
	return "원정 조달 필요"

static func material_primary(state: RefCounted, id: String, data: Dictionary) -> String:
	if data.pending > 0: return "재료 보관 대기 · %d개" % data.pending
	if data.count >= data.capacity: return "보관 가득 · 사용 후 재개"
	if id == "moon_mushroom":
		if not state.shop_open: return "영업 재개 필요"
		if not state.auto_purchase: return "자동 구매 활성화 필요"
		var cost: int = mini(state.DELIVERY_QUANTITY, data.capacity - data.count) * state.MUSHROOM_COST
		if state.gold < cost + state.GOLD_RESERVE: return "%d G 부족 · 발주 대기" % (cost + state.GOLD_RESERVE - state.gold)
	if not data.supplied:
		for source in Content.DATA.potions:
			if not source.get("grant_sources", []).has(id) and not (id == "starleaf" and Content.LEGACY_RECIPES.has(source.id)): continue
			var reason := purchase_condition(state, source.id)
			return "재배 · " + reason if not reason.is_empty() else "%s 레시피 · %d G 필요" % [source.name, state.purchase_cost(source.id)]
	var remaining: float = maxf(0.0, data.duration - data.get("display_elapsed", data.elapsed)) / maxf(0.0001, data.rate)
	return "%s · %.1f초 남음" % [data.action, remaining] if data.running else data.status

static func potion_primary(state: RefCounted, kind: Variant, data: Dictionary) -> String:
	if not known_potion(state, kind): return "특별 레시피 · 미발견"
	if not data.available:
		var reason := purchase_condition(state, kind_id(kind))
		return "레시피 · " + reason if not reason.is_empty() else "%d G · 레시피 구매 필요" % state.purchase_cost(kind_id(kind))
	var contract: bool = data.active and is_contract_batch(state)
	if state.stock >= state.capacity() and not contract: return "재고 가득 · 판매 후 재개"
	if data.active: return ("납품 제조 중" if contract else "제작 중") + " · %.1f초 남음" % state.brew_remaining_seconds()
	for item in ingredients(state, kind):
		if item.missing > 0: return "%s %d개 부족" % [item.name, item.missing]
	var priority := potion_priority(state, kind)
	if not priority.status.is_empty(): return priority.status
	return "자동 제조 순서 대기"

static func recommendation_purpose(item: Dictionary, state: RefCounted = null) -> String:
	if item.purchase_key == "workshop": return "판매·납품 동시 제작" if int(item.next_level) == 1 else "납품 제작 시간 줄이기"
	if item.purchase_key == CONTRACT_TRAINING_KEY: return "흥정 성공률 높이기"
	if item.purchase_key == LATE_INVESTMENT_PREFIX + "supply_support": return "부족한 특수 재료 보급"
	if item.purchase_key == LATE_INVESTMENT_PREFIX + "contract_batch": return "납품 한 배치 수량 늘리기"
	if item.purchase_key.begins_with(AGING_PREFIX): return {"open": "넘치는 재고를 비싸게 숙성", "barrels": "숙성통 늘리기", "cellar": "더 오래 숙성해 비싸게 팔기", "shelf": "숙성품 진열 늘리기"}.get(item.purchase_key.trim_prefix(AGING_PREFIX), "숙성 늘리기")
	if item.purchase_key.begins_with(KEEPER_PREFIX): return "수면 회복 늘리기" if item.purchase_key == KEEPER_PREFIX + "bed" else "깨어 있을 때 피로 줄이기"
	if item.kind == "recipe": return "새 물약 해금"
	if item.kind == "region": return "새 원정 재료 조달"
	var key: String = item.purchase_key.get_slice(":", 1)
	if key == "cauldron" and state != null:
		var next: Dictionary = state.next_investment(key)
		if float(next.get("effect", {}).get("base_brew_seconds", state.base_brew_duration())) >= state.base_brew_duration(): return "물약 판매 품질 높이기"
	return {"cauldron": "물약 제조 시간 줄이기", "herb_pot": "약초 채집 늘리기", "sales_counter": "판매 속도 높이기", "herb_storage": "재료 보관 늘리기", "potion_cabinet": "물약 보관 늘리기", "precision_filter": "제조 성공률 높이기", "drying_rack": "특수 약초 재배 빠르게", "expedition_path": "원정 시간 줄이기", "sales_assistant": "선호 판매 수입 늘리기", "brewing_assistant": "새 물약 제조 빠르게", "cultivation_assistant": "특수 약초 재배 빠르게", "expedition_guide": "원정 시간 줄이기"}.get(key, "선호 판매 수입 늘리기" if key.begins_with("family_") else "자동 작업 효율 높이기")

static func lifetime_summary(state: RefCounted) -> Dictionary:
	var p: RefCounted = state.progression
	var seconds := maxi(0, int(p.clock))
	var sales: int = state.total_sales_gold
	var materials_cost: int = state.total_spent_materials
	var fees: int = state.total_spent_expeditions
	var totals := contract_totals(state)
	var paid := int(totals.get("paid", 0))
	var keeper: Variant = state.get("keeper")
	var aging: Variant = state.get("aging")
	var keeper_totals: Dictionary = keeper.totals if keeper != null else {}
	var aging_totals: Dictionary = aging.totals if aging != null else {}
	return {"keeper_sleeps": int(keeper_totals.get("sleeps", 0)), "keeper_faints": int(keeper_totals.get("faints", 0)), "fatigue_failed": int(keeper_totals.get("fatigue_failed", 0)), "aged_sold": int(aging_totals.get("sold", 0)), "aged_revenue": int(aging_totals.get("revenue", 0)), "seconds": seconds, "time": "%d시간 %d분 %d초" % [seconds / 3600, seconds / 60 % 60, seconds % 60], "net": sales + paid - materials_cost - fees, "sales": sales, "materials_cost": materials_cost, "fees": fees, "brewed": int(p.totals.brewed), "sold": int(p.totals.sold), "expeditions": int(p.totals.expeditions), "reputation_gain": int(p.totals.reputation), "contract_paid": paid, "contract_shipped": int(totals.get("shipped", 0)), "contract_rounds": int(totals.get("rounds", 0))}

static func report_summary(state: RefCounted) -> Dictionary:
	var p: RefCounted = state.progression
	var seconds: int = maxi(0, int(p.clock - p.last_report_clock))
	var net: int = state.total_sales_gold - p.report_sales - (state.total_spent_materials - p.report_materials) - (state.total_spent_expeditions - p.report_expeditions)
	var contracts: Variant = state.get("contracts")
	net += int(contract_totals(state).get("paid", 0)) - (int(contracts.report_paid) if contracts != null else 0)
	var materials := []
	for id in p.expansion.reward_totals:
		var count: int = int(p.expansion.reward_totals[id]) - int(p.expansion.report_rewards.get(id, 0))
		if count > 0: materials.append({"id": id, "count": count})
	for addition in [{"id": "herb", "count": int(p.totals.harvested) - int(p.report_baseline.harvested)}, {"id": "moon_mushroom", "count": (state.total_spent_materials - p.report_materials) / state.MUSHROOM_COST}]:
		if addition.count <= 0: continue
		var existing := -1
		for i in materials.size():
			if materials[i].id == addition.id: existing = i
		if existing >= 0: materials[existing].count += int(addition.count)
		else: materials.append({"id": addition.id, "count": int(addition.count)})
	materials.sort_custom(func(a, b): return a.count > b.count if a.count != b.count else a.id < b.id)
	# Supply is an independent actual-receipt ledger, never mixed into the
	# existing top-three expedition/harvest/purchase material summary.
	var supply_materials := []
	var late: Variant = state.get("late_investments")
	var supply_baseline: Dictionary = state.get("report_supply") if state.get("report_supply") is Dictionary else {}
	if late != null:
		for material in Content.DATA.materials:
			var count: int = int(late.totals.get(material.id, 0)) - int(supply_baseline.get(material.id, 0))
			if count > 0: supply_materials.append({"id": material.id, "count": count, "source": "supply"})
	var discoveries := PackedStringArray()
	for source in Content.DATA.potions:
		var condition: Dictionary = source.unlock.get("discovery", {})
		if condition.is_empty(): continue
		if p.expansion.region_returns(condition.region, p) >= int(condition.returns) and int(p.expansion.report_returns.get(condition.region, 0)) < int(condition.returns): discoveries.append(source.name + " 레시피")
	var result := {"period": "%d시간 %d분 %d초" % [seconds / 3600, seconds / 60 % 60, seconds % 60], "net": net, "materials": materials.slice(0, 3), "supply_materials": supply_materials, "discoveries": discoveries}
	# F21: sleeps, faints, fatigue failures and aged sales in this period.
	if state.has_method("report_f21_counts"): result["keeper_aging"] = state.report_f21_counts()
	return result

static func job(elapsed: float, duration: float, running: bool, wait: String, action: String, rate: float = 1.0) -> Dictionary:
	return {"elapsed": elapsed, "duration": duration, "running": running, "progress": ratio(elapsed, duration), "action": action, "status": "%s · %.1f초 남음" % [action, maxf(0.0, duration - elapsed) / maxf(0.0001, rate)] if running else wait}

static func tick_display(data: Dictionary, phase: float, rate: float = 1.0) -> Dictionary:
	# Read subsecond time already accumulated by the simulation. Never finish work here.
	var shown: float = data.elapsed
	if data.running: shown = minf(maxf(0.0, data.duration - 0.000001), shown + clampf(phase, 0.0, 1.0) * rate)
	data["display_elapsed"] = shown
	data["display_progress"] = ratio(shown, data.duration)
	return data

static func material(state: RefCounted, id: String) -> Dictionary:
	var p: RefCounted = state.progression
	var ex: RefCounted = p.expansion
	var source := Content.lookup("materials", id)
	var count: int = state.material_count(id)
	var cap: int = state.herb_capacity() if id == "herb" else (state.MUSHROOM_CAPACITY if id == "moon_mushroom" else ex.special_capacity())
	var available: bool = id in ["herb", "moon_mushroom"] or ex.plants.has(id) or count > 0 or int(ex.pending.get(id, 0)) > 0
	var supplied: bool = ex.plants.has(id)
	var rate := 1.0
	var result: Dictionary
	var favored := false
	if id == "herb":
		supplied = true
		result = job(state.harvest_elapsed, state.harvest_duration(), count < cap, "보관 가득", "채집")
	elif id == "moon_mushroom":
		supplied = true
		var quantity: int = mini(state.DELIVERY_QUANTITY, cap - count)
		var running: bool = count < cap and state.gold >= state.GOLD_RESERVE + quantity * state.MUSHROOM_COST and state.auto_purchase and state.shop_open
		result = job(state.delivery_elapsed, state.DELIVERY_INTERVAL, running, "보관 가득" if count >= cap else "영업 대기" if not state.shop_open else "자동 구매 꺼짐" if not state.auto_purchase else "골드 부족", "구매")
	elif id == "starleaf":
		supplied = p.owned.any(func(recipe): return Content.LEGACY_RECIPES.has(recipe) or Content.lookup("potions", recipe).get("grant_sources", []).has("starleaf"))
		available = available or supplied
		rate = p.growth_rate()
		favored = supplied and rate > 1.0
		result = job(p.rare_growth, 12.0, supplied and count < cap, "보관 가득" if count >= cap else "재배 조건 필요", "재배", rate)
	else:
		favored = supplied and ex.favored(source.get("environment", "none"), p)
		rate = (float(source.get("favored_growth_multiplier", 1.5)) if favored else 1.0) * ex.effect("drying_rack", "new_material_growth_multiplier", 1.0) * ex.effect("cultivation_assistant", "new_material_growth_multiplier", 1.0)
		result = job(float(ex.growth.get(id, 0.0)), float(source.get("growth_seconds", 1.0)), supplied and count < cap, "보관 가득" if count >= cap else ("원정 조달" if available else "재배 조건 필요"), "재배", rate)
	result.merge({"count": count, "capacity": cap, "inventory": ratio(count, cap), "available": available, "supplied": supplied, "favored": favored, "pending": int(ex.pending.get(id, 0)), "rate": rate, "name": source["name"], "icon": id})
	result["condition"] = material_condition(state, id, result)
	return tick_display(result, p.tick_elapsed, rate) if id not in ["herb", "moon_mushroom"] else result

static func potion(state: RefCounted, kind: Variant) -> Dictionary:
	var p: RefCounted = state.progression
	var id := kind_id(kind)
	if not known_potion(state, kind):
		var hidden := {"name": "특별 물약 · 미발견", "known": false, "count": 0, "capacity": state.capacity(), "inventory": 0.0, "available": false, "active": false, "work": {}, "favored": false, "chance": 0.0, "icon": "", "ingredients": [], "priority": {"higher_id": "", "first_batch": false, "status": ""}}
		hidden.merge(potion_condition(state, kind, false, false))
		return hidden
	# Count directly, without inventory_order()'s legacy repair side effect.
	var count: int = state.inventory.count(kind) if state.inventory.size() == state.stock else (state.mana_stock if kind is bool and kind else state.stock - state.mana_stock if kind is bool else 0)
	var active: bool = state.brew_active and typeof(kind) == typeof(p.active_recipe) and kind == p.active_recipe
	var available: bool = kind is bool or p.owned.has(kind)
	var result := {"name": Content.lookup("potions", id)["name"], "known": true, "count": count, "capacity": state.capacity(), "inventory": ratio(count, state.capacity()), "available": available, "active": active, "work": job(state.brew_elapsed, state.brew_duration(), active and state.is_brewing(), "재고 가득" if state.stock >= state.capacity() else "", "제조") if active else {}, "favored": p.environment_bonus(kind) > 0.0001, "chance": p.batch_chance if active else p.success_chance(kind), "icon": id, "ingredients": ingredients(state, kind), "priority": potion_priority(state, kind)}
	result.merge(potion_condition(state, kind, available, active))
	return result

static func region(state: RefCounted, id: String) -> Dictionary:
	var p: RefCounted = state.progression
	var source := Content.lookup("regions", id)
	var cycle: Dictionary = p.expansion.cycles.get(id, {})
	var status := region_status(state, id)
	var result := job(float(cycle.get("elapsed", 0.0)), float(cycle.get("duration", float(source["explore_seconds"]) + float(source["return_seconds"]))), cycle.get("running", false), status, status.trim_suffix(" 중"))
	result.merge({"available": Trips.opened(id, p), "name": source["name"], "icon": id, "returns": p.expansion.region_returns(id, p), "max_returns": int(source["complete_returns"]), "fee": int(source["departure_cost"]), "cost": int(source["cost"]), "mode": str(cycle.get("mode", "normal")) if cycle.get("running", false) else "normal", "next_mode": Trips.departure_mode(id, p), "timing": expedition_timing(state, id)})
	return tick_display(result, p.tick_elapsed)

static func expedition_timing(state: RefCounted, id: String) -> Dictionary:
	var source := Content.lookup("regions", id)
	if source.is_empty(): return {}
	var ex: RefCounted = state.progression.expansion
	var cycle: Dictionary = ex.cycles.get(id, {})
	var base: float = float(source.explore_seconds) + float(source.return_seconds)
	var path: float = ex.effect("expedition_path", "trip_time_reduction")
	var guide: float = ex.effect("expedition_guide", "trip_time_reduction")
	var total := minf(0.3, path + guide)
	var next := base * (1.0 - total)
	var running: bool = cycle.get("running", false)
	var current: float = float(cycle.get("duration", 0.0)) if running else 0.0
	var text := "기본 %.1f초 · 다음 출발 %.1f초\n원정 길 %.0f%% + 길잡이 %.0f%% · 합산 %.0f%% (상한 30%%)" % [base, next, path * 100, guide * 100, total * 100]
	if running: text += "\n현재 회차 %.1f초 · 출발 시 소요 시간 유지" % current
	return {"base": base, "next": next, "current": current, "path": path, "guide": guide, "total": total, "running": running, "text": text}

static func effect_value(state: RefCounted, track: String, key: String) -> float:
	if key == "customer_seconds": return state.customer_interval()
	var defaults := {"base_brew_seconds": state.base_brew_duration(), "harvest_seconds": state.harvest_duration(), "herb_capacity": state.herb_capacity(), "total_potion_capacity": state.capacity(), "special_capacity": state.progression.expansion.special_capacity(), "harvest_quantity": 2.0, "new_material_growth_multiplier": 1.0, "new_recipe_time_multiplier": 1.0, "preferred_sale_flat": 2.0 if state.progression.employee else 0.0, "success_bonus": 0.05 if state.progression.filter_owned else 0.0}
	return state.progression.expansion.effect(track, key, float(defaults.get(key, 0.0)))

static func track_effects(state: RefCounted, track: String) -> Dictionary:
	# A later stage can change only quality while earlier timing still applies.
	# Values are final replacements, never summed across stages.
	var effects := {}
	var employee := Content.lookup("employees", track)
	for key in employee.get("effect", {}): effects[key] = effect_value(state, track, key)
	for row in Content.track_rows(track):
		for key in row.effect: effects[key] = effect_value(state, track, key)
	return effects

static func effects_text(effects: Dictionary) -> String:
	var parts := PackedStringArray()
	for key in effects:
		if not EFFECTS.has(key): continue
		var value: float = float(effects[key])
		if key in ["quality_sale_bonus", "success_bonus", "preferred_sale_bonus", "trip_time_reduction", "new_recipe_quality_bonus"]: value *= 100.0
		parts.append(EFFECTS[key] % value)
	return " · ".join(parts)

static func investment(state: RefCounted, track: String) -> Dictionary:
	var current: int = state.track_level(track)
	var entries := Content.track_rows(track)
	var maximum: int = int(entries[-1]["stage"])
	var next: Dictionary = state.next_investment(track)
	var reason: String = state.expansion_purchase_reason("upgrade:" + track)
	var target: String = {"cauldron": "cauldron", "herb_pot": "garden", "sales_counter": "sales_counter", "precision_filter": "filter"}.get(track, "growth:" + track)
	var title: String = TRACK_NAMES.get(track, str(Content.lookup("employees", track).get("name", track)) + " 훈련")
	var before := {}
	for key in next.get("effect", {}): before[key] = effect_value(state, track, key)
	var current_effects := track_effects(state, track)
	var text := "현재 효과 · " + effects_text(current_effects) if next.is_empty() else effects_text(before) + " → " + effects_text(next["effect"])
	if track == "sales_counter" and not next.is_empty(): text = "거래 %.2f → %.2f초" % [state.customer_interval(), Content.SALES_COUNTER_SECONDS[current + 1]]
	return {"target": target, "track": track, "name": title, "level": current, "maximum": maximum, "progress": ratio(current, maximum), "cost": int(next.get("cost", 0)), "reason": reason, "effect": text, "current_effects": current_effects, "maxed": current >= maximum, "available": current > 0 or reason.is_empty() or reason.ends_with(" G 부족"), "preview_effect": text if track == "sales_counter" or next.is_empty() else effects_text({next["effect"].keys()[0]: before[next["effect"].keys()[0]]}) + " → " + effects_text({next["effect"].keys()[0]: next["effect"][next["effect"].keys()[0]]})}

static func growth_candidates(state: RefCounted) -> Array[Dictionary]:
	var choices: Array[Dictionary] = []
	var tracks := []
	for entry in Content.DATA.upgrades:
		if tracks.has(entry.track): continue
		tracks.append(entry.track)
		var item := investment(state, entry.track)
		if not item.reason.is_empty() or item.maxed: continue
		var training: bool = entry.get("kind", "") == "training"
		item.merge({"purchase_key": "upgrade:" + entry.track, "next_level": int(item.level) + 1, "kind": "training" if training else "upgrade", "action": "훈련" if training else "강화", "why": "자동 운영의 효율을 높여요", "score": 70 if training else 40})
		if entry.track in ["cauldron", "herb_pot"] and item.level < 1: item.score = 110
		var bottleneck: bool = (state.stock >= state.capacity() * 0.75 and entry.track in ["sales_counter", "potion_cabinet"]) or (state.waiting_for_herbs() and entry.track == "herb_pot") or (state.customer_waiting and entry.track == "cauldron")
		if bottleneck: item.score = 120 if item.level < 2 else 80
		choices.append(item)
	for region in Content.DATA.regions:
		var key: String = "expedition" if region.id == "forest_edge" else "region:" + region.id
		if not state.purchase_reason(key).is_empty(): continue
		var rewards := PackedStringArray()
		for entry in ExpeditionRewards.preview(region.id): rewards.append(Content.lookup("materials", entry.id).name)
		var effect := "재료 " + "·".join(rewards) + " · 매회 %d G" % int(region.departure_cost)
		choices.append({"purchase_key": key, "kind": "region", "action": "원정 열기", "target": region.id, "name": region.name, "cost": state.purchase_cost(key), "effect": effect, "preview_effect": effect, "why": "새 재료를 자동으로 조달해요", "score": 100})
	for employee in Content.DATA.employees:
		var key: String = "staff:" + employee.id
		if not state.purchase_reason(key).is_empty(): continue
		var effect := effects_text(employee.effect)
		choices.append({"purchase_key": key, "kind": "staff", "action": "고용", "target": employee.id, "name": employee.name, "cost": state.purchase_cost(key), "effect": effect, "preview_effect": effect, "why": "직원이 자동 운영을 도와요", "score": 95})
	for id in Content.RECIPES:
		if not known_potion(state, id): continue
		if not state.purchase_reason(id).is_empty(): continue
		var item: Dictionary = Content.RECIPES[id]
		var effect := "자동 제작 합류 · 판매 %d G" % int(item.price)
		choices.append({"purchase_key": id, "kind": "recipe", "action": "레시피 구매", "target": id, "name": item.name, "cost": state.purchase_cost(id), "effect": effect, "preview_effect": effect, "why": "구매 후 재료가 준비되면 자동으로 만들어요", "score": 90})
	# Contract training has its own transaction/save path, outside Content upgrades.
	var contracts: Variant = state.get("contracts")
	if contracts != null:
		var training: Dictionary = contracts.training_view(state)
		if training.can_buy:
			var effect := "일반 흥정 %.0f%% → %.0f%%" % [float(training.chance) * 100.0, float(training.next_chance) * 100.0]
			choices.append({"purchase_key": CONTRACT_TRAINING_KEY, "next_level": int(training.get("next_level", int(training.level) + 1)), "kind": "training", "action": "훈련", "target": "contract_training", "name": "흥정 훈련", "cost": int(training.cost), "effect": effect, "preview_effect": effect, "why": "아직 시도하지 않은 흥정의 성공률을 높여요", "score": 70})
	var late: Variant = state.get("late_investments")
	if late != null:
		for track in LATE_TRACKS:
			var item := late_investment(state, track)
			if not item.can_buy: continue
			item.merge({"purchase_key": LATE_INVESTMENT_PREFIX + track, "kind": "late", "action": "투자", "target": LATE_INVESTMENT_PREFIX + track, "why": "부족한 특수 재료를 자동으로 보급해요" if track == "supply_support" else "같은 납품 배치에서 실제 병수를 늘려요", "score": 65 if track == "supply_support" else 60, "effect": item.effect_text, "preview_effect": item.effect_text})
			choices.append(item)
	var workshop: Dictionary = state.workshop.view(state)
	if workshop.can_buy:
		choices.append({"purchase_key": "workshop", "next_level": workshop.next_level, "kind": "late", "action": "확장" if workshop.level == 0 else "개선", "target": "workshop_%d" % workshop.next_level, "name": workshop.name, "cost": workshop.cost, "effect": workshop.next_effect, "preview_effect": workshop.next_effect, "why": "판매와 납품의 동시 제작", "score": 66})
	# F21 investments have their own save-safe purchase paths, like the workshop.
	# Aging ranks just below the existing late investments so their order is unchanged.
	var aging: Variant = state.get("aging")
	if aging != null:
		for track in aging.TRACKS:
			var item: Dictionary = aging.view(state, track)
			if not item.can_buy: continue
			choices.append({"purchase_key": AGING_PREFIX + track, "next_level": int(item.next_level), "kind": "aging", "action": "투자", "target": "aging_" + track, "name": item.name, "cost": int(item.cost), "effect": item.next_effect, "preview_effect": item.next_effect, "why": "넘치는 판매 재고를 오래 걸리지만 비싼 숙성 물약으로 바꿔요", "score": 59 if track == "open" else 57})
	var keeper: Variant = state.get("keeper")
	if keeper != null and keeper_upgrade_useful(state):
		for track in keeper.upgrades.TRACKS:
			var item: Dictionary = keeper.upgrades.view(state, track)
			if not item.can_buy: continue
			var effect := str(item.current_effect) + " → " + str(item.next_effect)
			choices.append({"purchase_key": KEEPER_PREFIX + track, "next_level": int(item.next_level), "kind": "keeper", "action": "투자", "target": "keeper_" + track, "name": item.name, "cost": int(item.cost), "effect": effect, "preview_effect": effect, "why": "%s 근무에서도 피로가 쌓이지 않게 해요" % keeper.POLICIES[keeper.policy].name, "score": 68})
	return choices

## Bed/tea only pay off when the chosen policy still accumulates fatigue or loses
## the rested bonus; a regular sleeper already recovers fully every night.
static func keeper_upgrade_useful(state: RefCounted) -> bool:
	var keeper: RefCounted = state.keeper
	return keeper.policy != "regular" and not bool(keeper.daily(keeper.policy).fresh)

static func late_investment(state: RefCounted, track: String) -> Dictionary:
	var late: Variant = state.get("late_investments")
	if late == null: return {}
	var item: Dictionary = late.view(state, track).duplicate(true)
	item["effect_text"] = "현재 효과 · " + str(item.current_effect) if int(item.level) >= int(item.max_level) else str(item.current_effect) + " → " + str(item.next_effect)
	return item

static func supply_support(state: RefCounted) -> Dictionary:
	var late: Variant = state.get("late_investments")
	if late == null: return {"purchased": false}
	return late.supply_view(state)

static func recommendation(state: RefCounted) -> Dictionary:
	var selected := {}
	for item in growth_candidates(state):
		if selected.is_empty() or item.score > selected.score: selected = item
	return selected

static func condition_text(reason: String) -> String:
	if reason.contains("귀환"):
		return reason.replace("귀환 ", "원정 ").replace("회 필요", "회 완료 필요")
	return reason.replace("조사 필요", "조사 완료 필요").replace("개방 완료", "열림")

static func region_requirements(id: String) -> String:
	var source := Content.lookup("regions", id)
	var text := "조건 · 명성 %d" % int(source.reputation)
	if source.previous_region != null: text += " · " + str(Content.lookup("regions", source.previous_region).name) + " 조사 완료"
	return text

static func region_preview(state: RefCounted, id: String) -> Array:
	var items := ExpeditionRewards.preview(id)
	for source in Content.DATA.potions:
		var discovery: Dictionary = source.unlock.get("discovery", {})
		if discovery.get("region", "") != id: continue
		items.append({"id": source.id, "kind": "recipe", "name": source.name + " 레시피", "status": "구매 완료" if state.progression.owned.has(source.id) else "조사 %d회 완료 시 해금" % int(discovery.returns)})
	# Optional recipes use Rare.preview's shared discovery mask. Keep the
	# ordinary recipe/material preview free of unrevealed names and artwork.
	return items

static func region_status(state: RefCounted, id: String) -> String:
	var p: RefCounted = state.progression
	if not Trips.opened(id, p): return "잠김"
	var cycle: Dictionary = p.expansion.cycles.get(id, {})
	if cycle.get("running", false) and cycle.get("mode", "normal") == "special": return "특별 탐색 중"
	var status := Trips.status(id, p)
	if status in ["탐색 중", "귀환 중"]: return status.replace("귀환 중", "재료 가져오는 중")
	if Trips.departure_mode(id, p) == "special":
		return "출발비 부족" if state.gold < int(_region_departure_budget(state, id).total) else "특별 탐색 대기"
	var related: Array = ExpeditionRewards.preview(id)
	for entry in related:
		var material: String = entry.id
		if int(p.expansion.pending.get(material, 0)) > 0: return "재료 보관 대기"
	return status.replace("보관 공간 대기", "보관 가득 · 출발 대기").replace("재료 충분 · 자동 대기", "재료 충분 · 출발 대기").replace("출발비 부족 · 자동 대기", "출발비 부족")

static func region_card_conditions(state: RefCounted, id: String) -> String:
	# This is presentation only: no cycle creation, departure or reward roll.
	var source := Content.lookup("regions", id)
	if source.is_empty(): return ""
	var p: RefCounted = state.progression
	var goal := int(source.complete_returns)
	var count := int(p.expansion.region_returns(id, p))
	var lines := PackedStringArray(["조사 완료" if count >= goal else "조사 %d/%d회" % [mini(count, goal), goal]])
	if not Trips.opened(id, p):
		var key := "expedition" if id == "forest_edge" else "region:" + id
		var cost := int(state.purchase_cost(key))
		var reputation := Content.EXPEDITION_REPUTATION if id == "forest_edge" else int(source.reputation)
		if source.previous_region != null:
			var previous := Content.lookup("regions", str(source.previous_region))
			var previous_count := int(p.expansion.region_returns(str(previous.id), p))
			var previous_goal := int(previous.complete_returns)
			if previous_count < previous_goal:
				lines.append("%s 조사 %d/%d회 필요" % [previous.name, previous_count, previous_goal])
		if p.reputation < reputation:
			lines.append("명성 %d 필요 · 현재 %d" % [reputation, p.reputation])
		if state.gold < cost:
			lines.append("원정 열기 %d G 필요 · 현재 %d G · %d G 부족" % [cost, state.gold, cost - state.gold])
		if lines.size() == 1: lines.append("원정 열기 가능 · %d G" % cost)
		return "\n".join(lines)
	if p.expansion.cycles.get(id, {}).get("running", false): return "\n".join(lines)
	var waiting := region_status(state, id)
	if waiting != "출발비 부족":
		lines.append(waiting)
		if waiting == "재료 보관 대기": lines.append("완료 보상은 보관 공간이 생기면 자동 입고해요")
		return "\n".join(lines)
	var budget := _region_departure_budget(state, id)
	if state.gold >= int(budget.total):
		lines.append("다음 출발 대기 · 현재 출발 조건 충족")
	else:
		lines.append("출발비 부족 · 출발에 필요한 골드 %d G" % int(budget.total))
		lines.append("현재 %d G · %d G 부족" % [state.gold, int(budget.total) - state.gold])
		lines.append("매회 %d G + 예비금 %d G" % [budget.fee, state.GOLD_RESERVE])
		if budget.protected_fee > 0: lines.append("다른 원정에 남겨둘 비용 %d G" % int(budget.protected_fee))
		if budget.prior_spent > 0: lines.append("먼저 출발하는 원정 비용 %d G" % int(budget.prior_spent))
	return "\n".join(lines)

static func _region_departure_budget(state: RefCounted, target: String) -> Dictionary:
	# Mirror only the current candidate priority and affordability arithmetic.
	# UI must not call Trips.ensure/candidates/tick or touch reserved rewards.
	var p: RefCounted = state.progression
	var candidates: Array[Dictionary] = []
	for source in Content.DATA.regions:
		if not Trips.departure_mode(source.id, p).is_empty():
			candidates.append(source)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary):
		var complete_a: bool = p.expansion.region_returns(a.id, p) >= int(a.complete_returns)
		var complete_b: bool = p.expansion.region_returns(b.id, p) >= int(b.complete_returns)
		if complete_a != complete_b: return not complete_a
		var wait_a: float = float(p.expansion.cycles.get(a.id, {}).get("wait_since", p.clock))
		var wait_b: float = float(p.expansion.cycles.get(b.id, {}).get("wait_since", p.clock))
		return wait_a < wait_b if wait_a != wait_b else Content.DATA.regions.find(a) < Content.DATA.regions.find(b))
	var remaining: int = state.gold
	var prior_spent := 0
	var protect := 0
	for source in candidates:
		var fee := int(source.departure_cost)
		var completed: bool = p.expansion.region_returns(source.id, p) >= int(source.complete_returns)
		var protected_fee := protect if completed else 0
		var reserve: int = state.GOLD_RESERVE + protected_fee
		if source.id == target:
			return {"fee": fee, "protected_fee": protected_fee, "prior_spent": prior_spent, "total": prior_spent + fee + reserve}
		if remaining - fee < reserve:
			if not completed and protect == 0: protect = fee
		else:
			remaining -= fee
			prior_spent += fee
	var source := Content.lookup("regions", target)
	return {"fee": int(source.departure_cost), "protected_fee": 0, "prior_spent": 0, "total": int(source.departure_cost) + state.GOLD_RESERVE}
