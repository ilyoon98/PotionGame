extends RefCounted
## F21 aging. When the retail shelf holds at least BATCH bottles, an empty barrel
## takes the BATCH most valuable bottles (any kinds) and ages them while the game
## runs (offline progress stays deferred). Matured bottles wait on the aged shelf
## and customers buy them first at a premium. Aging never fails and is not affected by keeper fatigue.
const Content = preload("res://scripts/shop_content.gd")
const VERSION := 1
## Barrels were 4 bottles in the first build; 12 per user decision 2026-10-21.
const BATCH := 12
## Cumulative seconds per stage and the sale multiplier of that stage.
const STAGES := [600.0, 1800.0, 5400.0]
const MULTIPLIERS := [3.0, 7.0, 16.0]
const STAGE_NAMES := ["숙성", "오래 숙성한", "명품"]
const UNLOCK_REPUTATION := 4000
const TRACKS := ["open", "barrels", "cellar", "shelf"]
const NAMES := {"open": "숙성 선반", "barrels": "숙성통 추가", "cellar": "숙성 지하실", "shelf": "숙성품 진열칸"}
## Provisional costs, one entry per stage of each track.
const COSTS := {"open": [20000], "barrels": [30000, 60000, 120000], "cellar": [50000, 150000], "shelf": [40000, 100000]}
const SHELF_CAPACITY := [12, 18, 24]
const EPSILON := 0.000001

var levels := {"open": 0, "barrels": 0, "cellar": 0, "shelf": 0}
var barrels: Array = [] # {bottles: [kind...], elapsed}
var shelf: Array = [] # {kind, stage}
var totals := {"sold": 0, "revenue": 0}

func opened() -> bool:
	return int(levels.open) > 0

func barrel_count() -> int:
	return 1 + int(levels.barrels) if opened() else 0

func max_stage() -> int:
	return 1 + int(levels.cellar)

func target_seconds() -> float:
	return float(STAGES[max_stage() - 1])

func shelf_capacity() -> int:
	return int(SHELF_CAPACITY[int(levels.shelf)]) if opened() else 0

## Seconds until the next barrel reaches its target stage (an event boundary).
func remaining() -> float:
	var wait := INF
	for barrel in barrels:
		if float(barrel.elapsed) < target_seconds() - EPSILON: wait = minf(wait, target_seconds() - float(barrel.elapsed))
	return wait

func tick(step: float) -> void:
	for barrel in barrels: barrel.elapsed = minf(target_seconds(), float(barrel.elapsed) + step)

## Move matured bottles to the aged shelf, then refill empty barrels from a full
## retail shelf. Pure function of state; safe to call at every boundary.
func settle(state: RefCounted) -> void:
	if not opened(): return
	var index := 0
	while index < barrels.size() and shelf.size() < shelf_capacity():
		var barrel: Dictionary = barrels[index]
		if float(barrel.elapsed) < target_seconds() - EPSILON:
			index += 1
			continue
		var bottles: Array = barrel.bottles
		while not bottles.is_empty() and shelf.size() < shelf_capacity():
			shelf.append({"kind": bottles.pop_front(), "stage": max_stage()})
		if bottles.is_empty(): barrels.remove_at(index)
		else: index += 1
	while barrels.size() < barrel_count() and state.stock >= BATCH and not state.stock_protection.active:
		var picked := _most_valuable(state)
		var bottles: Array = []
		# Remove from the back so earlier indices stay valid; keep shelf order in the barrel.
		for position in range(picked.size() - 1, -1, -1):
			var bottle: Variant = state.inventory[picked[position]]
			bottles.push_front(bottle)
			state.inventory.remove_at(picked[position])
			if bottle is bool and bottle: state.mana_stock -= 1
		state.stock -= BATCH
		barrels.append({"bottles": bottles, "elapsed": 0.0})

## Inventory indices of the BATCH highest-priced bottles, ascending. Equal prices
## prefer the oldest bottle, so the choice is deterministic.
func _most_valuable(state: RefCounted) -> Array:
	var ranked: Array = []
	for index in state.inventory.size(): ranked.append([state._retail_price(state.inventory[index], false), index])
	ranked.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	var picked: Array = []
	for row in ranked.slice(0, BATCH): picked.append(row[1])
	picked.sort()
	return picked

func has_aged() -> bool:
	return not shelf.is_empty()

## Take the oldest aged bottle. The caller prices and records the sale.
func take_aged() -> Dictionary:
	return shelf.pop_front()

static func multiplier(stage: int) -> float:
	return float(MULTIPLIERS[clampi(stage, 1, 3) - 1])

static func aged_name(kind: Variant, stage: int) -> String:
	return "%s %s" % [STAGE_NAMES[clampi(stage, 1, 3) - 1], Content.potion_name(kind)]

func view(state: RefCounted, track: String) -> Dictionary:
	if not TRACKS.has(track): return {"exists": false, "can_buy": false, "reason": "알 수 없는 숙성 투자"}
	var level := int(levels[track])
	var max_level: int = COSTS[track].size()
	var complete := level >= max_level
	var cost: int = 0 if complete else int(COSTS[track][level])
	var reason := "최대 단계" if complete else "명성 %d 필요" % UNLOCK_REPUTATION if state.progression.reputation < UNLOCK_REPUTATION else "숙성 선반 필요" if track != "open" and not opened() else "%d G 부족" % (cost - state.gold) if state.gold < cost else ""
	var next_effect := ""
	if not complete:
		match track:
			"open": next_effect = "숙성통 1개(%d병) · 10분 숙성 판매가 ×3" % BATCH
			"barrels": next_effect = "숙성통 %d개" % (2 + level)
			"cellar": next_effect = "%s 숙성 %d분 · 판매가 ×%.0f" % [STAGE_NAMES[1 + level], int(STAGES[1 + level] / 60.0), MULTIPLIERS[1 + level]]
			"shelf": next_effect = "진열칸 %d병" % SHELF_CAPACITY[1 + level]
	return {"exists": true, "id": track, "name": NAMES[track], "level": level, "max_level": max_level, "next_level": 0 if complete else level + 1, "cost": cost, "can_buy": reason.is_empty(), "reason": reason, "complete": complete, "next_effect": next_effect}

func purchase(state: RefCounted, track: String, expected_next_level: int) -> Dictionary:
	if not TRACKS.has(track): return {"ok": false, "error": "알 수 없는 숙성 투자"}
	if expected_next_level != int(levels[track]) + 1: return {"ok": false, "error": "투자 단계가 변경되었어요"}
	var item := view(state, track)
	if not item.can_buy: return {"ok": false, "error": item.reason}
	state.gold -= int(item.cost)
	state.progression.totals.manual_spent += int(item.cost)
	levels[track] = expected_next_level
	return {"ok": true, "error": "", "track": track, "level": expected_next_level, "cost": item.cost}

func to_data() -> Dictionary:
	return {"version": VERSION, "levels": levels.duplicate(), "barrels": barrels.duplicate(true), "shelf": shelf.duplicate(true), "totals": totals.duplicate()}

func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == int(value) and value >= low and value <= high

func load_data(data: Variant) -> bool:
	if not data is Dictionary or data.size() != 5 or not _integer(data.get("version"), VERSION, VERSION): return false
	if not data.get("levels") is Dictionary or data.levels.size() != TRACKS.size(): return false
	var candidate: RefCounted = get_script().new()
	for track in TRACKS:
		if not _integer(data.levels.get(track), 0, COSTS[track].size()): return false
		candidate.levels[track] = int(data.levels[track])
	if not candidate.opened() and (int(data.levels.barrels) + int(data.levels.cellar) + int(data.levels.shelf) > 0): return false
	if not data.get("barrels") is Array or data.barrels.size() > candidate.barrel_count(): return false
	for barrel in data.barrels:
		if not barrel is Dictionary or barrel.size() != 2 or not barrel.get("bottles") is Array or barrel.bottles.is_empty() or barrel.bottles.size() > BATCH: return false
		for bottle in barrel.bottles:
			if not Content.valid_kind(bottle): return false
		if not (barrel.get("elapsed") is int or barrel.get("elapsed") is float) or not is_finite(float(barrel.elapsed)) or barrel.elapsed < 0.0 or barrel.elapsed > candidate.target_seconds() + EPSILON: return false
		candidate.barrels.append({"bottles": barrel.bottles.duplicate(), "elapsed": float(barrel.elapsed)})
	if not data.get("shelf") is Array or data.shelf.size() > candidate.shelf_capacity(): return false
	for bottle in data.shelf:
		if not bottle is Dictionary or bottle.size() != 2 or not Content.valid_kind(bottle.get("kind")) or not _integer(bottle.get("stage"), 1, candidate.max_stage()): return false
		candidate.shelf.append({"kind": bottle.kind, "stage": int(bottle.stage)})
	if not data.get("totals") is Dictionary or data.totals.size() != 2 or not _integer(data.totals.get("sold"), 0, 1000000000) or not _integer(data.totals.get("revenue"), 0, 1000000000000): return false
	candidate.totals = {"sold": int(data.totals.sold), "revenue": int(data.totals.revenue)}
	levels = candidate.levels; barrels = candidate.barrels; shelf = candidate.shelf; totals = candidate.totals
	return true
