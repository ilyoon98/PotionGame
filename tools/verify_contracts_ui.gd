extends SceneTree
## Synthetic UI/model only. No native input, player saves or running-game access.
const Shop = preload("res://scripts/shop.gd")
const State = preload("res://scripts/shop_state.gd")
const Content = preload("res://scripts/shop_content.gd")
const Status = preload("res://scripts/management_status.gd")
const Rare = preload("res://scripts/rare_recipes.gd")
const F = preload("res://tests/contracts_fixture.gd")
const Centered = preload("res://scripts/centered_button_content.gd")
const Currency = preload("res://scripts/currency_text.gd")
var shop: Control
var panel: Window
var screen: Control
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

func layout() -> void:
	panel.refresh()
	for frame in 3: await process_frame

func fresh() -> RefCounted:
	var state := F.completed()
	shop.state = state
	return state

func token(state: RefCounted, partner: String, option: String = "basic") -> Dictionary:
	for item in state.contracts.partner_view(state, partner).options:
		if item.id == option: return item.token.duplicate(true)
	return {}

func choose(partner: String, option: String) -> void:
	var button: Button = screen.rows[partner].options[option].button
	button.button_down.emit()
	button.pressed.emit()

func texts(node: Node) -> String:
	var result := str(node.tooltip_text) + "\n" if node is Control else ""
	if node is Label or node is Button: result += node.text + "\n"
	elif node is RichTextLabel: result += str(node.get("source_text")) + "\n"
	for child in node.get_children(): result += texts(child)
	return result

func assert_readonly(before: Dictionary, message: String) -> void:
	check(F.stable_equal(before, shop.state.to_data()), message)

func ship_one(state: RefCounted, partner: String) -> Dictionary:
	var model: RefCounted = state.contracts
	var round_data: Dictionary = model.partners[partner].round
	var index := 0
	for family in round_data.requirements:
		if round_data.shipped[family] < round_data.requirements[family]:
			for id in round_data.allowed:
				if round_data.allowed[id].family != family: continue
				var kind: Variant = false if id == "health" else true if id == "mana" else id
				model.reserve({"partner": partner, "round_id": round_data.id, "kind": kind, "id": id, "family_index": index})
				return model.complete(state, kind)
		index += 1
	return {}

func verify_lock_and_navigation() -> void:
	shop.state = State.new()
	await layout()
	var before: Dictionary = shop.state.to_data().duplicate(true)
	panel.rows.contract_summary.button.pressed.emit()
	await layout()
	check(screen.visible and not panel.scroll.visible and panel.pages.size() == 8 and panel.tabs.size() == 7 and panel.REPORT == 6, "Contracts reuse one Window without adding a tab or replacing statistics")
	check(screen.notice.text.contains("별의 정원"), "The locked screen states its actual opening condition")
	for row in screen.rows.values(): check(row.action.disabled and row.status.text.contains("별의 정원"), "All three partners retain the same unlock gate")
	assert_readonly(before, "Locked contract browsing does not unlock, roll, spend or save")
	screen.back_button.pressed.emit()
	await layout()
	check(not screen.visible and panel.scroll.visible and panel.tabs[0].visible, "Back restores the ordinary management pages")
	shop.state = F.opened()
	panel.open_contracts()
	await layout()
	for row in screen.rows.values():
		check(row.status.text.contains("계열 레시피 필요"), "An opened destination still explains missing purchased ordinary families")
		for option in row.options.values(): check(option.button.disabled, "Missing-family proposals cannot mutate a contract")
	fresh()
	panel.close_contracts()
	panel.select_page(panel.OPERATION)
	await layout()
	panel.scroll.scroll_vertical = 180
	await process_frame
	var old_scroll: int = panel.scroll.scroll_vertical
	before = shop.state.to_data().duplicate(true)
	panel.rows.contract_summary.button.pressed.emit()
	await layout()
	for index in 5: panel.refresh()
	check(panel.contracts_origin_scroll == old_scroll, "Periodic refresh never overwrites the saved return scroll")
	screen.back_button.pressed.emit()
	await layout()
	check(panel.selected == panel.OPERATION and panel.scroll.scroll_vertical == old_scroll, "Back restores the original operation tab and exact clamped scroll")
	panel.open_contracts()
	panel.result_button.pressed.emit()
	await layout()
	check(not screen.visible and panel.selected == panel.REPORT and panel.scroll.visible, "The preserved graph icon exits the contract subpage into statistics")
	for page in panel.pages.size():
		panel.select_page(page)
		await layout()
		check(panel.pages[page].visible, "Every original page remains reachable")
	panel.open_contracts()
	await layout()
	for id in screen.rows:
		var row: Dictionary = screen.rows[id]
		check(row.icon.texture != null and row.icon.texture.get_size() == Vector2(32, 48) and row.icon.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Partners use existing native 32×48 characters without recoloring")
		check(row.title.get_theme_font_size("font_size") == 18 and row.status.get_theme_font_size("font_size") == 16 and row.action.get_theme_font_size("font_size") == 16, "Contract titles/body/actions retain readable 18/16px type")
		check(row.grade.get_line_count() == 1 and row.grade.size.x >= 54, "The partner grade retains its own single-line width beside the detail button")
		for rare in Rare.ROWS: check(not texts(row.panel).contains(rare.name), "Even owned special recipes never leak into contract quantities or unit-price details")
		row.toggle.set_pressed(true)
		row.action.pressed.emit()
	await layout()
	assert_readonly(before, "Tabs, hidden details, negotiation offers and repeated queries preserve model and every RNG")

func verify_options_and_training() -> void:
	var state := fresh()
	panel.open_contracts()
	for fixture: Dictionary in [{"points": 0, "grade": 1, "basic": 1.60, "payment": 1.80, "quantity": 10}, {"points": 60, "grade": 2, "basic": 1.70, "payment": 1.90, "quantity": 20}, {"points": 240, "grade": 3, "basic": 1.80, "payment": 2.00, "quantity": 30}, {"points": 600, "grade": 4, "basic": 1.90, "payment": 2.10, "quantity": 40}]:
		state.contracts.partners.caravan.points = fixture.points
		await layout()
		var view: Dictionary = screen.views.caravan
		check(view.grade == fixture.grade and screen.rows.caravan.grade.text == "%d등급" % fixture.grade, "Actual bottle-based thresholds determine the displayed grade")
		check(screen.rows.caravan.options.relationship.box.visible == (fixture.grade < 4), "The meaningless relationship option is absent at the final grade")
		for option in view.options:
			var improved: bool = option.id != "basic"
			var amount: int = int(ceil(int(fixture.quantity) * 1.2)) if improved else int(fixture.quantity)
			var points: int = amount * 2 * (2 if option.id == "relationship" else 1)
			check(option.requirements.values() == [amount, amount] and option.points == points, "The UI reads exact per-family quantity and bottle-based completion credit")
			check(is_equal_approx(option.multiplier, fixture.payment if option.id == "payment" else fixture.basic), "Payout preview follows the actual grade-specific module multiplier")
			var controls: Dictionary = screen.rows.caravan.options[option.id]
			check(controls.preview.source_text.contains("완료 실적 +%d점" % points) and controls.preview.source_text.contains("대금 +%.0f%%" % ((float(option.multiplier) - 1.0) * 100.0)), "No temporary threshold, payout or points values are hardcoded in the controls")
			check(controls.chance.text.contains("100%") if fixture.grade == 4 and improved else true, "Final-grade improvements display their guaranteed 100% chance")
	state = fresh()
	await layout()
	for stage in 4:
		var training: Dictionary = state.contracts.training_view(state)
		check(is_equal_approx(training.chance, 0.6 + 0.1 * stage) and panel.rows.contract_training.summary.source_text.contains("%.0f%%" % (training.chance * 100)), "Training progress and displayed 60/70/80/90% agree")
		check(panel.rows.contract_training.summary.source_text.contains("最终") == false and panel.rows.contract_training.summary.source_text.contains("최종 등급 100% 확정"), "The final-grade guarantee remains distinct from ordinary training")
		if stage < 3:
			var geometry: Dictionary = Centered.rects(panel.rows.contract_training.button)
			check(panel.rows.contract_training.button.icon != null and geometry.fits and geometry.gap == 6 and absf(geometry.block.get_center().x - panel.rows.contract_training.button.size.x / 2.0) <= 1, "The training cost keeps one original coin and its price/action as a centered fitting 6px block")
		if stage < 3:
			var gold: int = state.gold
			panel.rows.contract_training.button.pressed.emit()
			await layout()
			check(state.contracts.training == stage + 1 and state.gold == gold - int(training.cost), "The furniture/staff training action uses the single saved gateway")
	check(panel.rows.contract_training.button.disabled and state.progression.totals.manual_spent == 78000, "Three independent training purchases reach their cap and remain manual investment")
	for stage in 4:
		state = fresh()
		state.contracts.training = stage
		state.contracts.seed = 1
		await layout()
		choose("caravan", "payment")
		await layout()
		var record: Dictionary = screen.views.caravan.negotiation
		check(record.tried and record.success and is_equal_approx(record.chance, 0.6 + stage * 0.1), "Displayed action records the real deterministic chance exactly once")
		check(screen.rows.caravan.options.payment.button.get_meta("action") == "accept" and not screen.rows.caravan.options.payment.button.disabled, "Success exposes only acceptance of the successful condition")
		check(screen.rows.caravan.options.basic.button.disabled and screen.rows.caravan.options.relationship.button.disabled, "A successful improvement cannot silently switch to another term")
		if stage < 3:
			panel.rows.contract_training.button.pressed.emit()
			await layout()
			check(is_equal_approx(screen.views.caravan.chance, record.chance), "Later training does not reroll or change a decided opportunity's displayed chance")
		choose("caravan", "payment")
		await layout()
		check(screen.views.caravan.active and screen.views.caravan.round.terms.option == "payment", "Improved acceptance starts an actual automatic round")
		check(not screen.rows.caravan.action.visible and not screen.rows.caravan.negotiation.visible, "An accepted contract replaces the inactive negotiation button/form with its actual status and details")
		var before: Dictionary = state.to_data().duplicate(true)
		choose("caravan", "payment")
		await layout()
		assert_readonly(before, "Repeated accepted buttons cannot duplicate a round or payout")
	state = fresh()
	state.contracts.seed = 40000
	await layout()
	choose("grove", "relationship")
	await layout()
	check(screen.views.grove.negotiation.tried and not screen.views.grove.negotiation.success and screen.rows.grove.result.text.contains("실패"), "A fixed failure is visible without removing the base contract")
	check(not screen.rows.grove.options.basic.button.disabled and screen.rows.grove.options.relationship.button.disabled, "Failure offers base acceptance and blocks another draw")
	choose("grove", "basic")
	await layout()
	check(screen.views.grove.active, "First negotiation failure still leads to a growing basic contract")
	state = fresh()
	state.contracts.partners.caravan.points = 600
	state.contracts.seed = 40000
	await layout()
	var before_seed: int = state.contracts.seed
	choose("caravan", "payment")
	await layout()
	check(screen.views.caravan.negotiation.success and screen.views.caravan.chance == 1.0 and state.contracts.seed == before_seed, "The final-grade button is a real guaranteed result without another random draw")
	choose("caravan", "payment")
	await layout()
	check(screen.views.caravan.active and screen.views.caravan.round.terms.grade == 4 and not screen.rows.caravan.action.visible, "The highest agreement continues automatically and removes the completed CTA")

func verify_rounds_and_pending() -> void:
	var state := fresh()
	panel.open_contracts()
	await layout()
	for id in screen.rows: choose(id, "basic")
	await layout()
	check(screen.views.values().all(func(view): return view.active), "All three partners start real independent rounds")
	check(not screen.notice.visible and screen.rows.caravan.detail_text.source_text.contains("4배치"), "Internal batch-allocation explanations stay in folded details, outside the default screen")
	var initial_round: Dictionary = state.contracts.partners.caravan.round.duplicate(true)
	check(ship_one(state, "caravan").get("ok", false), "A successful reserved contract bottle changes actual delivered counts")
	await layout()
	check(screen.rows.caravan.gauge.bar.value == 5.0 and screen.rows.caravan.gauge.count.text == "1/20병", "The gauge reflects exactly one actual bottle, without interpolation")
	check(screen.rows.caravan.detail_text.source_text.contains("현재 누적 정산 예정") and screen.rows.caravan.detail_text.coin_count >= 2, "Accumulated payout estimate and already received lifetime pay are separate coin amounts")
	var held: Button = screen.rows.caravan.options.payment.button
	held.button_down.emit()
	# This synthetic threshold crossing represents completed prior rounds, not a UI write.
	state.contracts.partners.caravan.points = 60
	await layout()
	var before: Dictionary = state.to_data().duplicate(true)
	held.pressed.emit()
	await layout()
	assert_readonly(before, "A held stale grade token cannot be rebound by the periodic UI refresh")
	check(screen.error_label.visible and screen.error_label.text.contains("새 등급"), "Stale proposals show the gateway error in the same screen")
	state.contracts.seed = 1
	await layout()
	choose("caravan", "payment")
	await layout()
	choose("caravan", "payment")
	await layout()
	check(screen.views.caravan.status == "새 조건 적용 대기" and screen.rows.caravan.pending.text.contains("다음 회차"), "Newly accepted higher-grade terms explicitly wait for the next round")
	check(state.contracts.partners.caravan.round.terms == initial_round.terms and state.contracts.partners.caravan.round.requirements == initial_round.requirements and state.contracts.partners.caravan.round.allowed == initial_round.allowed, "The current round retains frozen terms, quantities, allowed items and prices")
	var previous: String = state.contracts.partners.caravan.round.id
	for index in 19: check(ship_one(state, "caravan").get("ok", false), "Each remaining bottle is shipped through a consumed reservation")
	await layout()
	check(screen.views.caravan.round.id != previous and screen.views.caravan.round.terms.grade == 2 and screen.views.caravan.round.terms.option == "payment", "Completing the old round applies pending conditions once to the next round")
	check(screen.rows.caravan.gauge.bar.value == 0.0 and screen.rows.caravan.gauge.count.text == "0/48병", "A new round shows its real zero count and new quantity immediately")
	F.clear_materials(state)
	await layout()
	check(screen.rows.caravan.status.text == "재료 대기", "Automatic shipping waits honestly when no paid ingredients are available")
	before = state.to_data().duplicate(true)
	for index in 12: screen.refresh()
	assert_readonly(before, "Displayed wait/next-round prices and gauges never manufacture, reserve, pay or reroll")

func verify_rollback_and_status() -> void:
	var state := fresh()
	panel.open_contracts()
	await layout()
	shop.set_meta("contract_save_fixture", func(): return false)
	var before: Dictionary = state.to_data().duplicate(true)
	choose("academy", "basic")
	await layout()
	assert_readonly(before, "Failed contract save rolls back acceptance, round creation and all RNG exactly")
	check(screen.error_label.visible and screen.error_label.text.contains("저장 실패"), "Save failure remains visible instead of showing an unsaved contract")
	state.contracts.seed = 1
	before = state.to_data().duplicate(true)
	choose("academy", "payment")
	await layout()
	assert_readonly(before, "Failed negotiation save also restores the consumed result and negotiation seed")
	panel.rows.contract_training.button.pressed.emit()
	await layout()
	assert_readonly(before, "Failed training save restores gold, investment and chance")
	check(panel.rows.contract_training.extra.visible and panel.rows.contract_training.extra.source_text.contains("저장 실패"), "The independent training row immediately opens its actual save failure")
	shop.set_meta("contract_save_fixture", func(): writes += 1; return true)
	state = fresh()
	await layout()
	choose("caravan", "basic")
	state.contracts.ordinary_batches = 4
	var candidate: Dictionary = state.contracts.candidate(state)
	check(not candidate.is_empty(), "The active real contract produces a pure manufacturing candidate")
	state.contracts.reserve(candidate)
	state.progression.active_recipe = candidate.kind
	state.progression.batch_chance = state.progression.success_chance(candidate.kind)
	state.brew_active = true
	state.brew_elapsed = state.brew_duration() / 2.0
	state.inventory.assign([])
	for index in state.capacity(): state.inventory.append(false)
	state.stock = state.inventory.size()
	F.clear_materials(state)
	await layout()
	var production := Status.production_current(state)
	check(production.purpose == "contract" and production.partner == candidate.partner and production.round_id == candidate.round_id and production.running and production.progress == 0.5, "Current cauldron projection exposes the actual reserved delivery identity and progress even at full retail storage")
	check(panel.rows.craft.work.caption.text == "납품 제조" and panel.rows.craft.detail.text.contains("납품 제조 중"), "The operation cauldron never reports full storage for an active delivery batch")
	var potion := Status.potion(state, candidate.kind)
	check(potion.condition.contains("납품용 자동 제작 중") and potion.condition.contains("다음 병 필요") and not potion.condition.contains("공간 필요"), "Reserved current ingredients and next-bottle shortages are separate for delivery")
	for ingredient in Status.ingredients(state, candidate.kind): check(ingredient.reserved and ingredient.missing == 0, "The active contract never charges its already reserved recipe twice")
	state.contracts.clear_batch()
	check(not state.is_brewing() and Status.production_current(state).status == "보관 가득", "The existing full-retail guard remains intact for an ordinary batch")

func verify_statistics_and_geometry() -> void:
	var state := fresh()
	state.total_sales_gold = 123456
	state.total_spent_materials = 2000
	state.total_spent_expeditions = 300
	state.contracts.totals = {"paid": 12000, "shipped": 21799, "rounds": 321, "points": 21799}
	state.contracts.report_paid = 3000
	var summary := Status.lifetime_summary(state)
	check(summary.net == 133156 and summary.sales == 123456 and summary.contract_paid == 12000, "Lifetime net adds contract pay once while preserving normal retail revenue")
	var report := Status.report_summary(state)
	check(report.net == 130156, "Period net includes only contract pay after its existing baseline")
	panel.result_button.pressed.emit()
	await layout()
	check(panel.statistics_values.size() == 12 and panel.statistics_values.contract_paid.source_text == "12,000 G" and panel.statistics_values.contract_shipped.source_text == "21,799병" and panel.statistics_values.contract_rounds.source_text == "321회", "Nine preserved statistics gain three separate exact contract aggregates")
	check(panel.statistics_values.contract_paid.coin_count == 1 and panel.statistics_values.contract_shipped.coin_count == 0, "Contract money uses the same coin-before-number convention")
	for button in [panel.result_button, panel.close_button]:
		var geometry: Dictionary = Centered.rects(button)
		check(button.icon != null and button.icon.get_size() == Vector2(16, 16) and geometry.gap == 6 and geometry.fits, "The existing statistics and close icons keep their original centered native blocks")
	fresh()
	panel.open_contracts()
	for row in screen.rows.values():
		row.action.pressed.emit()
		row.toggle.set_pressed(true)
	await layout()
	for row in screen.rows.values():
		check(row.panel.position.x >= 0 and row.panel.get_rect().end.x <= screen.scroll.size.x + 1, "Contract content stays inside the 480px scroll width")
		for option in row.options.values():
			var button: Button = option.button
			var geometry: Dictionary = Centered.rects(button)
			check(geometry.fits and absf(geometry.block.get_center().x - button.size.x / 2.0) <= 1, "Each real option's native action text stays centered and fits")
			check(option.preview.get_content_width() <= option.preview.size.x + 1 and option.preview.get_content_height() <= option.preview.size.y + 1, "Actual proposal quantity/unit-price text fits at 16px without shrinking")
	var before: Dictionary = shop.state.to_data().duplicate(true)
	panel.close_button.pressed.emit()
	await process_frame
	check(not panel.visible and is_instance_valid(panel), "Closing the contracts screen hides the same management Window")
	shop.open_management()
	await layout()
	check(shop.management == panel and screen.visible, "Reopening preserves the same contract subpage and detail state")
	assert_readonly(before, "Closing and reopening never rerolls, clears progress or replaces the game state")

func run() -> void:
	if DisplayServer.get_name() != "headless":
		push_error("Contracts UI requires isolated headless mode")
		quit(1)
		return
	Engine.max_fps = 60
	shop = Shop.new()
	root.add_child(shop)
	shop.set_process(false)
	if shop.art != null: shop.art.set_process(false)
	shop.set_meta("contract_save_fixture", func(): writes += 1; return true)
	shop.open_management()
	panel = shop.management
	panel.set_process(false)
	screen = panel.contracts_view
	await layout()
	await verify_lock_and_navigation()
	await verify_options_and_training()
	await verify_rounds_and_pending()
	await verify_rollback_and_status()
	await verify_statistics_and_geometry()
	check(writes > 0, "All successful tested contract actions pass the fake save gateway")
	if failures == 0: print("CONTRACTS UI PASS: %d isolated checks; seven tabs/same-window/back-scroll, 3 original partner icons, exact bottle thresholds/grade multipliers/options, training and frozen single rolls, stale token and failed-save rollback, next-round preservation/actual gauges/material wait, reserved delivery/full-store guard, 12 separate statistics, 18/16px geometry, no GUI/player files" % checks)
	else: print("CONTRACTS UI FAILED: %d/%d" % [failures, checks])
	quit(1 if failures else 0)
