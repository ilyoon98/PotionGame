extends SceneTree
## Isolated user-action transactions: no real player path, OS input or GUI.
const Shop = preload("res://scripts/shop.gd")
const State = preload("res://scripts/shop_state.gd")
const Compare = preload("res://tests/state_compare.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	assert(DisplayServer.get_name() == "headless")
	set_meta("isolated_preview", true)
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func option(state: RefCounted, id: String, key: String) -> Dictionary:
	for row in state.contracts.partner_view(state, id).options:
		if row.id == key: return row.token.duplicate(true)
	return {}

func run() -> void:
	var shop := Shop.new()
	root.add_child(shop)
	shop.set_process(false)
	if shop.art != null: shop.art.set_process(false)
	check(shop.test_mode and shop.instance_bypassed, "Gateway runs only in the isolated fixture")
	var state: RefCounted = shop.state
	state.gold = 200000
	state.progression.expansion.regions = ["star_garden"]
	state.progression.owned.assign(["vigor", "focus", "growth", "clarity"])
	state.contracts.seed = 1
	state.set_shop_open(false)
	var identity: RefCounted = state
	var progress_identity: RefCounted = state.progression
	var contract_identity: RefCounted = state.contracts
	shop.set_meta("contract_save_fixture", func(): return false)
	var before: Dictionary = state.to_data().duplicate(true)
	var failed: Dictionary = shop.perform_contract_action("train", "", {"next_level": 1})
	check(not failed.ok and failed.error.contains("저장 실패"), "Failed training save is reported instead of success")
	check(Compare.equivalent(before, state.to_data()), "Failed training restores all gold, investment and model fields")
	check(not state.shop_open and shop.state == identity and state.progression == progress_identity and state.contracts == contract_identity, "Rollback preserves a closed shop and all live object identities")
	var token := option(state, "caravan", "payment")
	failed = shop.perform_contract_action("negotiate", "caravan", token)
	check(not failed.ok and failed.error.contains("저장 실패"), "Failed negotiation save never displays the result as committed")
	check(Compare.equivalent(before, state.to_data()), "Failed negotiation restores its separate RNG and opportunity")
	shop.set_meta("contract_save_fixture", func(): return true)
	var result: Dictionary = shop.perform_contract_action("negotiate", "caravan", token)
	check(result.ok and result.success, "The exact saved negotiation can succeed once")
	before = state.to_data().duplicate(true)
	result = shop.perform_contract_action("negotiate", "caravan", token)
	check(not result.ok and Compare.equivalent(before, state.to_data()), "Repeated attempt is rejected without saving or redrawing")
	shop.set_meta("contract_save_fixture", func(): return false)
	failed = shop.perform_contract_action("accept", "caravan", token)
	check(not failed.ok and failed.error.contains("저장 실패"), "Failed acceptance save is reported")
	check(Compare.equivalent(before, state.to_data()), "Failed acceptance restores round creation, agreement and acceptance record")
	shop.set_meta("contract_save_fixture", func(): return true)
	result = shop.perform_contract_action("accept", "caravan", token)
	check(result.ok and not state.contracts.partners.caravan.round.is_empty(), "One committed acceptance starts one immutable round")
	before = state.to_data().duplicate(true)
	result = shop.perform_contract_action("accept", "caravan", token)
	check(not result.ok and Compare.equivalent(before, state.to_data()), "Duplicate acceptance cannot replace or create another round")
	state.contracts.ordinary_batches = 4
	state.herbs = 20
	state.mushrooms = 6
	state.progression.expansion.materials.dewgrass = 8
	state.progression.expansion.materials.blue_reed = 8
	state._start_batch()
	check(state.brew_active and state.contracts.batch.purpose == "contract", "The fixture owns an actual reserved contract batch")
	state.brew_elapsed = state.brew_duration() * 0.25
	before = state.to_data().duplicate(true)
	shop.set_meta("contract_save_fixture", func(): return false)
	failed = shop.perform_contract_action("train", "", {"next_level": 1})
	check(not failed.ok and Compare.equivalent(before, state.to_data()), "Save failure during an active contract preserves recipe, purpose, ingredients, judgement and progress")
	check(not state.shop_open and shop.state == identity and state.progression == progress_identity and state.contracts == contract_identity, "Active-batch rollback neither migrates nor reopens the shop")
	shop.set_meta("contract_save_fixture", func(): return true)
	result = shop.perform_contract_action("train", "", {"next_level": 1})
	check(result.ok and state.contracts.training == 1 and state.progression.totals.manual_spent == 8000, "One successful training charges its displayed price exactly once")
	check(state.contracts.partners.caravan.history["1"].chance == 0.6, "Training does not change a stored negotiation probability")
	var paid_before := int(state.contracts.totals.paid)
	state.start_report_period()
	check(state.contracts.report_paid == paid_before, "Period reset snapshots contract receipts separately")
	state.contracts.totals.paid += 13
	check(state.report_text().contains("계약 대금 +13 G") and state.report_text().contains("순영업수입 +13 G"), "Existing period text includes contract income once")
	state.contracts.totals.paid = paid_before
	shop.queue_free()
	await process_frame
	print("CONTRACT GATEWAY %s: %d checks; save-failure rollback, identity/closed-shop/active-batch preservation, separate RNG, one acceptance/training and period income; isolated only" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(1 if failures else 0)
