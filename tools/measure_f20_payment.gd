extends SceneTree
## Actual production advancement; only synthetic initial conditions/user returns.
const State = preload("res://.verification/f20-20261020/payment-fixed-model/scripts/shop_state.gd")
const F = preload("res://.verification/f20-20261020/payment-fixed-model/tests/late_investment_fixture.gd")
const M = preload("res://.verification/f20-20261020/payment-fixed-model/tests/contracts_fixture.gd")
const ROOT := "res://.verification/f20-20261020/payment-fixed"
var mode := "effects"
var seed_value := 73129
var return_seconds := 30
var control := false
func _initialize() -> void: call_deferred("run")
func snapshot(s: RefCounted) -> Dictionary:
	return {"time": s.progression.clock, "gold": s.gold, "manual_spent": s.progression.totals.manual_spent, "retail_revenue": s.total_sales_gold, "retail_sold": s.total_sold, "contract_paid": s.contracts.totals.paid, "contract_shipped": s.contracts.totals.shipped, "material_cost": s.total_spent_materials, "fees": s.total_spent_expeditions, "workshop_level": s.workshop.level, "late_stages": s.late_investments.stages.duplicate(), "unpaid": F.unpaid_value(s)}
func material_check(initial: Dictionary, s: RefCounted, consumed: Dictionary, supplied: Dictionary, bought: int) -> Dictionary:
	var generated := {}
	for id in initial:
		var amount: int = s.material_count(id) - int(initial[id]) + int(consumed.get(id, 0)) - int(supplied.get(id, 0)) - (bought if id == "moon_mushroom" else 0)
		assert(amount >= 0, "Material conservation, including both reserved batches and failures: " + id)
		generated[id] = amount
	return generated
func effects() -> void:
	for scenario in ["normal", "scarce_upper"]:
		for stage in range(1, 4):
			var s := F.completed_store(seed_value, "final", "both3", scenario)
			s.gold = 10000000
			for next in range(1, stage + 1): assert(s.workshop.purchase(s, next).ok)
			s.gold = 1000000 # Separate setup money from all measured income.
			var initial := snapshot(s); var ingredients: Dictionary = M.materials(s)
			var consumed := {}; var supplied := {}; var bought := 0; var retail_brewed := 0
			var starts := []; var settlements := []; var timeline := []
			var metrics := {"zero_stock_seconds": 0.0, "customer_wait_seconds": 0.0, "material_wait_seconds": 0.0, "inventory_seconds": 0.0, "main_activity_seconds": 0.0, "aux_activity_seconds": 0.0, "aux_material_wait_seconds": 0.0, "protection_seconds": 0.0}
			for i in 240:
				var event: Dictionary = s.advance(30)
				for key in metrics: metrics[key] += float(event.get(key, 0))
				for item in event.batch_events:
					M.add_counts(consumed, item.ingredients)
					var row: Dictionary = item.duplicate(true); row["time_upper"] = (i+1)*30; starts.append(row)
				for item in event.supply_events: supplied[item.material] = int(supplied.get(item.material, 0)) + int(item.quantity)
				bought += int(event.bought)
				for item in event.potion_events:
					if item.kind == "brew": retail_brewed += 1
				for item in event.contract_events:
					if item.paid > 0:
						var row: Dictionary = item.duplicate(true); row["time_upper"] = (i+1)*30; settlements.append(row)
				assert(s.gold == int(initial.gold) + s.total_sales_gold - int(initial.retail_revenue) + int(s.contracts.totals.paid)-int(initial.contract_paid) - s.total_spent_materials + int(initial.material_cost) - s.total_spent_expeditions + int(initial.fees))
				if (i+1)%30 == 0: timeline.append(snapshot(s))
			var generated := material_check(ingredients, s, consumed, supplied, bought)
			assert(retail_brewed - s.total_sold + int(initial.retail_sold) == s.stock, "Only ordinary completion feeds retail inventory")
			var report := {"seed": seed_value, "scenario": scenario, "stage": stage, "seconds": 7200, "initial": initial, "final": snapshot(s), "net": s.gold - int(initial.gold), "metrics": metrics, "mean_stock": float(metrics.inventory_seconds)/7200.0, "material_start": ingredients, "material_end": M.materials(s), "consumed": consumed, "supplied": supplied, "bought_mushrooms": bought, "generated": generated, "actual_batch_starts": starts, "settlements": settlements, "windows": timeline, "passed": true, "initial_state_is_synthetic": true}
			M.write_json(ROOT + "/effects/%d-%s-stage%d.json" % [seed_value, scenario, stage], report)
			print("F20 EFFECT %d %s stage%d net%d aux%.1fs zero%.1fs" % [seed_value, scenario, stage, report.net, metrics.aux_activity_seconds, metrics.zero_stock_seconds])
			await process_frame
func growth() -> void:
	var s := State.new()
	s.progression.seed_value = seed_value; s.progression.expansion.rare_seed = seed_value; s.contracts.seed = seed_value
	var returning := mode == "returning"
	if returning:
		s = F.completed_store(seed_value, "final", "both3", "normal"); s.gold = 2700000
	var initial := snapshot(s); var ingredient_start: Dictionary = M.materials(s)
	var decisions := []; var trades := []; var windows := []; var milestones := {}
	var consumed := {}; var supplied := {}; var bought := 0
	var previous_purchase := 0.0; var maximum_gap := 0.0
	var output_name := "%s-seed%d-return%d" % [mode, seed_value, return_seconds] + ("-control" if control else "")
	for i in 5760: #48 actual simulated hours, including after completion.
		var event: Dictionary = s.advance(30)
		var time := (i+1)*30
		for item in event.batch_events: M.add_counts(consumed, item.ingredients)
		for item in event.supply_events: supplied[item.material] = int(supplied.get(item.material, 0)) + int(item.quantity)
		bought += int(event.bought)
		assert(s.gold == int(initial.gold) + s.total_sales_gold-int(initial.retail_revenue) + int(s.contracts.totals.paid)-int(initial.contract_paid) - s.total_spent_materials+int(initial.material_cost) - s.total_spent_expeditions+int(initial.fees) - int(s.progression.totals.manual_spent)+int(initial.manual_spent), "Actual cash reconciles every30sec")
		if s.contracts.unlocked(s) and not milestones.has("contracts_unlocked"): milestones.contracts_unlocked = snapshot(s)
		if time % return_seconds == 0:
			var count := decisions.size()
			F.negotiate_returns(s, "relationship", trades)
			F.purchase_original(s, "recipe_first", decisions)
			F.purchase_late(s, decisions)
			if not control:
				for attempt in 3:
					var item: Dictionary = s.workshop.view(s)
					if not item.can_buy: break
					var gold_before: int = s.gold
					assert(s.workshop.purchase(s, int(item.next_level)).ok)
					decisions.append({"action": "workshop_purchase", "time": time, "stage": s.workshop.level, "cost": item.cost, "gold_before": gold_before, "gold_after": s.gold})
			if decisions.size() > count:
				maximum_gap = maxf(maximum_gap, time - previous_purchase)
				previous_purchase = time
			if F.complete_original(s) and not milestones.has("original_complete"): milestones.original_complete = snapshot(s)
			if s.late_investments.stages.values().all(func(stage): return int(stage) == 3) and not milestones.has("f19_complete"): milestones.f19_complete = snapshot(s)
			if s.workshop.view(s).unlocked and not milestones.has("workshop_unlocked"): milestones.workshop_unlocked = snapshot(s)
			if s.workshop.level == 3 and not milestones.has("f20_complete"): milestones.f20_complete = snapshot(s)
		if time % 900 == 0: windows.append(snapshot(s))
		if time in [86400, 129600, 172800]: milestones["balance_%dh" % (time/3600)] = snapshot(s)
		if time % 21600 == 0:
			print("F20 GROWTH %s %.0fh gold%d F19%s F20%d" % [output_name, time/3600.0, s.gold, str(s.late_investments.stages), s.workshop.level])
			M.write_json(ROOT+"/growth-progress/"+output_name+".json", {"time": time, "snapshot": snapshot(s), "milestones": milestones})
			await process_frame
	maximum_gap = maxf(maximum_gap, 172800.0-previous_purchase)
	var generated := material_check(ingredient_start, s, consumed, supplied, bought)
	M.write_json(ROOT+"/growth/"+output_name+".json", {"seed": seed_value, "return_seconds": return_seconds, "training_target": 0, "protected_f19_control": control, "synthetic_returning_2700000": returning, "seconds": 172800, "initial": initial, "final": snapshot(s), "milestones": milestones, "purchases": decisions, "trades": trades, "windows_15m": windows, "max_purchase_gap_including_final_wait": maximum_gap, "unfinished_goal_wait": 172800.0-previous_purchase if s.workshop.level < 3 and not control else 0.0, "material_start": ingredient_start, "material_end": M.materials(s), "consumed": consumed, "supplied": supplied, "bought_mushrooms": bought, "generated": generated, "passed": true})
	print("F20 GROWTH PASS " + output_name)
func run() -> void:
	assert(DisplayServer.get_name() == "headless")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="): mode = arg.trim_prefix("--mode=")
		if arg.begins_with("--seed="): seed_value = int(arg.trim_prefix("--seed="))
		if arg.begins_with("--return="): return_seconds = int(arg.trim_prefix("--return="))
		if arg == "--control": control = true
	assert(mode in ["effects", "growth", "returning"] and return_seconds in [30, 900] and seed_value in [73129,19337,9973])
	if mode != "effects":
		var name := "%s-seed%d-return%d" % [mode, seed_value, return_seconds] + ("-control" if control else "")
		if FileAccess.file_exists(ROOT + "/growth/" + name + ".json"):
			print("PRESERVED completed case " + name); quit(); return
		DirAccess.make_dir_recursive_absolute(ROOT + "/growth-locks")
		if DirAccess.make_dir_absolute(ROOT + "/growth-locks/" + name) != OK:
			print("SKIP already claimed case " + name); quit(); return
	if mode == "effects": await effects()
	else: await growth()
	quit()
