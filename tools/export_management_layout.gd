extends "res://tools/export_expedition_cards.gd"
## Share actual Control/TextServer glyph export; the whole window adds viewport clips.
var sage_preview := false
var statistics_preview := false

func _initialize() -> void:
	assert(DisplayServer.get_name() == "headless")
	set_meta("isolated_preview", true)
	server = TextServerManager.get_primary_interface()
	output = "res://.verification/management-layout-20261013"
	sage_preview = "--sage" in OS.get_cmdline_user_args()
	statistics_preview = "--stats" in OS.get_cmdline_user_args()
	assert(not (sage_preview and statistics_preview), "Select exactly one output proof mode")
	if sage_preview: output = "res://.verification/management-sage-20261013"
	if statistics_preview: output = "res://.verification/management-statistics-20261013"
	strict_export_bounds = false
	allow_text_clipping = true
	call_deferred("run")

func setup_fixture(amount: int) -> void:
	shop.state = fixture()
	var state: RefCounted = shop.state
	var p: RefCounted = state.progression
	state.gold = amount
	p.reputation = amount
	p.clock = 240.0
	p.owned = ["moon"]
	p.rare_herbs = 5
	state.herbs = 20
	state.stock = 4
	state.inventory = [false, true, false, true]
	state.mana_stock = 2
	state.brew_active = true
	state.brew_elapsed = state.brew_duration() * 0.4
	p.active_recipe = false
	state.customer_elapsed = state.customer_interval() * 0.6
	p.customer_selected = true
	p.customer = 0
	state.harvest_elapsed = state.harvest_duration() * 0.35
	var cycle: Dictionary = p.expansion.cycles.forest_edge
	cycle.merge({"running": true, "elapsed": 28.0, "duration": 70.0}, true)
	p.expansion.pending = {}
	# Synthetic aggregate fields exercise the report without simulating or paying.
	p.report_started = "2026-10-13T12:00:00"
	p.totals.harvested = 24
	p.totals.brewed = 12
	p.totals.sold = 10
	p.totals.reputation = 18
	state.total_sales_gold = 560
	state.total_spent_materials = 80
	state.total_spent_expeditions = 16
	p.expansion.reward_totals = {"dewgrass": 6, "starleaf": 2}

func statistics_fixture(item: Dictionary) -> void:
	var state: RefCounted = shop.state
	var p: RefCounted = state.progression
	p.reputation = int(item.get("reputation", item.amount))
	if item.get("statistics", "") == "zero":
		p.clock = 0.0
		state.total_sales_gold = 0
		state.total_spent_materials = 0
		state.total_spent_expeditions = 0
		state.total_sold = 0
		p.expedition_count = 0
		p.expansion.returns = {}
		p.expansion.reward_totals = {}
		for key in p.totals: p.totals[key] = 0
	else:
		p.clock = 90061.0
		state.total_sales_gold = 1234567
		state.total_spent_materials = 123456
		state.total_spent_expeditions = 8901
		state.total_sold = 1100
		p.totals.brewed = 1245
		p.totals.sold = 1100
		p.totals.expeditions = 17
		p.totals.reputation = 29609
		p.expedition_count = 12
		p.expansion.returns = {"ruined_greenhouse": 5}
		if item.get("statistics", "") == "negative":
			state.total_sales_gold = 1234
			state.total_spent_materials = 12345
			state.total_spent_expeditions = 89
		elif item.get("statistics", "") == "long":
			state.total_sales_gold = 999999999999
			state.total_spent_materials = 111111111111
			state.total_spent_expeditions = 222222222222
			state.total_sold = 999999999
			p.totals.brewed = 999999999
			p.totals.sold = 999999999
			p.totals.reputation = 999999999999
	# Deliberately distinct report baselines verify the new view is cumulative.
	p.last_report_clock = maxf(0.0, p.clock - 1.0)
	p.report_sales = maxi(0, state.total_sales_gold - 7)
	p.report_materials = maxi(0, state.total_spent_materials - 3)
	p.report_expeditions = maxi(0, state.total_spent_expeditions - 2)

func local_rect(node: Control, boundary: Control) -> Array:
	var area := node.get_global_rect()
	area.position -= boundary.global_position
	return rectangle(area)

func header_data(boundary: Control) -> Dictionary:
	var data := {"gold": {"group": local_rect(panel.gold_group, boundary), "icon": local_rect(panel.gold_icon, boundary), "value": local_rect(panel.gold_label, boundary), "text": panel.gold_label.text, "tooltip": panel.gold_label.tooltip_text}, "reputation": {"group": local_rect(panel.reputation_group, boundary), "icon": local_rect(panel.reputation_icon, boundary), "value": local_rect(panel.reputation_label, boundary), "text": panel.reputation_label.text, "tooltip": panel.reputation_label.tooltip_text}, "heading": local_rect(panel.heading, boundary), "result": local_rect(panel.result_button, boundary), "result_text": panel.result_button.text, "result_has_icon": panel.result_button.icon != null, "close": local_rect(panel.close_button, boundary), "title_drag": local_rect(panel.title_drag_handle, boundary), "headless_borderless_getter": panel.borderless, "borderless_source_requested": str(panel.get_script().source_code).contains("borderless = true"), "native_window_flags_verified": false, "native_note": "Headless exposes dummy Window flags; actual Windows titlebar/drag/focus not exercised."}
	for entry in [{"key": "gold", "property": "gold_caption"}, {"key": "reputation", "property": "reputation_caption"}]:
		if has_property(panel, entry.property):
			var caption: Label = panel.get(entry.property)
			data[entry.key]["caption"] = {"rect": local_rect(caption, boundary), "text": caption.text, "font_size": caption.get_theme_font_size("font_size")}
	return data

func statistics_data(boundary: Control) -> Dictionary:
	if not has_property(panel, "statistics_values") or panel.selected != panel.REPORT: return {}
	var data := {}
	for key in panel.statistics_values:
		var value: Control = panel.statistics_values[key]
		data[key] = {"rect": local_rect(value, boundary), "source_text": value.source_text, "text": value.get_parsed_text(), "font_size": value.get_theme_font_size("normal_font_size"), "alignment": value.money_alignment, "actual_line_count": value.get_line_count()}
	return data

func optional_ledger(open: bool) -> void:
	if has_property(panel, "ledger_toggle") and is_instance_valid(panel.get("ledger_toggle")): panel.get("ledger_toggle").set_pressed(open)

func ledger_is_open() -> bool:
	return has_property(panel, "ledger_box") and is_instance_valid(panel.get("ledger_box")) and panel.get("ledger_box").visible

func preview_cases() -> Array:
	if statistics_preview:
		return [{"id": "header-zero", "page": 0, "amount": 0, "reputation": 0, "label": "새 헤더 / 골드·명성 0"}, {"id": "header-sample", "page": 0, "amount": 487681, "reputation": 29609, "label": "새 헤더 / 487,681·29,609"}, {"id": "header-large", "page": 0, "amount": 9999999999999999, "reputation": 9999999999999999, "label": "새 헤더 / 긴 숫자·정확한 툴팁"}, {"id": "statistics-normal", "page": 6, "amount": 487681, "reputation": 29609, "statistics": "normal", "label": "통계 / 전체 누적·쉼표"}, {"id": "statistics-zero", "page": 6, "amount": 0, "reputation": 0, "statistics": "zero", "label": "통계 / 0"}, {"id": "statistics-negative", "page": 6, "amount": 487681, "reputation": 29609, "statistics": "negative", "label": "통계 / 음수 순영업수입"}, {"id": "statistics-long", "page": 6, "amount": 999999999999, "reputation": 999999999999, "statistics": "long", "label": "통계 / 긴 금액·판매 수"}, {"id": "statistics-short", "page": 6, "amount": 487681, "reputation": 29609, "statistics": "normal", "height": 600, "label": "통계 / 짧은 600px 창"}, {"id": "statistics-short-bottom", "page": 6, "amount": 487681, "reputation": 29609, "statistics": "normal", "height": 600, "bottom": true, "label": "통계 / 600px 맨 아래 스크롤"}]
	if not sage_preview:
		return [{"id": "operation-zero", "page": 0, "amount": 0, "label": "가게 운영 · 골드/명성 0"}, {"id": "operation-21799", "page": 0, "amount": 21799, "label": "가게 운영 · 골드/명성 21,799"}, {"id": "herbs-weather", "page": 1, "amount": 21799, "label": "약초 · 환경 강조"}, {"id": "expeditions", "page": 4, "amount": 21799, "label": "원정 · 목록"}]
	return [{"id": "operation-21799", "page": 0, "amount": 21799, "label": "먹색·세이지 / 가게 운영"}, {"id": "herbs-weather", "page": 1, "amount": 21799, "label": "먹색·세이지 / 약초·환경 강조"}, {"id": "expeditions", "page": 4, "amount": 21799, "label": "먹색·세이지 / 원정 목록"}, {"id": "results-ledger", "page": 6, "amount": 21799, "ledger": true, "label": "먹색·세이지 / 결과·상세 장부"}, {"id": "staff-settings", "page": 5, "amount": 21799, "bottom": true, "label": "먹색·세이지 / 직원·화면 설정"}, {"id": "potions-details", "page": 2, "amount": 21799, "details": ["potion_health", "potion_moon"], "label": "먹색·세이지 / 포션 상세"}]

func run() -> void:
	assert(DirAccess.make_dir_recursive_absolute(output.path_join("textures")) == OK)
	shop = Shop.new()
	root.add_child(shop)
	shop.set_process(false)
	shop.open_management()
	panel = shop.management
	panel.set_process(false)
	var cases := []
	for item in preview_cases():
		setup_fixture(item.amount)
		if statistics_preview: statistics_fixture(item)
		for row in panel.rows.values(): row.toggle.set_pressed(false)
		optional_ledger(false)
		panel.size = Vector2i(520, int(item.get("height", 800)))
		var before: Dictionary = shop.state.to_data().duplicate(true)
		panel.select_page(item.page)
		panel.scroll.scroll_vertical = 0
		panel.page_scroll[item.page] = 0
		panel.refresh()
		if item.get("ledger", false): optional_ledger(true)
		for id in item.get("details", []):
			assert(panel.rows.has(id), "Detailed potion proof must target an actual row")
			panel.rows[id].toggle.set_pressed(true)
		for frame in range(4): await process_frame
		if item.has("focus_row"):
			assert(panel.rows.has(item.focus_row))
			panel.scroll.scroll_vertical = int(panel.rows[item.focus_row].panel.position.y)
			for frame in range(3): await process_frame
		if item.get("bottom", false):
			panel.scroll.scroll_vertical = int(panel.scroll.get_v_scroll_bar().max_value)
			for frame in range(3): await process_frame
		commands = []
		nodes = []
		var boundary: Control = panel.get_child(0)
		export_node(boundary, boundary, Rect2(Vector2.ZERO, Vector2(panel.size)))
		assert(panel.size.x == 520)
		var background: Color = boundary.get_theme_stylebox("panel").bg_color
		if sage_preview or statistics_preview: assert(background == Color("1d242b"), "Sage proof must be generated after production palette is ready")
		assert(Compare.equivalent(before, shop.state.to_data()), "Preview layout/selection must preserve economy, fees, RNG and saved progress")
		var highlight_rows := []
		for id in panel.rows:
			var row: Dictionary = panel.rows[id]
			if row.page == item.page and row.panel.visible and row.highlighted: highlight_rows.append(id)
		if item.page == panel.HERBS: assert(not highlight_rows.is_empty(), "The weather fixture must include a genuinely favored supplied herb")
		cases.append({"id": item.id, "label": item.label, "size": vector(Vector2(panel.size)), "page": item.page, "amount": item.amount, "reputation": shop.state.progression.reputation, "statistics": statistics_data(boundary), "commands": commands.duplicate(true), "nodes": nodes.duplicate(true), "highlighted_rows": highlight_rows, "scroll_rect": rectangle(panel.scroll.get_rect()), "scroll_value": panel.scroll.scroll_vertical, "details": item.get("details", []), "ledger_open": ledger_is_open(), "background": background.to_html(), "header": header_data(boundary)})
	var file := FileAccess.open(output.path_join("management.json"), FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"verification": "Actual headless Control geometry/TextServer glyphs with scroll clips; production palette; file compositing, no screen/desktop capture", "palette": "sage" if sage_preview or statistics_preview else "original", "font": ProjectSettings.globalize_path(FONT.resource_path), "cases": cases}, "\t"))
	panel.free()
	shop.free()
	print("MANAGEMENT LAYOUT EXPORT PASS: ", cases.size(), " 520px production-palette layouts; actual styles/dividers/tabs/header/button content/TextServer glyphs/toggle/slider/scroll clips; economy/save/RNG unchanged; headless only: ", ProjectSettings.globalize_path(output))
	quit()
