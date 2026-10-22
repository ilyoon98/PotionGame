extends SceneTree
## F19 in-memory fixtures and actual headless Controls; no real game or saves.
const Shop = preload("res://scripts/shop.gd")
const State = preload("res://scripts/shop_state.gd")
const Status = preload("res://scripts/management_status.gd")
const Fixtures = preload("res://tools/f19_management_fixture.gd")
const F18 = preload("res://tests/contracts_fixture.gd")
const Compare = preload("res://tests/state_compare.gd")
const Centered = preload("res://scripts/centered_button_content.gd")
const Currency = preload("res://scripts/currency_text.gd")
var shop: Control
var panel: Window
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

func save_ok() -> bool:
	writes += 1
	return true

func save_failure() -> bool:
	writes += 1
	return false

func fixture(rank: int = 1, training: int = 0, all_partners: bool = false) -> RefCounted:
	var state := Fixtures.completed(rank, training, all_partners)
	shop.state = state
	shop.set_meta("contract_save_fixture", save_ok)
	shop.set_meta("late_save_fixture", save_ok)
	panel.recommend_feedback = ""
	panel.contract_feedback = ""
	panel.late_feedback.clear()
	panel.recommend_pressed_action = ""
	panel.recommend_pressed_next_level = 0
	panel.close_contracts()
	return state

func layout(page: int = -1) -> void:
	if page >= 0: panel.select_page(page)
	panel.refresh()
	for frame in 3: await process_frame

func click(button: Button) -> void:
	button.button_down.emit()
	button.pressed.emit()

func same(before: Dictionary, label: String) -> void:
	check(Compare.equivalent(before, shop.state.to_data()), label)

func late_row(track: String) -> Dictionary:
	return panel.rows[Status.LATE_INVESTMENT_PREFIX + track]

func verify_training() -> void:
	var state := fixture()
	await layout(panel.UPGRADES)
	check(state.contracts.training_view(state).remaining_opportunities == 9, "The first three grades of all three partners expose nine future probabilistic opportunities")
	check(panel.rows.contract_training.extra.source_text.contains("앞으로 적용 가능한 흥정 9회"), "Training details show the real remaining count")
	Fixtures.accept_basic(state, "caravan")
	await layout()
	check(state.contracts.training_view(state).remaining_opportunities == 8 and not panel.rows.contract_training.button.disabled, "Accepting a first-grade base proposal removes only that grade and keeps future grades trainable")
	state = fixture(3, 0, true)
	for partner in state.contracts.PARTNERS: Fixtures.accept_basic(state, partner.id)
	await layout(panel.UPGRADES)
	var row: Dictionary = panel.rows.contract_training
	check(row.button.disabled and row.button.text == "적용할 흥정 없음" and not row.completed and row.detail.source_text == "0/3단계", "Exhausted third-grade opportunities block training without falsely declaring max level")
	check(row.extra.source_text.contains("흥정 0회") and not Status.growth_candidates(state).any(func(item): return item.purchase_key == Status.CONTRACT_TRAINING_KEY), "Zero-opportunity training is absent from recommendations")
	var before: Dictionary = state.to_data().duplicate(true)
	click(row.button)
	await layout()
	same(before, "An exhausted formal training action cannot spend or alter a negotiation")
	state = fixture(4, 0, true)
	await layout()
	check(state.contracts.training_view(state).remaining_opportunities == 0 and panel.rows.contract_training.button.text == "적용할 흥정 없음", "Guaranteed final grades never count as remaining probabilistic training targets")
	# Direct and recommended actions preserve the displayed next-stage token.
	for recommended in [false, true]:
		state = fixture()
		await layout(panel.OPERATION if recommended else panel.UPGRADES)
		var button: Button = panel.recommend_button if recommended else panel.rows.contract_training.button
		button.button_down.emit()
		check(shop.perform_contract_action("train", "", {"next_level": 1}).ok, "An independent current-stage transaction advances the live model")
		await layout()
		before = state.to_data().duplicate(true)
		var paid := writes
		button.pressed.emit()
		await layout()
		same(before, "The old %s training press cannot purchase a more expensive new stage" % ("recommended" if recommended else "formal"))
		check(writes == paid and state.contracts.training == 1, "Rejected old stage makes no second save or payment")
		check(panel.recommend_feedback.contains("변경") if recommended else panel.contract_feedback.contains("변경"), "The stale-stage rejection is visible at its action surface")
	for recommended in [false, true]:
		state = fixture(3, 0, true)
		await layout(panel.OPERATION if recommended else panel.UPGRADES)
		var button: Button = panel.recommend_button if recommended else panel.rows.contract_training.button
		button.button_down.emit()
		for partner in state.contracts.PARTNERS: Fixtures.accept_basic(state, partner.id)
		await layout()
		before = state.to_data().duplicate(true)
		var paid := writes
		button.pressed.emit()
		await layout()
		same(before, "An old training press rechecks opportunities exhausted after button-down")
		check(writes == paid and (panel.recommend_feedback.contains("적용할 흥정 없음") if recommended else panel.contract_feedback.contains("적용할 흥정 없음")), "Lost opportunity makes no payment and displays its precise reason")
	state = fixture()
	await layout(panel.OPERATION)
	for next_level in range(1, 4):
		var paid := writes
		var gold: int = state.gold
		click(panel.recommend_button)
		await layout()
		check(state.contracts.training == next_level and gold - state.gold == [8000, 20000, 50000][next_level - 1] and writes == paid + 1, "A freshly displayed next stage buys exactly once at its actual price")

func verify_rows_and_recommendation() -> void:
	shop.state = State.new()
	await layout(panel.UPGRADES)
	for track in Status.LATE_TRACKS:
		var row := late_row(track)
		var view: Dictionary = shop.state.late_investments.view(shop.state, track)
		check(row.button.disabled and row.button.text == "가게 성장 완료 필요", "An incomplete shop sees the actual growth gate on both independent tracks")
		for condition in view.missing: check(row.extra.source_text.contains(condition), "Folded details retain every missing requirement")
	var state := fixture()
	await layout()
	for track in Status.LATE_TRACKS: check(late_row(track).button.text == "거래2등급 필요", "Completed original growth does not bypass the stage-one trade-rank gate")
	state = fixture(2, 3)
	state.gold = 149999
	await layout()
	for track in Status.LATE_TRACKS: check(late_row(track).button.disabled and late_row(track).button.get_meta("currency_source", "").contains("1 G 부족"), "Unaffordable investment shows the actual shortage")
	state.gold = 10000000
	await layout(panel.OPERATION)
	var candidates := Status.growth_candidates(state)
	check(candidates.any(func(item): return item.purchase_key == "late:supply_support" and item.score == 65) and candidates.any(func(item): return item.purchase_key == "late:contract_batch" and item.score == 60), "Actual late candidates retain the approved 65/60 scores")
	check(panel.recommendation.purchase_key == "late:supply_support", "Supply is recommended before bulk crafting when both are affordable")
	var before: Dictionary = state.to_data().duplicate(true)
	for index in 15:
		Status.growth_candidates(state)
		panel.refresh()
	same(before, "Candidate, condition, supply and effect display never advances time, supplies, negotiates or consumes RNG")
	click(panel.recommend_button)
	await layout()
	check(state.late_investments.stages.supply_support == 1 and panel.recommendation.purchase_key == "late:contract_batch", "The first recommendation directly buys supply and leaves the other branch independent")
	click(panel.recommend_button)
	await layout()
	check(state.late_investments.stages.contract_batch == 1 and state.progression.totals.manual_spent == 300000, "The second branch also purchases directly and counts one investment cost")
	check(not Status.growth_candidates(state).any(func(item): return item.kind == "late"), "Second-stage candidates wait for actual grade three")
	state = fixture(4)
	await layout(panel.OPERATION)
	check(panel.recommendation.purchase_key == Status.CONTRACT_TRAINING_KEY and panel.recommendation.score == 70, "Useful training at score70 stays ahead of the new65/60 candidates")
	# No special discovery is required to buy either late branch.
	state = fixture(2, 3)
	for id in state.progression.owned.duplicate():
		if State.Rare.is_special(id): state.progression.owned.erase(id)
	state.progression.expansion.rare_discovered.clear()
	await layout(panel.UPGRADES)
	for track in Status.LATE_TRACKS: check(not late_row(track).button.disabled, "Undiscovered special recipes do not participate in the original-growth gate")

func verify_purchases_and_supply() -> void:
	var state := fixture(4, 3)
	await layout(panel.UPGRADES)
	check(not panel.rows.supply_support.panel.visible and not panel.rows.gather_supply_support.panel.visible, "Both copies of the supply gauge stay absent before its first purchase")
	for track in Status.LATE_TRACKS:
		for stage in range(1, 4):
			var row := late_row(track)
			var view: Dictionary = state.late_investments.view(state, track)
			check(row.summary.source_text.contains(view.current_effect) and row.summary.source_text.contains(view.next_effect), "Each row shows the real current-to-next effect")
			check(int(row.button.get_meta("next_level")) == stage and row.button.icon == Currency.COIN, "Each investment CTA captures the actual target stage and original coin")
			var geometry: Dictionary = Centered.rects(row.button)
			check(geometry.fits and geometry.gap == 6 and absf(geometry.block.get_center().x - row.button.size.x / 2.0) <= 1, "Investment price/action content fits and stays centered with a6px gap")
			var gold: int = state.gold
			var previous: Dictionary = state.late_investments.supply.duplicate(true)
			var paid := writes
			click(row.button)
			await layout()
			check(state.late_investments.stages[track] == stage and gold - state.gold == [150000, 300000, 450000][stage - 1] and writes == paid + 1, "Each legitimate stage pays once and uses the single saved gateway")
			if track == "supply_support":
				if stage == 1:
					check(state.late_investments.supply.elapsed == 0.0 and state.late_investments.totals.is_empty(), "First purchase begins the real60s cycle without granting items")
					state.late_investments.supply.elapsed = 23.5
				else: check(state.late_investments.supply == previous, "Upgrading cannot reset or increase the in-flight supply reservation")
		check(late_row(track).completed and late_row(track).button.disabled and late_row(track).summary.source_text.begins_with("현재 효과"), "Maxed late investment remains one completed row with its real final effect")
	check(state.progression.totals.manual_spent == 1800000 and Status.recommendation(state).is_empty(), "The six independent investments cost exactly1.8million and stop being recommended")
	F18.clear_materials(state)
	await layout(panel.HERBS)
	var before: Dictionary = state.to_data().duplicate(true)
	panel.refresh_gauges(0.016)
	for id in ["supply_support", "gather_supply_support"]:
		var row: Dictionary = panel.rows[id]
		var detail_text: String = row.detail.text if row.detail is Label else row.detail.source_text
		check(row.panel.visible and is_equal_approx(row.work.bar.value, 23.5 / 60.0 * 100.0) and row.work.count.text == "36.5초" and detail_text.contains("36.5초"), "Both supply rows display the same actual cycle and smooth remaining time")
		check(row.extra.source_text.contains("예약 최대 %d개" % int(state.late_investments.SUPPLY_QUANTITIES[1])) and not row.stock.box.visible, "The newest maximum effect does not overwrite the first-cycle reserved quantity")
	same(before, "Rendering identical supply gauges never advances or finishes a supply cycle")
	F18.fill_materials(state)
	await layout()
	check(panel.rows.supply_support.detail.source_text == "보관 가득", "A full candidate pool is shown as storage full")
	state.progression.owned.clear()
	await layout()
	check(panel.rows.supply_support.detail.source_text == "대상 없음", "An empty eligible recipe pool is shown as no target")

func verify_stale_failures_and_contract_details() -> void:
	shop.state = State.new()
	shop.state.gold = 1000000
	shop.state.customer_waiting = true
	await layout(panel.OPERATION)
	var ordinary_key: String = panel.recommend_button.get_meta("purchase_key", "")
	check(ordinary_key.begins_with("upgrade:"), "The original game still offers a real ordinary upgrade")
	panel.recommend_button.button_down.emit()
	check(shop.state.purchase(ordinary_key), "An independent original purchase advances that track once")
	await layout()
	var ordinary_before: Dictionary = shop.state.to_data().duplicate(true)
	panel.recommend_button.pressed.emit()
	await layout()
	same(ordinary_before, "An old ordinary upgrade recommendation cannot charge the next stage")
	check(panel.recommend_feedback == "강화 단계가 변경되었어요", "The common stale-stage guard reports its exact reason")
	for recommended in [false, true]:
		var state := fixture(2, 3)
		await layout(panel.OPERATION if recommended else panel.UPGRADES)
		var button: Button = panel.recommend_button if recommended else late_row("supply_support").button
		button.button_down.emit()
		check(shop.perform_late_investment_action("supply_support", 1).ok, "An independent genuine first-stage transaction updates live supply")
		await layout()
		if recommended: check(panel.recommendation.purchase_key == "late:contract_batch", "The displayed replacement investment differs from the captured supply target")
		var before: Dictionary = state.to_data().duplicate(true)
		var paid := writes
		button.pressed.emit()
		await layout()
		same(before, "A captured old late-investment stage cannot buy a new higher-priced stage")
		check(writes == paid, "Rejected stage does not attempt another save")
	var state := fixture(4, 3)
	await layout(panel.OPERATION)
	shop.set_meta("late_save_fixture", save_failure)
	var before: Dictionary = state.to_data().duplicate(true)
	click(panel.recommend_button)
	await layout()
	same(before, "Failed late-investment save restores stage, cycle, cash and all live state")
	check(panel.recommend_feedback.contains("저장 실패") and panel.recommend_effect.source_text == panel.recommend_feedback, "Save failure is visible at the operation recommendation")
	shop.set_meta("late_save_fixture", save_ok)
	click(panel.recommend_button)
	await layout()
	check(state.late_investments.stages.supply_support == 1, "A rolled-back purchase remains retryable")
	Fixtures.buy_to(state, "contract_batch", 3)
	F18.fill_materials(state)
	state.contracts.ordinary_batches = 4
	state._start_batch()
	check(state.brew_active and state.contracts.batch.purpose == "contract" and int(state.contracts.batch.quantity) == 4, "A real current delivery reservation contains its actual four-bottle quantity")
	panel.open_contracts()
	await layout()
	for row in panel.contracts_view.rows.values(): check(row.detail_text.source_text.contains("한 번에 최대4병 · 재료·남은 주문량에 따라 감소"), "All three partner details show the same real bulk maximum and reduction rule")
	check(panel.contracts_view.rows.caravan.detail_text.source_text.contains("진행 중 예약 4병") and Status.production_current(state).quantity == 4, "Current reservation quantity is shown separately from the investment maximum")
	before = state.to_data().duplicate(true)
	panel.close_contracts()
	await layout()
	panel.close_button.pressed.emit()
	shop.open_management()
	await layout()
	same(before, "Back/close/reopen preserves purchases, supply timer and negotiation history")
	check(panel.tabs.size() == 7 and panel.pages.size() == 8 and panel.size.x == 520, "F19 preserves all seven tabs, the statistics page and520px width")

func run() -> void:
	if DisplayServer.get_name() != "headless": quit(1); return
	Engine.max_fps = 60
	shop = Shop.new()
	root.add_child(shop)
	shop.set_process(false)
	if shop.art != null: shop.art.set_process(false)
	shop.open_management()
	panel = shop.management
	panel.set_process(false)
	await layout()
	await verify_training()
	await verify_rows_and_recommendation()
	await verify_purchases_and_supply()
	await verify_stale_failures_and_contract_details()
	if failures == 0: print("F19 MANAGEMENT UI PASS: %d isolated checks; future-opportunity gates, direct/recommended frozen next-stage actions, late conditions and65/60/70 ranking, six actual prices/effects and1.8m investment, identical purchased-only supply gauges/current reservation, storage/no-target states, bulk detail, rollback/close and model/RNG preservation; no GUI/player data" % checks)
	else: print("F19 MANAGEMENT UI FAILED: %d/%d" % [failures, checks])
	quit(1 if failures else 0)
