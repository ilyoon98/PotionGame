extends SceneTree
const Shop = preload("res://scripts/shop.gd")
const State = preload("res://scripts/shop_state.gd")
const Trips = preload("res://scripts/parallel_expeditions.gd")
const Rewards = preload("res://scripts/expedition_rewards.gd")
const Status = preload("res://scripts/management_status.gd")
const Compare = preload("res://tests/state_compare.gd")
const Rare = preload("res://scripts/rare_recipes.gd")
var shop: Control
var panel: Window
var cases_complete := 0
var details_complete := 0
var conditions_complete := false
var recommendation_complete := false
var compact_heights := {}

func _initialize() -> void:
	set_meta("isolated_preview", true)
	call_deferred("run")

func clone(state: RefCounted) -> RefCounted:
	var copy := State.new()
	assert(copy.load_data(JSON.parse_string(JSON.stringify(state.to_data()))))
	return copy

func layout() -> void:
	panel.refresh()
	await process_frame
	await process_frame

func set_returns(state: RefCounted, id: String, count: int) -> void:
	if id == "forest_edge": state.progression.expedition_count = count
	else: state.progression.expansion.returns[id] = count

func region_fixture(id: String, phase: String) -> RefCounted:
	var state := State.new()
	# This historical matrix verifies ordinary investigation/storage semantics;
	# material-free undiscovered search is checked separately by special UI tests.
	for recipe in Rare.ROWS: state.progression.expansion.rare_discovered.append(recipe.id)
	if phase == "locked": return state
	state.gold = 1000000
	state.progression.reputation = 10000
	state.progression.expansion.stages.herb_storage = int(State.Content.track_rows("herb_storage")[-1].stage)
	for source in State.Content.DATA.regions:
		if source.id == id and phase == "ready": break
		state.progression.expansion.regions.append(source.id)
		if source.id == "forest_edge": state.progression.expedition_unlocked = true
		set_returns(state, source.id, 0 if source.id == id else int(source.complete_returns))
		if source.id == id: break
	Trips.ensure(state.progression)
	if phase == "ready": return state
	var source := State.Content.lookup("regions", id)
	var cycle: Dictionary = state.progression.expansion.cycles[id]
	cycle.duration = float(source.explore_seconds) + float(source.return_seconds)
	cycle.rewards = {Rewards.POOLS[id].main: int(Rewards.POOLS[id].min)}
	cycle.paid = true
	cycle.fee = int(source.departure_cost)
	cycle.id = 1
	cycle.running = phase in ["search", "carry", "complete"]
	cycle.elapsed = cycle.duration * (0.95 if phase == "carry" else 0.2) if cycle.running else cycle.duration * 0.5
	state.progression.expedition_active = cycle.running
	if phase in ["storage", "sufficient", "complete"]: set_returns(state, id, int(source.complete_returns) + (100 if phase == "complete" else 0))
	var main: String = Rewards.POOLS[id].main
	var capacity: int = state.progression.expansion.special_capacity()
	if phase in ["pending", "storage"]: state.progression.expansion.materials[main] = capacity
	if phase == "pending": state.progression.expansion.pending[main] = 2
	if phase == "sufficient":
		var quantity := int(floorf(capacity * 0.5)) + 1
		assert(quantity + int(Rewards.POOLS[id].max) <= capacity, "Upgraded fixture admits the distinct sufficient-material wait")
		state.progression.expansion.materials[main] = quantity
	if phase == "funds": state.gold = 0
	state.progression.tick_elapsed = 0.25
	return state

func verify_case(id: String, phase: String) -> void:
	shop.state = region_fixture(id, phase)
	var baseline: Dictionary = shop.state.to_data().duplicate(true)
	for source in State.Content.DATA.regions: panel.rows[source.id].toggle.button_pressed = false
	panel.select_page(panel.EXPEDITIONS)
	await layout()
	var row: Dictionary = panel.rows[id]
	var source := State.Content.lookup("regions", id)
	var pool: Dictionary = Rewards.POOLS[id]
	assert(panel.size.x == 520 and row.icon.size == Vector2(48, 48))
	assert(row.title.get_theme_font_size("font_size") == 18 and row.summary.get_theme_font_size("normal_font_size") == 16)
	assert(row.primary_icon.size == Vector2(32, 32) and row.primary_icon.texture != null)
	assert(row.summary.source_text == "주재료 %s %d~%d개 · 매회 %d G" % [State.Content.lookup("materials", pool.main).name, pool.min, pool.max, source.departure_cost])
	assert(row.summary.coin_count == 1 and not row.summary.source_text.contains("조사"))
	assert(row.summary.get_content_height() <= row.summary.size.y and row.summary.get_content_width() <= row.summary.size.x)
	assert(not row.detail.visible and not row.detail_box.visible and not row.extra.is_visible_in_tree() and not row.reward_list.is_visible_in_tree() and not row.result_title.is_visible_in_tree())
	assert(not row.reputation_marker.visible and not row.badge.visible)
	var minimum := 188 if Rewards.RARE.has(id) else 148
	assert(row.panel.custom_minimum_size.y == minimum and row.panel.size.y >= minimum and row.panel.size.y <= minimum + 12, id + ":" + phase + " collapsed height " + str(row.panel.size.y))
	compact_heights[id + ":" + phase] = row.panel.size.y
	var available := Trips.opened(id, shop.state.progression)
	assert(row.button.visible == not available and row.work.box.visible == available)
	if available:
		assert(row.work.caption.get_theme_font_size("font_size") == 16 and row.work.count.get_theme_font_size("font_size") == 16)
		var expected: String = {"search": "탐색 중", "carry": "재료 가져오는 중", "pending": "재료 보관 대기", "storage": "보관 가득", "sufficient": "재료 충분", "funds": "출발비 부족", "complete": "탐색 중"}[phase]
		assert(row.work.caption.text.begins_with(expected), id + ":" + phase + " actual status " + row.work.caption.text)
		var data := Status.region(shop.state, id)
		assert(is_equal_approx(row.work.bar.value, data.display_progress * 100.0 if data.running else 0.0))
		if not data.running: assert(shop.state.progression.expansion.cycles[id].elapsed == shop.state.progression.expansion.cycles[id].duration * 0.5, "Stopped display never rewrites the saved cycle elapsed time")
		if data.running: assert(row.work.count.text.contains("초 남음"))
		else: assert(row.work.count.text in ["", "대기"])
	else:
		var key := "expedition" if id == "forest_edge" else "region:" + id
		var reason := Status.purchase_condition(shop.state, key)
		assert(row.button.disabled == not reason.is_empty())
		if not reason.is_empty(): assert(row.button.get_meta("currency_source") == reason)
		else: assert(row.button.get_meta("currency_source").contains(str(shop.state.purchase_cost(key)) + " G"))
	var height: float = row.panel.size.y
	var positions := {}
	for source_row in State.Content.DATA.regions: positions[source_row.id] = panel.rows[source_row.id].panel.position
	for i in 6: panel.refresh()
	await layout()
	assert(row.panel.size.y == height)
	for key in positions: assert(panel.rows[key].panel.position == positions[key], "Display refresh never shakes the list")
	assert(Compare.equivalent(baseline, shop.state.to_data()), "Status, quantities, fees, reservations, RNG and save data remain read-only")
	cases_complete += 1

func verify_details(id: String) -> void:
	shop.state = region_fixture(id, "complete")
	panel.select_page(panel.EXPEDITIONS)
	for source in State.Content.DATA.regions: panel.rows[source.id].toggle.button_pressed = false
	await layout()
	var row: Dictionary = panel.rows[id]
	var baseline: Dictionary = shop.state.to_data().duplicate(true)
	row.toggle.button_pressed = true
	await layout()
	assert(row.detail_box.visible and row.extra.is_visible_in_tree() and row.reward_list.is_visible_in_tree() and row.result_title.is_visible_in_tree())
	assert(row.result_title.text == "획득 재료 · 보장")
	assert(row.guaranteed_list.entries.size() == 1 and row.reward_list.entries.size() == 3)
	var expected: Array = Rewards.preview(id)
	for list in [row.guaranteed_list, row.reward_list]:
		for entry in list.entries:
			assert(entry.kind == "material" and entry.range_only)
			assert(expected.any(func(item): return item.id == entry.id and item.min == entry.min and item.max == entry.max and item.guaranteed == entry.guaranteed))
		for chip in list.get_children():
			assert(chip.get_child(0).size == Vector2(32, 32) and chip.get_child(0).texture != null)
			assert(chip.get_child(1).get_theme_font_size("font_size") == 16)
			assert(not chip.get_child(1).text.contains("보장") and not chip.get_child(1).text.contains("추첨"))
			assert(chip.get_rect().end.x <= list.size.x and chip.get_child(1).get_rect().end.x <= chip.size.x)
	assert(row.guaranteed_list.entries[0].guaranteed)
	for item in row.reward_list.entries: assert(item.min == 0 and item.max == 2 and not item.guaranteed)
	for item in row.recipe_list.entries:
		assert(item.kind == "recipe" and not item.id.begins_with("rare_") and not shop.state.progression.owned.has(item.id))
		var discovery: Dictionary = State.Content.lookup("potions", item.id).unlock.discovery
		assert(discovery.region == id and item.status.contains("%d/%d" % [int(discovery.returns), int(discovery.returns)]) and not item.status.contains("1회 구매"))
		assert(row.recipe_title.text.contains("해금 후 1회 구매"))
	assert(not row.extra.source_text.contains("60/30/10") and not row.extra.source_text.contains("25%") and not row.extra.source_text.contains("실제 회차"))
	assert(row.extra.source_text.begins_with("조사 완료\n") and not row.extra.source_text.contains("100/"), "Completed running details keep concise investigation plus real timing/discovery information")
	if Rewards.RARE.has(id):
		assert(Rare.preview(id, shop.state.progression).known and not Status.region_preview(shop.state, id).any(func(item): return str(item.get("id", "")).begins_with("rare_")), "Special recipes use their shared discovery preview rather than the old unmasked ordinary catalog placeholder")
		assert(not row.recipe_list.entries.any(func(item): return item.id == Rewards.RARE[id].id))
	for i in 6: panel.refresh()
	panel.select_page(panel.REPORT)
	panel.select_page(panel.EXPEDITIONS)
	await layout()
	assert(row.toggle.button_pressed and row.detail_box.visible, "A user's detail toggle survives refresh and tab changes")
	assert(Compare.equivalent(baseline, shop.state.to_data()))
	if not row.recipe_list.entries.is_empty():
		var purchased: String = row.recipe_list.entries[0].id
		shop.state.progression.owned.append(purchased)
		baseline = shop.state.to_data().duplicate(true)
		await layout()
		assert(not row.recipe_list.entries.any(func(item): return item.id == purchased), "Purchased ordinary recipes leave the detail preview")
		assert(Compare.equivalent(baseline, shop.state.to_data()))
	row.toggle.button_pressed = false
	await layout()
	assert(not row.detail_box.visible and not row.extra.is_visible_in_tree() and not row.guaranteed_list.is_visible_in_tree() and not row.reward_list.is_visible_in_tree() and not row.recipe_list.is_visible_in_tree())
	details_complete += 1

func verify_conditions() -> void:
	var missing := State.new()
	missing.progression.expedition_unlocked = true
	missing.gold = 38
	var before: Dictionary = missing.to_data().duplicate(true)
	assert(Status.region_card_conditions(missing, "forest_edge").contains("다음 출발 대기"))
	assert(missing.progression.expansion.cycles.is_empty() and Compare.equivalent(before, missing.to_data()), "A read projection never creates missing cycles")
	missing.gold = 37
	var text := Status.region_card_conditions(missing, "forest_edge")
	assert(text.contains("출발에 필요한 골드 38 G") and text.contains("예비금 30 G") and text.contains("1 G 부족"))
	var locked := State.new()
	text = Status.region_card_conditions(locked, "star_garden")
	var locked_source := State.Content.lookup("regions", "star_garden")
	var previous: String = State.Content.lookup("regions", locked_source.previous_region).name
	assert(text.contains(previous) and text.contains("원정 열기") and text.contains(" G 부족"), text)
	assert(text.contains("명성") == (int(locked_source.reputation) > 0), "Only actual catalog fame requirements belong in the details")
	locked.gold = 0
	text = Status.region_card_conditions(locked, "forest_edge")
	assert(text.contains("명성 10 필요") and text.contains("400 G 필요") and text.contains("400 G 부족"), "Real fame and opening-cost blockers remain individually readable")
	var budget := State.new()
	budget.progression.expedition_unlocked = true
	budget.progression.expansion.regions = ["forest_edge", "abandoned_greenhouse"]
	budget.progression.expedition_count = 10
	Trips.ensure(budget.progression)
	for gold in [37, 45]:
		budget.gold = gold
		before = budget.to_data().duplicate(true)
		text = Status.region_card_conditions(budget, "forest_edge")
		assert(text.contains("출발에 필요한 골드 50 G"))
		assert(text.contains("남겨둘 비용 12 G") if gold == 37 else text.contains("원정 비용 12 G"))
		assert(Compare.equivalent(before, budget.to_data()))
	budget.progression.expansion.regions.append("mist_valley")
	Trips.ensure(budget.progression)
	text = Status.region_card_conditions(budget, "forest_edge")
	assert(text.contains("출발에 필요한 골드 70 G") and text.contains("남겨둘 비용 20 G") and text.contains("원정 비용 12 G"))
	conditions_complete = true

func verify_recommendation() -> void:
	shop.state = State.new()
	shop.state.gold = 1000000
	shop.state.progression.reputation = 10000
	shop.state.level = 2
	shop.state.garden_level = 2
	shop.state.progression.expansion.stages.cauldron = 1
	shop.state.progression.expansion.stages.herb_pot = 1
	panel.select_page(panel.OPERATION)
	await layout()
	assert(panel.recommendation.kind == "region" and panel.recommend_button.get_meta("purchase_key") == "expedition")
	var expected := clone(shop.state)
	assert(expected.purchase("expedition"))
	panel.recommend_button.pressed.emit()
	assert(panel.selected == panel.OPERATION and Compare.equivalent(expected.to_data(), shop.state.to_data()), "Recommendation still opens the region directly, paying exactly the original price and initial departure")
	panel.select_page(panel.EXPEDITIONS)
	await layout()
	assert(not panel.rows.forest_edge.button.visible)
	var before: Dictionary = shop.state.to_data().duplicate(true)
	panel.rows.forest_edge.button.pressed.emit()
	assert(Compare.equivalent(before, shop.state.to_data()), "Hidden opened callbacks cannot repurchase or depart again")
	recommendation_complete = true

func run() -> void:
	assert(DisplayServer.get_name() == "headless")
	var state := State.new()
	for id in Rewards.POOLS:
		var preview := Rewards.preview(id)
		var seen := {}
		var varieties := {}
		var main: Dictionary = preview[0]
		for i in 2000:
			var roll := Rewards.roll(id, state.progression)
			assert(roll.size() in [2, 3] and roll.has(main.id))
			varieties[str(roll)] = true
			for entry in preview:
				var quantity: int = int(roll.get(entry.id, 0))
				assert(quantity >= entry.min and quantity <= entry.max)
				seen[entry.id + ":" + str(quantity)] = true
			for material in roll: assert(preview.any(func(entry): return entry.id == material))
		assert(varieties.size() > 10)
		assert(seen.has(main.id + ":" + str(main.min)) and seen.has(main.id + ":" + str(main.max)))
		for entry in preview:
			if not entry.guaranteed:
				assert(seen.has(entry.id + ":0") and seen.has(entry.id + ":1") and seen.has(entry.id + ":2"))
	# Existing paid legs finish with their exact saved rewards, next legs roll once.
	state.gold = 100000
	state.progression.reputation = 10000
	assert(state.purchase("expedition"))
	var cycle: Dictionary = state.progression.expansion.cycles.forest_edge
	cycle.rewards = {"dewgrass": 2, "starleaf": 2}
	cycle.elapsed = cycle.duration - 1
	var before := clone(state)
	Trips.tick(state, 1)
	assert(state.progression.expansion.latest_returns.forest_edge == {"dewgrass": 2, "starleaf": 2})
	assert(cycle.rewards.size() in [2, 3])
	var restored := clone(state)
	var reserved: Dictionary = cycle.rewards.duplicate(true)
	var seed: int = state.progression.seed_value
	var spent: int = state.total_spent_expeditions
	Trips.tick(restored, 0)
	assert(Compare.equivalent(restored.progression.expansion.cycles.forest_edge.rewards, reserved) and restored.progression.seed_value == seed and restored.total_spent_expeditions == spent)
	Trips.tick(before, 1)
	assert(Compare.equivalent(state.to_data(), before.to_data()), "Same saved RNG and leg produce identical next rewards")
	# Basic herbs and mushrooms have their own stores, with overflow preserved.
	state.herbs = state.herb_capacity() - 1
	state.mushrooms = state.MUSHROOM_CAPACITY
	state.progression.expansion.pending = {"herb": 3, "moon_mushroom": 2}
	Trips.deposit(state.progression, state)
	assert(state.herbs == state.herb_capacity() and state.mushrooms == state.MUSHROOM_CAPACITY)
	assert(state.progression.expansion.pending == {"herb": 2, "moon_mushroom": 2})
	state.herbs -= 2
	state.mushrooms -= 1
	Trips.deposit(state.progression, state)
	assert(state.progression.expansion.pending == {"moon_mushroom": 1})
	assert(not state.progression.expansion.materials.has("herb") and not state.progression.expansion.materials.has("moon_mushroom"))
	assert(Compare.equivalent(clone(state).progression.expansion.pending, state.progression.expansion.pending))
	shop = Shop.new()
	root.add_child(shop)
	shop.set_process(false)
	shop.state = state
	shop.open_management()
	panel = shop.management
	panel.set_process(false)
	panel.select_page(panel.EXPEDITIONS)
	await process_frame
	await process_frame
	for source in State.Content.DATA.regions:
		for phase in ["locked", "ready", "search", "carry", "pending", "storage", "sufficient", "funds", "complete"]: await verify_case(source.id, phase)
		await verify_details(source.id)
	verify_conditions()
	await verify_recommendation()
	assert(cases_complete == 72 and details_complete == 8 and conditions_complete and recommendation_complete, "Every matrix, details, monetary and recommendation check must finish before success")
	print("EXPEDITION PREVIEW PASS: 72 real UI cases across 8 regions/9 states, 148px compact cards and 32px primary/16px body, whole detail toggles, grouped guaranteed/0~2 optional materials, only unpurchased ordinary recipes/clamped discovery, deferred RARE catalog preserved but hidden; actual progress/stopped elapsed retained/fees/pending/protect/priority/reserve, direct recommendation purchase; stored roll/RNG/overflow/save invariants; headless only")
	quit()
