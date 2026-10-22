extends SceneTree
const Shop = preload("res://scripts/shop.gd")
const Currency = preload("res://scripts/currency_text.gd")
const Compare = preload("res://tests/state_compare.gd")
func _initialize() -> void:
	set_meta("isolated_preview", true)
	call_deferred("run")
func run() -> void:
	assert(DisplayServer.get_name() == "headless")
	var shop := Shop.new()
	root.add_child(shop)
	shop.set_process(false)
	shop.state.gold = 148634
	shop.state.progression.reputation = 10000
	shop._update_interface()
	shop.companion.refresh()
	shop.open_management()
	var panel: Window = shop.management
	panel.set_process(false)
	# Header metric groups allocate their real available width during layout;
	# the fit/abbreviation decision must be checked after container allocation.
	await process_frame
	await process_frame
	var before: Dictionary = shop.state.to_data().duplicate(true)
	assert(panel.gold_label.text == "148,634" and panel.gold_icon.texture != null)
	assert(shop.workshop_gold.text == "14.9만" and shop.companion.gold.text == "14.9만")
	assert(shop.gold_label.coin_count == 1 and shop.minimal_gold.coin_count == 1 and shop.minimal_income.coin_count == 1)
	assert(shop.supply_card.detail_label.coin_count == 1 and shop.supply_card.status_label.coin_count == 1)
	assert(shop.upgrade_button.icon == Currency.COIN and shop.garden_button.icon == Currency.COIN)
	var money_fields := 0
	for page in panel.pages.size():
		panel.select_page(page)
		for row in panel.rows.values():
			if row.page != page: continue
			for key in ["detail", "summary", "extra"]:
				var field: Control = row[key]
				if field is Currency:
					assert(Currency.pattern().search(field.get_parsed_text()) == null, "No displayed numeric G suffix")
					if Currency.pattern().search(field.source_text) != null:
						assert(field.coin_count > 0 and field.text.contains(Currency.COIN_PATH))
						money_fields += 1
			var button: Button = row.button
			if Currency.pattern().search(str(button.get_meta("currency_source", ""))) != null:
				assert(button.icon == Currency.COIN and Currency.pattern().search(button.text) == null)
	assert(money_fields >= 30)
	for key in ["net", "sales", "materials_cost", "fees", "contract_paid"]:
		assert(panel.statistics_values[key].coin_count == 1, "Each statistics money field uses one original coin")
	assert(panel.rows.forest_edge.summary.coin_count == 1, "Region list shows only the real repeat price")
	assert(panel.rows.moon.summary.coin_count == 2)
	panel.select_page(panel.OPERATION)
	assert(panel.recommend_button.icon == Currency.COIN)
	assert(Compare.equivalent(before, shop.state.to_data()), "Currency presentation never buys or awards")
	# Multiple inline amounts, minus/plus signs, large abbreviations and literal brackets.
	var fixture := Currency.new()
	fixture.appearance(11, Color.WHITE)
	root.add_child(fixture)
	fixture.set_value("매출 +1,234 G / 원정비 −8 G · 보유 1.2억 G · [미발견]")
	assert(fixture.coin_count == 3)
	assert(fixture.get_parsed_text().contains("+1,234") and fixture.get_parsed_text().contains("−8") and fixture.get_parsed_text().contains("1.2억") and fixture.get_parsed_text().contains("[미발견]"))
	fixture.set_value("약초 12/24 · 조사 3/10회 · 명성 40")
	assert(fixture.coin_count == 0 and not fixture.text.contains("[img"))
	panel.visible = true
	for page in panel.pages.size():
		panel.select_page(page)
		await process_frame
		await process_frame
		for row in panel.rows.values():
			if row.page != page or not row.panel.visible: continue
			for key in ["summary", "extra", "button"]:
				var node: Control = row[key]
				if node.is_visible_in_tree(): assert(row.panel.get_global_rect().grow(1).encloses(node.get_global_rect()), "Visible currency controls fit the existing card")
	assert(shop.minimal_gold.get_content_height() <= shop.minimal_gold.size.y and shop.minimal_income.get_content_height() <= shop.minimal_income.size.y)
	assert(panel.recommend_effect.get_content_height() <= panel.recommend_effect.size.y)
	shop.income.advance(0.1, 12345678)
	shop._update_interface()
	await process_frame
	assert(shop.minimal_income.source_text == "+1234.6만 G / 1분")
	assert(shop.minimal_income.tooltip_text.contains("12,345,678"))
	assert(shop.minimal_income.get_content_height() <= shop.minimal_income.size.y)
	# Visible virtual information layout: larger glyphs/coins fit real long amounts.
	shop._set_window_mode(shop.State.WindowMode.MINIMAL)
	for amount in [0, 99999, 99999999, 123456789, 999999999999]:
		shop.state.gold = amount
		shop._update_interface()
		await process_frame
		await process_frame
		assert(shop.minimal_gold.get_theme_font_size("normal_font_size") == 22)
		assert(shop.minimal_income.get_theme_font_size("normal_font_size") == 14)
		for field in [shop.minimal_gold, shop.minimal_income]:
			assert(field.get_content_height() <= field.size.y, "Enlarged information coin/text line fits")
			assert(field.get_content_width() <= field.size.x, "Enlarged information amounts are not clipped")
		var font := shop.minimal_brew.get_theme_font("font")
		var pixels: int = shop.minimal_brew.get_theme_font_size("font_size")
		assert(pixels == 14 and font.get_height(pixels) <= shop.minimal_brew.size.y)
		assert(font.get_string_size(shop.minimal_brew.text, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x <= shop.minimal_brew.size.x)
		assert(shop.minimal_brew.get_rect().end.y < shop.minimal_bar.position.y)
		assert(shop.minimal_bar.get_rect().end.y < shop.mini_toolbar.position.y)
	print("CURRENCY DISPLAY PASS: shared coin before each amount, all tabs/buttons/statistics/recipe prices/supply/minimal income, no G suffix, exact signs/quantities, no false resource icons, stable bounds and unchanged economy; headless only")
	quit()
