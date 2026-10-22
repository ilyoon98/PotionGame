extends SceneTree
## F19 effect-only comparisons. The million-gold fixture is never growth evidence.
const State = preload("res://scripts/shop_state.gd")
const F = preload("res://tests/late_investment_fixture.gd")
const Materials = preload("res://tests/contracts_fixture.gd")
const DIR := "res://.verification/late-investment-f19-20261019"
var seed_value := 73129
var terms := "final"
var scenario := "normal"
var combo := "none"
var tag := "initial"
var duration := 7200
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func metadata(state: RefCounted) -> Dictionary:
	var hashes := {}
	for path in ["scripts/shop_state.gd", "scripts/shop_contracts.gd", "scripts/shop_late_investments.gd", "scripts/shop_progression.gd", "scripts/shop_expansion.gd", "scripts/parallel_expeditions.gd", "scripts/rare_recipes.gd", "data/content_expansion.json", "tools/measure_late_investments.gd", "tests/late_investment_fixture.gd"]:
		if FileAccess.file_exists("res://" + path): hashes[path] = FileAccess.get_sha256("res://" + path)
	var agreements := {}
	for partner in state.contracts.PARTNERS:
		var value: Dictionary = state.contracts.partners[partner.id]
		agreements[partner.id] = {"achieved_grade": state.contracts.grade(partner.id), "agreement": value.agreement.duplicate(true), "current_round": value.round.id, "multiplier": state.contracts._multiplier(value.round.terms)}
	return {"source_sha256": hashes, "save_version": State.SAVE_VERSION, "engine": Engine.get_version_info().string, "agreements": agreements, "late_state_at_start": state.late_investments.to_data(), "supply_view_at_start": state.late_investments.supply_view(state), "supply_investment_view": state.late_investments.view(state, "supply_support"), "batch_investment_view": state.late_investments.view(state, "contract_batch")}


func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): seed_value = int(arg.trim_prefix("--seed="))
		if arg.begins_with("--terms="): terms = arg.trim_prefix("--terms=")
		if arg.begins_with("--scenario="): scenario = arg.trim_prefix("--scenario=")
		if arg.begins_with("--combo="): combo = arg.trim_prefix("--combo=")
		if arg.begins_with("--tag="): tag = arg.trim_prefix("--tag=")
		if arg.begins_with("--seconds="): duration = maxi(1, int(arg.trim_prefix("--seconds=")))
	check(terms in ["standard", "final"] and scenario in ["normal", "scarce_upper", "inventory_full"] and combo in ["none", "support1", "support2", "support3", "bulk1", "bulk2", "bulk3", "both1", "both2", "both3"], "Only explicit synthetic F19 comparison cases are accepted")
	check(not tag.is_empty() and tag.is_valid_filename() and not tag.contains(".") and not tag.contains("/"), "Evidence tag is a dedicated directory name")
	if not failures.is_empty(): quit(1); return
	var path := DIR.path_join("effects").path_join(tag).path_join("%s-%s-seed%d-%s.json" % [terms, scenario, seed_value, combo])
	if FileAccess.file_exists(path):
		print("PRESERVED existing F19 evidence: " + path)
		quit()
		return
	var state := F.completed_store(seed_value, terms, combo, scenario)
	var initial := {"gold": state.gold, "sales": state.total_sales_gold, "contracts": state.contracts.totals.paid, "materials": state.total_spent_materials, "fees": state.total_spent_expeditions, "manual": state.progression.totals.manual_spent, "shipped": state.contracts.totals.shipped, "brewed": state.progression.totals.brewed, "failed": state.progression.totals.failed}
	var source_metadata := metadata(state)
	var starting_materials := Materials.materials(state)
	var consumed := {}
	var supplied := {}
	var bought := {}
	var starts := {"ordinary": 0, "contract": 0}
	var reserved_bottles := {"ordinary": 0, "contract": 0}
	var failed_reserved_bottles := {"ordinary": 0, "contract": 0}
	var quantity_distribution := {}
	var shipped_kinds := {}
	var shipped_families := {}
	var retail_income := 0
	var retail_brewed := 0
	var retail_sold := 0
	var contract_income := 0
	var completed_rounds: Array = []
	var supply_arrivals: Array = []
	var waits := {"customer": 0.0, "materials": 0.0, "stock_full": 0.0, "inventory_ratio_integral": 0.0}
	var elapsed := 0
	while elapsed < duration:
		var delta := mini(30, duration - elapsed)
		var event: Dictionary = state.advance(delta)
		elapsed += delta
		for started in event.get("batch_events", []):
			var purpose: String = started.purpose
			var quantity: int = started.get("quantity", 1)
			starts[purpose] += 1
			reserved_bottles[purpose] += quantity
			if not started.get("success", true): failed_reserved_bottles[purpose] += quantity
			if purpose == "contract": quantity_distribution[str(quantity)] = int(quantity_distribution.get(str(quantity), 0)) + 1
			else: check(quantity == 1, "Ordinary and special retail batches remain one bottle")
			Materials.add_counts(consumed, started.ingredients)
		for arrived in event.get("supply_events", []):
			supplied[arrived.material] = int(supplied.get(arrived.material, 0)) + int(arrived.quantity)
			supply_arrivals.append({"time_upper_bound": elapsed, "material": arrived.material, "quantity": arrived.quantity, "reserved_quantity": arrived.get("reserved_quantity", 0)})
		bought.moon_mushroom = int(bought.get("moon_mushroom", 0)) + int(event.get("bought", 0))
		for sale in event.get("potion_events", []):
			check(sale.kind in ["brew", "sale"], "Contract batches never enter the retail animation channel")
			if sale.kind == "sale":
				retail_income += int(sale.gold)
				retail_sold += 1
			else: retail_brewed += 1
		for sent in event.get("contract_events", []):
			var id := Materials.potion_id(sent.kind)
			var family: String = State.Content.lookup("potions", id).family
			shipped_kinds[id] = int(shipped_kinds.get(id, 0)) + int(sent.shipped)
			shipped_families[family] = int(shipped_families.get(family, 0)) + int(sent.shipped)
			contract_income += int(sent.paid)
			if int(sent.rounds) > 0: completed_rounds.append({"time_upper_bound": elapsed, "partner": sent.partner, "round_id": sent.completed_round, "paid": sent.paid})
		waits.customer += float(event.get("customer_wait_seconds", 0.0))
		waits.materials += float(event.get("material_wait_seconds", 0.0))
		waits.stock_full += float(event.get("full_seconds", 0.0))
		waits.inventory_ratio_integral += float(event.get("inventory_ratio_seconds", 0.0))
		check(state.gold == F.cash_identity(state, int(initial.gold), initial), "Effect-fixture cash ledger reconciles actual income/costs, excluding synthetic setup")
	var ending_materials := Materials.materials(state)
	var generated := {}
	for material in starting_materials:
		generated[material] = int(ending_materials[material]) - int(starting_materials[material]) + int(consumed.get(material, 0)) - int(supplied.get(material, 0)) - int(bought.get(material, 0))
		check(generated[material] >= 0, "Actual reservation/supply/purchase material ledger has no unexplained loss: " + material)
	var material_cost: int = state.total_spent_materials - int(initial.materials)
	var fees: int = state.total_spent_expeditions - int(initial.fees)
	var net := retail_income + contract_income - material_cost - fees
	check(net == state.gold - int(initial.gold), "Realized operating net equals the measured gold change")
	check(state.total_sales_gold - int(initial.sales) == retail_income and int(state.contracts.totals.paid) - int(initial.contracts) == contract_income, "Retail and contract income remain separate and exact")
	var active_quantity: int = int(state.contracts.batch.get("quantity", 1)) if state.brew_active else 0
	check(int(reserved_bottles.ordinary) + int(reserved_bottles.contract) == int(state.progression.totals.brewed) - int(initial.brewed) + int(state.progression.totals.failed) - int(initial.failed) + active_quantity, "Reserved actual bottles equal completed successes, failed consumption, and the one in-progress batch")
	var initial_stock: int = state.capacity() if scenario == "inventory_full" else 0
	check(initial_stock + retail_brewed - retail_sold == state.stock, "Only real retail bottles affect common inventory and customer sale counts")
	var report := {"scope": "F19 completed-store effect fixture only; synthetic initial gold/history are NOT a reached growth balance", "method": "Setup uses real stage purchases outside measured cash, then explicitly resets the effect fixture to one million gold. Normal means full ingredients plus empty ordinary stock (also covers low stock). Scarce-upper zeros star_seed/moonflower/ash_sage/crystal_herb. Thirty-second advance blocks retain actual batch/supply events; completion timestamps have30-second upper-bound resolution. Agreements stay fixed during measurement.", "seed": seed_value, "terms": terms, "scenario": scenario, "combo": combo, "tag": tag, "seconds": duration, "metadata": source_metadata, "initial": initial, "ending_gold": state.gold, "retail_income": retail_income, "contract_income": contract_income, "material_cost": material_cost, "expedition_cost": fees, "realized_net": net, "exact_unpaid_contract_value": F.unpaid_value(state), "cash_plus_exact_unpaid_net": net + F.unpaid_value(state), "batch_starts": starts, "reserved_bottles": reserved_bottles, "failed_reserved_bottles_by_judgement": failed_reserved_bottles, "average_contract_bottles_per_started_batch": float(reserved_bottles.contract) / maxi(1, starts.contract), "contract_quantity_distribution": quantity_distribution, "actual_shipped_by_kind": shipped_kinds, "actual_shipped_by_family": shipped_families, "actual_contract_shipped": int(state.contracts.totals.shipped) - int(initial.shipped), "actual_brewed_bottles": int(state.progression.totals.brewed) - int(initial.brewed), "actual_failed_bottles": int(state.progression.totals.failed) - int(initial.failed), "completed_rounds": completed_rounds, "actual_supplied_by_material": supplied, "actual_supply_arrivals": supply_arrivals, "starting_materials": starting_materials, "ending_materials": ending_materials, "actual_reserved_consumption_including_failures": consumed, "purchased_materials": bought, "other_generated_materials": generated, "waits": waits, "ending_inventory": state.inventory_order(), "ending_stock": state.stock, "ending_contracts": state.contracts.to_data(), "ending_late_state": state.late_investments.to_data(), "checks": checks, "failures": failures, "passed": failures.is_empty()}
	F.write_json(path, report)
	print("%s F19 EFFECT %s %s seed=%d %s net=%d exactWIP=%.3f avgBatch=%.3f supplied=%s" % ["PASS" if failures.is_empty() else "FAIL", terms, scenario, seed_value, combo, net, report.exact_unpaid_contract_value, report.average_contract_bottles_per_started_batch, JSON.stringify(supplied)])
	quit(0 if failures.is_empty() else 1)
