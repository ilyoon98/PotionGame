extends SceneTree
const Shop = preload("res://scripts/shop.gd")
const State = preload("res://scripts/shop_state.gd")
const Status = preload("res://scripts/management_status.gd")
const Content = preload("res://scripts/shop_content.gd")
const Compare = preload("res://tests/state_compare.gd")
var shop: Control
var panel: Window

func _initialize() -> void:
	set_meta("isolated_preview", true)
	call_deferred("run")

func layout() -> void:
	panel.refresh()
	await process_frame
	await process_frame

func assert_button(id: String, key: String, completion: String = "") -> void:
	var button: Button = panel.rows[id].button
	if Status.Rare.is_special(key) and not Status.known_potion(shop.state, key):
		assert(button.disabled and button.icon == null and button.get_meta("currency_source") == "원정 발견 필요", "An undiscovered optional recipe retains its common masked prerequisite instead of exposing a price/name")
		return
	var reason := Status.purchase_condition(shop.state, key)
	var expected := completion if not completion.is_empty() else reason
	assert(button.disabled == (not completion.is_empty() or not reason.is_empty()), key)
	if not expected.is_empty(): assert(button.get_meta("currency_source") == expected, key + " must explain the actual blocking rule")
	assert(not button.text.contains(" G"), "Use coins for fund deficits")
	var width := button.get_theme_font("font").get_multiline_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x
	assert(width + (24 if button.icon != null else 0) + 20 <= button.size.x, key + " condition must fit visibly")

func verify_visible_conditions() -> void:
	for page in [panel.HERBS, panel.POTIONS]:
		panel.select_page(page)
		await layout()
		for row in panel.rows.values():
			if row.page != page: continue
			assert(row.panel.visible and row.detail.visible and row.work.box.visible and row.stock.box.visible)
			assert(not row.detail.source_text.is_empty() and not row.extra.source_text.is_empty())
			assert(row.detail.get_content_height() <= row.detail.size.y and row.detail.get_content_width() <= row.detail.size.x, row.title.text + " representative condition must fit without cutting")

func run() -> void:
	assert(DisplayServer.get_name() == "headless")
	shop = Shop.new()
	root.add_child(shop)
	shop.set_process(false)
	shop.state = State.new()
	shop.open_management()
	panel = shop.management
	panel.set_process(false)
	for phase in ["poor", "rich", "famous", "discovered", "purchased"]:
		shop.state.gold = 0 if phase == "poor" else 1000000
		shop.state.progression.reputation = 10000 if phase in ["famous", "discovered", "purchased"] else 0
		if phase in ["discovered", "purchased"]:
			for region in Content.DATA.regions:
				shop.state.progression.expansion.returns[region.id] = int(region.complete_returns)
				if not shop.state.progression.expansion.regions.has(region.id): shop.state.progression.expansion.regions.append(region.id)
			shop.state.progression.expedition_count = 10
			shop.state.progression.expedition_unlocked = true
		if phase == "purchased":
			assert(shop.state.purchase("moon"))
			assert(shop.state.purchase("staff:sales_assistant"))
			shop.state.level = State.MAX_LEVEL
		panel.select_page(panel.RECIPES)
		await layout()
		for id in Content.RECIPES: assert_button(id, id, "구매 완료" if shop.state.progression.owned.has(id) else "")
		panel.select_page(panel.UPGRADES)
		await layout()
		var tracks := []
		for source in Content.DATA.upgrades:
			if tracks.has(source.track): continue
			tracks.append(source.track)
			var data := Status.investment(shop.state, source.track)
			assert_button(data.target, "upgrade:" + source.track, "최대 단계" if data.maxed else "")
			assert(panel.rows[data.target].work.box.visible)
		for employee in Content.DATA.employees:
			var owned: bool = shop.state.progression.expansion.staff.has(employee.id)
			assert_button("employee" if employee.id == "sales_assistant" else employee.id, "staff:" + employee.id, "고용 완료" if owned else "")
		panel.select_page(panel.EXPEDITIONS)
		await layout()
		for source in Content.DATA.regions:
			var row: Dictionary = panel.rows[source.id]
			if Status.region(shop.state, source.id).available:
				assert(not row.button.visible, "Opened regions no longer show a completed purchase action")
			else:
				assert(row.button.visible)
				assert_button(source.id, "expedition" if source.id == "forest_edge" else "region:" + source.id)
		await verify_visible_conditions()
	# A held batch must not claim the already reserved ingredients are missing.
	shop.state = State.new()
	shop.state.herbs = 0
	shop.state.mushrooms = 0
	shop.state.brew_active = true
	shop.state.progression.active_recipe = true
	assert(Status.potion(shop.state, true).condition.contains("예약 완료"))
	assert(Status.potion(shop.state, false).condition.contains("기본 약초 2개"))
	shop.state.brew_active = false
	assert(Status.potion(shop.state, true).condition.contains("달빛 버섯 1개"))
	shop.state.gold = 37
	assert(Status.material(shop.state, "moon_mushroom").condition.begins_with("1 G 부족"))
	shop.state.gold = 38
	assert(Status.material(shop.state, "moon_mushroom").condition.begins_with("자동 발주"))
	shop.state.progression.expansion.materials.dewgrass = 1
	assert(Status.material(shop.state, "dewgrass").condition.contains("활력 레시피 구매 필요"))
	assert(not Status.material(shop.state, "dewgrass").supplied, "A trip reward must not imply cultivation is unlocked")
	assert(Status.purchase_condition(shop.state, "upgrade:sales_assistant") == "판매 보조 고용 필요")
	shop.state.shop_open = false
	assert(Status.material(shop.state, "moon_mushroom").condition.contains("영업 재개 필요"))
	shop.state.shop_open = true
	# No projections or redraws may advance the game, pay, reserve or alter RNG.
	var before: Dictionary = shop.state.to_data().duplicate(true)
	await verify_visible_conditions()
	for i in 10: panel.refresh_gauges(0.05)
	assert(Compare.equivalent(before, shop.state.to_data()))
	# Conditions can change without adding/removing a row, bar or line of space.
	panel.select_page(panel.POTIONS)
	await layout()
	var height: float = panel.rows.potion_moon.panel.size.y
	var following_y: float = panel.rows.potion_purify.panel.position.y
	shop.state.gold = 1000000
	assert(shop.state.purchase("moon"))
	shop.state.herbs = 2
	shop.state.progression.rare_herbs = 1
	await layout()
	assert(panel.rows.potion_moon.panel.size.y == height and panel.rows.potion_purify.panel.position.y == following_y)
	shop.state.stock = shop.state.capacity()
	await layout()
	assert(panel.rows.potion_moon.panel.size.y == height and panel.rows.potion_purify.panel.position.y == following_y)
	print("PASS management conditions: shared purchase blockers, named staff, exact ingredient/fund shortages, locked rows, readable fixed slots, read-only projections; herb height=%s potion height=%s" % [panel.rows.herb_inventory.panel.size.y, height])
	shop.queue_free()
	await process_frame
	quit()
