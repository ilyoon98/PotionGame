extends RefCounted
## F21 keeper investments: the bed speeds up sleep recovery and the herb-tea
## shelf slows fatigue while awake. A gold sink outside Content upgrades, so the
## 125-step growth and F19 "existing growth complete" checks are unchanged.
## Rates only change between advance() calls, so every boundary the keeper
## schedules from them stays exact.
const VERSION := 1
const TRACKS := ["bed", "tea"]
const NAMES := {"bed": "침대", "tea": "허브차 선반"}
## Same gate as the busier work policies: the upgrades only pay off there.
const UNLOCK_REPUTATION := 1000
## Provisional costs, one entry per stage of each track.
const COSTS := {"bed": [10000, 25000, 60000, 150000], "tea": [20000, 50000, 120000]}
## Sleep recovery per game hour by bed level (0 = no bed upgrade).
const SLEEP_PER_HOUR := [5.0, 6.0, 7.0, 8.0, 9.0]
## Share of awake fatigue gain removed by tea level.
const TEA_CUT := [0.0, 0.10, 0.20, 0.30]

var levels := {"bed": 0, "tea": 0}

func sleep_per_hour() -> float:
	return float(SLEEP_PER_HOUR[int(levels.bed)])

func awake_factor() -> float:
	return 1.0 - float(TEA_CUT[int(levels.tea)])

func _effect(track: String, level: int) -> String:
	if track == "bed": return "수면 회복 −%.0f / 게임시" % float(SLEEP_PER_HOUR[level])
	return "깨어 있는 동안 피로 증가 −%.0f%%" % (float(TEA_CUT[level]) * 100.0)

func view(state: RefCounted, track: String) -> Dictionary:
	if not TRACKS.has(track): return {"exists": false, "can_buy": false, "reason": "알 수 없는 주인공 투자"}
	var level := int(levels[track])
	var max_level: int = COSTS[track].size()
	var complete := level >= max_level
	var cost: int = 0 if complete else int(COSTS[track][level])
	var reason := "최대 단계" if complete else "명성 %d 필요" % UNLOCK_REPUTATION if state.progression.reputation < UNLOCK_REPUTATION else "%d G 부족" % (cost - state.gold) if state.gold < cost else ""
	return {"exists": true, "id": track, "name": NAMES[track], "level": level, "max_level": max_level, "next_level": 0 if complete else level + 1, "cost": cost, "can_buy": reason.is_empty(), "reason": reason, "complete": complete, "current_effect": _effect(track, level), "next_effect": "" if complete else _effect(track, level + 1)}

func purchase(state: RefCounted, track: String, expected_next_level: int) -> Dictionary:
	if not TRACKS.has(track): return {"ok": false, "error": "알 수 없는 주인공 투자"}
	if expected_next_level != int(levels[track]) + 1: return {"ok": false, "error": "투자 단계가 변경되었어요"}
	var item := view(state, track)
	if not item.can_buy: return {"ok": false, "error": item.reason}
	state.gold -= int(item.cost)
	state.progression.totals.manual_spent += int(item.cost)
	levels[track] = expected_next_level
	return {"ok": true, "error": "", "track": track, "level": expected_next_level, "cost": item.cost}

func to_data() -> Dictionary:
	return {"version": VERSION, "levels": levels.duplicate()}

func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == int(value) and value >= low and value <= high

func load_data(data: Variant) -> bool:
	if not data is Dictionary or data.size() != 2 or not _integer(data.get("version"), VERSION, VERSION): return false
	if not data.get("levels") is Dictionary or data.levels.size() != TRACKS.size(): return false
	var candidate := {}
	for track in TRACKS:
		if not _integer(data.levels.get(track), 0, COSTS[track].size()): return false
		candidate[track] = int(data.levels[track])
	levels = candidate
	return true
