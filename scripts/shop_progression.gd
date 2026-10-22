extends RefCounted
const Content = preload("res://scripts/shop_content.gd")
const Expansion = preload("res://scripts/shop_expansion.gd")
const Expeditions = preload("res://scripts/parallel_expeditions.gd")
var expansion := Expansion.new()
var report_expeditions := 0
var clock := 0.0
var tick_elapsed := 0.0
var seed_value := 73129
var owned: Array = []
var rare_herbs := 0
var rare_growth := 0.0
var recipe_cursor := 0
var active_recipe: Variant = false
var batch_success := true
var batch_chance := 1.0
var reputation := 0
var employee := false
var filter_owned := false
var expedition_unlocked := false
var expedition_active := false
var expedition_elapsed := 0.0
var expedition_pending := 0
var expedition_count := 0
var customer := 0
var customer_selected := false
var effects := 1.0
var brightness_floor := 0.6
var totals := {"harvested": 0, "rare": 0, "brewed": 0, "failed": 0, "sold": 0, "visits": 0, "preferred": 0, "reputation": 0, "expeditions": 0, "unlocks": 0, "manual_spent": 0}
var by_potion := {}
var by_customer := {}
var last_report_clock := 0.0
var report_baseline := {}
var report_sales := 0
var report_materials := 0
var report_started := ""


func _init() -> void:
	report_started = Time.get_datetime_string_from_system()
	for key in totals:
		report_baseline[key] = 0


func random_value() -> float:
	seed_value = (seed_value * 48271) % 2147483647
	return float(seed_value) / 2147483647.0


func phase() -> float:
	return fposmod(0.45 + clock / Content.DAY_SECONDS, 1.0)


func daylight() -> float:
	return smoothstep(-0.12, 0.3, sin((phase() - 0.25) * TAU))


func is_night() -> bool:
	return phase() < 0.25 - 0.000001 or phase() >= 0.75 - 0.000001


func weather() -> int:
	return int((clock + 0.000001) / Content.WEATHER_SECONDS) % 3


func environment_name() -> String:
	return ("밤" if is_night() else "낮") + " · " + ["맑음", "흐림", "비"][weather()]


func growth_rate() -> float:
	return (1.25 if is_night() else 1.0) * (1.5 if weather() == 2 else 1.0)


func success_chance(recipe: Variant) -> float:
	if recipe is bool:
		return 1.0
	var bonus := (0.07 if is_night() else 0.0) + (0.03 if weather() == 2 else 0.0)
	if not Content.LEGACY_RECIPES.has(recipe):
		var row := Content.lookup("potions", recipe)
		bonus = float(row["environment_bonus"]) if expansion.favored(row["environment"], self) else 0.0
	return minf(1.0, Content.RECIPES[recipe]["success"] + bonus + expansion.effect("precision_filter", "success_bonus", 0.05 if filter_owned else 0.0))


func environment_bonus(recipe: Variant) -> float:
	if recipe is bool: return 0.0
	var without_environment := minf(1.0, Content.RECIPES[recipe]["success"] + expansion.effect("precision_filter", "success_bonus", 0.05 if filter_owned else 0.0))
	return success_chance(recipe) - without_environment


func choose_recipe(has_mushroom: bool) -> Variant:
	var legacy: Array = owned.filter(func(id): return Content.LEGACY_RECIPES.has(id))
	if rare_herbs > 0 and not legacy.is_empty():
		var recipe: String = legacy[recipe_cursor % legacy.size()]
		recipe_cursor += 1
		rare_herbs -= 1
		return recipe
	return has_mushroom


func reserve_batch(has_mushroom: bool, keeper: RefCounted = null) -> void:
	active_recipe = choose_recipe(has_mushroom)
	if keeper != null:
		keeper.judge(self, success_chance(active_recipe), active_recipe is bool)
		return
	batch_chance = success_chance(active_recipe)
	batch_success = batch_chance >= 1.0 or random_value() < batch_chance


func customer_weights() -> Array[float]:
	var weights: Array[float] = []
	for row in Content.CUSTOMERS:
		if not row.get("enabled", true):
			weights.append(0.0)
			continue
		weights.append(maxf(0.5, row["base"] + (row["night"] if is_night() else 0.0) + (row["clear"] if weather() == 0 else 0.0) + (row["rain"] if weather() == 2 else 0.0) + (2.0 if row["id"] == "mage" and weather() == 1 else 0.0)))
	return weights


func select_customer() -> void:
	var weights := customer_weights()
	var roll: float = random_value() * weights.reduce(func(a, b): return a + b, 0.0)
	customer = weights.size() - 1
	for index in weights.size():
		if weights[index] <= 0.0: continue
		roll -= weights[index]
		if roll <= 0.0:
			customer = index
			break
	customer_selected = true
	totals["visits"] += 1
	var id: String = Content.CUSTOMERS[customer]["id"]
	by_customer[id] = int(by_customer.get(id, 0)) + 1


func sale_index(order: Array) -> int:
	var best := -1
	var best_order := -1
	for index in order.size():
		var id: Variant = order[index]
		if id is String and not Content.LEGACY_RECIPES.has(id) and is_preferred(id):
			var rank: int = int(Content.lookup("potions", id)["order"])
			if rank > best_order:
				best = index
				best_order = rank
	if best >= 0: return best
	# Preference chooses a kind; age still decides among bottles of that kind.
	for preferred in Content.CUSTOMERS[customer]["preferences"]:
		var index := order.find(preferred)
		if index >= 0:
			return index
	return 0


func is_preferred(kind: Variant) -> bool:
	if kind is String and not Content.LEGACY_RECIPES.has(kind):
		return Content.lookup("potions", kind)["preferred_customer"] == Content.CUSTOMERS[customer]["id"]
	return Content.CUSTOMERS[customer]["preferences"].has(kind)


func tick_second() -> void:
	expansion.grow(self)
	if owned.any(func(id): return Content.LEGACY_RECIPES.has(id) or Content.lookup("potions", id).get("grant_sources", []).has("starleaf")) and rare_herbs < expansion.special_capacity():
		rare_growth += growth_rate()
		if rare_growth >= 12.0:
			rare_growth -= 12.0
			rare_herbs += 1
			totals["rare"] += 1


func expedition_progress() -> float:
	return Expeditions.progress("forest_edge", self)


func completed_regions() -> int:
	return expansion.completed_regions(self)


func expedition_status() -> String:
	return Expeditions.status("forest_edge", self)


func record_sale(kind: Variant) -> void:
	totals["sold"] += 1
	var preferred := is_preferred(kind)
	totals["preferred"] += int(preferred)
	var fame := 2 if preferred else 1
	reputation += fame
	totals["reputation"] += fame
	var name := Content.potion_name(kind)
	by_potion[name] = int(by_potion.get(name, 0)) + 1


func to_data() -> Dictionary:
	var result := {}
	result["expansion"] = expansion.to_data()
	for key in ["clock", "tick_elapsed", "seed_value", "owned", "rare_herbs", "rare_growth", "recipe_cursor", "active_recipe", "batch_success", "batch_chance", "reputation", "employee", "filter_owned", "expedition_unlocked", "expedition_active", "expedition_elapsed", "expedition_pending", "expedition_count", "customer", "customer_selected", "effects", "brightness_floor", "totals", "by_potion", "by_customer", "last_report_clock", "report_baseline", "report_sales", "report_materials", "report_started", "report_expeditions"]:
		result[key] = get(key)
	return result.duplicate(true)


func load_data(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	data = data.duplicate(true)
	if not data.has("report_expeditions"): data["report_expeditions"] = 0
	var defaults := to_data()
	var saved_expansion := Expansion.new()
	if not data.has("expansion"): saved_expansion.parallel_version = 0
	if data.has("expansion") and not saved_expansion.load_data(data["expansion"]): return false
	for region in saved_expansion.cycles:
		if not saved_expansion.regions.has(region) and not (region == "forest_edge" and data.get("expedition_unlocked", false)): return false
	for key in defaults:
		if key == "expansion": continue
		if not data.has(key):
			return false
		var value: Variant = data[key]
		if key == "active_recipe": continue
		if defaults[key] is bool:
			if not value is bool: return false
		elif defaults[key] is int or defaults[key] is float:
			if not (value is int or value is float) or not is_finite(float(value)) or value < 0: return false
		elif defaults[key] is Dictionary:
			if not value is Dictionary: return false
			for entry in value:
				if not entry is String or not (value[entry] is int or value[entry] is float) or not is_finite(float(value[entry])) or value[entry] < 0: return false
		elif defaults[key] is String and not value is String:
			return false
	if not Content.valid_kind(data["active_recipe"]): return false
	if not data["owned"] is Array or data["owned"].size() > Content.RECIPES.size(): return false
	var seen := []
	for recipe in data["owned"]:
		if not Content.RECIPES.has(recipe) or seen.has(recipe): return false
		seen.append(recipe)
	for key in totals:
		if not data["totals"].has(key) or not data["report_baseline"].has(key): return false
	if data["customer"] >= Content.CUSTOMERS.size() or data["rare_herbs"] > saved_expansion.special_capacity() or data["expedition_pending"] > 2 or data["seed_value"] < 1 or data["seed_value"] >= 2147483647: return false
	if data["tick_elapsed"] > 1.0 or data["batch_chance"] > 1.0 or data["effects"] > 1.0 or data["brightness_floor"] < 0.5 or data["brightness_floor"] > 1.0: return false
	for key in defaults:
		if key == "expansion": continue
		if defaults[key] is int:
			set(key, int(data[key]))
		elif defaults[key] is Dictionary:
			var normalized := {}
			for entry in data[key]: normalized[entry] = int(data[key][entry])
			set(key, normalized)
		else:
			set(key, data[key])
	# Resume a removed visitor as a traveler without a new roll, visit or reward.
	if not Content.CUSTOMERS[customer].get("enabled", true):
		customer = 0
	# An unlocked expedition resumes its saved leg or pending deposit automatically.
	if saved_expansion.parallel_version == 0: expedition_active = expedition_unlocked
	expansion = saved_expansion
	return true
