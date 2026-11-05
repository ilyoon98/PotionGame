extends SceneTree
## F27 post-connection check (2026-11-05). Same synthetic late store and warm-up as probe_f27_economy.gd, but the
## aurora snowfield, frost flower and four recipes now come from data/ and scripts/ (real parallel expeditions, real
## reward rolls, real planter). Both modes first finish the live F26 content exactly like the probe (= today's end):
##   baseline: F26 finished, F27 not bought
##   complete: + aurora snowfield surveyed (8 returns), four F27 recipes owned, frost flower planter granted, storage full
## Nothing is saved; never touches a player save. art/ has .gdignore, so pass this file's absolute path:
##   Godot --headless --path <project> --script <abs path> -- --mode=complete --seed=73129 --hours=6 --out=<json>
const State = preload("res://scripts/shop_state.gd")
const Content = preload("res://scripts/shop_content.gd")
const F = preload("res://tests/late_investment_fixture.gd")
const F26 := ["sunrise", "beacon", "sea_spray", "sun_moon_elixir"]
const NEW := ["warmth", "thin_ice", "pine_wind", "aurora_elixir"]
var seed_value := 73129
var mode := "baseline"
var hours := 6.0
var out := ""

func _initialize() -> void: call_deferred("run")

func late_store() -> RefCounted:
	var s: RefCounted = F.completed_store(seed_value, "final", "both3", "normal")
	s.progression.reputation = maxi(int(s.progression.reputation), 130000)
	s.gold = 50000000
	for level in range(1, 4): assert(s.workshop.purchase(s, level).ok)
	for track in s.aging.TRACKS:
		while s.aging.view(s, track).can_buy: assert(s.aging.purchase(s, track, int(s.aging.view(s, track).next_level)).ok)
	for track in s.keeper.upgrades.TRACKS:
		while s.keeper.upgrades.view(s, track).can_buy: assert(s.keeper.upgrades.purchase(s, track, int(s.keeper.upgrades.view(s, track).next_level)).ok)
	s.gold = 3000000
	return s

func finish(s: RefCounted, region: String, ids: Array, material: String) -> void:
	var ex: RefCounted = s.progression.expansion
	ex.regions.append(region)
	ex.returns[region] = 8
	State.Progression.Expeditions.ensure(s.progression)
	for id in ids:
		s.progression.owned.append(id)
		ex.grant_recipe(id)
	ex.materials[material] = ex.special_capacity()
	ex.first_batches.clear()

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): seed_value = int(arg.split("=")[1])
		if arg.begins_with("--mode="): mode = arg.split("=")[1]
		if arg.begins_with("--hours="): hours = float(arg.split("=")[1])
		if arg.begins_with("--out="): out = arg.split("=", true, 1)[1]
	var s := late_store()
	for i in 120: s.advance(30)
	var ex: RefCounted = s.progression.expansion
	finish(s, "dawn_lighthouse", F26, "dawn_bloom")
	if mode == "complete": finish(s, "aurora_snowfield", NEW, "frost_flower")
	var start := {"gold": s.gold, "spent": int(s.progression.totals.manual_spent), "sold": {}, "rewards": int(ex.reward_totals.get("frost_flower", 0)), "fees": int(s.total_spent_expeditions)}
	for id in NEW + F26: start.sold[id] = int(s.progression.by_potion.get(Content.potion_name(id), 0))
	for i in int(hours * 3600 / 30): s.advance(30)
	var net: int = (s.gold + int(s.progression.totals.manual_spent)) - (int(start.gold) + int(start.spent))
	var sold := {}
	for id in NEW + F26: sold[id] = int(s.progression.by_potion.get(Content.potion_name(id), 0)) - int(start.sold[id])
	var report := {"seed": seed_value, "mode": mode, "hours": hours, "net_per_hour": int(net / hours), "sold": sold,
		"frost_flower_expedition_rewards": int(ex.reward_totals.get("frost_flower", 0)) - int(start.rewards), "aurora_returns": int(ex.returns.get("aurora_snowfield", 0)),
		"fees_per_hour": int((int(s.total_spent_expeditions) - int(start.fees)) / hours),
		"supply_frost_flower": int(s.late_investments.totals.get("frost_flower", 0))}
	if not out.is_empty():
		var file := FileAccess.open(out, FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	print("F27 CONNECTED %s seed%d net/h %d sold %s" % [mode, seed_value, report.net_per_hour, str(sold)])
	quit()
