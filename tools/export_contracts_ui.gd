extends "res://tools/export_management_layout.gd"
## File-only proof of the actual UI tree and TextServer glyphs, no visible game.
const F = preload("res://tests/contracts_fixture.gd")

func _initialize() -> void:
	assert(DisplayServer.get_name() == "headless")
	set_meta("isolated_preview", true)
	server = TextServerManager.get_primary_interface()
	output = "res://.verification/contracts-ui-20261015/files"
	strict_export_bounds = false
	allow_text_clipping = true
	call_deferred("run")

func option(state: RefCounted, partner: String, id: String) -> Dictionary:
	for choice in state.contracts.partner_view(state, partner).options:
		if choice.id == id: return choice.token
	return {}

func base(state: RefCounted, id: String = "caravan") -> void:
	assert(state.contracts.accept(state, id, option(state, id, "basic")).ok)

func fixture_case(item: Dictionary) -> void:
	shop.state = F.completed()
	var state: RefCounted = shop.state
	var model: RefCounted = state.contracts
	match item.id:
		"locked": state.progression.expansion.regions.erase("star_garden")
		"success":
			model.seed = 1
			assert(model.negotiate(state, "caravan", option(state, "caravan", "payment")).success)
		"failure":
			model.seed = 40000
			assert(not model.negotiate(state, "caravan", option(state, "caravan", "relationship")).success)
		"upgrade", "pending":
			base(state)
			model.partners.caravan.points = 60
			if item.id == "pending":
				model.seed = 1
				assert(model.negotiate(state, "caravan", option(state, "caravan", "payment")).success)
				assert(model.accept(state, "caravan", option(state, "caravan", "payment")).ok)
		"waiting":
			base(state)
			F.clear_materials(state)
		"max-options", "max-delivery":
			model.partners.caravan.points = 600
			if item.id == "max-delivery":
				assert(model.negotiate(state, "caravan", option(state, "caravan", "payment")).success)
				assert(model.accept(state, "caravan", option(state, "caravan", "payment")).ok)
		"statistics":
			state.progression.clock = 90061.0
			state.total_sales_gold = 1234567
			state.total_spent_materials = 123456
			state.total_spent_expeditions = 8901
			state.progression.totals.brewed = 1245
			state.progression.totals.sold = 1100
			model.totals = {"paid": 45321, "shipped": 240, "rounds": 12, "points": 360}
		"training": model.training = 1
	if item.get("all_active", false):
		for id in ["caravan", "academy", "grove"]: base(state, id)
	panel.size = Vector2i(520, int(item.get("height", 800)))
	panel.close_contracts()
	panel.select_page(int(item.get("page", 0)))
	panel.scroll.scroll_vertical = 0
	if item.get("contracts", true):
		panel.open_contracts()
		var screen: Control = panel.contracts_view
		screen.scroll.scroll_vertical = 0
		for row in screen.rows.values():
			row.toggle.set_pressed(false)
			row.negotiation.hide()
		if item.get("offers", false): screen.rows.caravan.negotiation.show()
		if item.get("details", false): screen.rows.caravan.toggle.set_pressed(true)
		if item.get("back", false): panel.close_contracts()
	else:
		for row in panel.rows.values(): row.toggle.set_pressed(false)
		if item.id == "training": panel.rows.contract_training.toggle.set_pressed(true)
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
		{"id": "locked", "label": "해금 전 · 별의 정원 조건"},
		{"id": "partners", "label": "세 거래처 · 실제 자동 납품", "all_active": true},
		{"id": "first-proposal", "label": "첫 계약 · 기본/대금/거래 관계", "offers": true},
		{"id": "success", "label": "흥정 성공 · 개선 조건 수락", "offers": true},
		{"id": "failure", "label": "흥정 실패 · 기본 계약 유지", "offers": true},
		{"id": "upgrade", "label": "등급 상승 · 미협의 상태", "offers": true},
		{"id": "pending", "label": "새 조건 적용 대기 · 현재 회차 보존", "details": true},
		{"id": "waiting", "label": "자동 납품 · 실제 재료 대기"},
		{"id": "max-options", "label": "최고 등급 · 100%와 두 선택지", "offers": true},
		{"id": "max-delivery", "label": "최고 등급 · 자동 반복"},
		{"id": "unit-prices", "label": "수락 전 품목별 단가 · 상세", "details": true},
		{"id": "training", "label": "가구·직원 · 독립 흥정 훈련", "contracts": false, "page": 5},
		{"id": "statistics", "label": "기존 누적 보존 · 계약 별도 12통계", "contracts": false, "page": 6},
		{"id": "short", "label": "600px 관리 · 같은 본문 크기", "height": 600, "offers": true},
		{"id": "back", "label": "돌아가기 · 기존 운영 화면", "back": true},
	]
	for item in samples:
		fixture_case(item)
		for frame in 4: await process_frame
		if item.id == "training":
			panel.scroll.ensure_control_visible(panel.rows.contract_training.panel)
			for frame in 3: await process_frame
		var before: Dictionary = shop.state.to_data().duplicate(true)
		commands = []
		nodes = []
		var boundary: Control = panel.get_child(0)
		export_node(boundary, boundary, Rect2(Vector2.ZERO, Vector2(panel.size)))
		assert(Compare.equivalent(before, shop.state.to_data()), "File proof cannot mutate state or RNG")
		cases.append({"id": item.id, "label": item.label, "size": vector(Vector2(panel.size)), "commands": commands.duplicate(true), "nodes": nodes.duplicate(true), "header": header_data(boundary), "background": "1d242bff"})
	var file := FileAccess.open(output.path_join("management.json"), FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"verification": "Actual isolated Control/TextServer file export; no GUI, player save, native input or process", "font": ProjectSettings.globalize_path(FONT.resource_path), "palette": "sage", "cases": cases}, "\t"))
	file.close()
	panel.free()
	shop.free()
	print("CONTRACTS UI FILE EXPORT PASS: ", cases.size(), " actual layouts, original partner pixels, 520px/18+16px, state and RNG preserved")
	quit()
