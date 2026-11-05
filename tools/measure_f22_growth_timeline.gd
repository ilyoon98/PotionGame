extends SceneTree
## F22 growth timeline: regulars points and economy at play-time checkpoints.
## Fresh State.new() (0 gold), actual production advance(30). The return-time
## purchase policy is the existing F21 growth path (measure_f21_aux --mode=growth
## --return=30 --aging): contracts negotiated/accepted, original purchases in the
## recipe_first recommendation order, late investments, aging bought when
## affordable, workshop upgrades. Optional --variant=keeper_auto adds bed/herb tea
## purchases and the busiest rested work policy (F21 --keeper --policy=auto).
## Decor is never bought (cosmetic). Never reads or writes user:// or player saves.
const State = preload("res://scripts/shop_state.gd")
const Content = preload("res://scripts/shop_content.gd")
const Rare = preload("res://scripts/rare_recipes.gd")
const F = preload("res://tests/late_investment_fixture.gd")
const M = preload("res://tests/contracts_fixture.gd")
const ROOT := "res://.verification/f22-growth-timeline-20261105"
const CHECKPOINTS := [600, 1800, 3600, 7200, 10800, 18000, 28800, 43200, 86400]
const CUSTOMER_IDS := ["traveler", "mage", "elf", "rogue"]
var seed_value := 73129
var variant := "aging"
var hours := 24
var failures: Array[String] = []


func _initialize() -> void: call_deferred("run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)


func recipe_counts(s: RefCounted) -> Dictionary:
	var owned := 0
	var total := 0
	var start := 0
	for row in Content.DATA.potions:
		if row.get("owned_at_start", false):
			start += 1
			continue
		total += 1
		if s.progression.owned.has(row.id): owned += 1
	var specials := 0
	for row in Rare.ROWS:
		if Rare.is_owned(row.id, s.progression): specials += 1
	return {"bought": owned, "bought_total": total, "starting": start, "specials": specials, "specials_total": Rare.ROWS.size(), "held_including_starting": start + owned}


func operating_net(s: RefCounted) -> int:
	# Income minus running costs; excludes direct investments (manual_spent).
	return s.total_sales_gold + int(s.contracts.totals.paid) - s.total_spent_materials - s.total_spent_expeditions


func snapshot(s: RefCounted, time: int, sales: Dictionary, preferred: Dictionary) -> Dictionary:
	var customers := {}
	for id in CUSTOMER_IDS:
		customers[id] = {"points": s.regulars.points_of(id), "stage": s.regulars.stage(id), "sales": int(sales.get(id, 0)), "preferred_sales": int(preferred.get(id, 0)), "visits": int(s.progression.by_customer.get(id, 0))}
	return {"time": time, "gold": s.gold, "operating_net_total": operating_net(s), "manual_spent": int(s.progression.totals.manual_spent), "reputation": int(s.progression.reputation), "regions_completed": s.progression.completed_regions(), "recipes": recipe_counts(s), "retail_sold": s.total_sold, "retail_revenue": s.total_sales_gold, "contract_paid": int(s.contracts.totals.paid), "material_cost": s.total_spent_materials, "expedition_fees": s.total_spent_expeditions, "aging_revenue": int(s.aging.totals.revenue), "late_stages": s.late_investments.stages.duplicate(), "workshop_level": s.workshop.level, "keeper_policy": s.keeper.policy, "original_complete": F.complete_original(s), "customers": customers}


func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): seed_value = int(arg.trim_prefix("--seed="))
		if arg.begins_with("--variant="): variant = arg.trim_prefix("--variant=")
		if arg.begins_with("--hours="): hours = clampi(int(arg.trim_prefix("--hours=")), 1, 48)
	if not variant in ["aging", "keeper_auto"]:
		push_error("variant must be aging or keeper_auto"); quit(1); return
	var started_msec := Time.get_ticks_msec()
	var s := State.new()
	s.progression.seed_value = seed_value; s.progression.expansion.rare_seed = seed_value; s.contracts.seed = seed_value
	check(s.gold == 0, "Growth starts with zero gold")
	var initial := {"retail_revenue": s.total_sales_gold, "contract_paid": int(s.contracts.totals.paid), "material_cost": s.total_spent_materials, "fees": s.total_spent_expeditions, "manual_spent": int(s.progression.totals.manual_spent), "gold": s.gold}
	var sales := {}; var preferred := {}
	var decisions := []; var trades := []
	var windows := [] # every 10 minutes
	var checkpoints := []
	var crossings := {} # customer -> {points threshold -> first time}
	var ladder := [1, 5, 10, 15, 20, 30, 40, 50, 60, 80, 100, 150, 200, 300, 400, 500, 750, 1000, 1500, 2000, 3000, 5000, 7500, 10000, 15000, 20000, 30000, 50000]
	for id in CUSTOMER_IDS: crossings[id] = {}
	var stage_events := []
	var milestones := {}
	var previous_window_net := 0
	var previous_window_gold := 0
	var duration := hours * 3600
	var steps := duration / 30
	for i in steps:
		var event: Dictionary = s.advance(30)
		var time := (i + 1) * 30
		for item in event.get("potion_events", []):
			if item.kind == "sale" or item.kind == "aged_sale":
				var id: String = Content.CUSTOMERS[int(item.customer)].id
				sales[id] = int(sales.get(id, 0)) + 1
				if item.preferred: preferred[id] = int(preferred.get(id, 0)) + 1
		for item in event.get("regular_events", []):
			stage_events.append({"time": time, "customer": item.customer, "stage": item.stage})
		check(s.gold == int(initial.gold) + s.total_sales_gold - int(initial.retail_revenue) + int(s.contracts.totals.paid) - int(initial.contract_paid) - s.total_spent_materials + int(initial.material_cost) - s.total_spent_expeditions + int(initial.fees) - int(s.progression.totals.manual_spent) + int(initial.manual_spent), "Cash reconciles every 30 s at %d" % time)
		for id in CUSTOMER_IDS:
			var value: int = s.regulars.points_of(id)
			for threshold in ladder:
				if value >= threshold and not crossings[id].has(str(threshold)): crossings[id][str(threshold)] = time
		# Return-time decisions every 30 s, identical order to measure_f21_aux growth.
		F.negotiate_returns(s, "relationship", trades)
		F.purchase_original(s, "recipe_first", decisions)
		F.purchase_late(s, decisions)
		for track in s.Aging.TRACKS:
			while s.aging.view(s, track).can_buy:
				var item: Dictionary = s.aging.view(s, track)
				check(s.aging.purchase(s, track, int(item.next_level)).ok, "Aging purchase")
				decisions.append({"action": "aging_purchase", "track": track, "time": time, "level": item.next_level, "cost": item.cost})
		if variant == "keeper_auto":
			for track in s.keeper.upgrades.TRACKS:
				while s.keeper.upgrades.view(s, track).can_buy:
					var item: Dictionary = s.keeper.upgrades.view(s, track)
					check(s.keeper.upgrades.purchase(s, track, int(item.next_level)).ok, "Keeper purchase")
					decisions.append({"action": "keeper_purchase", "track": track, "time": time, "level": item.next_level, "cost": item.cost})
			for policy in ["allnighter", "busy", "regular"]:
				if not s.keeper_policy_reason(policy).is_empty() or not s.keeper.daily(policy).fresh: continue
				if policy != s.keeper.policy:
					check(s.set_keeper_policy(policy), "Keeper policy")
					decisions.append({"action": "keeper_policy", "policy": policy, "time": time})
				break
		for attempt in 3:
			var item: Dictionary = s.workshop.view(s)
			if not item.can_buy: break
			check(s.workshop.purchase(s, int(item.next_level)).ok, "Workshop purchase")
			decisions.append({"action": "workshop_purchase", "time": time, "stage": s.workshop.level, "cost": item.cost})
		if s.contracts.unlocked(s) and not milestones.has("contracts_unlocked"): milestones.contracts_unlocked = time
		if F.complete_original(s) and not milestones.has("original_complete"): milestones.original_complete = time
		if time % 600 == 0:
			var snap := snapshot(s, time, sales, preferred)
			var net := int(snap.operating_net_total)
			snap["window_10m_operating_net"] = net - previous_window_net
			snap["window_10m_operating_net_per_min"] = (net - previous_window_net) / 10.0
			snap["window_10m_cash_change"] = s.gold - previous_window_gold
			previous_window_net = net
			previous_window_gold = s.gold
			windows.append(snap)
			if time in CHECKPOINTS: checkpoints.append(snap)
		if time % 21600 == 0:
			print("F22 TIMELINE seed%d %s %.0fh gold%d" % [seed_value, variant, time / 3600.0, s.gold])
			await process_frame
	for id in CUSTOMER_IDS:
		check(s.regulars.points_of(id) == int(sales.get(id, 0)) + 2 * int(preferred.get(id, 0)), "Points equal sales + 2 x preferred for " + id)
	var report := {"seed": seed_value, "variant": variant, "seconds": duration, "policy": "Fresh State.new() at 0 gold, actual advance(30). Every 30 s: contracts relationship->payment negotiation, original purchases (recipe_first ranking, F19/F20/F21 fixture), late investments, aging bought when affordable, workshop upgrades" + (", bed/herb tea bought when affordable + busiest rested work policy" if variant == "keeper_auto" else ", keeper stays regular, no bed/tea") + ". Decor never bought.", "operating_net_definition": "retail sales + contract paid - material cost - expedition fees (excludes direct investments)", "regulars_thresholds_current": [1, 15, 60, 150], "decor_costs_current": [120, 240], "checkpoints": checkpoints, "windows_10m": windows, "threshold_crossings": crossings, "stage_events": stage_events, "milestones": milestones, "purchases": decisions, "wall_seconds": (Time.get_ticks_msec() - started_msec) / 1000.0, "failures": failures, "passed": failures.is_empty()}
	M.write_json(ROOT + "/runs/%s-seed%d.json" % [variant, seed_value], report)
	print("%s F22 TIMELINE seed%d %s hours%d wall%.1fs" % ["PASS" if failures.is_empty() else "FAIL", seed_value, variant, hours, report.wall_seconds])
	quit(0 if failures.is_empty() else 1)
