extends RefCounted
## Each paid leg is immutable until its return. All returns precede departures.
const Content = preload("res://scripts/shop_content.gd")
const Rewards = preload("res://scripts/expedition_rewards.gd")
const Rare = preload("res://scripts/rare_recipes.gd")

static func opened(id: String, p: RefCounted) -> bool:
	return p.expansion.regions.has(id) or (id == "forest_edge" and p.expedition_unlocked)

static func ensure(p: RefCounted) -> void:
	var e = p.expansion
	for row in Content.DATA["regions"]:
		var id: String = row["id"]
		if opened(id, p) and not e.cycles.has(id):
			e.cycles[id] = {"id": 0, "fee": 0, "paid": false, "running": false, "elapsed": 0.0, "duration": 0.0, "rewards": {}, "wait_since": p.clock, "mode": "normal", "rare_valid": false, "rare_recipe": "", "rare_success": false, "rare_attempt": 0}

static func migrate(p: RefCounted) -> void:
	ensure(p)
	var e = p.expansion
	if e.parallel_version == 1: return
	if e.report_returns.is_empty():
		if e.regions.is_empty(): e.report_returns["forest_edge"] = int(p.report_baseline.get("expeditions", 0))
		else:
			# Old v7 recorded only an aggregate period; do not invent region detail.
			for row in Content.DATA["regions"]: e.report_returns[row["id"]] = e.region_returns(row["id"], p)
	# A saved old leg is grandfathered; no historical departure charge.
	if p.expedition_unlocked and p.expedition_pending == 0 and e.pending.is_empty():
		var id: String = e.trip_region
		if not opened(id, p): id = "forest_edge"
		var row := Content.lookup("regions", id)
		var duration: float = e.trip_seconds if e.trip_seconds > 0 else 70.0
		var rewards := {"starleaf": 2} if id == "forest_edge" else {row["material"]: int(row["repeat_material_quantity"])}
		var cycle: Dictionary = e.cycles[id]
		cycle.merge({"id": 1, "paid": false, "running": true, "elapsed": minf(p.expedition_elapsed, duration), "duration": duration, "rewards": rewards}, true)
	e.parallel_version = 1

static func stock(id: String, p: RefCounted) -> int:
	return p.rare_herbs if id == "starleaf" else int(p.expansion.materials.get(id, 0))

static func deposit(p: RefCounted, state: RefCounted = null) -> void:
	var e = p.expansion
	if p.expedition_pending > 0:
		e.pending["starleaf"] = int(e.pending.get("starleaf", 0)) + p.expedition_pending
		p.expedition_pending = 0
	for id in e.pending.keys():
		if id in ["herb", "moon_mushroom"]:
			if state == null: continue
			var count: int = state.material_count(id)
			var capacity: int = state.herb_capacity() if id == "herb" else state.MUSHROOM_CAPACITY
			var added := mini(int(e.pending[id]), maxi(0, capacity - count))
			if id == "herb": state.herbs += added
			else: state.mushrooms += added
			e.pending[id] -= added
			if e.pending[id] == 0: e.pending.erase(id)
			continue
		var amount := mini(int(e.pending[id]), maxi(0, e.special_capacity() - stock(id, p)))
		if id == "starleaf":
			p.rare_herbs += amount
			p.totals["rare"] += amount
		else: e.materials[id] = stock(id, p) + amount
		e.pending[id] -= amount
		if e.pending[id] == 0: e.pending.erase(id)

static func storage_reason(row: Dictionary, p: RefCounted) -> String:
	var e = p.expansion
	if e.region_returns(row["id"], p) < int(row["complete_returns"]): return ""
	# Only the guaranteed material gates repeats. Optional rewards never reroll
	# for space, and any overflow stays in pending until it can be deposited.
	var pool: Dictionary = Rewards.POOLS[row.id]
	var count := stock(pool.main, p) + int(e.pending.get(pool.main, 0))
	if count + int(pool.max) > e.special_capacity(): return "보관 공간 대기"
	return "" if count <= e.special_capacity() * 0.5 else "재료 충분 · 자동 대기"

static func candidates(p: RefCounted) -> Array:
	var list := []
	for row in Content.DATA["regions"]:
		if not departure_mode(row.id, p).is_empty(): list.append(row)
	list.sort_custom(func(a, b):
		var complete_a: bool = p.expansion.region_returns(a["id"], p) >= int(a["complete_returns"])
		var complete_b: bool = p.expansion.region_returns(b["id"], p) >= int(b["complete_returns"])
		if complete_a != complete_b: return not complete_a
		var wait_a: float = p.expansion.cycles[a["id"]]["wait_since"]
		var wait_b: float = p.expansion.cycles[b["id"]]["wait_since"]
		return wait_a < wait_b if wait_a != wait_b else Content.DATA["regions"].find(a) < Content.DATA["regions"].find(b))
	return list

static func departure_mode(id: String, p: RefCounted) -> String:
	if not opened(id, p) or p.expansion.cycles.get(id, {}).get("running", false): return ""
	var row := Content.lookup("regions", id)
	if row.is_empty(): return ""
	if storage_reason(row, p).is_empty(): return "normal"
	return "special" if Rare.needs_search(id, p) else ""

static func tick(state: RefCounted, seconds: float = 1.0) -> void:
	var p = state.progression
	var e = p.expansion
	ensure(p)
	for id in e.cycles:
		var c: Dictionary = e.cycles[id]
		if not c["running"]: continue
		c["elapsed"] += seconds
		if c["elapsed"] + 0.000001 < c["duration"]: continue
		c["running"] = false
		c["elapsed"] = 0.0
		c["wait_since"] = p.clock
		if c.get("mode", "normal") == "normal":
			if id == "forest_edge": p.expedition_count += 1
			else: e.returns[id] = int(e.returns.get(id, 0)) + 1
		p.totals["expeditions"] += 1
		Rare.complete(c, p)
		e.latest_returns[id] = c["rewards"].duplicate(true)
		for material in c["rewards"]:
			e.pending[material] = int(e.pending.get(material, 0)) + int(c["rewards"][material])
			e.reward_totals[material] = int(e.reward_totals.get(material, 0)) + int(c["rewards"][material])
	deposit(p, state)
	var protect := 0
	for row in candidates(p):
		var fee: int = int(row["departure_cost"])
		var mode := departure_mode(row.id, p)
		var completed: bool = e.region_returns(row["id"], p) >= int(row["complete_returns"])
		var reserve := 30 + (protect if completed else 0)
		if state.gold - fee < reserve:
			if not completed and protect == 0: protect = fee
			continue
		state.gold -= fee
		state.total_spent_expeditions += fee
		var c: Dictionary = e.cycles[row["id"]]
		c["id"] += 1
		c["paid"] = true
		c["fee"] = fee
		c["running"] = true
		c["elapsed"] = 0.0
		c["mode"] = mode
		var reduction := minf(0.3, e.effect("expedition_path", "trip_time_reduction") + e.effect("expedition_guide", "trip_time_reduction"))
		c["duration"] = (float(row["explore_seconds"]) + float(row["return_seconds"])) * (1.0 - reduction)
		c["rewards"] = Rewards.roll(row.id, p) if mode == "normal" else {}
		c.merge(Rare.reserve(row.id, p), true)
	# Legacy getters describe the forest only, never an average of distinct legs.
	if e.cycles.has("forest_edge"):
		p.expedition_elapsed = e.cycles["forest_edge"]["elapsed"]
		e.trip_seconds = e.cycles["forest_edge"]["duration"]
	p.expedition_active = active_count(p) > 0

static func active_count(p: RefCounted) -> int:
	var count := 0
	for c in p.expansion.cycles.values(): count += int(c["running"])
	return count

static func progress(id: String, p: RefCounted) -> float:
	var c: Dictionary = p.expansion.cycles.get(id, {})
	return float(c["elapsed"]) / maxf(1.0, c["duration"]) if c.get("running", false) else 0.0

static func status(id: String, p: RefCounted) -> String:
	if not opened(id, p): return "미해금"
	var c: Dictionary = p.expansion.cycles.get(id, {})
	var row := Content.lookup("regions", id)
	if c.get("running", false):
		if c.get("mode", "normal") == "special": return "특별 탐색 중"
		return "탐색 중" if progress(id, p) < float(row["explore_seconds"]) / (float(row["explore_seconds"]) + float(row["return_seconds"])) else "귀환 중"
	var reason := storage_reason(row, p)
	return reason if not reason.is_empty() else "출발비 부족 · 자동 대기"
