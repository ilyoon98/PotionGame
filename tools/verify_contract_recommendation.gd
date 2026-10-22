extends SceneTree
## Isolated headless recommendation fixtures. No player I/O, GUI or OS input.
const Shop = preload("res://scripts/shop.gd")
const State = preload("res://scripts/shop_state.gd")
const Status = preload("res://scripts/management_status.gd")
const F = preload("res://tests/contracts_fixture.gd")
const Currency = preload("res://scripts/currency_text.gd")
const Centered = preload("res://scripts/centered_button_content.gd")
const Compare = preload("res://tests/state_compare.gd")
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

func fixture(stage: int = 0) -> RefCounted:
	var initial := F.completed()
	initial.contracts.training = stage
	var state := State.new()
	check(state.load_data(F.data(initial)), "The synthetic completed fixture is normalized before either action path")
	var roundtrip := State.new()
	check(roundtrip.load_data(F.data(state)) and Compare.equivalent(roundtrip.to_data(), state.to_data()), "Normalized fixture is unchanged by a second JSON roundtrip")
	shop.state = state
	panel.recommend_feedback = ""
	panel.feedback_elapsed = 0.0
	panel.recommend_pressed_action = ""
	panel.contract_feedback = ""
	shop.set_meta("contract_save_fixture", save_ok)
	panel.select_page(panel.OPERATION)
	return state

func clone(state: RefCounted) -> RefCounted:
	var result := State.new()
	check(result.load_data(F.data(state)), "Synthetic complete-shop state roundtrips before comparing actions")
	return result

func layout() -> void:
	panel.refresh()
	await process_frame
	await process_frame

func same(before: Dictionary, message: String) -> void:
	if not Compare.equivalent(before, shop.state.to_data()): print("DIFFERENCES ", differences(before, shop.state.to_data()))
	check(Compare.equivalent(before, shop.state.to_data()), message)

func differences(a: Variant, b: Variant, path: String = "") -> Array[String]:
	var result: Array[String] = []
	if Compare.equivalent(a, b): return result
	if a is Dictionary and b is Dictionary:
		for key in a:
			if not b.has(key): result.append(path + "/" + str(key) + " missing")
			else: result.append_array(differences(a[key], b[key], path + "/" + str(key)))
	elif a is Array and b is Array and a.size() == b.size():
		for index in a.size(): result.append_array(differences(a[index], b[index], path + "/" + str(index)))
	else: result.append("%s: %s != %s" % [path, str(a), str(b)])
	return result

func contract_choices(state: RefCounted) -> Array:
	return Status.growth_candidates(state).filter(func(item): return item.purchase_key == Status.CONTRACT_TRAINING_KEY)

func click_recommendation() -> void:
	panel.recommend_button.button_down.emit()
	panel.recommend_button.pressed.emit()

func verify_candidates() -> void:
	for stage in 3:
		var state := fixture(stage)
		var cost: int = [8000, 20000, 50000][stage]
		var before: Dictionary = state.to_data().duplicate(true)
		var first: Dictionary = {}
		for index in 20:
			var choices := contract_choices(state)
			check(choices.size() == 1, "An affordable unlocked nonmaxed training appears exactly once")
			if not choices.is_empty(): first = choices[0]
			Status.recommendation(state)
			Status.recommendation_purpose(first, state)
		same(before, "Repeated recommendation/effect projection preserves every state field and RNG")
		check(first.kind == "training" and first.target == "contract_training" and first.name == "흥정 훈련" and first.action == "훈련" and first.score == 70, "The independent purchase uses the normal training category and priority")
		check(first.cost == cost and first.effect == "일반 흥정 %d%% → %d%%" % [60 + stage * 10, 70 + stage * 10] and first.preview_effect == first.effect, "All three exact prices and current-to-next effects come from the real contract module")
		check(Status.recommendation_purpose(first, state) == "흥정 성공률 높이기", "The recommendation describes negotiation instead of a generic efficiency effect")
		check(Status.recommendation(state).purchase_key == Status.CONTRACT_TRAINING_KEY, "A completed ordinary shop still recommends its unbought contract training")
		state.gold = cost - 1
		check(contract_choices(state).is_empty(), "Unaffordable contract training is excluded")
		state.gold = cost
		check(contract_choices(state).size() == 1, "Exactly the next price is sufficient")
		state.progression.expansion.regions.erase("star_garden")
		check(contract_choices(state).is_empty(), "The actual star-garden unlock remains required")
	var maxed := fixture(3)
	# F21 aging (2026-10-21) is a newer gold sink outside the completed growth; only it may remain.
	var remaining: Dictionary = Status.recommendation(maxed)
	check(contract_choices(maxed).is_empty() and (remaining.is_empty() or str(remaining.purchase_key).begins_with(Status.AGING_PREFIX)), "Fully completed ordinary and contract growth leaves no obsolete training candidate")

func verify_payments_and_layout() -> void:
	for stage in 3:
		var state := fixture(stage)
		await layout()
		var before: Dictionary = state.to_data().duplicate(true)
		var button: Button = panel.recommend_button
		var cost: int = state.contracts.training_view(state).cost
		check(button.get_meta("purchase_key", "") == Status.CONTRACT_TRAINING_KEY and not button.disabled, "The visible operation CTA is the real contract-training action")
		check(button.icon == Currency.COIN and Currency.pattern().search(button.text) == null and button.text.contains(shop._number(cost)), "The exact price keeps the original coin and no G suffix")
		check(panel.recommend_title.text == "성장 추천 · 흥정 훈련" and panel.recommend_effect.source_text == "흥정 성공률 높이기", "The new candidate uses the existing title and short purpose display")
		check(panel.recommend_effect.tooltip_text.contains("%d%% → %d%%" % [60 + stage * 10, 70 + stage * 10]), "Current and next success rates are visible in the existing detail tooltip")
		var geometry: Dictionary = Centered.rects(button)
		check(button.size == Vector2(210, 40) and geometry.fits and geometry.gap >= 6 and geometry.gap <= 8 and Rect2(Vector2.ZERO, button.size).encloses(geometry.block), "Original recommendation dimensions and coin/text block fit without clipping")
		check(absf(geometry.block.get_center().x - button.size.x / 2.0) <= 1.0 and geometry.margin_left >= 14 and is_equal_approx(geometry.margin_left, geometry.margin_right), "The coin/price/action remains centered with symmetric readable padding")
		var title_size: Vector2 = panel.recommend_title.get_theme_font("font").get_string_size(panel.recommend_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
		check(title_size.x <= panel.recommend_title.size.x and panel.recommend_effect.get_content_width() <= panel.recommend_effect.size.x + 1 and panel.recommend_effect.get_content_height() <= panel.recommend_effect.size.y + 1, "Actual 18px title and 16px purpose glyphs stay inside the existing strip")
		same(before, "Displaying the recommendation and measuring its real glyphs does not mutate the model")
		var expected := clone(state)
		check(expected.contracts.train(expected).ok, "The pure reference uses the real contract training transaction")
		var previous_writes := writes
		click_recommendation()
		await layout()
		check(writes == previous_writes + 1 and state.contracts.training == stage + 1 and state.gold == int(before.gold) - cost and int(state.progression.totals.manual_spent) == cost, "One recommendation press charges one exact price, advances one stage and saves once")
		same(expected.to_data(), "Recommended training matches the core action in every saved field and RNG")
		check(panel.selected == panel.OPERATION and panel.recommend_pressed_action.is_empty(), "Training executes immediately without navigating or retaining a pressed target")
		var formal := State.new()
		check(formal.load_data(before), "The independent formal-button comparison starts from exactly the same state")
		shop.state = formal
		panel.select_page(panel.UPGRADES)
		await layout()
		previous_writes = writes
		panel.rows.contract_training.button.pressed.emit()
		await layout()
		check(writes == previous_writes + 1 and Compare.equivalent(expected.to_data(), formal.to_data()), "The formal furniture/staff button and recommendation share the same saved transaction")

func verify_held_and_invalidated_actions() -> void:
	var state := fixture()
	await layout()
	panel.recommend_button.button_down.emit()
	state.progression.owned.erase("vigor")
	await layout()
	check(panel.recommend_button.get_meta("purchase_key", "") == "vigor", "A real newly eligible higher-priority recipe replaces the displayed recommendation while held")
	var expected := clone(state)
	check(expected.contracts.train(expected).ok, "The held action remains valid in the current state")
	panel.recommend_button.pressed.emit()
	await layout()
	same(expected.to_data(), "Release uses the captured contract action instead of the newly displayed recipe")
	check(not state.progression.owned.has("vigor"), "The replacement recipe is never accidentally purchased")
	for invalidation in ["gold", "unlock", "max"]:
		state = fixture()
		await layout()
		panel.recommend_button.button_down.emit()
		match invalidation:
			"gold": state.gold = 7999
			"unlock": state.progression.expansion.regions.erase("star_garden")
			"max": state.contracts.training = 3
		await layout()
		var before: Dictionary = state.to_data().duplicate(true)
		var previous_writes := writes
		panel.recommend_button.pressed.emit()
		await layout()
		same(before, "A captured action invalidated by %s makes no charge, training or RNG change" % invalidation)
		check(writes == previous_writes and not panel.recommend_feedback.is_empty() and panel.recommend_effect.source_text == panel.recommend_feedback, "Invalid %s conditions are rechecked at the gateway and displayed on the operation strip" % invalidation)

func verify_save_failure_and_frozen_result() -> void:
	var state := fixture()
	state.set_shop_open(false)
	state.contracts.seed = 1
	var option: Dictionary = state.contracts.partner_view(state, "caravan").options[1].token
	check(state.contracts.negotiate(state, "caravan", option).ok, "The synthetic fixture contains a fixed decided negotiation")
	var frozen: Dictionary = state.contracts.partner_view(state, "caravan").negotiation.duplicate(true)
	await layout()
	var before: Dictionary = state.to_data().duplicate(true)
	var state_identity: RefCounted = state
	var progress_identity: RefCounted = state.progression
	var module_identity: RefCounted = state.contracts
	shop.set_meta("contract_save_fixture", save_failure)
	var previous_writes := writes
	click_recommendation()
	await layout()
	same(before, "Failed recommendation save rolls back gold, training, manual spending, reserved result and every state field")
	check(writes == previous_writes + 1 and shop.state == state_identity and state.progression == progress_identity and state.contracts == module_identity and not state.shop_open, "Rollback retains live object identities and the closed shop")
	check(panel.recommend_feedback.contains("저장 실패") and panel.recommend_effect.source_text == panel.recommend_feedback and panel.feedback_elapsed > 0.0, "A failed save is shown in the visible operation recommendation, not only the hidden upgrades row")
	check(panel.recommend_button.get_meta("purchase_key", "") == Status.CONTRACT_TRAINING_KEY and not panel.recommend_button.disabled, "The rolled-back training remains retryable")
	shop.set_meta("contract_save_fixture", save_ok)
	click_recommendation()
	await layout()
	check(state.contracts.training == 1 and state.contracts.partner_view(state, "caravan").negotiation == frozen, "A successful retry upgrades future chances without altering a decided negotiation")
	check(panel.recommend_feedback.is_empty() and panel.contract_feedback.is_empty(), "Successful retry clears the obsolete failure display")

func verify_ordinary_action_preserved() -> void:
	var state := State.new()
	state.gold = 1000000
	state.progression.reputation = 10000
	shop.state = state
	panel.select_page(panel.OPERATION)
	await layout()
	var choice: Dictionary = panel.recommendation.duplicate(true)
	check(not choice.is_empty() and choice.purchase_key != Status.CONTRACT_TRAINING_KEY, "Early-game ordinary purchases retain their existing recommendation")
	var expected := clone(state)
	check(expected.purchase(choice.purchase_key), "The original recommendation still uses its original purchase path")
	var previous_writes := writes
	click_recommendation()
	await layout()
	same(expected.to_data(), "Ordinary recommendation still charges exactly the original model purchase")
	check(writes == previous_writes and panel.selected == panel.OPERATION, "Ordinary purchase does not call the independent contract gateway")

func run() -> void:
	if DisplayServer.get_name() != "headless":
		push_error("Contract recommendation verification requires isolated headless mode")
		quit(1)
		return
	Engine.max_fps = 60
	shop = Shop.new()
	root.add_child(shop)
	shop.set_process(false)
	if shop.art != null: shop.art.set_process(false)
	shop.open_management()
	panel = shop.management
	panel.set_process(false)
	await layout()
	verify_candidates()
	await verify_payments_and_layout()
	await verify_held_and_invalidated_actions()
	await verify_save_failure_and_frozen_result()
	await verify_ordinary_action_preserved()
	if failures == 0: print("CONTRACT RECOMMENDATION PASS: %d isolated checks; unlock/funds/max filters, 3 real prices and chance effects, pure query/state/RNG, one saved charge, formal-button equivalence, held target, invalidation without charge, failed-save rollback and visible retry, frozen negotiation, ordinary purchase, existing coin/glyph geometry; no GUI/player files" % checks)
	else: print("CONTRACT RECOMMENDATION FAILED: %d/%d" % [failures, checks])
	quit(1 if failures else 0)
