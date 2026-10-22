extends "res://tools/export_management_layout.gd"
## Actual Control/TextServer file proofs, separate from older approved evidence.
const Content = preload("res://scripts/shop_content.gd")
const Rare = preload("res://scripts/rare_recipes.gd")
const Measure = preload("res://tools/measure_endgame_supply.gd")
const Status = preload("res://scripts/management_status.gd")

func _initialize() -> void:
	assert(DisplayServer.get_name() == "headless")
	set_meta("isolated_preview", true)
	server = TextServerManager.get_primary_interface()
	output = "res://.verification/special-management-20261013"
	strict_export_bounds = false
	allow_text_clipping = true
	call_deferred("run")

func sample(item: Dictionary) -> void:
	var maker := Measure.new()
	shop.state = maker.fixture(false)
	maker.free()
	var state: RefCounted = shop.state
	var p: RefCounted = state.progression
	Trips.ensure(p)
	for rare in Rare.ROWS:
		if item.get("rare", "unfound") in ["discovered", "owned"]: p.expansion.rare_discovered.append(rare.id)
		if item.get("rare", "unfound") == "owned": p.owned.append(rare.id)
	if item.get("special", false):
		var cycle: Dictionary = p.expansion.cycles.forest_edge
		cycle.merge({"id": 1, "mode": "special", "paid": true, "fee": 8, "duration": 49.0, "running": true, "elapsed": 18.0, "rewards": {}, "rare_valid": true, "rare_recipe": "rare_forest_breath", "rare_attempt": 1, "rare_success": false}, true)
	if item.get("active", false):
		state.brew_active = true
		p.active_recipe = "rare_mist_veil"
		p.batch_chance = p.success_chance(p.active_recipe)
		state.brew_elapsed = state.brew_duration() * 0.5
		p.expansion.materials.blue_reed = 0
		p.expansion.materials.silver_moss = 0
		p.expansion.materials.dewgrass = 0

func run() -> void:
	assert(DirAccess.make_dir_recursive_absolute(output.path_join("textures")) == OK)
	shop = Shop.new()
	root.add_child(shop)
	shop.set_process(false)
	shop.open_management()
	panel = shop.management
	panel.set_process(false)
	var cases := []
	var samples := [
		{"id": "icons-statistics", "page": 6, "target": "", "label": "통계 · 그래프와 닫기 아이콘"},
		{"id": "expedition-unfound", "page": 4, "target": "forest_edge", "label": "원정 · 미발견 지도"},
		{"id": "expedition-discovered", "page": 4, "target": "forest_edge", "rare": "discovered", "label": "원정 · 발견, 미구매"},
		{"id": "expedition-owned", "page": 4, "target": "forest_edge", "rare": "owned", "label": "원정 · 구매 완료"},
		{"id": "expedition-special", "page": 4, "target": "forest_edge", "special": true, "details": true, "label": "특별 탐색 · 재료 보상 없음"},
		{"id": "recipe-unfound", "page": 3, "target": "rare_forest_breath", "label": "레시피 · 정체와 배합 숨김"},
		{"id": "recipe-discovered", "page": 3, "target": "rare_forest_breath", "rare": "discovered", "label": "레시피 · 발견 후 구매와 배합"},
		{"id": "recipe-owned", "page": 3, "target": "rare_forest_breath", "rare": "owned", "label": "레시피 · 구매 완료"},
		{"id": "recipe-basic", "page": 3, "target": "basic", "label": "기본 체력과 마나 · 각 배합"},
		{"id": "potion-unfound", "page": 2, "target": "potion_rare_forest_breath", "label": "포션 · 특별 정체 숨김"},
		{"id": "potion-active-reserved", "page": 2, "target": "potion_rare_mist_veil", "rare": "owned", "active": true, "details": true, "label": "포션 · 현재 예약, 다음 병 부족"},
		{"id": "max-cauldron", "page": 5, "target": "cauldron", "details": true, "label": "최대 설비 · 실제 최종 효과"},
		{"id": "max-path", "page": 5, "target": "expedition_path", "details": true, "label": "최대 길 정비 · 자체16%"},
		{"id": "max-guide", "page": 5, "target": "expedition_guide", "details": true, "label": "최대 길잡이 · 자체14%"},
	]
	for item in samples:
		sample(item)
		if item.page == panel.UPGRADES: item.target = Status.investment(shop.state, item.target).target
		for row in panel.rows.values(): row.toggle.set_pressed(false)
		panel.size = Vector2i(520, 800)
		panel.select_page(item.page)
		panel.refresh()
		var before: Dictionary = shop.state.to_data().duplicate(true)
		panel.scroll.scroll_vertical = 0
		if not str(item.target).is_empty():
			assert(panel.rows.has(item.target), "Use actual row IDs")
			panel.rows[item.target].toggle.set_pressed(item.get("details", false))
		for frame in range(4): await process_frame
		if not str(item.target).is_empty():
			panel.scroll.ensure_control_visible(panel.rows[item.target].panel)
			for frame in range(3): await process_frame
		commands = []
		nodes = []
		var boundary: Control = panel.get_child(0)
		export_node(boundary, boundary, Rect2(Vector2.ZERO, Vector2(panel.size)))
		assert(Compare.equivalent(before, shop.state.to_data()), "Preview must preserve the entire model and RNG")
		cases.append({"id": item.id, "label": item.label, "size": vector(Vector2(panel.size)), "commands": commands.duplicate(true), "nodes": nodes.duplicate(true), "header": header_data(boundary), "background": "1d242bff", "target": item.target})
	var file := FileAccess.open(output.path_join("management.json"), FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"verification": "Isolated actual Control/font glyph file export, no GUI/save/input/process use", "font": ProjectSettings.globalize_path(FONT.resource_path), "palette": "sage", "cases": cases}, "\t"))
	file.close()
	panel.free()
	shop.free()
	print("SPECIAL MANAGEMENT EXPORT PASS: ", cases.size(), " cases, model preserved, actual header icons and discovery/blend/max effect Controls")
	quit()
