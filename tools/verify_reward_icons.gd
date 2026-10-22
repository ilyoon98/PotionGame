extends SceneTree
const Shop = preload("res://scripts/shop.gd")
const State = preload("res://scripts/shop_state.gd")
const Rewards = preload("res://scripts/reward_icons.gd")
const ItemArt = preload("res://scripts/item_art.gd")
const Compare = preload("res://tests/state_compare.gd")
func _initialize() -> void:
	set_meta("isolated_preview", true)
	call_deferred("run")
func run() -> void:
	assert(DisplayServer.get_name() == "headless")
	var shop := Shop.new()
	root.add_child(shop)
	shop.set_process(false)
	shop.state.gold = 10000
	shop.state.progression.reputation = 10000
	assert(shop.state.purchase("expedition"))
	assert(shop.state.progression.expansion.latest_returns.is_empty(), "Never show next reserved rewards as completed")
	var reserved: Dictionary = shop.state.progression.expansion.cycles.forest_edge.rewards.duplicate(true)
	shop.state.advance(70.0)
	var latest: Dictionary = shop.state.progression.expansion.latest_returns.forest_edge
	assert(latest == reserved, "Record the completed leg even when the first leg is grandfathered")
	reserved = shop.state.progression.expansion.cycles.forest_edge.rewards.duplicate(true)
	shop.state.advance(70.0)
	latest = shop.state.progression.expansion.latest_returns.forest_edge
	assert(latest == reserved and latest.size() in [2, 3])
	var restored := State.new()
	assert(restored.load_data(shop.state.to_data()) and restored.progression.expansion.latest_returns == shop.state.progression.expansion.latest_returns)
	var legacy: Dictionary = shop.state.to_data().duplicate(true)
	legacy.progression.expansion.erase("latest_returns")
	assert(restored.load_data(legacy) and restored.progression.expansion.latest_returns.is_empty(), "Old saves do not invent previous result records")
	var malformed: Dictionary = shop.state.to_data().duplicate(true)
	malformed.progression.expansion.latest_returns.forest_edge.starleaf = -1
	var old: Dictionary = restored.to_data().duplicate(true)
	assert(not restored.load_data(malformed) and Compare.equivalent(old, restored.to_data()))
	shop.open_management()
	var panel: Window = shop.management
	panel.set_process(false)
	panel.select_page(panel.EXPEDITIONS)
	var chips: HFlowContainer = panel.rows.forest_edge.reward_list
	var guaranteed: HFlowContainer = panel.rows.forest_edge.guaranteed_list
	assert(panel.rows.forest_edge.result_title.text == "획득 재료 · 보장" and not panel.rows.forest_edge.detail_box.visible)
	assert(guaranteed.entries.size() == 1 and chips.entries.size() == 3)
	var expected: Array = panel.Status.ExpeditionRewards.preview("forest_edge")
	for entry in expected: entry["range_only"] = true
	assert(guaranteed.entries == expected.slice(0, 1) and chips.entries == expected.slice(1))
	panel.rows.forest_edge.toggle.button_pressed = true
	assert(panel.rows.forest_edge.detail_box.visible)
	for list in [guaranteed, chips]:
		for i in list.entries.size():
			var id: String = list.entries[i].id
			assert(list.get_child(i).get_child(0).texture.resource_path == ItemArt.icon(id).resource_path)
			assert(list.get_child(i).get_child(1).text.contains("%d~%d개" % [list.entries[i].min, list.entries[i].max]))
			assert(not list.get_child(i).get_child(1).text.contains("보장") and not list.get_child(i).get_child(1).text.contains("추첨"))
	panel.select_page(panel.REPORT)
	assert(panel.statistics_values.expeditions.source_text == "%d회" % shop.state.progression.totals.expeditions)
	var baseline: Dictionary = shop.state.to_data().duplicate(true)
	for i in 20:
		panel.select_page(panel.EXPEDITIONS if i % 2 else panel.REPORT)
		panel.refresh()
	assert(Compare.equivalent(baseline, shop.state.to_data()), "Result display never deposits, rerolls or awards again")
	# A narrow fixture uses genuine material IDs; long names wrap with exact quantities.
	var fixture := Rewards.new()
	fixture.size = Vector2(180, 200)
	root.add_child(fixture)
	fixture.show_rewards({"crystal_herb": 123, "starleaf": 2, "dewgrass": 4})
	await process_frame
	await process_frame
	assert(fixture.get_child_count() == 3)
	for chip in fixture.get_children():
		assert(chip.get_child(0).texture != null)
		assert(chip.get_rect().end.x <= fixture.size.x)
		assert(chip.get_child(1).get_rect().end.x <= chip.size.x)
	assert(fixture.get_child(1).position.y > fixture.get_child(0).position.y)
	fixture.show_entries([{"kind": "recipe", "id": "unregistered-special", "name": "특별 레시피", "count": 1}])
	assert(fixture.get_child(0).get_child(0).texture != null and fixture.get_child(0).get_child(1).text == "특별 레시피 · 특별 발견")
	assert(Compare.equivalent(baseline, shop.state.to_data()))
	print("REWARD ICONS PASS: public preview IDs/ranges, saved actual results/legacy/malformed, cumulative expedition statistics, no next-leg disclosure or double awards, narrow wrap/long names, recipe discovery fallback; headless")
	quit()
