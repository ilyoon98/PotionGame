extends SceneTree
const Shop = preload("res://scripts/shop.gd")
const State = preload("res://scripts/shop_state.gd")
const Compare = preload("res://tests/state_compare.gd")
const Status = preload("res://scripts/management_status.gd")
var shop: Control
var panel: Window

func _initialize() -> void:
	set_meta("isolated_preview", true)
	call_deferred("run")

func layout() -> void:
	panel.refresh()
	await process_frame
	await process_frame

func fits(label: Label) -> void:
	var extent := label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size"))
	assert(extent.x <= label.size.x, "Read without relying on title ellipsis: " + label.text)
	assert(extent.y <= label.size.y, "Readable type must fit vertically: " + label.text)

func rich_fits(label: RichTextLabel, font_size: int = 16) -> void:
	assert(label.get_theme_font_size("normal_font_size") == font_size)
	assert(label.get_content_width() <= label.size.x + 1, "Complete rendered text/coins fit horizontally: " + label.get_parsed_text())
	assert(label.get_content_height() <= label.size.y + 1, "Wrapped detail text fits vertically: " + label.get_parsed_text())

func button_fits(button: Button) -> void:
	assert(button.get_theme_font_size("font_size") == 16)
	var extent := button.get_theme_font("font").get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	var icon_width := minf(button.icon.get_width(), button.get_theme_constant("icon_max_width")) + maxi(0, button.get_theme_constant("h_separation")) if button.icon != null else 0.0
	var margins := button.get_theme_stylebox("normal").get_minimum_size()
	if button.autowrap_mode != TextServer.AUTOWRAP_OFF:
		var available := button.size.x - icon_width - margins.x
		extent = button.get_theme_font("font").get_multiline_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, available, 16)
		assert(extent.x <= available + 1 and extent.y + margins.y <= button.size.y + 1, "Wrapped expedition condition remains fully readable: " + button.text)
	else: assert(extent.x + icon_width + margins.x <= button.size.x, "Action/condition remains fully readable: " + button.text)
	assert(extent.y <= button.size.y)

func visible_text_fits(node: Node) -> void:
	if node is Control and not node.is_visible_in_tree(): return
	if node is RichTextLabel:
		rich_fits(node, (22 if node == panel.statistics_values.net else 18) if panel.statistics_values.values().has(node) else 16)
	elif node is Label:
		assert(node.get_theme_font_size("font_size") in [14, 16, 18, 24], "Every management label has enlarged readable type: " + node.text)
		if node.autowrap_mode == TextServer.AUTOWRAP_OFF:
			fits(node)
		else:
			assert(node.get_minimum_size().y <= node.size.y, "Wrapped setting/reward text is allocated all rendered lines: " + node.text)
	elif node is Button:
		button_fits(node)
	for child in node.get_children(): visible_text_fits(child)

func run() -> void:
	assert(DisplayServer.get_name() == "headless")
	shop = Shop.new()
	root.add_child(shop)
	shop.set_process(false)
	shop.open_management()
	panel = shop.management
	panel.set_process(false)
	assert(shop.body_font.resource_path.ends_with("Pretendard-Regular.otf"))
	assert(shop.title_font.resource_path.ends_with("Pretendard-SemiBold.otf"))
	for code in [0xac00, 0xd790, 0xae08, 0x0030, 0x0039, 0x00d7]: assert(shop.body_font.has_char(code))
	assert(shop.art.lettering == shop.body_font)
	assert(FileAccess.file_exists("res://assets/fonts/pretendard/LICENSE.txt"))
	assert(panel.size == Vector2i(520, 800))
	assert(panel.heading.get_theme_font_size("font_size") == 24)
	assert(panel.gold_label.get_theme_font_size("font_size") == 18 and panel.reputation_label.get_theme_font_size("font_size") == 18)
	for tab in panel.tabs:
		assert(tab.get_theme_font("font") == shop.title_font)
		var width: float = tab.get_theme_font("font").get_string_size(tab.text, HORIZONTAL_ALIGNMENT_LEFT, -1, tab.get_theme_font_size("font_size")).x
		assert(width + 16 <= tab.size.x)
		assert(tab.get_rect().end.x <= panel.size.x - 20)
		button_fits(tab)
	# Measure the actual longest potential recommendation title, not a sample.
	for entry in State.Content.DATA.upgrades:
		var name: String = Status.investment(shop.state, entry.track).name
		var extent: Vector2 = panel.recommend_title.get_theme_font("font").get_string_size("성장 추천 · " + name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
		assert(extent.x <= panel.recommend_title.size.x, "Every actual recommendation title fits: " + name)
	# Fresh locks and fully acquired/high-reputation states exercise title badges.
	for complete in [false, true]:
		shop.state = State.new()
		shop.state.gold = 123456789
		if complete:
			shop.state.progression.reputation = 123456789
			for region in State.Content.DATA.regions:
				shop.state.progression.expansion.regions.append(region.id)
				shop.state.progression.expansion.returns[region.id] = region.complete_returns
			shop.state.progression.expedition_unlocked = true
			shop.state.progression.expedition_count = 10
			for rare in State.Content.RARE_ROWS: shop.state.progression.expansion.rare_discovered.append(rare.id)
			for id in State.Content.RECIPES:
				shop.state.progression.owned.append(id)
				if not State.Content.LEGACY_RECIPES.has(id): shop.state.progression.expansion.grant_recipe(id)
		shop.state.progression.clock = 190 # Highlighted states must fit too.
		var before: Dictionary = shop.state.to_data().duplicate(true)
		for page in panel.pages.size():
			panel.select_page(page)
			await layout()
			fits(panel.heading)
			fits(panel.gold_label)
			fits(panel.reputation_label)
			if page == panel.OPERATION:
				assert(panel.recommend_panel.get_rect().end.y + 8 <= panel.scroll.position.y)
				fits(panel.recommend_title)
				rich_fits(panel.recommend_effect)
				button_fits(panel.recommend_button)
			for row in panel.rows.values():
				# Operation has only its actual representatives; hidden legacy
				# rows intentionally have no laid-out rectangle.
				if row.page != page or not row.panel.visible: continue
				assert(row.icon.size == Vector2(48, 48) and row.icon.texture != null)
				assert(row.icon.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST)
				assert(row.title.get_theme_font_size("font_size") == 18)
				assert(row.title.get_theme_font("font") == shop.title_font)
				fits(row.title)
				if row.detail is RichTextLabel:
					assert(row.detail.get_theme_font("normal_font") == shop.body_font)
					if row.detail.visible: rich_fits(row.detail)
				elif row.detail.visible: fits(row.detail)
				var work_size := 16 if page == panel.EXPEDITIONS else 14
				assert(row.work.caption.get_theme_font_size("font_size") == work_size and row.work.count.get_theme_font_size("font_size") == work_size)
				for gauge in [row.work, row.stock]:
					if gauge.box.visible:
						fits(gauge.caption)
						fits(gauge.count)
				if row.button.visible: button_fits(row.button)
				button_fits(row.toggle)
			# Open the actual longest descriptions together and measure container
			# bounds after layout, including wrapped conditions and inline coins.
			for row in panel.rows.values():
				if row.page == page: row.toggle.button_pressed = true
			await layout()
			for row in panel.rows.values():
				if row.page != page or not row.panel.visible: continue
				rich_fits(row.extra)
				var bounds: Rect2 = row.extra.get_global_rect()
				bounds.position -= row.panel.global_position
				assert(Rect2(Vector2.ZERO, row.panel.size).grow(1).encloses(bounds))
				if row.has("detail_box"):
					assert(row.detail_box.visible)
					for list in [row.guaranteed_list, row.reward_list, row.recipe_list]:
						if not list.visible: continue
						for chip in list.get_children():
							assert(chip.get_child(0).size == Vector2(32, 32))
							assert(chip.get_child(1).get_theme_font_size("font_size") == 16)
							assert(chip.get_rect().end.x <= list.size.x)
							assert(chip.get_child(1).get_minimum_size().y <= chip.get_child(1).size.y)
				row.toggle.button_pressed = false
			visible_text_fits(panel.pages[page])
			if page == panel.REPORT:
				# Nine lifetime values, three contract totals, five F21 keeper/aging values.
				assert(panel.statistics_values.keys() == ["play_time", "net", "sales", "materials_cost", "fees", "brewed", "sold", "expeditions", "reputation_gain", "contract_paid", "contract_shipped", "contract_rounds", "keeper_sleeps", "keeper_faints", "fatigue_failed", "aged_sold", "aged_revenue"])
				assert(panel.pages[page].find_children("*", "Button", true, false).is_empty())
		assert(Compare.equivalent(before, shop.state.to_data()), "Readability changes must not mutate the economy, RNG, saved progress or fees")
	# The same scroll layout must stay inside a smaller virtual display area.
	panel.size.y = 640
	for page in [panel.OPERATION, panel.EXPEDITIONS, panel.REPORT]:
		panel.select_page(page)
		await layout()
		assert(panel.scroll.get_rect().end.y == 620)
		assert(panel.scroll.get_rect().end.x == 500)
	print("READABILITY PASS: Pretendard header icons24/captions14/values18, title18/body-button-tab16/aux14; actual longest titles/conditions/actions, opened wrapped details and statistics values/coins fit; 48px item icons/32px rewards; six tabs + statistics, shorter screen scroll; unchanged economy/RNG")
	quit()
