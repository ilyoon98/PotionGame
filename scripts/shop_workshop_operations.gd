extends RefCounted
## One independent contract line. All methods except view/status are simulation
## boundaries or transactions; UI never rolls, reserves or advances production.
const Contracts = preload("res://scripts/shop_contracts.gd")
const Content = preload("res://scripts/shop_content.gd")
# F21 (2026-10-21): about 52h payback at the slower auxiliary output.
const COSTS := [500000, 700000, 1300000]
const FACTORS := [6.0, 4.5, 3.0]
const MIN_SECONDS := [8.0, 6.0, 4.0]
# F20 reservations made before the F21 slowdown keep their frozen time.
const LEGACY_FACTORS := [2.0, 1.5, 1.0]
## Slower auxiliary batches carry more bottles: F19 limit x3 (up to 12).
const AUX_BOTTLES := 3
var level := 0
var seed := 129731
var main_duration := 0.0
var aux := {}

static func derived_seed(state: RefCounted) -> int:
	return 1 + (int(state.progression.seed_value) * 48271 + int(state.contracts.seed) * 31 + int(state.progression.expansion.rare_seed)) % 2147483646

func view(state: RefCounted) -> Dictionary:
	var missing: Array[String] = []
	if not state.late_investments.growth_view(state).complete: missing.append("기존 가게 성장 완료 필요")
	if int(state.late_investments.stages.supply_support) < 3: missing.append("보급 지원 3단계 필요")
	if int(state.late_investments.stages.contract_batch) < 3: missing.append("납품 일괄 조제 3단계 필요")
	if state.late_investments.highest_grade(state) < 4: missing.append("거래 4등급 필요")
	var cost: int = COSTS[level] if level < 3 else 0
	var reason := "모든 개선 완료" if level == 3 else missing[0] if not missing.is_empty() else "%d G 부족" % (cost - state.gold) if state.gold < cost else ""
	var current := "메인 솥으로 판매·납품" if level == 0 else "판매·납품 동시 제작 · " + speed_text(level)
	var future := "판매·납품 동시 제작 · " + speed_text(mini(level, 2) + 1)
	return {"name": "작업실 운영 확장" if level == 0 else "보조 조제대 개선%d" % level if level < 3 else "보조 조제대", "level": level, "next_level": level + 1 if level < 3 else 0, "cost": cost, "can_buy": reason.is_empty(), "reason": reason, "missing": missing, "unlocked": missing.is_empty(), "complete": level == 3, "current_effect": current, "next_effect": future}

func aux_max(state: RefCounted) -> int:
	return int(state.late_investments.batch_max()) * AUX_BOTTLES

func speed_text(target_level: int) -> String:
	return "납품 시간 ×%.1f · 최소 %d초" % [FACTORS[target_level - 1], int(MIN_SECONDS[target_level - 1])]

## Frozen auxiliary time for a reservation; legacy F20 factors had no floor.
static func aux_duration(base_duration: float, factor: float) -> float:
	var index := FACTORS.find(factor)
	return base_duration * factor if index < 0 else maxf(float(MIN_SECONDS[index]), base_duration * factor)

func purchase(state: RefCounted, expected_level: int) -> Dictionary:
	if expected_level != level + 1 or expected_level > 3: return {"ok": false, "error": "투자 단계가 변경되었어요"}
	var item := view(state)
	if not item.can_buy: return {"ok": false, "error": item.reason}
	state.gold -= int(item.cost)
	state.progression.totals.manual_spent += int(item.cost)
	if level == 0:
		seed = derived_seed(state)
		if state.brew_active and state.contracts.batch.get("purpose") != "contract": main_duration = state.brew_duration()
	level = expected_level
	return {"ok": true, "level": level, "cost": item.cost}

func status(state: RefCounted) -> Dictionary:
	if not aux.is_empty():
		var batch: Dictionary = aux.batch
		return {"running": true, "status": "납품 제작 중", "elapsed": aux.elapsed, "duration": batch.duration, "progress": clampf(float(aux.elapsed) / float(batch.duration), 0.0, 1.0), "quantity": batch.quantity, "kind": batch.kind, "partner": batch.partner}
	var description := "작업실 확장 필요" if level == 0 else "기존 납품 완료 대기" if state.contracts.batch.get("purpose") == "contract" else "판매 재고 확보 중" if state.stock_protection.active else "판매 재료 확보 중" if state.contracts.candidate(state, state.stock_protection.reserve_materials(state), true, aux_max(state)).is_empty() else "납품 대기"
	return {"running": false, "status": description, "elapsed": 0.0, "duration": 1.0, "progress": 0.0, "quantity": 0, "kind": null, "partner": ""}

func start(state: RefCounted) -> void:
	if level == 0 or not aux.is_empty() or state.stock_protection.active or state.contracts.batch.get("purpose") == "contract": return
	var choice: Dictionary = state.contracts.candidate(state, state.stock_protection.reserve_materials(state), true, aux_max(state))
	if choice.is_empty(): return
	# No yield or callbacks between candidate, reservation and actual debit.
	var old_seed := seed
	seed = (seed * 48271) % 2147483647
	var success := float(seed) / 2147483647.0 < float(choice.chance)
	var main_batch: Dictionary = state.contracts.batch.duplicate(true)
	state.contracts.reserve(choice, {"chance": choice.chance, "success": success})
	var reserved: Dictionary = state.contracts.batch.duplicate(true)
	state.contracts.batch = main_batch
	assert(reserved.get("purpose") == "contract")
	state._consume_materials(choice.ingredients)
	var base_duration: float = choice.duration
	reserved.duration = aux_duration(base_duration, float(FACTORS[level - 1]))
	aux = {"batch": reserved, "elapsed": 0.0, "base_duration": base_duration, "factor": FACTORS[level - 1], "rng_before": old_seed}
	var event: Dictionary = reserved.duplicate(true)
	event["line"] = "aux"
	state._pending_batch_events.append(event)

func remaining() -> float:
	return INF if aux.is_empty() else maxf(0.0, float(aux.batch.duration) - float(aux.elapsed))

func tick(seconds: float) -> void:
	if not aux.is_empty(): aux.elapsed = minf(float(aux.batch.duration), float(aux.elapsed) + seconds)

func finish(state: RefCounted) -> Dictionary:
	if aux.is_empty() or remaining() > 0.000001: return {}
	var batch: Dictionary = aux.batch.duplicate(true)
	aux.clear() # Consume exactly once, before changing a round or paying it.
	var quantity := int(batch.quantity)
	if not batch.success:
		state.progression.totals.failed += quantity
		return {"line": "aux", "ok": false, "failed": quantity, "paid": 0}
	state.progression.totals.brewed += quantity
	state.progression.expansion.first_batches.erase(batch.kind)
	if batch.kind is String and not state.progression.expansion.first_brewed.has(batch.kind): state.progression.expansion.first_brewed.append(batch.kind)
	var main_batch: Dictionary = state.contracts.batch.duplicate(true)
	state.contracts.batch = batch
	var result: Dictionary = state.contracts.complete(state, batch.kind)
	state.contracts.batch = main_batch
	result["line"] = "aux"
	return result

func to_data() -> Dictionary:
	return {"version": 1, "level": level, "seed": seed, "main_duration": main_duration, "aux": aux.duplicate(true)}

func restore(data: Dictionary) -> void:
	level = int(data.level); seed = int(data.seed); main_duration = float(data.main_duration); aux = data.aux.duplicate(true)

func _number(value: Variant, low: float, high: float, integer: bool = false) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= low and value <= high and (not integer or float(value) == int(value))

func _keys(value: Dictionary, keys: Array) -> bool:
	return value.size() == keys.size() and keys.all(func(key): return value.has(key))

func load_data(data: Variant, state: RefCounted) -> bool:
	if not data is Dictionary or not _keys(data, ["version", "level", "seed", "main_duration", "aux"]): return false
	if not _number(data.version, 1, 1, true) or not _number(data.level, 0, 3, true) or not _number(data.seed, 1, 2147483646, true) or not _number(data.main_duration, 0, 100) or not data.aux is Dictionary: return false
	if int(data.level) > 0 and not view(state).unlocked: return false
	var ordinary: bool = state.brew_active and state.contracts.batch.get("purpose") != "contract"
	if ordinary and int(data.level) > 0:
		var kind: Variant = state.progression.active_recipe
		var max_duration: float = 5.0 * (1.25 if kind is bool and kind else 1.0 if kind is bool else float(Content.RECIPES[kind].duration))
		if float(data.main_duration) < state.brew_duration_for(kind) - 0.000001 or float(data.main_duration) > max_duration + 0.000001 or state.brew_elapsed < 0.0 or state.brew_elapsed > float(data.main_duration) + 0.000001: return false
	elif float(data.main_duration) != 0.0: return false
	if not data.aux.is_empty():
		var a: Dictionary = data.aux
		if int(data.level) == 0 or state.contracts.batch.get("purpose") == "contract" or not _keys(a, ["batch", "elapsed", "base_duration", "factor", "rng_before"]) or not a.batch is Dictionary: return false
		if not _number(a.factor, 1.0, 6.0) or not _number(a.base_duration, 0.8, 100) or not _number(a.rng_before, 1, 2147483646, true): return false
		# Upgrades only shorten future batches: a frozen factor is never faster than
		# the purchased level's own factor in the same (legacy or current) table.
		var table: Array = FACTORS if float(a.factor) in FACTORS else LEGACY_FACTORS
		if float(a.factor) not in table or float(a.factor) < float(table[int(data.level) - 1]): return false
		if not _number(a.batch.get("duration"), 0.8, 600) or not _number(a.elapsed, 0.0, float(a.batch.duration)) or absf(float(a.batch.duration) - aux_duration(float(a.base_duration), float(a.factor))) > 0.000001: return false
		var rolled: int = (int(a.rng_before) * 48271) % 2147483647
		if int(data.seed) != rolled or not _number(a.batch.get("chance"), 0, 1) or not a.batch.get("success") is bool or a.batch.success != (float(rolled) / 2147483647.0 < float(a.batch.chance)): return false
		var copy: Dictionary = state.contracts.to_data()
		copy.batch = a.batch.duplicate(true); copy.ordinary_batches = 0
		var validator := Contracts.new()
		var kind: Variant = a.batch.get("kind")
		if not Content.valid_kind(kind): return false
		# Every auxiliary start requires all original upgrades, so the filter
		# cannot have been weaker than it is now. Weather only adds a bonus.
		var minimum_chance: float = state.progression.success_chance(kind) - state.progression.environment_bonus(kind)
		if float(a.batch.chance) < minimum_chance - 0.000001: return false
		# The contract ceiling is the slowest unupgraded time; keep the floor inside it.
		var slowest: float = 5.0 * (1.25 if kind is bool and kind else 1.0 if kind is bool else float(Content.RECIPES[kind].duration))
		var expected := {"chance": a.batch.chance, "success": a.batch.success, "max_quantity": state.late_investments.batch_max() * (AUX_BOTTLES if float(a.factor) in FACTORS else 1), "duration": aux_duration(state.brew_duration_for(kind), float(a.factor)), "duration_ceiling_factor": aux_duration(slowest, float(a.factor)) / slowest}
		if not validator.load_data(copy, state.progression, true, kind, expected): return false
	restore(data)
	return true
