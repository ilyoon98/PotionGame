extends SceneTree
const Shop = preload("res://scripts/shop.gd")
const Status = preload("res://scripts/management_status.gd")
const Compare = preload("res://tests/state_compare.gd")
func _initialize() -> void:
	set_meta("isolated_preview", true)
	call_deferred("run")
func run() -> void:
	assert(DisplayServer.get_name() == "headless")
	var shop := Shop.new()
	root.add_child(shop)
	shop.set_process(false)
	shop.open_management()
	var panel: Window = shop.management
	panel.set_process(false)
	panel.select_page(panel.EXPEDITIONS)
	var state: RefCounted = shop.state
	var p: RefCounted = state.progression
	var row: Dictionary = panel.rows.forest_edge
	var height := -1.0
	for step in ["fame", "money", "ready", "opened"]:
		state.gold = 0 if step == "money" else 100000
		p.reputation = 0 if step == "fame" else 10000
		if step == "opened": row.button.pressed.emit()
		panel.refresh()
		await process_frame
		await process_frame
		if height < 0: height = row.panel.size.y
		if step == "opened":
			assert(not row.button.visible and row.work.box.visible)
		else:
			assert(is_equal_approx(row.panel.size.y, height), "Locked condition refresh retains readable slots")
			assert(row.button.visible and row.button.size.y >= 34 and row.panel.get_global_rect().encloses(row.button.get_global_rect()))
			assert(row.button.text == "명성 %d 필요" % shop.State.Content.EXPEDITION_REPUTATION if step == "fame" else row.button.text == "400 부족" if step == "money" else row.button.text == "400 · 원정 열기")
		if step in ["money", "ready"]: assert(row.button.icon == panel.CurrencyText.COIN)
		if step != "opened": assert(row.button.disabled == (step != "ready"))
	var greenhouse: Dictionary = panel.rows.abandoned_greenhouse
	assert(greenhouse.button.text == "숲 가장자리 조사 완료 필요" and greenhouse.button.disabled)
	assert(greenhouse.extra.source_text.contains("숲 가장자리 조사 0/10회 필요"))
	var font: Font = greenhouse.button.get_theme_font("font")
	assert(font.get_string_size(greenhouse.button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x < greenhouse.button.size.x - 12)
	p.expedition_count = 3
	panel.refresh()
	assert(row.extra.source_text.contains("3/10") and not row.summary.source_text.contains("조사"))
	p.expedition_count = 10
	panel.refresh()
	assert(row.extra.source_text.contains("조사 완료") and not row.summary.source_text.contains("조사") and not greenhouse.button.disabled)
	var cycle: Dictionary = p.expansion.cycles.forest_edge
	cycle.elapsed = cycle.duration * 0.2
	assert(Status.region_status(state, "forest_edge") == "탐색 중")
	cycle.elapsed = cycle.duration * 0.95
	assert(Status.region_status(state, "forest_edge") == "재료 가져오는 중")
	cycle.running = false
	p.expansion.pending["starleaf"] = 2
	assert(Status.region_status(state, "forest_edge") == "재료 보관 대기")
	p.expansion.pending.clear()
	p.rare_herbs = 12
	p.expansion.materials["dewgrass"] = 12
	assert(Status.region_status(state, "forest_edge") == "보관 가득 · 출발 대기")
	p.rare_herbs = 7
	p.expansion.materials["dewgrass"] = 7
	assert(Status.region_status(state, "forest_edge") == "재료 충분 · 출발 대기")
	p.rare_herbs = 0
	p.expansion.materials["dewgrass"] = 0
	state.gold = 0
	assert(Status.region_status(state, "forest_edge") == "출발비 부족")
	panel.refresh()
	assert(not row.button.visible and row.work.caption.text == "출발비 부족")
	var before: Dictionary = state.to_data().duplicate(true)
	row.button.pressed.emit()
	panel.select_page(panel.REPORT)
	assert(not panel.statistics_values.expeditions.source_text.contains("귀환") and Compare.equivalent(before, state.to_data()))
	assert(Status.condition_text("숲 가장자리 귀환 5회 필요") == "숲 가장자리 원정 5회 완료 필요")
	print("REGION TERMS PASS: visible locked conditions/ready action; hidden opened action; locked bounds/height; actual search/carry/pending/storage/supply/funds; investigation only in details; unchanged save/departure")
	quit()
