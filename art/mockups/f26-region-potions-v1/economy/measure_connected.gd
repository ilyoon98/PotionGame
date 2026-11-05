extends SceneTree
## F26 post-connection check (2026-11-05). Same synthetic late store and warm-up as probe_f26_economy.gd, but
## the dawn lighthouse, dawn bloom and four recipes now come from data/ and scripts/ (real parallel expeditions,
## real reward rolls, real planter). Modes: baseline (F26 not bought) | complete (region surveyed, four recipes,
## planter granted, dawn bloom storage full). Nothing is saved; never touches a player save.
##   Godot --headless --path <project> --script <this file> -- --mode=complete --seed=73129 --hours=6 --out=<json>
const State = preload("res://scripts/shop_state.gd")
const Content = preload("res://scripts/shop_content.gd")
const F = preload("res://tests/late_investment_fixture.gd")
const NEW := ["sunrise", "beacon", "sea_spray", "sun_moon_elixir"]
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

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): seed_value = int(arg.split("=")[1])
		if arg.begins_with("--mode="): mode = arg.split("=")[1]
		if arg.begins_with("--hours="): hours = float(arg.split("=")[1])
		if arg.begins_with("--out="): out = arg.split("=", true, 1)[1]
	var s := late_store()
	for i in 120: s.advance(30)
	var ex: RefCounted = s.progression.expansion
	if mode == "complete":
		ex.regions.append("dawn_lighthouse")
		ex.returns["dawn_lighthouse"] = 8
		State.Progression.Expeditions.ensure(s.progression)
		for id in NEW:
			s.progression.owned.append(id)
			ex.grant_recipe(id)
		ex.materials["dawn_bloom"] = ex.special_capacity()
		ex.first_batches.clear()
	var start := {"gold": s.gold, "spent": int(s.progression.totals.manual_spent), "sold": {}, "rewards": int(ex.reward_totals.get("dawn_bloom", 0))}
	for id in NEW: start.sold[id] = int(s.progression.by_potion.get(Content.potion_name(id), 0))
	for i in int(hours * 3600 / 30): s.advance(30)
	var net: int = (s.gold + int(s.progression.totals.manual_spent)) - (int(start.gold) + int(start.spent))
	var sold := {}
	for id in NEW: sold[id] = int(s.progression.by_potion.get(Content.potion_name(id), 0)) - int(start.sold[id])
	var report := {"seed": seed_value, "mode": mode, "hours": hours, "net_per_hour": int(net / hours), "new_sold": sold,
		"dawn_bloom_expedition_rewards": int(ex.reward_totals.get("dawn_bloom", 0)) - int(start.rewards), "dawn_returns": int(ex.returns.get("dawn_lighthouse", 0)),
		"supply_dawn_bloom": int(s.late_investments.totals.get("dawn_bloom", 0))}
	if not out.is_empty():
		var file := FileAccess.open(out, FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	print("F26 CONNECTED %s seed%d net/h %d sold %s" % [mode, seed_value, report.net_per_hour, str(sold)])
	quit()
