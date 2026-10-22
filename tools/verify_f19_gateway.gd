extends SceneTree
## Workspace fixtures only: verify transactions without player files or OS input.
const Shop = preload("res://scripts/shop.gd")
const F = preload("res://tests/contracts_fixture.gd")
const Compare = preload("res://tests/state_compare.gd")
var checks := 0
var failures := 0
var writes := 0

func _initialize() -> void:
	set_meta("isolated_preview", true)
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func saved(ok: bool) -> bool:
	writes += 1
	return ok

func mature(state: RefCounted) -> void:
	var model: RefCounted = state.contracts
	var option: Dictionary = model.partner_view(state, "caravan").options[0]
	check(model.accept(state, "caravan", option.token).ok, "The fixture starts a real accepted agreement")
	while model.grade("caravan") < 4:
		var round_data: Dictionary = model.partners.caravan.round
		for index in 2:
			var family: String = model.PARTNERS[0].families[index]
			if round_data.shipped[family] >= round_data.requirements[family]: continue
			for id in round_data.allowed:
				if round_data.allowed[id].family != family: continue
				model.reserve({"partner": "caravan", "round_id": round_data.id, "id": id, "kind": false if id == "health" else true if id == "mana" else id, "family_index": index})
				model.complete(state, false if id == "health" else true if id == "mana" else id)
				break
			break

func run() -> void:
	if DisplayServer.get_name() != "headless":
		push_error("F19 gateway verification is headless only")
		quit(1)
		return
	var shop := Shop.new()
	root.add_child(shop)
	shop.set_process(false)
	if shop.art != null: shop.art.set_process(false)
	var state: RefCounted = F.completed()
	mature(state)
	state.gold = 3000000
	shop.state = state
	state.set_shop_open(false)
	check(state.late_investments.purchase(state, "supply_support", 1).ok, "A paid initial support cycle exists")
	state.late_investments.supply_tick(23.5)
	state.contracts.ordinary_batches = 4
	state._start_batch()
	state.brew_elapsed = state.brew_duration() * 0.25
	check(state.brew_active and state.contracts.batch.purpose == "contract" and state.contracts.batch.quantity == 1, "A real one-bottle shipment is already reserved")
	var late_identity: RefCounted = state.late_investments
	var contract_identity: RefCounted = state.contracts
	var progress_identity: RefCounted = state.progression
	shop.set_meta("late_save_fixture", func(): return saved(false))
	var before: Dictionary = state.to_data().duplicate(true)
	var result: Dictionary = shop.perform_late_investment_action("supply_support", 2)
	check(not result.ok and result.error.contains("저장 실패") and writes == 1, "A failed investment reports one failed write")
	check(Compare.equivalent(before, state.to_data()), "Failed support restores every stage, cycle, receipt, gold and investment field")
	check(shop.state == state and state.late_investments == late_identity and state.contracts == contract_identity and state.progression == progress_identity and not state.shop_open, "Rollback preserves all live identities, the closed shop and the active batch")
	shop.set_meta("late_save_fixture", func(): return saved(true))
	result = shop.perform_late_investment_action("supply_support", 2)
	check(result.ok and state.late_investments.stages.supply_support == 2 and state.gold == int(before.gold) - 300000, "The current next stage charges its exact cost once")
	check(state.late_investments.supply == before.late_investments.supply, "An upgrade preserves the current 23.5-second cycle and its original quantity")
	before = state.to_data().duplicate(true)
	var write_count := writes
	result = shop.perform_late_investment_action("supply_support", 2)
	check(not result.ok and writes == write_count and Compare.equivalent(before, state.to_data()), "Repeated stale stage cannot purchase the next price or save again")
	shop.set_meta("late_save_fixture", func(): return saved(false))
	result = shop.perform_late_investment_action("contract_batch", 1)
	check(not result.ok and Compare.equivalent(before, state.to_data()), "Failed bulk investment preserves the entire in-progress one-bottle reservation")
	shop.set_meta("late_save_fixture", func(): return saved(true))
	result = shop.perform_late_investment_action("contract_batch", 1)
	check(result.ok and state.late_investments.batch_max() == 2 and state.contracts.batch == before.contracts.batch, "Bulk purchase changes only future batch capacity")
	before = state.to_data().duplicate(true)
	shop.set_meta("contract_save_fixture", func(): return saved(false))
	result = shop.perform_contract_action("train", "", {"next_level": 1})
	check(not result.ok and result.error.contains("저장 실패") and Compare.equivalent(before, state.to_data()), "Training rollback accepts an existing frozen reservation under the new saved capacity")
	shop.set_meta("contract_save_fixture", func(): return saved(true))
	result = shop.perform_contract_action("train", "", {"next_level": 1})
	check(result.ok and state.contracts.training == 1 and state.gold == int(before.gold) - 8000, "Explicit training stage purchases once while future opportunities remain")
	before = state.to_data().duplicate(true)
	write_count = writes
	for malformed: Variant in [-1, 1, 1.5, "2", 4]:
		result = shop.perform_contract_action("train", "", {"next_level": malformed})
		check(not result.ok and writes == write_count and Compare.equivalent(before, state.to_data()), "Stale or invalid training level never changes another price")
	result = shop.perform_contract_action("train")
	check(not result.ok and writes == write_count and Compare.equivalent(before, state.to_data()), "The user-action gateway requires the displayed training level")
	check(not state.shop_open and shop.state == state and state.contracts == contract_identity, "Every transaction leaves the original closed game and contract object alive")
	shop.queue_free()
	await process_frame
	print("F19 GATEWAY %s: %d checks; one-cost transactions, stale levels, frozen cycle/batch, failed-save rollback, live identities, closed shop and future training; isolated only" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(1 if failures else 0)
