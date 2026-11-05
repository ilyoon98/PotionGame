extends SceneTree
## F26 candidate economy probe (planning evidence, not a runtime/test tool). Real ShopState advancement on a
## synthetic late store (tests/late_investment_fixture.gd completed_store + F20 workshop 3 + aging + keeper
## upgrades, reputation 130,000). The candidate catalog rows are injected in memory only; data/ and scripts/ are
## untouched and nothing is saved. Region 9 is not added to Content.DATA.regions (expedition_rewards.gd POOLS is a
## const), so its trips are simulated here with the same rules: paid departure, 30% time cap, main 6-8 + extras
## 60/30/10, 25% second extra, refill only while stock+pending <= 50% after the survey.
## Run (art/ has .gdignore, so pass the file path):
##   Godot_v4.6-stable_win64_console.exe --headless --path <project> --script <this file> -- --mode=baseline|complete|progress
##     --seed=73129 --hours=6 [--check=300] [--gold=3000000] [--price=1.0] [--cost=1.0] --out=<json path>
const State = preload("res://scripts/shop_state.gd")
const Content = preload("res://scripts/shop_content.gd")
const F = preload("res://tests/late_investment_fixture.gd")

var REGION := {"id": "dawn_lighthouse", "explore": 450.0, "return": 90.0, "complete": 8, "fee": 150, "cost": 400000,
	"main": "dawn_bloom", "min": 6, "max": 8, "extra": ["star_seed", "moonflower", "dewgrass"]}
var MATERIAL := {"id": "dawn_bloom", "name": "여명초", "source": "recipe_granted_garden", "region": "dawn_lighthouse", "growth_seconds": 26, "capacity": 12, "environment": "clear", "favored_growth_multiplier": 1.5, "seed_quantity": 2}
var POTIONS := [
	{"id": "sunrise", "name": "해돋이", "family": "vitality", "preferred_customer": "traveler", "order": 36, "returns": 1, "recipes": [], "cost": 250000, "sale_price": 200, "ingredients": {"herb": 2, "dawn_bloom": 1, "dewgrass": 1}, "duration_multiplier": 3.1, "success": 0.82},
	{"id": "beacon", "name": "등대불", "family": "craft", "preferred_customer": "rogue", "order": 37, "returns": 3, "recipes": [], "cost": 350000, "sale_price": 215, "ingredients": {"herb": 2, "dawn_bloom": 1, "mist_mushroom": 1}, "duration_multiplier": 3.2, "success": 0.80},
	{"id": "sea_spray", "name": "물보라", "family": "nature", "preferred_customer": "elf", "order": 38, "returns": 5, "recipes": [], "cost": 450000, "sale_price": 230, "ingredients": {"herb": 2, "dawn_bloom": 1, "blue_reed": 1}, "duration_multiplier": 3.3, "success": 0.80},
	{"id": "sun_moon_elixir", "name": "일월의 물약", "family": "arcane", "preferred_customer": "mage", "order": 39, "returns": 8, "recipes": ["sunrise", "beacon", "sea_spray"], "cost": 800000, "sale_price": 320, "ingredients": {"herb": 2, "dawn_bloom": 1, "moonflower": 1, "star_seed": 1}, "duration_multiplier": 3.6, "success": 0.78},
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
var region_open := false
var trip := {"running": false, "elapsed": 0.0, "duration": 0.0, "rewards": {}}
var rng := RandomNumberGenerator.new()
var reward_total := {}
var events := []

func _initialize() -> void: call_deferred("run")

func parse() -> void:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--seed="): seed_value = int(arg.split("=")[1])
		if arg.begins_with("--mode="): mode = arg.split("=")[1]
		if arg.begins_with("--hours="): hours = float(arg.split("=")[1])
		if arg.begins_with("--check="): check_every = int(arg.split("=")[1])
		if arg.begins_with("--out="): out = arg.split("=", true, 1)[1]
		if arg.begins_with("--price="): price_scale = float(arg.split("=")[1])
		if arg.begins_with("--cost="): cost_scale = float(arg.split("=")[1])
		if arg.begins_with("--gold="): start_gold = int(arg.split("=")[1])
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

func inject_catalog() -> void:
	Content.DATA["materials"].append(MATERIAL.duplicate(true))
	for row in POTIONS:
		var data := {"id": row.id, "name": row.name, "family": row.family, "preferred_customer": row.preferred_customer, "order": row.order, "existing": false, "owned_at_start": false,
			"unlock": {"discovery": {"region": REGION.id, "returns": row.returns}, "recipes": row.recipes}, "cost": int(row.cost * cost_scale), "sale_price": int(round(row.sale_price * price_scale)),
			"ingredients": row.ingredients.duplicate(), "duration_multiplier": row.duration_multiplier, "success": row.success, "environment": "clear", "environment_bonus": 0.08,
			"grant_material": "dawn_bloom", "grant_sources": row.ingredients.keys().filter(func(m): return m != "herb")}
		Content.DATA["potions"].append(data)
		Content.RECIPES[row.id] = {"name": row.name, "cost": data.cost, "reputation": 0, "price": data.sale_price, "duration": row.duration_multiplier, "success": row.success, "color": "c6aeed"}
	Content.LOOKUPS.clear()

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

func snapshot(s: RefCounted, time: float) -> Dictionary:
	var sold := {}
	for row in POTIONS: sold[row.id] = int(s.progression.by_potion.get(row.name, 0))
	return {"time": time, "gold": s.gold, "manual_spent": int(s.progression.totals.manual_spent), "retail": int(s.total_sales_gold), "retail_sold": int(s.total_sold),
		"contract_paid": int(s.contracts.totals.paid), "aging_revenue": int(s.aging.totals.revenue), "aging_sold": int(s.aging.totals.sold), "materials": int(s.total_spent_materials),
		"fees": int(s.total_spent_expeditions), "new_sold": sold, "dawn_bloom": s.material_count("dawn_bloom") if Content.lookup("materials", "dawn_bloom").size() > 0 else 0,
		"returns": int(s.progression.expansion.returns.get(REGION.id, 0)), "failed": int(s.progression.totals.failed), "reputation": int(s.progression.reputation)}

func run() -> void:
	parse()
	rng.seed = seed_value
	var s := late_store()
	for i in int(warmup / 30): s.advance(30)
	if mode != "baseline": inject_catalog()
	if mode == "complete":
		region_open = true
		s.progression.expansion.returns[REGION.id] = int(REGION.complete)
		for row in POTIONS: buy_recipe(s, row.id, 0)
		s.progression.expansion.materials["dawn_bloom"] = s.progression.expansion.special_capacity()
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
		"complete_returns": REGION.complete, "windows": windows, "events": events, "region_rewards": reward_total, "synthetic_start": true}
	var file := FileAccess.open(out, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	var last: Dictionary = windows[-1]
	var net: int = (int(last.gold) + int(last.manual_spent)) - (int(start.gold) + int(start.manual_spent))
	print("F26 %s seed%d net/h %d events %d" % [mode, seed_value, int(net / hours), events.size()])
	quit()
