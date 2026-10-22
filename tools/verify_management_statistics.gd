extends SceneTree
## Read-only statistics in an isolated headless viewport; no player files or OS input.
const Shop = preload("res://scripts/shop.gd")
const State = preload("res://scripts/shop_state.gd")
const Currency = preload("res://scripts/currency_text.gd")
const Compare = preload("res://tests/state_compare.gd")
const CenteredButton = preload("res://scripts/centered_button_content.gd")
var shop: Control
var panel: Window
var checks := 0
var failures := 0
const KEYS := ["play_time", "net", "sales", "materials_cost", "fees", "brewed", "sold", "expeditions", "reputation_gain", "contract_paid", "contract_shipped", "contract_rounds"]
const MONEY := ["net", "sales", "materials_cost", "fees", "contract_paid"]

func _initialize() -> void:
	set_meta("isolated_preview", true)
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func layout() -> void:
	panel.refresh()
	await process_frame
	await process_frame

func verify_header_buttons() -> void:
	for fixture: Dictionary in [{"button": panel.result_button, "text": "통계", "path": "res://assets/icons/statistics.svg", "rect": Rect2(328, 16, 80, 34)}, {"button": panel.close_button, "text": "닫기", "path": "res://assets/icons/management_close.svg", "rect": Rect2(420, 16, 80, 34)}]:
		var button: Button = fixture.button
		check(button.text == fixture.text and not button.disabled and button.icon != null, "Both header actions retain active native buttons with their icon and label")
		if button.icon == null: continue
		check(button.get_rect() == fixture.rect, "Header icon additions preserve the original 80×34 hit areas")
		check(button.icon.get_size() == Vector2(16, 16) and button.icon.resource_path == fixture.path, "Each header action loads its correct 16px SVG")
		check(button.alignment == HORIZONTAL_ALIGNMENT_LEFT and button.icon_alignment == HORIZONTAL_ALIGNMENT_LEFT, "The icon and label remain one native content block")
		var geometry: Dictionary = CenteredButton.rects(button)
		check(geometry.fits and geometry.icon.size == Vector2(16, 16) and Rect2(Vector2.ZERO, button.size).encloses(geometry.block), "Complete native icon and text fit without clipping or shrinking")
		check(geometry.gap == 6 and absf(geometry.text.position.x - geometry.icon.end.x - 6.0) <= 1.0, "Each icon and label keep their 6px gap within native pixel rounding")
		check(absf(geometry.block.get_center().x - button.size.x / 2.0) <= 1.0, "The complete icon/label block is horizontally centered")
		check(geometry.margin_left >= 12 and geometry.margin_right >= 12 and is_equal_approx(geometry.margin_left, geometry.margin_right), "Both header actions retain equal minimum 12px side padding")

func verify_close_action() -> void:
	var before: Dictionary = shop.state.to_data().duplicate(true)
	var existing: Window = panel
	var selected: int = panel.selected
	var scroll: int = panel.scroll.scroll_vertical
	panel.close_button.pressed.emit()
	await process_frame
	await process_frame
	check(not panel.visible and is_instance_valid(panel), "The icon-bearing close button hides the same management window")
	check(Compare.equivalent(before, shop.state.to_data()), "Closing management changes no economy, RNG or saved model")
	shop.open_management()
	await layout()
	check(shop.management == existing and panel.visible and panel.selected == selected and panel.scroll.scroll_vertical == scroll, "Reopening preserves the same management window, statistics and scroll")
	check(Compare.equivalent(before, shop.state.to_data()), "Close and reopen remain read-only")

func verify_case(data: Dictionary) -> void:
	shop.state = State.new()
	var state: RefCounted = shop.state
	var p: RefCounted = state.progression
	p.clock = data.clock
	state.total_sales_gold = data.sales
	state.total_spent_materials = data.materials
	state.total_spent_expeditions = data.fees
	p.totals.brewed = 21799
	p.totals.sold = 1234
	p.totals.expeditions = 321
	p.totals.reputation = 6789
	p.totals.manual_spent = 987654 # Investments are not operating costs.
	p.last_report_clock = p.clock / 2.0
	p.report_sales = data.sales / 2
	p.report_materials = data.materials / 2
	p.report_expeditions = data.fees / 2
	for key in ["brewed", "sold", "expeditions", "reputation"]: p.report_baseline[key] = p.totals[key] / 2
	var before: Dictionary = state.to_data().duplicate(true)
	panel.result_button.pressed.emit()
	await layout()
	check(panel.selected == panel.REPORT and panel.pages[panel.REPORT].visible, "Statistics opens through the original real button")
	var expected := {"play_time": data.time, "net": data.net + " G", "sales": data.sales_text + " G", "materials_cost": data.materials_text + " G", "fees": data.fees_text + " G", "brewed": "21,799개", "sold": "1,234개", "expeditions": "321회", "reputation_gain": "6,789"}
	expected.merge({"contract_paid": "0 G", "contract_shipped": "0병", "contract_rounds": "0회"})
	for key in KEYS:
		var value: RichTextLabel = panel.statistics_values[key]
		check(value.source_text == expected[key], "Exact lifetime statistics, comma grouping and sign: " + key)
		check(value.money_alignment == HORIZONTAL_ALIGNMENT_RIGHT, "Every statistic retains right-aligned values: " + key)
		check(value.coin_count == (1 if key in MONEY else 0), "Only real currency amounts carry one original coin: " + key)
		check(Currency.pattern().search(value.get_parsed_text()) == null, "No numeric G suffix remains on screen: " + key)
		check(value.get_content_width() <= value.size.x + 1 and value.get_content_height() <= value.size.y + 1, "The complete statistic/coin fits without clipping: " + key)
		check(value.get_theme_font_size("normal_font_size") == (22 if key == "net" else 18), "Readable statistic values keep the intended size: " + key)
		check(value.get_theme_font("normal_font") == shop.body_font, "Statistics keep Pretendard")
	check(Compare.equivalent(before, state.to_data()), "Statistics never resets the existing period or changes save/RNG/economy")
	for page in panel.pages.size():
		panel.select_page(page)
		await layout()
		panel.result_button.pressed.emit()
		await layout()
	check(Compare.equivalent(before, state.to_data()), "All six tabs and statistics transitions preserve the complete serialized model")
	# The old period remains intact and can differ from the cumulative display.
	var summary: Dictionary = panel.Status.lifetime_summary(state)
	check(summary.seconds == int(data.clock) and summary.time == data.time and summary.net == data.net_value, "Read-only lifetime summary uses total clock and operating costs, independent of report baselines/manual investment")

func run() -> void:
	if DisplayServer.get_name() != "headless":
		push_error("Statistics check requires headless mode")
		quit(1)
		return
	Engine.max_fps = 60
	shop = Shop.new()
	root.add_child(shop)
	shop.set_process(false)
	shop.open_management()
	panel = shop.management
	panel.set_process(false)
	await layout()
	check(panel.tabs.size() == 7 and panel.pages.size() == 8, "Statistics keeps its independent page beside seven tabs")
	verify_header_buttons()
	# F21 (2026-10-22) appends a keeper/aging section after the original rows.
	check(panel.statistics_values.keys() == KEYS + ["keeper_sleeps", "keeper_faints", "fatigue_failed", "aged_sold", "aged_revenue"], "The original nine statistics retain their order, gain three contract totals, then the F21 keeper/aging rows")
	for property in panel.get_property_list():
		check(not str(property.name) in ["report", "report_rewards", "report_overview", "report_materials", "report_discoveries", "ledger_toggle", "ledger_box"], "Retired report/ledger widgets are removed")
	var controls: Array[Node] = panel.pages[panel.REPORT].find_children("*", "Button", true, false)
	check(controls.is_empty(), "Statistics has no ledger, reset, receipt or other action buttons")
	for data in [
		{"clock": 0.0, "time": "0시간 0분 0초", "sales": 0, "materials": 0, "fees": 0, "sales_text": "0", "materials_text": "0", "fees_text": "0", "net": "0", "net_value": 0},
		{"clock": 3661.9, "time": "1시간 1분 1초", "sales": 100001, "materials": 21799, "fees": 73, "sales_text": "100,001", "materials_text": "−21,799", "fees_text": "−73", "net": "+78,129", "net_value": 78129},
		{"clock": 90061.25, "time": "25시간 1분 1초", "sales": 10, "materials": 20001, "fees": 8, "sales_text": "10", "materials_text": "−20,001", "fees_text": "−8", "net": "−19,999", "net_value": -19999},
		{"clock": 99999999.75, "time": "27777시간 46분 39초", "sales": 123456789, "materials": 1234567, "fees": 654321, "sales_text": "123,456,789", "materials_text": "−1,234,567", "fees_text": "−654,321", "net": "+121,567,901", "net_value": 121567901}
	]: await verify_case(data)
	panel.size.y = 600
	panel.select_page(panel.REPORT)
	await layout()
	check(panel.scroll.get_rect().end.y == 580 and panel.scroll.get_rect().end.x == 500, "Statistics keeps its scroll inside a short management window: %s / window %s" % [panel.scroll.get_rect(), panel.size])
	check(panel.pages[panel.REPORT].size.y > panel.scroll.size.y, "The compact statistics scrolls at the shortest window size")
	await verify_close_action()
	if failures == 0: print("MANAGEMENT STATISTICS PASS: %d checks; correct 16px header action icons, 6px gaps and centered fitting native content, statistics-open/close-hide/reopen preserve the same window and model; exact zero/positive/negative/large cumulative time and comma values, four coin/sign fields, unchanged period/manual-investment rules/save/RNG, six tabs + read-only compact statistics, no ledger/reset widgets, short-window scroll; headless only" % checks)
	else: print("MANAGEMENT STATISTICS FAILED: %d of %d checks" % [failures, checks])
	quit(1 if failures else 0)
