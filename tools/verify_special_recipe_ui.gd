extends SceneTree
## Isolated headless UI tree only. No real files, input, focus or game process.
const Shop = preload("res://scripts/shop.gd")
const State = preload("res://scripts/shop_state.gd")
const Content = preload("res://scripts/shop_content.gd")
const Status = preload("res://scripts/management_status.gd")
const Rare = preload("res://scripts/rare_recipes.gd")
const Trips = preload("res://scripts/parallel_expeditions.gd")
const Items = preload("res://scripts/item_art.gd")
const Centered = preload("res://scripts/centered_button_content.gd")
const Compare = preload("res://tests/state_compare.gd")
const Currency = preload("res://scripts/currency_text.gd")
var shop: Control
var panel: Window
var checks := 0
var failures := 0
var region_heights := {}

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

func fixture() -> RefCounted:
	var state := State.new()
	state.gold = 1000000
	state.level = State.MAX_LEVEL
	state.garden_level = State.MAX_GARDEN_LEVEL
	state.sales_counter_level = Content.SALES_COUNTER_COSTS.size()
	var p: RefCounted = state.progression
	p.reputation = 10000
	p.filter_owned = true
	p.employee = true
	p.expedition_unlocked = true
	for employee in Content.DATA.employees: p.expansion.staff.append(employee.id)
	for row in Content.DATA.upgrades: p.expansion.stages[row.track] = int(row.stage)
	state.contracts.training = 3 # Complete the independent F18 growth track too.
	for id in Content.RECIPES:
		if not Rare.is_special(id): p.owned.append(id)
	for region in Content.DATA.regions:
		p.expansion.regions.append(region.id)
		if region.id == "forest_edge": p.expedition_count = int(region.complete_returns)
		else: p.expansion.returns[region.id] = int(region.complete_returns)
	Trips.ensure(p)
	return state

func texture_path(texture: Texture2D) -> String:
	if texture == null: return ""
	return texture_path(texture.atlas) if texture is AtlasTexture else texture.resource_path

func surfaces(node: Node, strings: PackedStringArray, paths: PackedStringArray) -> void:
	if node is Control:
		strings.append(node.tooltip_text)
		if node is Label or node is Button: strings.append(node.text)
		elif node is RichTextLabel:
			strings.append(node.text)
			if node.get("source_text") != null: strings.append(str(node.source_text))
		if node is TextureRect: paths.append(texture_path(node.texture))
		elif node is Button: paths.append(texture_path(node.icon))
	for child in node.get_children(): surfaces(child, strings, paths)

func verify_unknown_surfaces() -> void:
	var strings := PackedStringArray()
	var paths := PackedStringArray()
	surfaces(panel, strings, paths)
	var text := "\n".join(strings)
	var art := "\n".join(paths)
	for row in Rare.ROWS:
		if Rare.is_discovered(row.id, shop.state.progression): continue
		check(not text.contains(row.name) and not art.contains(row.id), "Undiscovered true name/art is absent from every tab, hidden detail and tooltip: " + row.id)
		for id in [row.id, "potion_" + row.id]:
			var item: Dictionary = panel.rows[id]
			check(item.title.text == "특별 레시피 · 미발견" and texture_path(item.icon.texture) == Items.UNKNOWN_RECIPE_PATH, "The same unknown map replaces each recipe and potion identity")
			check(item.blend.entries.is_empty() and not item.blend.visible and not item.blend_title.visible and item.blend.tooltip_text.is_empty(), "Unknown blends and ingredient names/quantities are cleared even in hidden details")
		check(panel.rows[row.id].button.disabled and panel.rows[row.id].button.icon == null, "Undiscovered recipes offer no purchase/price coin")
		var region: Dictionary = panel.rows[row.region]
		check(region.rare_link.text == "특별 레시피 · 미발견" and region.rare_link.disabled and texture_path(region.rare_icon.texture) == Items.UNKNOWN_RECIPE_PATH, "The expedition uses the same masked disabled identity")
	# Later approved purchases (F20 workshop, F21 aging/keeper) may still be
	# recommended; an undiscovered special recipe never is.
	var recommended := str(panel.recommendation.get("purchase_key", ""))
	check(not Rare.ROWS.any(func(row): return not Rare.is_discovered(row.id, shop.state.progression) and recommended.contains(row.id)) and (recommended.is_empty() or recommended == "workshop" or recommended.begins_with(Status.AGING_PREFIX) or recommended.begins_with(Status.KEEPER_PREFIX)), "A completed ordinary shop never recommends a missing discovery (recommended: %s)" % recommended)

func verify_region_rows() -> void:
	var special_count := 0
	for source in Content.DATA.regions:
		var row: Dictionary = panel.rows[source.id]
		var special: bool = not Rare.by_region(source.id).is_empty()
		if special: special_count += 1
		check(row.has("rare_line") == special and row.panel.custom_minimum_size.y == (188 if special else 148), "Only the four true special destinations reserve an extra discovery line")
		check(not row.button.visible and not row.detail_box.visible, "Opened expedition basics preserve hidden completed actions and collapsed details")
		check(row.primary_icon.size == Vector2(32, 32), "Expedition ingredient icons keep the existing readable size")
		if not region_heights.has(source.id): region_heights[source.id] = row.panel.size.y
		else: check(is_equal_approx(float(region_heights[source.id]), row.panel.size.y), "Discovery/purchase transitions keep collapsed region heights stable: " + source.id)
	check(special_count == 4, "No fake special discovery is added to the other four regions")

func verify_blend(row: Dictionary, kind: Variant) -> void:
	var expected := Status.ingredients(shop.state, kind)
	check(row.blend_title.text == "1병 배합" and row.blend_title.visible and row.blend.entries == expected, "Recipe and potion rows read the same real one-bottle blend")
	check(row.blend.entries.size() == Content.lookup("potions", Status.kind_id(kind)).ingredients.size(), "No material species disappears from a multi-material blend")
	for chip in row.blend.get_children():
		var item: Dictionary = chip.get_meta("ingredient")
		var icon: TextureRect = chip.get_node("Icon")
		var amount: Label = chip.get_node("RequiredQuantity")
		check(icon.texture != null and icon.size == Vector2(32, 32) and amount.text == "× %d" % item.required and amount.get_theme_font_size("font_size") == 16, "Original material art and 16px true recipe quantities remain legible")
		check(chip.tooltip_text.contains(item.name) and chip.tooltip_text.contains("1병당 %d개 필요" % item.required), "Ingredient tooltip retains its full actual name and quantity")
		check(chip.get_rect().end.x <= row.blend.size.x + 1, "Wrapped ingredient chips fit the actual allocated flow width")
		check(amount.get_theme_font("font").get_string_size(amount.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x <= amount.size.x + 1, "Required quantity glyphs fit without smaller text")

func verify_header_actions() -> void:
	for button in [panel.result_button, panel.close_button]:
		var geometry: Dictionary = Centered.rects(button)
		check(button.icon != null and button.icon.get_size() == Vector2(16, 16) and button.size == Vector2(80, 34), "Statistics and close icons remain present at the agreed fixed size")
		check(geometry.fits and geometry.gap == 6 and absf(geometry.block.get_center().x - 40.0) <= 1.0, "Both header icon/label blocks retain their 6px gap, centering and fit")
	check(panel.result_button.text == "통계" and panel.close_button.text == "닫기", "Statistics and internal close actions remain intact")

func verify_purchase_buttons() -> void:
	for row in panel.rows.values():
		if row.page != panel.selected or row.page not in [panel.RECIPES, panel.UPGRADES] or not row.button.visible: continue
		var button: Button = row.button
		var source: String = button.get_meta("currency_source", "")
		var amounts := Currency.pattern().search_all(source)
		var geometry: Dictionary = Centered.rects(button)
		check(geometry.fits and geometry.gap == 6 and absf(geometry.block.get_center().x - button.size.x / 2.0) <= 1.0, "Single-line purchase/condition icon and text remain one centered fitting block")
		check(not Currency.pattern().search(button.text), "Native purchase text retains no numeric G suffix")
		if not amounts.is_empty():
			check(amounts.size() == 1 and button.icon == Currency.COIN and button.text.begins_with(amounts[0].get_string(1)), "Exactly one original coin precedes the one real price/shortage amount")
			check(geometry.icon.size.x == 16 and absf(geometry.text.position.x - geometry.icon.end.x - 6.0) <= 1.0, "Price and coin retain their 6px adjacency at native pixel rounding")

func verify_masks_and_transitions() -> void:
	shop.state = fixture()
	var before: Dictionary = shop.state.to_data().duplicate(true)
	for row in panel.rows.values(): row.toggle.set_pressed_no_signal(false)
	for page in panel.pages.size():
		panel.select_page(page)
		await layout()
		verify_unknown_surfaces()
	panel.select_page(panel.EXPEDITIONS)
	await layout()
	verify_region_rows()
	for source in Content.DATA.regions:
		panel.rows[source.id].toggle.button_pressed = true
	await layout()
	verify_unknown_surfaces()
	for source in Content.DATA.regions: panel.rows[source.id].toggle.button_pressed = false
	check(Compare.equivalent(before, shop.state.to_data()), "All tabs, recommendation, details and unknown masks preserve full progress/RNG")
	for rare in Rare.ROWS:
		shop.state.progression.expansion.rare_discovered.append(rare.id)
		before = shop.state.to_data().duplicate(true)
		panel.select_page(panel.EXPEDITIONS)
		await layout()
		var region: Dictionary = panel.rows[rare.region]
		check(region.rare_link.text == rare.name and not region.rare_link.disabled and region.rare_state.text == "발견 · 미구매" and texture_path(region.rare_icon.texture) == rare.recipe_icon_candidate, "Discovery replaces the map with the real named recipe, retaining purchase separation")
		region.rare_link.pressed.emit()
		await layout()
		await process_frame
		check(panel.selected == panel.RECIPES and not panel.rows[rare.id].button.disabled and not panel.rows[rare.id].completed, "The discovery link opens its one-time purchase on the existing recipe tab")
		verify_purchase_buttons()
		verify_blend(panel.rows[rare.id], rare.id)
		check(panel.rows["potion_" + rare.id].detail.source_text.contains("레시피"), "A discovered but unpurchased potion still has no manufacture permission")
		check(Compare.equivalent(before, shop.state.to_data()), "Discovery naming, tab navigation and blend display grant no purchase/resources or RNG")
		before = shop.state.to_data().duplicate(true)
		panel.rows[rare.id].button.pressed.emit() # Explicit isolated fixture purchase.
		await layout()
		check(Rare.is_owned(rare.id, shop.state.progression) and shop.state.gold == int(before.gold) - int(rare.cost), "The native purchase action spends its actual price once after discovery")
		check(panel.rows[rare.id].button.disabled and panel.rows[rare.id].completed and region.rare_state.text == "구매 완료", "The paid recipe remains recorded and its purchase action completes")
		var after_purchase: Dictionary = shop.state.to_data().duplicate(true)
		panel.buy(rare.id)
		await layout()
		check(Compare.equivalent(after_purchase, shop.state.to_data()), "Repeated purchase cannot pay or grant ingredients/sources twice")
		verify_unknown_surfaces()
	panel.select_page(panel.EXPEDITIONS)
	await layout()
	verify_region_rows()
	shop.state = fixture() # Reset only this private model; reuse all existing UI nodes.
	before = shop.state.to_data().duplicate(true)
	for page in panel.pages.size():
		panel.select_page(page)
		await layout()
		verify_unknown_surfaces()
	check(Compare.equivalent(before, shop.state.to_data()), "Reusing the panel with a fresh isolated model clears old revealed name/art/blends without saving")

func verify_all_blends_and_effects() -> void:
	shop.state = fixture()
	for rare in Rare.ROWS:
		shop.state.progression.expansion.rare_discovered.append(rare.id)
		shop.state.progression.owned.append(rare.id)
	var before: Dictionary = shop.state.to_data().duplicate(true)
	panel.select_page(panel.RECIPES)
	await layout()
	verify_blend(panel.rows.basic, false)
	verify_blend(panel.rows.basic_mana, true)
	for id in Content.RECIPES: verify_blend(panel.rows[id], id)
	panel.select_page(panel.POTIONS)
	await layout()
	var kinds: Array = [false, true] + Content.RECIPES.keys()
	check(kinds.size() == 36 and panel.potion_heading.text.contains("공용 창고"), "All 32 ordinary plus 4 special recipes use one explicitly shared potion warehouse")
	for kind in kinds:
		var row: Dictionary = panel.rows["potion_" + Status.kind_id(kind)]
		verify_blend(row, kind)
		check(row.stock.count.text == "0개" and row.stock.box.tooltip_text.contains("품목별 목표량이 아니"), "Each item count does not pretend the shared limit is its own production target")
	panel.select_page(panel.UPGRADES)
	await layout()
	verify_purchase_buttons()
	var tracks := []
	for entry in Content.DATA.upgrades:
		if tracks.has(entry.track): continue
		tracks.append(entry.track)
		var data := Status.investment(shop.state, entry.track)
		var row: Dictionary = panel.rows[data.target]
		check(row.summary.source_text == data.effect and not row.summary.source_text.contains("→") and row.button.disabled and row.button.text == "최대 단계", "Every completed equipment/family/training keeps actual final effects without price or future arrow")
		check(row.summary.get_content_width() <= row.summary.size.x + 1 and row.summary.get_content_height() <= row.summary.size.y + 1, "Complete final effect text fits at the existing 16px font")
	panel.select_page(panel.EXPEDITIONS)
	for source in Content.DATA.regions: panel.rows[source.id].toggle.button_pressed = true
	await layout()
	for source in Content.DATA.regions:
		var row: Dictionary = panel.rows[source.id]
		check(row.extra.source_text.contains(Status.expedition_timing(shop.state, source.id).text), "Region details display real base/next timing and separate self/combined effects")
	check(Compare.equivalent(before, shop.state.to_data()), "All 36 blends, final effects, storage labels and timing/detail refresh preserve the complete model/RNG")
	# Consumed current materials must never turn an active batch into a shortage.
	shop.state.brew_active = true
	shop.state.progression.active_recipe = "rare_forest_breath"
	shop.state.herbs = 0
	shop.state.mushrooms = 0
	shop.state.progression.rare_herbs = 0
	shop.state.progression.expansion.materials.clear()
	before = shop.state.to_data().duplicate(true)
	panel.select_page(panel.POTIONS)
	panel.rows.potion_rare_forest_breath.toggle.button_pressed = true
	await layout()
	var active: Dictionary = panel.rows.potion_rare_forest_breath
	check(active.detail.source_text.begins_with("제작 중") and active.extra.source_text.contains("예약 완료") and active.extra.source_text.contains("다음 병"), "Current reserved production and next-bottle shortages are distinct on screen")
	for entry in active.blend.entries: check(entry.reserved and entry.missing == 0 and entry.next_missing == entry.required, "Every current special material is reserved once despite empty leftover stock")
	check(Compare.equivalent(before, shop.state.to_data()), "Reserved-batch UI does not reconsume ingredients or reroll the fixed success")
	verify_header_actions()

func verify_purchase_conditions() -> void:
	shop.state = fixture()
	shop.state.progression.expansion.stages.herb_storage = 0
	var before: Dictionary = shop.state.to_data().duplicate(true)
	panel.select_page(panel.UPGRADES)
	await layout()
	verify_purchase_buttons()
	check(not panel.rows["growth:herb_storage"].button.disabled and panel.rows["growth:herb_storage"].button.icon == Currency.COIN, "An available unmaxed upgrade retains its actual purchase price/action")
	check(Compare.equivalent(before, shop.state.to_data()), "Centering an available purchase never buys the upgrade")
	shop.state.gold = 0
	shop.state.progression.reputation = 0
	shop.state.progression.employee = false
	shop.state.progression.expansion.staff.erase("sales_assistant")
	shop.state.progression.expansion.stages.sales_assistant = 0
	before = shop.state.to_data().duplicate(true)
	await layout()
	verify_purchase_buttons()
	var shortage: Button = panel.rows["growth:herb_storage"].button
	check(shortage.disabled and shortage.get_meta("currency_source") == Status.purchase_condition(shop.state, "upgrade:herb_storage") and shortage.text.contains("부족"), "A centered shortage retains its original amount and disabled condition")
	var fame: Button = panel.rows.employee.button
	check(fame.disabled and fame.text == Status.purchase_condition(shop.state, "staff:sales_assistant") and fame.text.contains("명성") and fame.icon != null and fame.icon != Currency.COIN, "The fame condition keeps its distinct original meaning and reputation icon")
	check(Compare.equivalent(before, shop.state.to_data()), "Price/shortage/fame layout preserves original purchases, costs and RNG")

func verify_special_leg_and_normal_restore() -> void:
	shop.state = fixture()
	var state: RefCounted = shop.state
	state.progression.expansion.stages.expedition_path = 0
	state.progression.expansion.stages.expedition_guide = 0
	state.progression.expansion.materials.dewgrass = state.progression.expansion.special_capacity()
	state.progression.expansion.pending.dewgrass = 3
	Trips.tick(state, 0.0) # Start a paid private special leg, with no ordinary rewards.
	state.progression.expansion.stages.expedition_path = 8
	state.progression.expansion.stages.expedition_guide = 5
	var before: Dictionary = state.to_data().duplicate(true)
	panel.select_page(panel.EXPEDITIONS)
	panel.rows.forest_edge.toggle.button_pressed = true
	await layout()
	var row: Dictionary = panel.rows.forest_edge
	check(row.work.caption.text == "특별 탐색 중" and row.summary.source_text.begins_with("특별 탐색 · 매회"), "A real paid special leg declares its actual material-free purpose and fee")
	check(not row.guaranteed_list.visible and not row.reward_list.visible and not row.draw_title.visible and row.result_title.text.contains("재료 보상 없음"), "A special leg never promises ordinary guaranteed or optional materials")
	var timing := Status.expedition_timing(state, "forest_edge")
	check(timing.current > timing.next and row.extra.source_text.contains(timing.text), "Mid-leg upgrades retain the earlier paid duration while details show the new next departure time")
	check(row.extra.source_text.contains("일반 재료를 지급하지") and row.extra.source_text.contains("유효 완료"), "Only opened details explain the special payment/initial guarantee progress")
	verify_unknown_surfaces()
	check(Compare.equivalent(before, state.to_data()), "Special-leg progress/detail/pending display neither deposits rewards nor redraws its reserved result")
	var public_text: String = row.extra.source_text + row.rare_link.text + row.rare_state.text
	state.progression.expansion.cycles.forest_edge.rare_success = not state.progression.expansion.cycles.forest_edge.rare_success
	before = state.to_data().duplicate(true)
	await layout()
	check(row.extra.source_text + row.rare_link.text + row.rare_state.text == public_text, "The stored future discovery outcome is not disclosed before completion")
	check(Compare.equivalent(before, state.to_data()), "Reading a different reserved future result does not roll or reveal it")
	shop.state = fixture()
	Trips.tick(shop.state, 0.0) # Normal full-reward legs; main materials are needed.
	before = shop.state.to_data().duplicate(true)
	await layout()
	check(row.work.caption.text == "탐색 중" and row.summary.source_text.begins_with("주재료 "), "Returning to a normal leg restores actual material production information")
	check(row.guaranteed_list.visible and row.reward_list.visible and row.draw_title.visible and row.guaranteed_list.entries.size() == 1 and row.reward_list.entries.size() == 3, "Normal promised pools reappear after a previous special-search display")
	check(row.result_title.text == "획득 재료 · 보장" and not row.extra.source_text.contains("일반 재료를 지급하지"), "No stale special-only text remains on a normal leg")
	check(Compare.equivalent(before, shop.state.to_data()), "Normal/special UI transitions preserve every immutable paid leg and seed")
	panel.result_button.pressed.emit()
	await layout()
	# Nine lifetime values, three contract totals, then the five F21 keeper/aging values.
	check(panel.selected == panel.REPORT and panel.statistics_values.keys() == ["play_time", "net", "sales", "materials_cost", "fees", "brewed", "sold", "expeditions", "reputation_gain", "contract_paid", "contract_shipped", "contract_rounds", "keeper_sleeps", "keeper_faints", "fatigue_failed", "aged_sold", "aged_revenue"], "The preserved graph action opens original lifetime values plus contract and F21 totals")
	panel.close_button.pressed.emit()
	await process_frame
	check(not panel.visible and Compare.equivalent(before, shop.state.to_data()), "The preserved close icon hides management without mutating the private model")

func run() -> void:
	if DisplayServer.get_name() != "headless":
		push_error("Special UI verification requires headless mode")
		quit(1)
		return
	Engine.max_fps = 60
	shop = Shop.new()
	root.add_child(shop)
	shop.set_process(false)
	if shop.art != null: shop.art.set_process(false)
	shop.open_management()
	panel = shop.management
	panel.set_process(false)
	await layout()
	await verify_masks_and_transitions()
	await verify_all_blends_and_effects()
	await verify_purchase_conditions()
	await verify_special_leg_and_normal_restore()
	if failures == 0: print("SPECIAL RECIPE UI PASS: %d isolated checks; every tab/recommendation/tooltip/hidden detail mask, discovery/purchase/reset, only four taller destinations, 36 actual blends/base recipe split/reserved batch, all max effects and timing, shared warehouse, header icons, unchanged read-only model/RNG; no native GUI or player files" % checks)
	else: print("SPECIAL RECIPE UI FAILED: %d/%d" % [failures, checks])
	quit(1 if failures else 0)
