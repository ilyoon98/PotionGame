extends SceneTree
## F19 real-cost synthetic growth. Never reads user:// or any player snapshot.
const State = preload("res://scripts/shop_state.gd")
const F = preload("res://tests/late_investment_fixture.gd")
const Materials = preload("res://tests/contracts_fixture.gd")
const DIR := "res://.verification/late-investment-f19-20261019"
var seed_value := 73129
var return_seconds := 30
var training_target := 0
var duration := 64800
var tag := "final"
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func snapshot(state: RefCounted) -> Dictionary:
	var grades := {}
	for partner in state.contracts.PARTNERS: grades[partner.id] = state.contracts.grade(partner.id)
	var goals := []
	for track in F.TRACKS: goals.append(state.late_investments.view(state, track).duplicate(true))
	return {"time": state.progression.clock, "gold": state.gold, "original_remaining": F.remaining(state), "late_stages": state.late_investments.stages.duplicate(true), "grades": grades, "training_actual": state.contracts.training, "training_view": state.contracts.training_view(state), "next_late_goals": goals, "sales_income": state.total_sales_gold, "contract_income": state.contracts.totals.paid, "material_cost": state.total_spent_materials, "expedition_cost": state.total_spent_expeditions, "manual_spent": state.progression.totals.manual_spent, "contract_shipped": state.contracts.totals.shipped, "cash_plus_exact_unpaid": state.gold + F.unpaid_value(state)}


func metadata() -> Dictionary:
	var hashes := {}
	for path in ["scripts/shop_state.gd", "scripts/shop_contracts.gd", "scripts/shop_late_investments.gd", "scripts/shop_progression.gd", "scripts/shop_expansion.gd", "scripts/parallel_expeditions.gd", "scripts/rare_recipes.gd", "data/content_expansion.json", "tools/measure_late_growth.gd", "tests/late_investment_fixture.gd"]:
		if FileAccess.file_exists("res://" + path): hashes[path] = FileAccess.get_sha256("res://" + path)
	return {"source_sha256": hashes, "save_version": State.SAVE_VERSION, "engine": Engine.get_version_info().string}


func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): seed_value = int(arg.trim_prefix("--seed="))
		if arg.begins_with("--return="): return_seconds = int(arg.trim_prefix("--return="))
		if arg.begins_with("--training="): training_target = clampi(int(arg.trim_prefix("--training=")), 0, 3)
		if arg.begins_with("--seconds="): duration = maxi(1, int(arg.trim_prefix("--seconds=")))
		if arg.begins_with("--tag="): tag = arg.trim_prefix("--tag=")
	check(return_seconds in [30, 900], "Only30-second and15-minute return policies are simulated")
	check(not tag.is_empty() and tag.is_valid_filename() and not tag.contains(".") and not tag.contains("/"), "Growth proof tag stays in a dedicated workspace directory")
	if not failures.is_empty(): quit(1); return
	var state := State.new()
	state.progression.seed_value = seed_value
	state.progression.expansion.rare_seed = seed_value
	state.contracts.seed = seed_value
	check(state.gold == 0, "Growth really starts with zero gold")
	var starting_materials := Materials.materials(state)
	var consumed := {}
	var supplied := {}
	var bought := {}
	var decisions: Array = []
	var windows: Array = []
	var milestones := {}
	var trade_log: Array = []
	var last_checkpoint := 0
	var actual_seconds := 0
	var previous_stage := state.late_investments.stages.duplicate()
	var report := {"scope": "Fresh zero-gold growth with actual original purchases, manual return-time contracts/training/late investments; no initial million-gold fixture", "policy": "At each return: train toward the chosen target while valid/affordable, manually negotiate relationship until grade4 then payment, original recipe-first purchases, then lowest-stage late investment with supply tie-break. This simulates user decisions and does not add automatic buying to production.", "seed": seed_value, "return_seconds": return_seconds, "training_target": training_target, "measurement_cap_seconds": duration, "passive_observation_resolution_seconds": 30, "metadata": metadata()}
	while actual_seconds < duration:
		var delta := mini(30, duration - actual_seconds)
		var event: Dictionary = state.advance(delta)
		actual_seconds += delta
		for started in event.get("batch_events", []): Materials.add_counts(consumed, started.ingredients)
		for arrived in event.get("supply_events", []): supplied[arrived.material] = int(supplied.get(arrived.material, 0)) + int(arrived.quantity)
		bought.moon_mushroom = int(bought.get("moon_mushroom", 0)) + int(event.get("bought", 0))
		check(state.gold == F.cash_identity(state), "Every30-second growth cash ledger reconciles actual sales/contracts/fees/manual investments")
		if state.contracts.unlocked(state) and not milestones.has("contracts_unlocked_observed"): milestones.contracts_unlocked_observed = snapshot(state)
		if F.complete_original(state) and not milestones.has("original_growth_complete_observed"): milestones.original_growth_complete_observed = snapshot(state)
		if actual_seconds % return_seconds == 0:
			F.train_to(state, training_target, decisions)
			F.negotiate_returns(state, "relationship", trade_log)
			F.purchase_original(state, "recipe_first", decisions)
			F.purchase_late(state, decisions)
			check(state.gold == F.cash_identity(state), "Return-time purchases debit real cash and manual investment totals exactly once")
			for track in F.TRACKS:
				if int(state.late_investments.stages[track]) != int(previous_stage[track]):
					milestones["%s_stage%d" % [track, int(state.late_investments.stages[track])]] = snapshot(state)
			previous_stage = state.late_investments.stages.duplicate()
			if F.complete_original(state) and not milestones.has("original_growth_complete_observed"): milestones.original_growth_complete_observed = snapshot(state)
		if actual_seconds >= last_checkpoint + 900:
			windows.append(snapshot(state))
			last_checkpoint = actual_seconds
		if actual_seconds == 32400:
			milestones.nine_hour_actual_growth = snapshot(state)
			F.write_json(DIR.path_join("growth-fixtures").path_join(tag).path_join("%d-return%d-training%d-9h.json" % [seed_value, return_seconds, training_target]), F.data(state))
		if F.TRACKS.all(func(track): return int(state.late_investments.stages[track]) == 3):
			if not milestones.has("all_late_complete"): milestones.all_late_complete = snapshot(state)
			if actual_seconds >= 32400: break
	var ending_materials := Materials.materials(state)
	var generated := {}
	for material in starting_materials:
		generated[material] = int(ending_materials[material]) - int(starting_materials[material]) + int(consumed.get(material, 0)) - int(supplied.get(material, 0)) - int(bought.get(material, 0))
		check(generated[material] >= 0, "Growth material ledger has no unexplained loss: " + material)
	report.merge({"actual_seconds": actual_seconds, "milestones": milestones, "windows_15m": windows, "purchases": decisions, "contract_decisions": trade_log, "starting_materials": starting_materials, "ending_materials": ending_materials, "actual_reserved_consumption_including_failures": consumed, "actual_late_supplies": supplied, "purchased_materials": bought, "other_generated_materials": generated, "final": snapshot(state), "all_late_completed": milestones.has("all_late_complete"), "checks": checks, "failures": failures, "passed": failures.is_empty()})
	var path := DIR.path_join("growth").path_join(tag).path_join("return%d-training%d-seed%d.json" % [return_seconds, training_target, seed_value])
	F.write_json(path, report)
	print("%s F19 GROWTH return=%d target_training=%d seed=%d hours=%.2f gold=%d completed=%s checks=%d" % ["PASS" if failures.is_empty() else "FAIL", return_seconds, training_target, seed_value, actual_seconds / 3600.0, state.gold, milestones.has("all_late_complete"), checks])
	quit(0 if failures.is_empty() else 1)
