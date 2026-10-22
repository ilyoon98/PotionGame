extends "res://tools/export_management_layout.gd"
## Actual Control/TextServer file proof; never a visible game or desktop capture.
const Fixtures = preload("res://tools/f19_management_fixture.gd")
const F18 = preload("res://tests/contracts_fixture.gd")

func _initialize() -> void:
	assert(DisplayServer.get_name() == "headless")
	set_meta("isolated_preview", true)
	server = TextServerManager.get_primary_interface()
	output = "res://.verification/f19-20261019/ui-files"
	if "--final" in OS.get_cmdline_user_args(): output += "-final"
	strict_export_bounds = false
	allow_text_clipping = true
	call_deferred("run")

func sample(item: Dictionary) -> void:
	shop.state = Fixtures.completed(int(item.get("rank", 1)), int(item.get("training", 0)), bool(item.get("all", false)))
	var state: RefCounted = shop.state
	if item.id == "growth-locked": state.progression.owned.erase("vigor")
	if item.id == "training-future": Fixtures.accept_basic(state, "caravan")
	if item.id == "training-exhausted":
		for partner in state.contracts.PARTNERS: Fixtures.accept_basic(state, partner.id)
	if item.id == "funds": state.gold = 149999
	if item.get("supply", 0) > 0:
		Fixtures.buy_to(state, "supply_support", int(item.supply))
		state.late_investments.supply.elapsed = 23.5
	if item.get("bulk", 0) > 0: Fixtures.buy_to(state, "contract_batch", int(item.bulk))
	if item.get("shortage", false): F18.clear_materials(state)
	if item.id == "supply-none": state.progression.owned.clear()
	panel.size = Vector2i(520, int(item.get("height", 800)))
	panel.close_contracts()
	for row in panel.rows.values(): row.toggle.set_pressed(false)
	panel.select_page(int(item.get("page", 5)))
	panel.scroll.scroll_vertical = 0
	var target: String = str(item.get("target", ""))
	if not target.is_empty(): panel.rows[target].toggle.set_pressed(bool(item.get("details", false)))
	if item.get("contracts", false):
		panel.open_contracts()
		panel.contracts_view.scroll.scroll_vertical = 0
		for row in panel.contracts_view.rows.values(): row.toggle.set_pressed(false)
		panel.contracts_view.rows.caravan.toggle.set_pressed(true)
	panel.refresh()

func run() -> void:
	assert(DirAccess.make_dir_recursive_absolute(output.path_join("textures")) == OK)
	shop = Shop.new()
	root.add_child(shop)
	shop.set_process(false)
	if shop.art != null: shop.art.set_process(false)
	shop.open_management()
	panel = shop.management
	panel.set_process(false)
	var cases := []
	var samples := [
		{"id": "training-nine", "label": "훈련 · 앞으로 적용 가능한9회", "target": "contract_training", "details": true},
		{"id": "training-future", "label": "현재 협의 종료 · 미래등급은 남음", "target": "contract_training", "details": true},
		{"id": "training-exhausted", "label": "3등급 모두 소진 · 적용할 흥정 없음", "rank": 3, "all": true, "target": "contract_training", "details": true},
		{"id": "training-final", "label": "4등급 보장 협의 · 훈련낭비 차단", "rank": 4, "all": true, "target": "contract_training", "details": true},
		{"id": "growth-locked", "label": "후반 투자 · 부족한 기존 성장 조건", "training": 3, "target": "late:supply_support", "details": true},
		{"id": "rank-locked", "label": "기존 성장 완료 · 거래2등급 필요", "training": 3, "target": "late:supply_support", "details": true},
		{"id": "funds", "label": "거래 등급 충족 · 실제 부족골드", "rank": 2, "training": 3, "target": "late:supply_support", "details": true},
		{"id": "late-ready", "label": "후반 투자 · 독립적인 두 갈래", "rank": 2, "training": 3, "target": "late:supply_support"},
		{"id": "late-max", "label": "최대 투자 · 실제 최종 효과", "rank": 4, "training": 3, "supply": 3, "bulk": 3, "target": "late:supply_support", "details": true},
		{"id": "supply-herbs", "label": "약초 · 실제 보급 주기와 예약3개", "rank": 4, "training": 3, "supply": 3, "shortage": true, "page": 1, "target": "supply_support", "details": true},
		{"id": "supply-operation", "label": "가게 운영 · 같은 보급 게이지", "rank": 4, "training": 3, "supply": 3, "shortage": true, "page": 0, "target": "gather_supply_support", "details": true},
		{"id": "supply-full", "label": "보급 후보 전부 가득 · 주기는 유지", "rank": 2, "training": 3, "supply": 1, "page": 1, "target": "supply_support"},
		{"id": "supply-none", "label": "극단 fixture · 보급 대상 없음", "rank": 2, "training": 3, "supply": 1, "page": 1, "target": "supply_support"},
		{"id": "bulk-detail", "label": "수주 상세 · 한 번에 최대4병", "rank": 4, "training": 3, "bulk": 3, "contracts": true},
		{"id": "recommend-training", "label": "추천70 · 유효한 흥정 훈련", "rank": 2, "page": 0},
		{"id": "recommend-supply", "label": "추천65 · 보급 지원 직접 투자", "rank": 2, "training": 3, "page": 0},
		{"id": "recommend-bulk", "label": "추천60 · 납품 일괄 조제", "rank": 2, "training": 3, "supply": 1, "page": 0},
		{"id": "short", "label": "600px · 폰트와 두 투자 행 유지", "rank": 2, "training": 3, "height": 600, "target": "late:supply_support", "details": true},
		{"id": "late-stage-one", "label": "1단계 구매 · 현재에서 다음 효과", "rank": 3, "training": 3, "supply": 1, "bulk": 1, "target": "late:supply_support"},
		{"id": "return", "label": "수주에서 돌아오기 · 원래 스크롤", "rank": 2, "training": 3, "target": "late:supply_support"},
		{"id": "next-stale", "label": "오래된 단계 거부 · 다른 투자 무차감", "rank": 2, "training": 3, "page": 0},
	]
	for item in samples:
		sample(item)
		for frame in 4: await process_frame
		var target: String = str(item.get("target", ""))
		if not target.is_empty():
			panel.scroll.ensure_control_visible(panel.rows[target].panel)
			if target.begins_with("late:"): panel.scroll.scroll_vertical = maxi(0, int(panel.rows[target].panel.position.y) - 28)
			for frame in 3: await process_frame
		if item.id == "return":
			var original_scroll: int = panel.scroll.scroll_vertical
			var original_page: int = panel.selected
			var original_model: Dictionary = shop.state.to_data().duplicate(true)
			panel.open_contracts()
			for frame in 3: await process_frame
			panel.contracts_view.back_button.pressed.emit()
			for frame in 3: await process_frame
			assert(panel.selected == original_page and panel.scroll.scroll_vertical == original_scroll and Compare.equivalent(original_model, shop.state.to_data()), "The actual Back action preserves its original page, scroll and model")
		if item.id == "next-stale":
			panel.recommend_button.button_down.emit()
			assert(shop.perform_late_investment_action("supply_support", 1).ok)
			var paid_model: Dictionary = shop.state.to_data().duplicate(true)
			panel.recommend_button.pressed.emit()
			for frame in 3: await process_frame
			assert(Compare.equivalent(paid_model, shop.state.to_data()) and panel.recommend_feedback.contains("변경"), "The file shows a real rejected stale token without another charge")
		var before: Dictionary = shop.state.to_data().duplicate(true)
		commands = []
		nodes = []
		var boundary: Control = panel.get_child(0)
		export_node(boundary, boundary, Rect2(Vector2.ZERO, Vector2(panel.size)))
		assert(Compare.equivalent(before, shop.state.to_data()), "F19 file export preserves every model field and RNG")
		cases.append({"id": item.id, "label": item.label, "size": vector(Vector2(panel.size)), "commands": commands.duplicate(true), "nodes": nodes.duplicate(true), "header": header_data(boundary), "background": "1d242bff"})
	var file := FileAccess.open(output.path_join("management.json"), FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"verification": "Isolated actual Controls and TextServer glyphs, no GUI/player data/desktop capture", "font": ProjectSettings.globalize_path(FONT.resource_path), "palette": "sage", "cases": cases}, "\t"))
	file.close()
	panel.free()
	shop.free()
	print("F19 MANAGEMENT FILE EXPORT PASS: ", cases.size(), " actual layouts, original assets/520px/Pretendard18+16, unchanged model/RNG")
	quit()
