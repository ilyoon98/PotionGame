extends SceneTree
## F27 candidate economy probe (planning evidence, not a runtime/test tool).
## Real ShopState.advance() on the same synthetic late store as F26 (tests/late_investment_fixture.gd completed_store
## + F20 workshop 3 + aging + keeper upgrades, reputation 130,000, gold 3,000,000, 1 hour warm-up).
## Then, exactly like art/mockups/f26-region-potions-v1/economy/measure_connected.gd "complete", the live F26 content
## (data/ + scripts/) is finished: dawn lighthouse surveyed, four F26 recipes owned, dawn bloom planter granted and its
## storage full. That is the F27 baseline (= today's endgame).
## The F27 candidate rows (one material, four potions) are injected in memory only; data/ and scripts/ are untouched and
## nothing is saved (no player save is read or written). Region 10 is NOT added to Content.DATA.regions
## (expedition_rewards.gd POOLS is a const), so its trips are simulated here with the same rules as the real parallel
## expeditions: paid departure, 30% time cap, main min..max + extras 60/30/10, 25% second extra, refill only while
## stock+pending <= 50% of special storage after the survey.
## Run (art/ has .gdignore, so pass the file path):
##   Godot_v4.6-stable_win64_console.exe --headless --path <project> --script <this file> -- --mode=pre_f26|baseline|complete|progress
##     --seed=73129 --hours=6 [--check=300] [--gold=3000000] [--price=1.0] [--cost=1.0] [--env=night] [--growth=28]
##     [--no-garden] [--complete=8] --out=<json path>
const State = preload("res://scripts/shop_state.gd")
const Content = preload("res://scripts/shop_content.gd")
const F = preload("res://tests/late_investment_fixture.gd")
const F26 := ["sunrise", "beacon", "sea_spray", "sun_moon_elixir"]

var REGION := {"id": "aurora_snowfield", "explore": 500.0, "return": 100.0, "complete": 8, "fee": 200, "cost": 500000,
	"main": "frost_flower", "min": 7, "max": 9, "extra": ["dawn_bloom", "star_seed", "moonflower"]}
var MATERIAL := {"id": "frost_flower", "name": "서리꽃", "source": "recipe_granted_garden", "region": "aurora_snowfield", "growth_seconds": 28, "capacity": 12, "environment": "night", "favored_growth_multiplier": 1.5, "seed_quantity": 2}
var POTIONS := [
	{"id": "warmth", "name": "온기", "family": "vitality", "preferred_customer": "traveler", "order": 40, "returns": 1, "recipes": [], "cost": 300000, "sale_price": 230, "ingredients": {"herb": 2, "frost_flower": 1, "ash_sage": 1}, "duration_multiplier": 3.4, "success": 0.80},
	{"id": "thin_ice", "name": "살얼음", "family": "craft", "preferred_customer": "rogue", "order": 41, "returns": 3, "recipes": [], "cost": 400000, "sale_price": 245, "ingredients": {"herb": 2, "frost_flower": 1, "crystal_herb": 1}, "duration_multiplier": 3.5, "success": 0.78},
	{"id": "pine_wind", "name": "솔바람", "family": "nature", "preferred_customer": "elf", "order": 42, "returns": 5, "recipes": [], "cost": 500000, "sale_price": 260, "ingredients": {"herb": 2, "frost_flower": 1, "silver_moss": 1}, "duration_multiplier": 3.6, "success": 0.78},
	{"id": "aurora_elixir", "name": "오로라의 물약", "family": "arcane", "preferred_customer": "mage", "order": 43, "returns": 8, "recipes": ["warmth", "thin_ice", "pine_wind"], "cost": 900000, "sale_price": 370, "ingredients": {"herb": 2, "frost_flower": 1, "star_seed": 1, "crystal_herb": 1}, "duration_multiplier": 3.9, "success": 0.76},
]
var seed_value := 73129
var mode := "baseline"
var hours := 6.0
var warmup := 3600
var check_every := 300
var out := ""
var price_scale := 1.0
var cost_scale := 1.0
var start_gold := 3000000
var no_garden := false
var region_open := false
var trip := {"running": false, "elapsed": 0.0, "duration": 0.0, "rewards": {}}
var rng := RandomNumberGenerator.new()
var reward_total := {}
var events := []
var injected := false

func _initialize() -> void: call_deferred("run")

func parse() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): seed_value = int(arg.split("=")[1])
		if arg.begins_with("--mode="): mode = arg.split("=")[1]
		if arg.begins_with("--hours="): hours = float(arg.split("=")[1])
		if arg.begins_with("--check="): check_every = int(arg.split("=")[1])
		if arg.begins_with("--out="): out = arg.split("=", true, 1)[1]
		if arg.begins_with("--price="): price_scale = float(arg.split("=")[1])
		if arg.begins_with("--cost="): cost_scale = float(arg.split("=")[1])
		if arg.begins_with("--gold="): start_gold = int(arg.split("=")[1])
		if arg.begins_with("--env="): MATERIAL.environment = arg.split("=")[1]
		if arg.begins_with("--growth="): MATERIAL.growth_seconds = int(arg.split("=")[1])
		if arg == "--no-garden": no_garden = true
		if arg.begins_with("--complete="): REGION.complete = int(arg.split("=")[1])

func late_store() -> RefCounted:
	var s: RefCounted = F.completed_store(seed_value, "final", "both3", "normal")
	s.progression.reputation = maxi(int(s.progression.reputation), 130000)
	s.gold = 50000000
	for level in range(1, 4): assert(s.workshop.purchase(s, level).ok)
	for track in s.aging.TRACKS:
		while s.aging.view(s, track).can_buy: assert(s.aging.purchase(s, track, int(s.aging.view(s, track).next_level)).ok)
	for track in s.keeper.upgrades.TRACKS:
		while s.keeper.upgrades.view(s, track).can_buy: assert(s.keeper.upgrades.purchase(s, track, int(s.keeper.upgrades.view(s, track).next_level)).ok)
	s.gold = start_gold
	return s

## Live F26 content finished, same as measure_connected.gd --mode=complete.
func finish_f26(s: RefCounted) -> void:
	var ex: RefCounted = s.progression.expansion
	ex.regions.append("dawn_lighthouse")
	ex.returns["dawn_lighthouse"] = 8
	State.Progression.Expeditions.ensure(s.progression)
	for id in F26:
		s.progression.owned.append(id)
		ex.grant_recipe(id)
	ex.materials["dawn_bloom"] = ex.special_capacity()
	ex.first_batches.clear()

func inject_catalog() -> void:
	Content.DATA["materials"].append(MATERIAL.duplicate(true))
	for row in POTIONS:
		var data := {"id": row.id, "name": row.name, "family": row.family, "preferred_customer": row.preferred_customer, "order": row.order, "existing": false, "owned_at_start": false,
			"unlock": {"discovery": {"region": REGION.id, "returns": row.returns}, "recipes": row.recipes}, "cost": int(row.cost * cost_scale), "sale_price": int(round(row.sale_price * price_scale)),
			"ingredients": row.ingredients.duplicate(), "duration_multiplier": row.duration_multiplier, "success": row.success, "environment": MATERIAL.environment, "environment_bonus": 0.08,
			"grant_material": "frost_flower", "grant_sources": row.ingredients.keys().filter(func(m): return m != "herb" and (not no_garden or m != "frost_flower"))}
		Content.DATA["potions"].append(data)
		Content.RECIPES[row.id] = {"name": row.name, "cost": data.cost, "reputation": 0, "price": data.sale_price, "duration": row.duration_multiplier, "success": row.success, "color": "c6aeed"}
	Content.LOOKUPS.clear()
	injected = true

func buy_recipe(s: RefCounted, id: String, cost: int) -> void:
	s.gold -= cost
	s.progression.totals["manual_spent"] += cost
	s.progression.owned.append(id)
	s.progression.expansion.grant_recipe(id)

func roll() -> Dictionary:
	var result := {REGION.main: rng.randi_range(REGION.min, REGION.max)}
	var extras: Array = REGION.extra.duplicate()
	var weights: Array = [60, 30, 10]
	var count := 2 if rng.randf() < 0.25 else 1
	for i in count:
		var total := 0
		for w in weights: total += int(w)
		var choice := rng.randf() * total
		var picked := weights.size() - 1
		for index in weights.size():
			choice -= int(weights[index])
			if choice < 0:
				picked = index
				break
		result[extras[picked]] = rng.randi_range(1, 2)
		extras.remove_at(picked)
		weights.remove_at(picked)
	return result

func expedition_step(s: RefCounted, dt: float, time: float) -> void:
	if not region_open: return
	var ex: RefCounted = s.progression.expansion
	if trip.running:
		trip.elapsed += dt
		if trip.elapsed + 0.000001 >= trip.duration:
			trip.running = false
			ex.returns[REGION.id] = int(ex.returns.get(REGION.id, 0)) + 1
			for m in trip.rewards:
				ex.pending[m] = int(ex.pending.get(m, 0)) + int(trip.rewards[m])
				reward_total[m] = int(reward_total.get(m, 0)) + int(trip.rewards[m])
			if int(ex.returns[REGION.id]) == int(REGION.complete): events.append({"time": time, "event": "survey_complete"})
	if trip.running: return
	var returns := int(ex.returns.get(REGION.id, 0))
	if returns >= int(REGION.complete):
		var count: int = s.material_count(REGION.main) + int(ex.pending.get(REGION.main, 0))
		if count + int(REGION.max) > ex.special_capacity() or count > ex.special_capacity() * 0.5: return
	if s.gold - int(REGION.fee) < 30: return
	s.gold -= int(REGION.fee)
	s.total_spent_expeditions += int(REGION.fee)
	var reduction := minf(0.3, ex.effect("expedition_path", "trip_time_reduction") + ex.effect("expedition_guide", "trip_time_reduction"))
	trip.duration = (float(REGION.explore) + float(REGION["return"])) * (1.0 - reduction)
	trip.elapsed = 0.0
	trip.running = true
	trip.rewards = roll()

func purchases(s: RefCounted, time: float) -> void:
	if not region_open and s.gold >= int(REGION.cost * cost_scale):
		s.gold -= int(REGION.cost * cost_scale)
		s.progression.totals["manual_spent"] += int(REGION.cost * cost_scale)
		region_open = true
		events.append({"time": time, "event": "region_open", "cost": int(REGION.cost * cost_scale)})
	if not region_open: return
	var returns := int(s.progression.expansion.returns.get(REGION.id, 0))
	for row in POTIONS:
		if s.progression.owned.has(row.id) or returns < int(row.returns): continue
		var ready := true
		for need in row.recipes:
			if not s.progression.owned.has(need): ready = false
		var cost := int(row.cost * cost_scale)
		if ready and s.gold >= cost:
			buy_recipe(s, row.id, cost)
			events.append({"time": time, "event": "recipe", "id": row.id, "cost": cost})

func sold_counts(s: RefCounted, ids: Array) -> Dictionary:
	var sold := {}
	for id in ids: sold[id] = int(s.progression.by_potion.get(Content.potion_name(id), 0))
	return sold

func snapshot(s: RefCounted, time: float) -> Dictionary:
	var ex: RefCounted = s.progression.expansion
	var stock := {}
	for m in ["frost_flower", "dawn_bloom", "star_seed", "crystal_herb", "silver_moss", "ash_sage", "moonflower"]:
		stock[m] = s.material_count(m) if not Content.lookup("materials", m).is_empty() else 0
	return {"time": time, "gold": s.gold, "manual_spent": int(s.progression.totals.manual_spent), "retail": int(s.total_sales_gold), "retail_sold": int(s.total_sold),
		"contract_paid": int(s.contracts.totals.paid), "aging_revenue": int(s.aging.totals.revenue), "aging_sold": int(s.aging.totals.sold), "materials": int(s.total_spent_materials),
		"fees": int(s.total_spent_expeditions), "new_sold": sold_counts(s, POTIONS.map(func(r): return r.id)) if injected else {}, "f26_sold": sold_counts(s, F26),
		"stock": stock, "returns": int(ex.returns.get(REGION.id, 0)), "failed": int(s.progression.totals.failed), "reputation": int(s.progression.reputation),
		"dawn_bloom_rewards": int(ex.reward_totals.get("dawn_bloom", 0))}

func run() -> void:
	parse()
	rng.seed = seed_value
	var s := late_store()
	for i in int(warmup / 30): s.advance(30)
	if mode != "pre_f26": finish_f26(s)
	if mode in ["complete", "progress"]: inject_catalog()
	if mode == "complete":
		region_open = true
		s.progression.expansion.returns[REGION.id] = int(REGION.complete)
		for row in POTIONS: buy_recipe(s, row.id, 0)
		if not no_garden: s.progression.expansion.materials["frost_flower"] = s.progression.expansion.special_capacity()
		s.progression.expansion.first_batches.clear()
	var start := snapshot(s, 0)
	var windows := [start]
	var steps := int(hours * 3600 / 30)
	for i in steps:
		var time := float((i + 1) * 30)
		if mode == "progress" and int(time - 30) % check_every == 0: purchases(s, time - 30)
		s.advance(30)
		expedition_step(s, 30.0, time)
		if int(time) % 1800 == 0: windows.append(snapshot(s, time))
	var report := {"seed": seed_value, "mode": mode, "hours": hours, "warmup": warmup, "check_every": check_every, "price_scale": price_scale, "cost_scale": cost_scale,
		"environment": MATERIAL.environment, "growth_seconds": MATERIAL.growth_seconds, "no_garden": no_garden, "complete_returns": REGION.complete,
		"windows": windows, "events": events, "region_rewards": reward_total, "synthetic_start": true}
	if not out.is_empty():
		var file := FileAccess.open(out, FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	var last: Dictionary = windows[-1]
	var net: int = (int(last.gold) + int(last.manual_spent)) - (int(start.gold) + int(start.manual_spent))
	print("F27 %s seed%d net/h %d events %d new %s" % [mode, seed_value, int(net / hours), events.size(), str(last.new_sold)])
	quit()
