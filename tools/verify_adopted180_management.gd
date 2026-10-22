extends "res://tools/export_management_layout.gd"
## Adopted 150/300/450k policy. Actual in-memory gateway/Controls only.
const Fixtures = preload("res://tools/f19_management_fixture.gd")
const F18 = preload("res://tests/contracts_fixture.gd")
const Status = preload("res://scripts/management_status.gd")
const Centered = preload("res://scripts/centered_button_content.gd")
var checks := 0
var failures := 0
var writes := 0
var cases := []
var ledger := []

func _initialize() -> void:
	assert(DisplayServer.get_name() == "headless")
	set_meta("isolated_preview", true)
	server = TextServerManager.get_primary_interface()
	output = "res://.verification/f19-adopted180-20261019/ui"
	strict_export_bounds = false
	allow_text_clipping = true
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func save_ok() -> bool:
	writes += 1
	return true

func setup(track: String, gold: int, both_two: bool = false) -> RefCounted:
	var state := Fixtures.completed(4, 3)
	for id in Status.LATE_TRACKS: Fixtures.buy_to(state, id, 2 if id == track or both_two else 3)
	state.gold = gold
	shop.state = state
	shop.set_meta("late_save_fixture", save_ok)
	panel.close_contracts()
	panel.recommend_pressed_action = ""
	panel.recommend_pressed_next_level = 0
	panel.recommend_feedback = ""
	panel.late_feedback.clear()
	for row in panel.rows.values(): row.toggle.set_pressed(false)
	return state

func layout(page: int) -> void:
	panel.select_page(page)
	panel.refresh()
	for frame in 4: await process_frame

func purchase_geometry(button: Button) -> void:
	var geometry := Centered.rects(button)
	var original_gap := 8 if button == panel.recommend_button else 6
	check(button.icon == Currency.COIN and str(button.get_meta("currency_source", "")).contains("450,000 G"), "The real original coin and comma-formatted adopted price are used")
	check(geometry.fits and geometry.gap == original_gap and absf(geometry.block.get_center().x - button.size.x / 2.0) <= 1.0, "The native coin/action/price group fits with its unchanged formal6px/recommendation8px centered gap")
	check(button.get_theme_font_size("font_size") == 16, "Adopting the new price retains the existing readable font size")

func capture(id: String, label: String, track: String = "") -> void:
	if panel.selected == panel.UPGRADES and not track.is_empty():
		var target: Control = panel.rows["late:" + track].panel
		panel.scroll.scroll_vertical = maxi(0, int(target.position.y) - 28)
		for frame in 3: await process_frame
	var before: Dictionary = shop.state.to_data().duplicate(true)
	commands = []
	nodes = []
	var boundary: Control = panel.get_child(0)
	export_node(boundary, boundary, Rect2(Vector2.ZERO, Vector2(panel.size)))
	check(Compare.equivalent(before, shop.state.to_data()), "Adopted-price file extraction does not change State, time, inventory or RNG")
	cases.append({"id": id, "label": label, "size": vector(Vector2(panel.size)), "commands": commands.duplicate(true), "nodes": nodes.duplicate(true), "background": "1d242bff"})

func test_track(track: String) -> void:
	var state := setup(track, 449999)
	await layout(panel.UPGRADES)
	var row: Dictionary = panel.rows["late:" + track]
	var view: Dictionary = Status.late_investment(state, track)
	check(int(view.cost) == 450000 and int(view.next_level) == 3, "Both third-stage views read the same adopted 450000 price and real next level")
	check(row.button.disabled and str(row.button.get_meta("currency_source", "")).contains("1 G 부족"), "At449999 the exact one-gold shortage is disabled on the formal row")
	check(not Status.growth_candidates(state).any(func(item): return item.purchase_key == "late:" + track), "The unaffordable third stage is excluded from executable recommendations")
	await capture(track + "-short-one", "3단계45만 · 1골드 부족", track)
	var before: Dictionary = state.to_data().duplicate(true)
	var saves := writes
	row.button.button_down.emit()
	row.button.pressed.emit()
	check(Compare.equivalent(before, state.to_data()) and writes == saves, "Invoking an old unaffordable action cannot charge or save")
	state = setup(track, 450000)
	await layout(panel.UPGRADES)
	row = panel.rows["late:" + track]
	purchase_geometry(row.button)
	check(not row.button.disabled and int(row.button.get_meta("next_level")) == 3, "Exactly450000 enables the actual formal third-stage token")
	await capture(track + "-formal", "정식3단계 · 실제45만 결제", track)
	saves = writes
	var spent: int = state.progression.totals.manual_spent
	var reservation: Dictionary = state.late_investments.supply.duplicate(true)
	row.button.button_down.emit()
	row.button.pressed.emit()
	await layout(panel.UPGRADES)
	check(state.gold == 0 and int(state.late_investments.stages[track]) == 3 and state.progression.totals.manual_spent - spent == 450000 and writes == saves + 1, "Formal purchase pays exactly450000 once through the saved gateway")
	var purchase_writes := writes - saves
	check(state.late_investments.supply == reservation, "The changed third-stage price does not restart or replace an in-flight supply reservation")
	check(row.completed and row.button.disabled and row.button.text == "최대 단계" and not row.button.tooltip_text.contains("450,000"), "A newly owned maximum has no repurchase price or duplicate row")
	before = state.to_data().duplicate(true)
	saves = writes
	row.button.pressed.emit()
	check(Compare.equivalent(before, state.to_data()) and writes == saves, "An immediate duplicate release cannot spend another third-stage price")
	ledger.append({"track": track, "surface": "formal", "gold_before": 450000, "gold_after": state.gold, "paid": state.progression.totals.manual_spent - spent, "next_level": 3, "purchase_save_count": purchase_writes, "duplicate_release_save_count": writes - saves})
	state = setup(track, 450000)
	await layout(panel.OPERATION)
	check(panel.recommendation.purchase_key == "late:" + track and int(panel.recommendation.cost) == 450000 and int(panel.recommendation.next_level) == 3, "Operation recommends the same affordable target/stage/450000 price")
	purchase_geometry(panel.recommend_button)
	await capture(track + "-recommendation", "가게운영 추천 · 같은45만")
	saves = writes
	spent = state.progression.totals.manual_spent
	panel.recommend_button.button_down.emit()
	panel.recommend_button.pressed.emit()
	check(state.gold == 0 and state.progression.totals.manual_spent - spent == 450000 and writes == saves + 1 and int(state.late_investments.stages[track]) == 3, "Recommended purchase uses the same saved450000 transaction as the formal row")
	ledger.append({"track": track, "surface": "recommendation", "gold_before": 450000, "gold_after": state.gold, "paid": state.progression.totals.manual_spent - spent, "next_level": 3})
	state = setup(track, 900000)
	await layout(panel.UPGRADES)
	row = panel.rows["late:" + track]
	row.button.button_down.emit()
	check(shop.perform_late_investment_action(track, 3).ok, "Another transaction advances a formally held third-stage token")
	await layout(panel.UPGRADES)
	before = state.to_data().duplicate(true)
	saves = writes
	row.button.pressed.emit()
	await layout(panel.UPGRADES)
	check(Compare.equivalent(before, state.to_data()) and writes == saves and str(panel.late_feedback.get(track, "")).contains("변경"), "The formal row also validates its held next-level token after rerender without a second charge")
	await capture(track + "-formal-stale", "정식 옛3단계 거부 · 재차감 없음", track)
	# Hold a real third-stage target, then complete it through another gateway.
	# Supply's replacement is bulk; bulk's replacement is the empty recommendation.
	state = setup(track, 900000, track == "supply_support")
	await layout(panel.OPERATION)
	check(panel.recommendation.purchase_key == "late:" + track, "The pressed recommendation starts on the intended real third stage")
	panel.recommend_button.button_down.emit()
	check(shop.perform_late_investment_action(track, 3).ok, "Another genuine action purchases the held stage first")
	await layout(panel.OPERATION)
	check(panel.recommendation.get("purchase_key", "") != "late:" + track, "The displayed recommendation changes before release")
	if track == "supply_support": check(panel.recommendation.purchase_key == "late:contract_batch", "The changed live recommendation names the other investment branch")
	before = state.to_data().duplicate(true)
	saves = writes
	panel.recommend_button.pressed.emit()
	await layout(panel.OPERATION)
	check(Compare.equivalent(before, state.to_data()) and writes == saves and panel.recommend_feedback.contains("변경"), "The old held target/next stage is rejected instead of purchasing its replacement")
	await capture(track + "-stale", "옛3단계 거부 · 대체추천 무차감")

func old_owned() -> void:
	var previous := Fixtures.completed(4, 3)
	for track in Status.LATE_TRACKS: Fixtures.buy_to(previous, track, 3)
	# Previously valid v11 history paid600000 for both last stages. No refund.
	previous.gold = 7900000
	previous.progression.totals.manual_spent = 2100000
	previous.late_investments.supply.elapsed = 23.5
	var saved: Dictionary = F18.data(previous)
	var restored := State.new()
	check(restored.load_data(saved) and Compare.equivalent(saved, restored.to_data()), "An already-maxed historical2.1m v11 preserves cash, spending, levels and active cycle without refund")
	shop.state = restored
	await layout(panel.UPGRADES)
	for track in Status.LATE_TRACKS:
		var row: Dictionary = panel.rows["late:" + track]
		check(row.completed and row.button.disabled and row.button.text == "최대 단계" and not row.button.tooltip_text.contains("450,000") and not row.button.tooltip_text.contains("600,000"), "Previously owned maximum has neither a repurchase nor a refund price")
	var before: Dictionary = restored.to_data().duplicate(true)
	for track in Status.LATE_TRACKS: check(not shop.perform_late_investment_action(track, 3).ok, "The historical owned level cannot be repurchased")
	check(Compare.equivalent(before, restored.to_data()) and Status.recommendation(restored).is_empty(), "Old ownership is unchanged and never recommended again")
	check(panel.tabs.size() == 7 and panel.pages.size() == 8 and panel.statistics_values.size() == 12 and panel.size.x == 520, "Price adoption retains seven tabs, twelve cumulative statistics and520px layout")
	panel.late_feedback.clear()
	panel.recommend_feedback = ""
	for row in panel.rows.values(): row.toggle.set_pressed(false)
	await layout(panel.UPGRADES)
	await capture("historical-owned-max", "과거60만 구매 · 재구매·환급 없음", "supply_support")
	ledger.append({"track": "both", "surface": "old_owned_v11", "gold": restored.gold, "manual_spent": restored.progression.totals.manual_spent, "stages": restored.late_investments.stages, "supply": restored.late_investments.supply, "unchanged": Compare.equivalent(before, restored.to_data())})

func run() -> void:
	assert(DirAccess.make_dir_recursive_absolute(output.path_join("textures")) == OK)
	shop = Shop.new()
	root.add_child(shop)
	shop.set_process(false)
	if shop.art != null: shop.art.set_process(false)
	shop.open_management()
	panel = shop.management
	panel.set_process(false)
	check(State.LateInvestments.COSTS == [150000, 300000, 450000], "The single production cost table is exactly the adopted policy")
	for track in Status.LATE_TRACKS: await test_track(track)
	await old_owned()
	F18.write_json(output.path_join("management.json"), {"verification": "Actual isolated Controls/TextServer file composites, not screenshots; no player save or normal process access", "font": ProjectSettings.globalize_path(FONT.resource_path), "palette": "sage", "cases": cases})
	F18.write_json(output.path_join("proof.json"), {"checks": checks, "failures": failures, "costs": State.LateInvestments.COSTS, "six_total": 1800000, "file_cases": cases.size(), "ledger": ledger})
	panel.free()
	shop.free()
	print("ADOPTED180 MANAGEMENT ", "PASS" if failures == 0 else "FAIL", ": ", checks, " isolated checks; both branches450000 formal/recommended original-coin prices,449999 shortage, exact saved payment, held target/next-stage rejection and historical max without refund; ", cases.size(), " real Control/TextServer file cases; no GUI/player data")
	quit(1 if failures > 0 else 0)
