extends RefCounted
## Only progress is saved here; catalog rows never contain player progress.
const Content = preload("res://scripts/shop_content.gd")
const Rare = preload("res://scripts/rare_recipes.gd")
var materials := {}
var growth := {}
var plants: Array = []
var regions: Array = []
var returns := {}
var destination := "forest_edge"
var trip_region := "forest_edge"
var trip_seconds := 0.0
var pending := {}
var stages := {}
var staff: Array = []
var first_batches: Array = []
var first_brewed: Array = []
var first_sold: Array = []
var family_cursor := 0
var parallel_version := 1
var cycles := {}
var reward_totals := {}
var report_returns := {}
var report_rewards := {}
var latest_returns := {}
var rare_version := 1
var rare_discovered: Array = []
var rare_failures := {}
var rare_seed := Rare.INITIAL_SEED
var rare_cursor := 0
var rare_turn := true


func effect(track: String, key: String, fallback: float = 0.0) -> float:
	if not staff.has(track) and int(stages.get(track, 0)) == 0: return fallback
	var value := fallback
	if staff.has(track): value = float(Content.lookup("employees", track)["effect"].get(key, fallback))
	for row in Content.track_rows(track):
		if row["stage"] <= int(stages.get(track, 0)) and row["effect"].has(key):
			value = float(row["effect"][key])
	return value


func special_capacity() -> int:
	return int(effect("herb_storage", "special_capacity", 12))


func potion_capacity() -> int:
	return int(effect("potion_cabinet", "total_potion_capacity", 12))


func favored(environment: String, p: RefCounted) -> bool:
	return {"rain": p.weather() == 2, "cloudy": p.weather() == 1, "clear": p.weather() == 0, "day": not p.is_night(), "night": p.is_night(), "night_clear": p.is_night() and p.weather() == 0}.get(environment, false)


func grow(p: RefCounted) -> void:
	for id in plants:
		var row := Content.lookup("materials", id)
		var amount: int = int(materials.get(id, 0))
		if amount >= special_capacity(): continue
		var rate := float(row.get("favored_growth_multiplier", 1.5)) if favored(row.get("environment", "none"), p) else 1.0
		rate *= effect("drying_rack", "new_material_growth_multiplier", 1.0) * effect("cultivation_assistant", "new_material_growth_multiplier", 1.0)
		growth[id] = float(growth.get(id, 0.0)) + rate
		while growth[id] >= float(row["growth_seconds"]) and amount < special_capacity():
			growth[id] -= float(row["growth_seconds"])
			amount += 1
		materials[id] = amount


func grant_recipe(id: String) -> void:
	var row := Content.lookup("potions", id)
	if not first_batches.has(id): first_batches.append(id)
	for material in row.get("grant_sources", []):
		if material in ["herb", "moon_mushroom", "starleaf"] or plants.has(material): continue
		plants.append(material)
		var quantity: int = int(Content.lookup("materials", material).get("seed_quantity", 2))
		var added := mini(quantity, maxi(0, special_capacity() - int(materials.get(material, 0))))
		materials[material] = int(materials.get(material, 0)) + added
		if added < quantity: pending[material] = int(pending.get(material, 0)) + quantity - added
		growth[material] = 0.0


func region_returns(id: String, p: RefCounted) -> int:
	return p.expedition_count if id == "forest_edge" else int(returns.get(id, 0))


func completed_regions(p: RefCounted) -> int:
	var count := 0
	for row in Content.DATA["regions"]:
		if (regions.has(row["id"]) or (row["id"] == "forest_edge" and p.expedition_unlocked)) and region_returns(row["id"], p) >= int(row["complete_returns"]): count += 1
	return count


func recipe_reason(id: String, p: RefCounted) -> String:
	if Rare.is_special(id): return "" if Rare.is_discovered(id, p) else "특별 레시피 미발견"
	var unlock: Dictionary = Content.lookup("potions", id)["unlock"]
	if unlock.has("discovery"):
		var discovery: Dictionary = unlock["discovery"]
		if region_returns(discovery["region"], p) < int(discovery["returns"]):
			return "%s 귀환 %d회 필요" % [Content.lookup("regions", discovery["region"])["name"], int(discovery["returns"])]
	for required in unlock.get("recipes", []):
		if not p.owned.has(required): return "%s 레시피 필요" % Content.potion_name(required)
	return ""


func region_reason(id: String, p: RefCounted) -> String:
	var row := Content.lookup("regions", id)
	if row.is_empty(): return "알 수 없는 지역"
	if regions.has(id) or (id == "forest_edge" and p.expedition_unlocked): return "개방 완료"
	if p.reputation < int(row["reputation"]): return "명성 %d 필요" % int(row["reputation"])
	if row["previous_region"] != null:
		var previous := Content.lookup("regions", row["previous_region"])
		if region_returns(previous["id"], p) < int(previous["complete_returns"]): return "%s 조사 필요" % previous["name"]
	return ""


func to_data() -> Dictionary:
	var result := {}
	for key in ["materials", "growth", "plants", "regions", "returns", "destination", "trip_region", "trip_seconds", "pending", "stages", "staff", "first_batches", "first_brewed", "first_sold", "family_cursor", "parallel_version", "cycles", "reward_totals", "report_returns", "report_rewards", "latest_returns", "rare_version", "rare_discovered", "rare_failures", "rare_seed", "rare_cursor", "rare_turn"]: result[key] = get(key)
	return result.duplicate(true)


func load_data(data: Variant) -> bool:
	if not data is Dictionary: return false
	data = data.duplicate(true)
	if not data.has("latest_returns"): data["latest_returns"] = {}
	if not data.has("parallel_version"):
		data.merge({"parallel_version": 0, "cycles": {}, "reward_totals": {}, "report_returns": {}, "report_rewards": {}})
	if not data.has("rare_version"):
		for key in ["rare_discovered", "rare_failures", "rare_seed", "rare_cursor", "rare_turn"]:
			if data.has(key): return false
		data.merge({"rare_version": 1, "rare_discovered": [], "rare_failures": {}, "rare_seed": Rare.INITIAL_SEED, "rare_cursor": 0, "rare_turn": true})
		# Already-started old legs keep their stored rewards and never gain a roll.
		if not data.get("cycles") is Dictionary: return false
		for cycle in data.cycles.values():
			if not cycle is Dictionary: return false
			cycle.merge({"mode": "normal", "rare_valid": false, "rare_recipe": "", "rare_success": false, "rare_attempt": 0}, true)
	var defaults := to_data()
	for key in defaults:
		if not data.has(key) or typeof(data[key]) != typeof(defaults[key]):
			if key not in ["trip_seconds", "family_cursor", "parallel_version", "rare_version", "rare_seed", "rare_cursor"] or not (data.get(key) is int or data.get(key) is float): return false
		if key == "cycles":
			if not validate_cycles(data[key]): return false
		elif key == "rare_failures":
			for id in data[key]:
				var value: Variant = data[key][id]
				if not id is String or not Rare.is_special(id) or not (value is int or value is float) or not is_finite(float(value)) or value < 0 or value >= Rare.GUARANTEE or float(value) != int(value): return false
		elif key == "rare_discovered":
			var seen := []
			for id in data[key]:
				if not id is String or not Rare.is_special(id) or seen.has(id): return false
				seen.append(id)
		elif key == "latest_returns":
			for id in data[key]:
				if not id is String or Content.lookup("regions", id).is_empty() or not data[key][id] is Dictionary: return false
				for material in data[key][id]:
					var count: Variant = data[key][id][material]
					if not material is String or Content.lookup("materials", material).is_empty() or not (count is int or count is float) or not is_finite(float(count)) or count < 1 or count > 1000 or float(count) != int(count): return false
		elif key in ["materials", "growth", "returns", "pending", "stages", "reward_totals", "report_returns", "report_rewards"]:
			for id in data[key]:
				var value: Variant = data[key][id]
				if not id is String or not (value is int or value is float) or not is_finite(float(value)) or value < 0: return false
				var category := "regions" if key in ["returns", "report_returns"] else "materials"
				if key == "stages":
					var max_stage := 0
					for row in Content.DATA["upgrades"]:
						if row["track"] == id: max_stage = maxi(max_stage, int(row["stage"]))
					if max_stage == 0 or value > max_stage or float(value) != int(value): return false
				elif Content.lookup(category, id).is_empty(): return false
				elif key != "growth" and (float(value) != int(value) or value > (1000000000 if key in ["returns", "pending", "reward_totals", "report_returns", "report_rewards"] else 42)): return false
		elif defaults[key] is Array:
			var category := "regions" if key == "regions" else ("employees" if key == "staff" else ("materials" if key == "plants" else "potions"))
			var seen := []
			for id in data[key]:
				if not id is String or seen.has(id) or Content.lookup(category, id).is_empty(): return false
				if key == "plants" and id in ["herb", "moon_mushroom", "starleaf"]: return false
				seen.append(id)
		elif defaults[key] is String and Content.lookup("regions", data[key]).is_empty(): return false
		elif key in ["trip_seconds", "family_cursor", "parallel_version", "rare_version", "rare_seed", "rare_cursor"] and (not is_finite(float(data[key])) or data[key] < 0): return false
	if float(data["family_cursor"]) != int(data["family_cursor"]) or float(data["parallel_version"]) != int(data["parallel_version"]) or int(data["parallel_version"]) not in [0, 1]: return false
	if float(data.rare_version) != 1.0 or float(data.rare_seed) != int(data.rare_seed) or data.rare_seed < 1 or data.rare_seed >= 2147483647 or float(data.rare_cursor) != int(data.rare_cursor) or data.rare_cursor >= Rare.ROWS.size(): return false
	for cycle in data.cycles.values():
		if cycle.running and cycle.rare_valid and (data.rare_discovered.has(cycle.rare_recipe) or cycle.rare_attempt != int(data.rare_failures.get(cycle.rare_recipe, 0)) + 1): return false
	for key in defaults: set(key, data[key].duplicate(true) if data[key] is Array or data[key] is Dictionary else data[key])
	return true


func validate_cycles(saved: Dictionary) -> bool:
	for id in saved:
		if not id is String or Content.lookup("regions", id).is_empty() or not saved[id] is Dictionary: return false
		var c: Dictionary = saved[id]
		if not c.get("rewards") is Dictionary: return false
		if not c.get("mode") is String or c.mode not in ["normal", "special"]: return false
		for key in ["rare_valid", "rare_success"]:
			if not c.get(key) is bool: return false
		if not c.get("rare_recipe") is String or not (c.get("rare_attempt") is int or c.get("rare_attempt") is float) or not is_finite(float(c.rare_attempt)) or float(c.rare_attempt) != int(c.rare_attempt): return false
		if c.rare_valid:
			if Rare.by_region(id).get("id", "") != c.rare_recipe or c.rare_attempt < 1 or c.rare_attempt > Rare.GUARANTEE or (c.rare_attempt == Rare.GUARANTEE and not c.rare_success): return false
		elif c.rare_recipe != "" or c.rare_attempt != 0 or c.rare_success: return false
		if c.mode == "special" and (not c.rare_valid or not c.get("paid", false) or not c.get("rewards", {}).is_empty()): return false
		for key in ["paid", "running"]:
			if not c.get(key) is bool: return false
		for key in ["id", "fee", "elapsed", "duration", "wait_since"]:
			if not (c.get(key) is int or c.get(key) is float) or not is_finite(float(c[key])) or c[key] < 0: return false
		if float(c["id"]) != int(c["id"]) or c["elapsed"] > c["duration"] or (c["running"] and (c["id"] < 1 or c["duration"] <= 0)): return false
		if float(c["fee"]) != int(c["fee"]) or c["fee"] > 1000000000 or (c["paid"] and c["fee"] <= 0): return false
		if c.rare_valid and (not c.paid or c.id < 1 or c.duration <= 0): return false
		if not c.get("rewards") is Dictionary: return false
		for material in c["rewards"]:
			var quantity: Variant = c["rewards"][material]
			if not material is String or Content.lookup("materials", material).is_empty() or not (quantity is int or quantity is float) or not is_finite(float(quantity)) or quantity < 1 or quantity > 1000 or float(quantity) != int(quantity): return false
	return true
