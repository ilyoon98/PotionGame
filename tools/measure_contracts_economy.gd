extends SceneTree
## F18 initial-balance comparison. Synthetic fixtures only; no user:// reads/writes.
const State = preload("res://scripts/shop_state.gd")
const Content = preload("res://scripts/shop_content.gd")
const F = preload("res://tests/contracts_fixture.gd")
const OUT := "res://.verification/contracts-f18-20261015/economy.json"
const SEEDS := [1, 73129, 4444]
const SCENARIOS := ["normal", "materials_empty", "inventory_full"]
const POLICIES := ["none", "basic", "payment", "relationship"]
const DEFAULT_SECONDS := 1800
var failures: Array[String] = []
var mature := false
var mature_hour := false
var mature_long := false
var candidate_margin45 := false
var actual_rules := {}


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)


func decisions(state: RefCounted, policy: String, log: Array) -> void:
	if policy == "none": return
	for partner in state.contracts.PARTNERS:
		var view: Dictionary = state.contracts.partner_view(state, partner.id)
		var current: Dictionary = view.negotiation
		if current.accepted: continue
		var chosen := "payment" if policy == "relationship" and view.grade == 4 else policy
		var option := option_for(view, chosen)
		if chosen != "basic" and option.can_negotiate:
			var result: Dictionary = state.contracts.negotiate(state, partner.id, option.token)
			log.append({"time": state.progression.clock, "partner": partner.id, "grade": view.grade, "requested": policy, "negotiation": result.duplicate(true)})
			check(result.get("ok", false), "Synthetic economy policy negotiation is permitted")
			view = state.contracts.partner_view(state, partner.id)
			option = option_for(view, chosen)
		if not option.can_accept:
			option = view.options[0] # One failed improved offer falls back to basic; never rerolls.
		if option.can_accept:
			var accepted: Dictionary = state.contracts.accept(state, partner.id, option.token)
			check(accepted.get("ok", false), "Synthetic economy policy acceptance is permitted")
			log.append({"time": state.progression.clock, "partner": partner.id, "grade": view.grade, "accepted": option.id, "result": accepted.duplicate(true)})


func option_for(view: Dictionary, id: String) -> Dictionary:
	for option in view.options:
		if option.id == id: return option
	return {}


func rules_snapshot() -> Dictionary:
	var model := State.new()
	var multipliers := {}
	for rank in range(1, 5):
		multipliers[str(rank)] = {}
		for kind in model.contracts.OPTIONS:
			if rank == 4 and kind == "relationship": continue
			multipliers[str(rank)][kind] = model.contracts._multiplier({"grade": rank, "option": kind})
	var hashes := {}
	for path in ["res://scripts/shop_contracts.gd", "res://scripts/shop_state.gd", "res://scripts/shop_progression.gd", "res://scripts/shop_expansion.gd", "res://scripts/parallel_expeditions.gd", "res://scripts/rare_recipes.gd", "res://data/content_expansion.json", "res://tools/measure_contracts_economy.gd", "res://tests/contracts_fixture.gd"]:
		hashes[path] = FileAccess.get_sha256(path)
	return {"condition_version": model.contracts.VERSION, "save_version": State.SAVE_VERSION, "multipliers": multipliers, "thresholds": model.contracts.THRESHOLDS, "basic_quantities": model.contracts.QUANTITIES, "training_costs": model.contracts.TRAINING_COSTS, "allocation": "Four ordinary actual starts then one shared contract slot; common-inventory-full exception can start contract directly", "source_sha256": hashes, "godot": Engine.get_version_info().string, "measurement_time_utc": Time.get_datetime_string_from_system(true)}


func fixture(seed_value: int, scenario: String, policy: String) -> RefCounted:
	var source := F.completed(seed_value)
	source.contracts.seed = seed_value
	source.contracts.training = 3
	if scenario == "materials_empty": F.clear_materials(source)
	if scenario == "inventory_full":
		for index in source.capacity():
			source.inventory.append(["eternity", "sage_elixir", "worldtree_elixir", "shadow_elixir", "rare_nebula_distillate"][index % 5])
		source.stock = source.inventory.size()
	var state := State.new()
	check(state.load_data(F.data(source)), "Completed all-owned fixture roundtrips before economics")
	if mature and policy != "none":
		# Valid past deliveries establish terminal agreements without simulating
		# hours of growth. They are outside every measured income/material delta.
		for partner in state.contracts.PARTNERS:
			check(state.contracts.accept(state, partner.id, option_for(state.contracts.partner_view(state, partner.id), "basic").token).get("ok", false), "Mature synthetic history starts with a valid agreement")
			while state.contracts.grade(partner.id) < 4:
				finish_synthetic_round(state, partner.id)
		var setup_log: Array = []
		decisions(state, policy, setup_log)
		for partner in state.contracts.PARTNERS:
			finish_synthetic_round(state, partner.id) # Apply accepted grade4 after the old round.
			check(state.contracts.partners[partner.id].round.terms.grade == 4, "Mature fixture begins its measured round under grade4 terms")
		state.gold = 1000000
		var validated := State.new()
		check(validated.load_data(F.data(state)), "Completed terminal-grade synthetic history passes strict save validation")
		state = validated
	return state


func finish_synthetic_round(state: RefCounted, partner: String) -> void:
	var current_id: String = state.contracts.partners[partner].round.id
	while state.contracts.partners[partner].round.id == current_id:
		var current: Dictionary = state.contracts.partners[partner].round
		var selected := ""
		var best := -1
		for id in current.allowed:
			var family: String = current.allowed[id].family
			var order: int = Content.lookup("potions", id).order
			if current.shipped[family] < current.requirements[family] and order > best:
				selected = id
				best = order
		check(not selected.is_empty(), "Terminal synthetic history has an unfinished allowed family")
		if selected.is_empty(): return
		state.contracts.batch = {"purpose": "contract", "partner": partner, "round_id": current_id, "kind": false if selected == "health" else true if selected == "mana" else selected}
		check(state.contracts.complete(state, state.contracts.batch.kind).get("ok", false), "Terminal synthetic history completes a real module reservation once")


func simulate(seed_value: int, scenario: String, policy: String, seconds: int) -> Dictionary:
	var state := fixture(seed_value, scenario, policy)
	var initial_data := F.data(state)
	var starting := F.materials(state)
	var consumed := {}
	var purchased := {}
	var ordinary_kinds := {}
	var shipped_kinds := {}
	var shipped_families := {}
	var starts := {"ordinary": 0, "contract": 0}
	var sales := 0
	var retail_gold := 0
	var contract_gold := 0
	var contract_shipped := 0
	var round_finishes: Array = []
	var per_partner_finish := {}
	var customer_wait := 0.0
	var material_wait := 0.0
	var inventory_full_time := 0.0
	var empty_sale_attempts := 0
	var policy_log: Array = []
	decisions(state, policy, policy_log)
	for time in seconds:
		decisions(state, policy, policy_log)
		var events: Dictionary = state.advance(1.0)
		for started in events.get("batch_events", []):
			var purpose: String = started.purpose
			check(starts.has(purpose), "Only ordinary and contract batch purposes are emitted")
			starts[purpose] = int(starts.get(purpose, 0)) + 1
			F.add_counts(consumed, started.ingredients)
		for event in events.get("potion_events", []):
			check(event.kind in ["brew", "sale"], "Retail animation channel has no contract event")
			if event.kind == "sale":
				sales += 1
				retail_gold += int(event.gold)
				var id := F.potion_id(event.mana)
				ordinary_kinds[id] = int(ordinary_kinds.get(id, 0)) + 1
		for event in events.get("contract_events", []):
			var id := F.potion_id(event.kind)
			check(not id.begins_with("rare_"), "Special potions remain outside contractual deliveries")
			var family: String = Content.lookup("potions", id).family
			contract_shipped += int(event.get("shipped", 0))
			contract_gold += int(event.get("paid", 0))
			shipped_kinds[id] = int(shipped_kinds.get(id, 0)) + int(event.get("shipped", 0))
			shipped_families[family] = int(shipped_families.get(family, 0)) + int(event.get("shipped", 0))
			if int(event.get("rounds", 0)) > 0:
				var previous: float = float(per_partner_finish.get(event.partner, 0.0))
				round_finishes.append({"time_upper_bound": time + 1, "partner": event.partner, "round_id": event.completed_round, "seconds_since_previous_round": time + 1 - previous, "payout": event.paid})
				per_partner_finish[event.partner] = time + 1
		purchased.moon_mushroom = int(purchased.get("moon_mushroom", 0)) + int(events.get("bought", 0))
		customer_wait += float(events.get("customer_wait_seconds", 0.0))
		material_wait += float(events.get("material_wait_seconds", 0.0))
		inventory_full_time += float(events.get("full_seconds", 0.0))
		empty_sale_attempts += int(events.get("empty_sale_attempts", 0))
	var ending := F.materials(state)
	var generated := {}
	for id in starting:
		generated[id] = int(ending[id]) - int(starting[id]) + int(consumed.get(id, 0)) - int(purchased.get(id, 0))
		check(generated[id] >= 0, "Material conservation has no unexplained loss: " + id)
	var fees: int = state.total_spent_expeditions - int(initial_data.total_spent_expeditions)
	var cost: int = state.total_spent_materials - int(initial_data.total_spent_materials)
	var net := retail_gold + contract_gold - cost - fees
	check(state.gold - int(initial_data.gold) == net, "Economy gold reconciles retail + contract - purchases - trip fees exactly")
	check(state.total_sold - int(initial_data.total_sold) == sales and state.total_sales_gold - int(initial_data.total_sales_gold) == retail_gold, "Retail statistics exclude contract shipping/payment")
	check(int(state.contracts.totals.shipped) - int(initial_data.contracts.totals.shipped) == contract_shipped and int(state.contracts.totals.paid) - int(initial_data.contracts.totals.paid) == contract_gold, "Contract totals match only the separate contract event stream")
	if policy == "none": check(starts.contract == 0 and contract_gold == 0 and contract_shipped == 0, "No-contract control keeps all started batches retail")
	var unsettled_base := 0
	var unsettled_estimate := 0
	var unsettled_exact := 0.0
	for partner in state.contracts.PARTNERS:
		var projection: Dictionary = state.contracts.partner_view(state, partner.id)
		unsettled_base += int(projection.round.get("base_total", 0))
		unsettled_estimate += int(projection.estimate)
		unsettled_exact += int(projection.round.get("base_total", 0)) * float(projection.multiplier)
	return {"seed": seed_value, "scenario": scenario, "policy": policy, "mature_grade4": mature, "seconds": seconds, "resolution_seconds": 1, "starting_gold": initial_data.gold, "ending_gold": state.gold, "starting_materials": starting, "ending_materials": ending, "generated_materials_excluding_purchases": generated, "purchased_materials": purchased, "consumed_materials_actual_reservations": consumed, "batch_starts_including_failures": starts, "retail_sales": sales, "retail_income": retail_gold, "retail_sold_by_kind": ordinary_kinds, "contract_shipped": contract_shipped, "contract_income": contract_gold, "contract_shipped_by_kind": shipped_kinds, "contract_shipped_by_family": shipped_families, "unsettled_contract_base": unsettled_base, "unsettled_contract_estimate_rounded_per_partner": unsettled_estimate, "unsettled_contract_value_exact": unsettled_exact, "net_plus_unsettled_contract_value": net + unsettled_exact, "round_completions": round_finishes, "rounds_completed": round_finishes.size(), "customer_wait_seconds": customer_wait, "material_wait_seconds": material_wait, "inventory_full_seconds": inventory_full_time, "empty_sale_attempts": empty_sale_attempts, "material_cost": cost, "expedition_fees": fees, "net_income": net, "failed_batches": state.progression.totals.failed, "policy_decisions": policy_log, "initial_contract_totals": initial_data.contracts.totals, "final_contracts": state.contracts.to_data()}


func run() -> void:
	var seconds := DEFAULT_SECONDS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="): seconds = maxi(1, int(arg.trim_prefix("--seconds=")))
		if arg == "--mature": mature = true
		if arg == "--mature-hour":
			mature = true
			mature_hour = true
		if arg == "--mature-long":
			mature = true
			mature_long = true
		if arg == "--margin45": candidate_margin45 = true
	if mature_hour: seconds = 3600
	if mature_long: seconds = 7200
	var selected_policies: Array = ["none", "basic", "payment"] if mature_hour or mature_long else POLICIES
	actual_rules = rules_snapshot()
	if candidate_margin45:
		check(is_equal_approx(float(actual_rules.multipliers["1"].basic), 1.60) and is_equal_approx(float(actual_rules.multipliers["4"].payment), 2.10), "margin45 evidence records the actual approved +45 percentage-point rules")
	print("F18 ACTUAL RULES " + JSON.stringify(actual_rules))
	var rows: Array = []
	for scenario in (["normal"] if mature else SCENARIOS):
		for seed_value in SEEDS:
			for policy in selected_policies:
				var row := simulate(seed_value, scenario, policy, seconds)
				rows.append(row)
				print("F18 ECONOMY %s seed=%d %s retail=%d contract=%d shipped=%d rounds=%d net=%d" % [scenario, seed_value, policy, row.retail_income, row.contract_income, row.contract_shipped, row.rounds_completed, row.net_income])
	var output := OUT.replace(".json", "-mature-long.json") if mature_long else OUT.replace(".json", "-mature-hour.json") if mature_hour else OUT.replace(".json", "-mature.json") if mature else OUT
	if candidate_margin45: output = output.get_base_dir().path_join("margin45").path_join(output.get_file())
	F.write_json(output, {"purpose": "F18 initial development-balance comparison; synthetic data, not final balance approval", "safety": "Only in-memory fake fixtures; workspace output; no player save or GUI", "method": "Same completed all-owned/all-special fixture per seed/scenario; initial negotiation training3. Policies accept the named improved condition when available, fall back to basic once after failure, and accept new current-grade opportunities without rerolls. Relationship requests payment at final grade4, where relationship is intentionally unavailable. Mature mode establishes valid past deliveries and grade4 agreements outside measured deltas, retaining identical gold/materials/upgrades/retail RNG at the measured start. All decisions and actual starts are recorded. Generated materials are the conservation residual end-start+reserved-purchased, including cultivation and expedition arrivals. Round times have at most one second measurement rounding.", "actual_rules": actual_rules, "candidate_margin45": candidate_margin45, "seeds": SEEDS, "scenarios": ["normal"] if mature else SCENARIOS, "policies": selected_policies, "seconds_per_run": seconds, "mature_grade4": mature, "runs": rows, "failures": failures, "passed": failures.is_empty()})
	if failures.is_empty(): print("PASS F18 economic comparison: %d runs; exact gold/material/retail/contract reconciliation" % rows.size())
	else: print("FAIL F18 economic comparison: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
