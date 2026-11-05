extends RefCounted
## F19 provisional balance. Existing growth gates never include these two tracks.
const Content = preload("res://scripts/shop_content.gd")
const VERSION := 1
const TRACKS := ["supply_support", "contract_batch"]
const NAMES := {"supply_support": "보급 지원", "contract_batch": "납품 일괄 조제"}
const COSTS := [150000, 300000, 450000]
const SUPPLY_SECONDS := 60.0
const SUPPLY_QUANTITIES := [0, 7, 12, 24]
const SPECIAL_IDS := ["starleaf", "dewgrass", "silver_moss", "blue_reed", "crystal_herb", "mist_mushroom", "ash_sage", "moonflower", "star_seed"]
const EXISTING_STAGES := {"cauldron": 20, "herb_pot": 15, "sales_counter": 10, "potion_cabinet": 8, "herb_storage": 10, "drying_rack": 8, "expedition_path": 8, "precision_filter": 6, "family_vitality": 5, "family_arcane": 5, "family_nature": 5, "family_craft": 5, "sales_assistant": 5, "cultivation_assistant": 5, "brewing_assistant": 5, "expedition_guide": 5}
const EXISTING_EMPLOYEES := ["sales_assistant", "cultivation_assistant", "brewing_assistant", "expedition_guide"]
var stages := {"supply_support": 0, "contract_batch": 0}
var supply := {}
var totals := {}

func growth_view(state: RefCounted) -> Dictionary:
	var p: RefCounted = state.progression
	var missing: Array[String] = []
	var owned := 0
	for row in Content.DATA.potions:
		# F26/F27 post-growth rows (content_set) never stand in for an original recipe.
		if row.has("content_set"): continue
		if row.id in ["health", "mana"] or p.owned.has(row.id): owned += 1
	if owned < 32: missing.append("일반 레시피 32종 보유 필요 · %d/32" % owned)
	var regions: int = p.completed_regions()
	if regions < 8: missing.append("원정 8곳 일반 조사 완료 필요 · %d/8" % regions)
	var employees := 0
	for id in EXISTING_EMPLOYEES:
		if p.expansion.staff.has(id) or (id == "sales_assistant" and p.employee): employees += 1
	if employees < 4: missing.append("기존 직원 4명 고용 필요 · %d/4" % employees)
	var completed_tracks := 0
	for track in EXISTING_STAGES:
		var actual: int = state.track_level(track)
		if actual >= int(EXISTING_STAGES[track]): completed_tracks += 1
		else:
			var rows: Array = Content.track_rows(track)
			var name: String = rows[0].name if not rows.is_empty() else track
			missing.append("%s %d단계 필요 · 현재 %d단계" % [name, int(EXISTING_STAGES[track]), actual])
	return {"complete": missing.is_empty(), "missing": missing, "recipes": owned, "regions": regions, "employees": employees, "tracks": completed_tracks}

func highest_grade(state: RefCounted) -> int:
	var highest := 1
	for partner in state.contracts.PARTNERS: highest = maxi(highest, state.contracts.grade(partner.id))
	return highest

func batch_max() -> int:
	return int(stages.contract_batch) + 1

func view(state: RefCounted, track: String) -> Dictionary:
	if not TRACKS.has(track): return {"exists": false, "can_buy": false, "reason": "알 수 없는 후반 투자"}
	var level := int(stages[track])
	var next_level := level + 1 if level < 3 else 0
	var cost: int = COSTS[level] if level < 3 else 0
	var growth := growth_view(state)
	var grade_now := highest_grade(state)
	var required_grade := mini(4, level + 2)
	var missing: Array[String] = []
	missing.assign(growth.missing)
	if grade_now < required_grade: missing.append("거래%d등급 필요 · 현재 최고 %d등급" % [required_grade, grade_now])
	if level < 3 and state.gold < cost: missing.append("%d G 부족" % (cost - state.gold))
	var reason := "최대 단계" if level == 3 else "가게 성장 완료 필요" if not growth.complete else "거래%d등급 필요" % required_grade if grade_now < required_grade else "%d G 부족" % (cost - state.gold) if state.gold < cost else ""
	var current_quantity := int(SUPPLY_QUANTITIES[level]) if track == "supply_support" else level + 1
	var next_quantity := int(SUPPLY_QUANTITIES[mini(3, level + 1)]) if track == "supply_support" else mini(4, level + 2)
	var current_effect := "미구매" if track == "supply_support" and level == 0 else "60초마다 최대 %d개" % current_quantity if track == "supply_support" else "한 번에 최대 %d병" % current_quantity
	var next_effect := "60초마다 최대 %d개" % next_quantity if track == "supply_support" else "한 번에 최대 %d병" % next_quantity
	return {"exists": true, "id": track, "name": NAMES[track], "level": level, "max_level": 3, "next_level": next_level, "cost": cost, "can_buy": reason.is_empty(), "reason": reason, "missing": missing, "growth_complete": growth.complete, "highest_grade": grade_now, "required_grade": required_grade, "current_effect": current_effect, "next_effect": next_effect, "current_quantity": current_quantity, "next_quantity": next_quantity, "max_bottles": batch_max(), "expected_stage": next_level}

func purchase(state: RefCounted, track: String, expected_next_level: int) -> Dictionary:
	if not TRACKS.has(track): return {"ok": false, "error": "알 수 없는 후반 투자"}
	if expected_next_level != int(stages[track]) + 1 or expected_next_level > 3:
		return {"ok": false, "error": "이전 단계 필요" if expected_next_level > int(stages[track]) + 1 else "투자 단계가 변경되었어요"}
	var item := view(state, track)
	if not item.can_buy: return {"ok": false, "error": item.reason}
	state.gold -= int(item.cost)
	state.progression.totals.manual_spent += int(item.cost)
	stages[track] = expected_next_level
	if track == "supply_support" and supply.is_empty():
		supply = {"elapsed": 0.0, "duration": SUPPLY_SECONDS, "quantity": int(SUPPLY_QUANTITIES[expected_next_level])}
	return {"ok": true, "error": "", "track": track, "level": expected_next_level, "cost": item.cost}

func supply_candidates(state: RefCounted) -> Array[String]:
	var used := {}
	var p: RefCounted = state.progression
	var recipes: Array = Content.DATA.potions.duplicate()
	recipes.append_array(Content.RARE_ROWS)
	for recipe in recipes:
		if recipe.id not in ["health", "mana"] and not p.owned.has(recipe.id): continue
		if Content.Rare.is_special(recipe.id) and not Content.Rare.is_owned(recipe.id, p): continue
		for material in recipe.ingredients:
			if SPECIAL_IDS.has(material): used[material] = true
	var result: Array[String] = []
	# Catalog order is the deterministic tie break; no separate random stream.
	for row in Content.DATA.materials:
		if not used.has(row.id): continue
		var source_open: bool = p.expansion.plants.has(row.id)
		if row.id == "starleaf":
			for recipe in p.owned:
				if Content.LEGACY_RECIPES.has(recipe) or Content.lookup("potions", recipe).get("grant_sources", []).has("starleaf"): source_open = true
		if source_open: result.append(row.id)
	return result

func _target(state: RefCounted) -> String:
	var chosen := ""
	var fraction := INF
	for material in supply_candidates(state):
		var count: int = state.material_count(material)
		var cap: int = state.progression.expansion.special_capacity()
		if count >= cap: continue
		var actual := float(count) / cap
		if actual < fraction:
			fraction = actual
			chosen = material
	return chosen

func supply_view(state: RefCounted) -> Dictionary:
	var purchased := int(stages.supply_support) > 0
	var candidates: Array[String] = []
	if purchased: candidates = supply_candidates(state)
	var target := _target(state) if purchased else ""
	var elapsed: float = float(supply.get("elapsed", 0.0))
	var duration: float = float(supply.get("duration", SUPPLY_SECONDS))
	var amount := 0
	for count in totals.values(): amount += int(count)
	var status := "미구매" if not purchased else "대상 없음" if candidates.is_empty() else "보관 가득" if target.is_empty() else "보급 중 · %d초" % int(ceil(maxf(0.0, duration - elapsed)))
	return {"purchased": purchased, "level": int(stages.supply_support), "running": purchased, "elapsed": elapsed, "duration": duration, "reserved_quantity": int(supply.get("quantity", 0)), "progress": clampf(elapsed / duration, 0.0, 1.0), "status": status, "total_received": amount, "totals": totals.duplicate(), "target": target, "candidates": candidates}

func supply_tick(seconds: float) -> void:
	if supply.is_empty() or not is_finite(seconds) or seconds <= 0.0: return
	# State.advance chooses this boundary before stepping, then calls boundary
	# after existing arrivals. Do not wrap or grant inside this clock operation.
	supply.elapsed = minf(float(supply.duration), float(supply.elapsed) + seconds)

func supply_boundary(state: RefCounted) -> Dictionary:
	if supply.is_empty() or float(supply.elapsed) + 0.000001 < float(supply.duration): return {}
	var reserved := int(supply.quantity)
	var material := _target(state)
	var added := 0
	if not material.is_empty():
		added = mini(reserved, maxi(0, state.progression.expansion.special_capacity() - state.material_count(material)))
		if material == "starleaf": state.progression.rare_herbs += added
		else: state.progression.expansion.materials[material] = state.material_count(material) + added
		if added > 0: totals[material] = int(totals.get(material, 0)) + added
	supply = {"elapsed": 0.0, "duration": SUPPLY_SECONDS, "quantity": int(SUPPLY_QUANTITIES[int(stages.supply_support)])}
	return {"material": material, "quantity": added, "reserved_quantity": reserved}

func to_data() -> Dictionary:
	return {"version": VERSION, "stages": stages.duplicate(), "supply": supply.duplicate(), "totals": totals.duplicate()}

func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == int(value) and value >= low and value <= high

func _keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size(): return false
	for key in expected:
		if not value.has(key): return false
	return true

func load_data(data: Variant, validation_state: RefCounted = null) -> bool:
	if not data is Dictionary or not _keys(data, ["version", "stages", "supply", "totals"]) or not _integer(data.version, VERSION, VERSION): return false
	if not data.stages is Dictionary or not _keys(data.stages, TRACKS) or not data.supply is Dictionary or not data.totals is Dictionary: return false
	var copied_stages := {}
	var purchased := false
	for track in TRACKS:
		if not _integer(data.stages[track], 0, 3): return false
		copied_stages[track] = int(data.stages[track])
		purchased = purchased or int(data.stages[track]) > 0
		if validation_state != null and int(data.stages[track]) > 0 and highest_grade(validation_state) < int(data.stages[track]) + 1: return false
	if validation_state != null and purchased and not growth_view(validation_state).complete: return false
	var copied_supply := {}
	if int(copied_stages.supply_support) == 0:
		if not data.supply.is_empty() or not data.totals.is_empty(): return false
	else:
		if not _keys(data.supply, ["elapsed", "duration", "quantity"]): return false
		if not (data.supply.elapsed is int or data.supply.elapsed is float) or not is_finite(float(data.supply.elapsed)) or data.supply.elapsed < 0 or data.supply.elapsed > SUPPLY_SECONDS: return false
		if not (data.supply.duration is int or data.supply.duration is float) or float(data.supply.duration) != SUPPLY_SECONDS: return false
		if not _integer(data.supply.quantity, 1, int(SUPPLY_QUANTITIES[int(copied_stages.supply_support)])) or not SUPPLY_QUANTITIES.has(int(data.supply.quantity)): return false
		copied_supply = {"elapsed": float(data.supply.elapsed), "duration": SUPPLY_SECONDS, "quantity": int(data.supply.quantity)}
	var copied_totals := {}
	var candidates: Array = supply_candidates(validation_state) if validation_state != null else SPECIAL_IDS
	for material in data.totals:
		if not material is String or not candidates.has(material) or not _integer(data.totals[material], 1, 1000000000): return false
		copied_totals[material] = int(data.totals[material])
	stages = copied_stages
	supply = copied_supply
	totals = copied_totals
	return true
