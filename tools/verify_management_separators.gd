extends SceneTree
## Virtual headless layout only: no desktop input, focus, save or native helper.
const Shop = preload("res://scripts/shop.gd")
const State = preload("res://scripts/shop_state.gd")
const Currency = preload("res://scripts/currency_text.gd")
const Compare = preload("res://tests/state_compare.gd")
const CenteredButton = preload("res://scripts/centered_button_content.gd")
const Regulars = preload("res://scripts/shop_regulars.gd")
# Statistics page order: original nine, three contract totals, then the F21
# keeper/aging section. F22 regulars are separate cards (panel.regular_cards).
const STATISTIC_KEYS := ["play_time", "net", "sales", "materials_cost", "fees", "brewed", "sold", "expeditions", "reputation_gain", "contract_paid", "contract_shipped", "contract_rounds", "keeper_sleeps", "keeper_faints", "fatigue_failed", "aged_sold", "aged_revenue"]
var shop: Control
var panel: Window
var server: TextServer
var checks := 0
var failures := 0
var glyph_cache := {}
var measured := []

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

func owned_fixture() -> RefCounted:
	var state := State.new()
	state.gold = 1000000
	state.progression.reputation = 10000
	state.purchase("moon")
	state.purchase("expedition")
	state.herbs = 3
	return state

func ink_glyph(glyph: Dictionary) -> Rect2:
	# Raster alpha bounds, not character advance or an estimated string rectangle.
	var rid: RID = glyph.font_rid
	var pixels := Vector2i(glyph.font_size, 0)
	var key := "%s-%d-%d" % [rid.get_id(), glyph.font_size, glyph.index]
	if glyph_cache.has(key): return glyph_cache[key]
	server.font_render_glyph(rid, pixels, glyph.index)
	var uv := server.font_get_glyph_uv_rect(rid, pixels, glyph.index)
	if not uv.has_area(): return Rect2()
	var image := server.font_get_texture_image(rid, pixels, server.font_get_glyph_texture_idx(rid, pixels, glyph.index)).get_region(Rect2i(uv))
	image.convert(Image.FORMAT_RGBA8)
	var used := image.get_used_rect()
	var scale := server.font_get_glyph_size(rid, pixels, glyph.index) / Vector2(image.get_size())
	var result := Rect2(server.font_get_glyph_offset(rid, pixels, glyph.index) + Vector2(used.position) * scale, Vector2(used.size) * scale)
	glyph_cache[key] = result
	return result

func text_ink(font: Font, pixels: int, text: String, rect: Rect2, alignment: int = HORIZONTAL_ALIGNMENT_LEFT) -> Rect2:
	var paragraph := TextParagraph.new()
	paragraph.add_string(text, font, pixels)
	paragraph.width = -1
	var extent := paragraph.get_size()
	var pen := rect.position.x
	if alignment == HORIZONTAL_ALIGNMENT_CENTER: pen += (rect.size.x - extent.x) / 2.0
	elif alignment == HORIZONTAL_ALIGNMENT_RIGHT: pen += rect.size.x - extent.x
	var baseline := rect.position.y + (rect.size.y - extent.y) / 2.0 + paragraph.get_line_ascent(0)
	var result := Rect2()
	for glyph: Dictionary in server.shaped_text_get_glyphs(paragraph.get_line_rid(0)):
		for repeat in int(glyph.repeat):
			if glyph.font_rid.is_valid() and int(glyph.index) > 0:
				var ink := ink_glyph(glyph)
				if ink.has_area():
					ink.position += Vector2(pen, baseline) + Vector2(glyph.offset)
					result = result.merge(ink) if result.has_area() else ink
			pen += float(glyph.advance)
	return result

func label_ink(label: Label) -> Rect2:
	return text_ink(label.get_theme_font("font"), label.get_theme_font_size("font_size"), label.text, label.get_global_rect(), label.horizontal_alignment)

func native_content(button: Button) -> Dictionary:
	# Match Godot 4.6 Button draw rules; this independently measures the native
	# text and icon, including largest-state style margins and icon downscaling.
	var margin := [0.0, 0.0, 0.0, 0.0]
	for side in 4:
		margin[side] = button.get_theme_stylebox("normal").get_margin(side)
		if button.get_theme_constant("align_to_largest_stylebox"):
			for part in ["hover", "pressed", "disabled"]:
				margin[side] = maxf(margin[side], button.get_theme_stylebox(part).get_margin(side))
	var bounds := button.get_global_rect()
	var inner := Rect2(bounds.position + Vector2(margin[SIDE_LEFT], margin[SIDE_TOP]), bounds.size - Vector2(margin[SIDE_LEFT] + margin[SIDE_RIGHT], margin[SIDE_TOP] + margin[SIDE_BOTTOM]))
	var text_rect := inner
	var icon_rect := Rect2()
	if button.icon != null:
		var available := inner.size
		if button.icon_alignment != HORIZONTAL_ALIGNMENT_CENTER and not button.clip_text and not button.text.is_empty():
			available.x -= button.get_theme_font("font").get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x + button.get_theme_constant("h_separation")
		var extent := button.icon.get_size()
		if button.expand_icon: extent *= minf(available.x / extent.x, available.y / extent.y)
		var max_width := button.get_theme_constant("icon_max_width")
		if max_width > 0 and extent.x > max_width: extent *= float(max_width) / extent.x
		extent = extent.round()
		var offset := Vector2(0, (inner.size.y - extent.y) / 2.0)
		if button.icon_alignment == HORIZONTAL_ALIGNMENT_CENTER: offset.x = (inner.size.x - extent.x) / 2.0
		elif button.icon_alignment == HORIZONTAL_ALIGNMENT_RIGHT: offset.x = inner.size.x - extent.x
		icon_rect = Rect2((inner.position + offset).floor(), extent)
		if button.icon_alignment != HORIZONTAL_ALIGNMENT_CENTER:
			var advance := extent.x + maxi(0, button.get_theme_constant("h_separation"))
			text_rect.size.x -= advance
			if button.icon_alignment == HORIZONTAL_ALIGNMENT_LEFT: text_rect.position.x += advance
	var ink := text_ink(button.get_theme_font("font"), button.get_theme_font_size("font_size"), button.text, text_rect, button.alignment)
	return {"icon": icon_rect, "text": ink, "content": icon_rect.merge(ink) if icon_rect.has_area() else ink, "inner": inner}

func simple_divider(style: StyleBoxFlat, favored: bool = false) -> void:
	check(is_zero_approx(style.bg_color.a), "Rows/strips must be transparent")
	check(style.border_width_top == 0 and style.border_width_right == 0 and style.border_width_bottom == 1, "Only a one-pixel bottom divider remains")
	check(style.border_width_left == (2 if favored else 0), "Only favorable environment rows retain the left accent")
	for corner in ["corner_radius_top_left", "corner_radius_top_right", "corner_radius_bottom_left", "corner_radius_bottom_right"]:
		check(style.get(corner) == 0, "Divider rows have no rounded card corners")

func verify_header() -> void:
	for value in [0, 21799, 9999999999999999]:
		shop.state.gold = value
		shop.state.progression.reputation = value
		var before: Dictionary = shop.state.to_data().duplicate(true)
		await layout()
		var glyphs := []
		for group: Dictionary in [{"box": panel.gold_group, "icon": panel.gold_icon, "label": panel.gold_label, "caption": panel.gold_caption, "name": "골드"}, {"box": panel.reputation_group, "icon": panel.reputation_icon, "label": panel.reputation_label, "caption": panel.reputation_caption, "name": "명성"}]:
			var label: Label = group.label
			var icon: TextureRect = group.icon
			var caption: Label = group.caption
			var full: String = shop._number(value)
			var extent := label.get_theme_font("font").get_string_size(full, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
			var expected: String = full if extent.x <= label.size.x else shop._compact_number(value)
			check(label.text == expected and label.tooltip_text == group.name + " " + full, "Only overflowing numeric values abbreviate; tooltip keeps the caption and exact amount")
			check(icon.size == Vector2(24, 24) and caption.text == group.name and caption.get_theme_font_size("font_size") == 14, "Gold and fame use uniform 24px icons and separate 14px captions")
			check(label.get_theme_font_size("font_size") == 18, "Header never shrinks its font")
			var gap := caption.get_global_rect().position.x - icon.get_global_rect().end.x
			check(gap >= 8 and gap <= 12, "Each metric has an 8–12px icon/caption gap")
			gap = label.get_global_rect().position.x - caption.get_global_rect().end.x
			check(gap >= 8 and gap <= 12, "Caption and numeric value retain their own 8–12px gap")
			check(absf(icon.get_global_rect().get_center().y - label.get_global_rect().get_center().y) <= 0.5, "Each header metric is vertically centered within native pixel rounding")
			var ink := label_ink(label)
			var caption_ink := label_ink(caption)
			check(ink.has_area() and label.get_global_rect().grow(1).encloses(ink), "Actual rasterized header glyphs fit the value slot")
			check(caption.get_global_rect().grow(1).encloses(caption_ink) and not caption_ink.intersects(ink), "Actual caption glyphs fit and never overlap the numeric value")
			check(not ink.intersects(icon.get_global_rect()), "Icon never overlaps actual header glyph ink")
			check(group.box.get_global_rect().grow(1).encloses(ink), "Header ink never crosses into another metric")
			glyphs.append(ink)
		check(panel.gold_group.get_global_rect().end.x + 24 <= panel.reputation_group.get_global_rect().position.x, "Metric groups retain their separate 24px gap")
		check(not glyphs[0].intersects(glyphs[1]), "Gold and fame actual glyphs never overlap")
		for child in panel.get_child(0).get_children():
			if child is Button and child.text in ["통계", "닫기"]:
				check(not panel.header_stats.get_global_rect().intersects(child.get_global_rect()), "Header groups stay below result/close hit areas")
		check(panel.header_stats.get_rect().end.y + 8 <= panel.tabs[0].position.y, "Text tabs keep header breathing room")
		check(Compare.equivalent(before, shop.state.to_data()), "Header refresh never changes economy or RNG")
		measured.append({"gold": value, "gold_display": panel.gold_label.text, "fame_display": panel.reputation_label.text, "gold_icon": str(panel.gold_icon.get_global_rect()), "gold_label": str(panel.gold_label.get_global_rect()), "fame_icon": str(panel.reputation_icon.get_global_rect()), "fame_label": str(panel.reputation_label.get_global_rect()), "gold_ink": str(glyphs[0]), "fame_ink": str(glyphs[1])})

func verify_tabs_rows_sections() -> void:
	shop.state = owned_fixture()
	var before: Dictionary = shop.state.to_data().duplicate(true)
	check(panel.tabs.size() == 7 and panel.pages.size() == 8, "Seven tabs and the independent statistics page remain")
	# Tabs map to pages through TAB_PAGES: statistics (REPORT) is reached from the
	# header button, so the seventh tab opens the separate SETTINGS page.
	check(panel.TAB_PAGES == [panel.OPERATION, panel.HERBS, panel.POTIONS, panel.RECIPES, panel.EXPEDITIONS, panel.UPGRADES, panel.SETTINGS] and not panel.TAB_PAGES.has(panel.REPORT), "Seven text tabs open their own pages; statistics stays off the tab row")
	for index in panel.tabs.size():
		var page_index: int = panel.TAB_PAGES[index]
		panel.tabs[index].pressed.emit()
		await layout()
		check(panel.selected == page_index and panel.pages[page_index].visible, "Native tab pressed signal retains its own page callback")
		for tab_index in panel.tabs.size():
			var tab: Button = panel.tabs[tab_index]
			var active: bool = tab_index == index
			check(tab.button_pressed == active and bool(tab.get_meta("selected_underline", false)) == active, "Selection and toggle state agree")
			check(tab.focus_mode == Control.FOCUS_ALL and tab.get_theme_font_size("font_size") == 16, "Text tabs preserve keyboard focus support and readable fonts")
			for part in ["normal", "pressed", "disabled"]:
				var style: StyleBoxFlat = tab.get_theme_stylebox(part)
				check(is_zero_approx(style.bg_color.a) and style.border_width_bottom == (2 if active else 0), "Text tabs have no fill and only the selected underline")
			var focus: StyleBoxFlat = tab.get_theme_stylebox("focus")
			check(is_zero_approx(focus.bg_color.a) and focus.border_width_top == 1 and focus.border_width_left == 1 and focus.border_width_right == 1 and focus.border_width_bottom == 1, "Keyboard focus has a separate one-pixel outline")
			check(focus.border_color != tab.get_theme_stylebox("normal").border_color, "Keyboard focus and selected underline use distinct accents")
		for row: Dictionary in panel.rows.values():
			if row.page != page_index or not row.panel.visible: continue
			simple_divider(row.style, row.highlighted)
			check(row.icon.size == Vector2(48, 48) and row.title.get_theme_font_size("font_size") == 18, "Existing large row icon and title remain")
			if page_index == panel.EXPEDITIONS:
				check(row.panel.size.y == (188 if row.has("rare_line") else 148) and not row.detail_box.visible, "Only four real discovery destinations add the stable 40px line; other collapsed regions retain 148px")
				check(row.primary_icon.size == Vector2(32, 32) and row.summary.get_theme_font_size("normal_font_size") == 16, "All eight region primary ingredients retain their 32px icon and 16px text")
				check(row.work.caption.get_theme_font_size("font_size") == 16 and row.work.count.get_theme_font_size("font_size") == 16, "Expedition state and remaining-time text are not reduced")
			check(row.toggle.focus_mode == Control.FOCUS_ALL and row.toggle.get_theme_font_size("font_size") == 16 and row.toggle.custom_minimum_size == Vector2(52, 32), "Text detail retains its hit area and keyboard semantics")
			check(is_zero_approx(row.toggle.get_theme_stylebox("normal").bg_color.a), "Detail is no longer a filled mini-card")
	panel.select_page(panel.OPERATION)
	await layout()
	simple_divider(panel.recommend_panel.get_theme_stylebox("panel"))
	var children: Array = panel.pages[panel.OPERATION].get_children()
	var section_names := []
	var previous_visible: Control
	for index in children.size():
		var child: Control = children[index]
		if not child.visible: continue
		if child is Label:
			section_names.append(child.text)
			check(index > 0 and children[index - 1].get_meta("section_gap", false), "Each operation title has its own section spacer")
			if previous_visible != null:
				var distance := child.position.y - previous_visible.get_rect().end.y
				check(distance >= 16 and distance <= 24, "Visible operation section boundaries keep 16–24px of whitespace")
		elif child.has_meta("row_id") and previous_visible != null and previous_visible.has_meta("row_id"):
			check(is_equal_approx(child.position.y - previous_visible.get_rect().end.y, 4), "Rows within the same section preserve their original 4px gap")
		if not child.get_meta("section_gap", false): previous_visible = child
	check(section_names == ["포션", "자동 납품", "채집", "원정"], "Operation titles include the contract summary and retain catalog order")
	var first_heading: Label = children[1]
	var first_gap: float = first_heading.get_global_rect().position.y - panel.recommend_panel.get_global_rect().end.y
	check(first_gap >= 16 and first_gap <= 24, "First title has 16–24px after the recommendation strip")
	check(panel.scroll.position.y - panel.recommend_panel.get_rect().end.y == 8, "Recommendation keeps the separate existing 8px content-area gap")
	check(Compare.equivalent(before, shop.state.to_data()), "Tabs, separators and section layout never mutate state")

func verify_details_weather_scroll() -> void:
	panel.select_page(panel.EXPEDITIONS)
	await layout()
	var before: Dictionary = shop.state.to_data().duplicate(true)
	var region: Dictionary = panel.rows.forest_edge
	var collapsed_height: float = region.panel.size.y
	check(collapsed_height == (188 if region.has("rare_line") else 148) and not region.detail_box.visible, "Expedition keeps its approved discovery-line height and complete collapsed detail")
	region.toggle.button_pressed = true
	await layout()
	check(region.detail_box.visible and region.toggle.get_theme_stylebox("normal").border_width_bottom == 2, "Detail opens all rewards and shows its expanded underline")
	check(region.toggle.get_theme_stylebox("focus").border_width_top == 1, "Expanded detail still has an independent focus outline")
	region.toggle.button_pressed = false
	await layout()
	check(not region.detail_box.visible and region.panel.size.y == collapsed_height, "Closing detail restores the exact original row")
	panel.result_button.pressed.emit()
	await layout()
	check(panel.selected == panel.REPORT and panel.pages[panel.REPORT].visible and not panel.recommend_panel.visible, "Statistics remains an independent seventh page")
	check(panel.statistics_values.keys() == STATISTIC_KEYS and panel.pages[panel.REPORT].find_children("*", "Button", true, false).is_empty(), "Statistics retains nine values, three contract totals and five F21 keeper/aging values in order, with no ledger/reset action")
	check(panel.regular_cards.keys() == Regulars.ids() and Regulars.ids().size() == 4 and not panel.regular_cards.keys().any(func(id): return panel.statistics_values.has(id)), "F22 regulars stay four separate read-only cards, never statistics values")
	check(Compare.equivalent(before, shop.state.to_data()), "Details and statistics never award, charge, roll or alter saved state")
	shop.state.progression.clock = 190.0
	shop.state.progression.effects = 0.0
	panel.select_page(panel.HERBS)
	await layout()
	check(panel.rows.rare_inventory.highlighted, "Night/rain herb effect retains its actual environment emphasis")
	simple_divider(panel.rows.rare_inventory.style, true)
	check(not panel.rows.rare_inventory.panel.tooltip_text.is_empty(), "Weather condition text remains available on the row")
	panel.select_page(panel.POTIONS)
	await layout()
	check(panel.rows.potion_moon.highlighted and not panel.rows.potion_health.highlighted, "Favorable potion effect remains distinct from an ordinary potion")
	simple_divider(panel.rows.potion_moon.style, true)
	simple_divider(panel.rows.potion_health.style)
	before = shop.state.to_data().duplicate(true)
	panel.size.y = 600
	for page in [panel.OPERATION, panel.HERBS, panel.POTIONS, panel.RECIPES, panel.EXPEDITIONS, panel.UPGRADES, panel.REPORT]:
		panel.select_page(page)
		await layout()
		check(panel.scroll.get_rect().end.y == 580 and panel.scroll.get_rect().end.x == 500, "Every page keeps its scroll inside a short 520px-wide management window")
		if page != panel.REPORT: check(panel.pages[page].size.y > panel.scroll.size.y, "Long lists use real scrollable contents rather than clipping away rows")
		panel.scroll.scroll_vertical = 45 + page
		await process_frame
		var remembered: int = panel.scroll.scroll_vertical
		panel.select_page((page + 1) % panel.pages.size())
		await layout()
		panel.select_page(page)
		await layout()
		check(panel.scroll.scroll_vertical == remembered, "Each page remembers its own scroll position (page %d, expected %d, actual %d)" % [page, remembered, panel.scroll.scroll_vertical])
	check(Compare.equivalent(before, shop.state.to_data()), "Short-window layout and page scroll preserve economy, reservations and RNG")
	panel.size.y = 800

func verify_recommendation() -> void:
	shop.state = owned_fixture()
	panel.select_page(panel.OPERATION)
	await layout()
	var before: Dictionary = shop.state.to_data().duplicate(true)
	var button: Button = panel.recommend_button
	check(button.icon == Currency.COIN and button.get_theme_font_size("font_size") == 16 and button.focus_mode == Control.FOCUS_ALL, "Recommendation keeps its real native purchase Button, original coin and keyboard support")
	check(button.icon_alignment == HORIZONTAL_ALIGNMENT_LEFT and button.alignment == HORIZONTAL_ALIGNMENT_LEFT, "Coin and text stay contiguous in native drawing")
	check(button.get_theme_constant("h_separation") >= 6 and button.get_theme_constant("h_separation") <= 8, "Recommendation coin-to-price spacing is 6–8px")
	var fixtures := ["강화 · 80 G", "원정 열기 · 23,800 G", "레시피 구매 · 65,000 G", "훈련 · 10,000 G", "구매 대기"]
	var source: String = button.get_meta("currency_source", "")
	for fixture in fixtures:
		Currency.button_value(button, fixture)
		# Exercise production formatting and layout on each real action type,
		# independently verifying its native drawing with actual glyph alpha bounds.
		CenteredButton.apply(button)
		await process_frame
		var content := native_content(button)
		var geometry := CenteredButton.rects(button)
		check(geometry.fits and geometry.margin_left >= 14 and is_equal_approx(geometry.margin_left, geometry.margin_right), "Native content helper retains symmetric padding and complete content: " + fixture)
		var reported_icon: Rect2 = geometry.icon
		reported_icon.position += button.global_position
		check(reported_icon.is_equal_approx(content.icon) if reported_icon.has_area() else not content.icon.has_area(), "Independent native icon geometry matches helper results: " + fixture)
		check(button.get_global_rect().grow(1).encloses(content.content), "Actual recommendation icon/glyph ink fits the CTA: " + fixture)
		check(absf(content.content.get_center().x - button.get_global_rect().get_center().x) <= 1.5, "Recommendation coin+price+action are centered together: " + fixture)
		check(content.content.position.x - button.global_position.x >= 12 and button.get_global_rect().end.x - content.content.end.x >= 12, "Recommendation preserves at least 12px of inner breathing room: " + fixture)
		if content.icon.has_area(): check(content.text.position.x - content.icon.end.x >= 6 and content.text.position.x - content.icon.end.x <= 10, "Coin stays immediately beside rasterized price glyphs: " + fixture)
		measured.append({"recommendation": fixture, "text": button.text, "icon_rect": str(content.icon), "glyph_rect": str(content.text), "content_rect": str(content.content)})
	Currency.button_value(button, source)
	await layout()
	check(Compare.equivalent(before, shop.state.to_data()), "CTA presentation fixtures never purchase or change RNG")
	# The model changes while the user holds the real button; only the original
	# captured target may be charged, with the latest conditions checked on release.
	var held: String = button.get_meta("purchase_key", "")
	button.button_down.emit()
	shop.state.stock = shop.state.capacity()
	shop.state.inventory.clear()
	for i in shop.state.stock: shop.state.inventory.append(false)
	await layout()
	check(button.get_meta("purchase_key", "") != held, "A real bottleneck changes the visible recommendation while held")
	var control := State.new()
	check(control.load_data(shop.state.to_data().duplicate(true)), "Purchase reference fixture loads")
	check(control.purchase(held), "Original held recommendation remains a valid purchase")
	button.pressed.emit()
	await layout()
	check(panel.selected == panel.OPERATION and panel.recommend_pressed_action.is_empty(), "Purchase does not navigate and clears the held target")
	check(Compare.equivalent(control.to_data(), shop.state.to_data()), "Pressed-target freeze charges exactly the original purchase once")
	button.button_down.emit()
	shop.state.gold = 0
	await layout()
	before = shop.state.to_data().duplicate(true)
	button.pressed.emit()
	check(Compare.equivalent(before, shop.state.to_data()), "Funds disappearing while held cannot cause a charge, purchase or RNG change")

func verify_internal_close_and_title() -> void:
	panel.select_page(panel.UPGRADES)
	await layout()
	panel.scroll.scroll_vertical = 90
	await process_frame
	var selected: int = panel.selected
	var scroll_value: int = panel.scroll.scroll_vertical
	var state_before: Dictionary = shop.state.to_data().duplicate(true)
	var login_before: Dictionary = shop.login_resume.data.duplicate(true)
	var start_position: Vector2i = panel.position
	# Headless DisplayServer does not report native Window flags. The OS title-bar
	# change itself is intentionally untested; internal close/drag behavior is real.
	check(panel.close_button.text == "닫기", "The internal management close remains")
	check(panel.title_drag_handle.get_rect() == Rect2(0, 0, 520, 54), "Draggable title area stays above header statistics and text tabs")
	for button in [panel.result_button, panel.close_button]:
		var bounds: Rect2 = button.get_rect()
		for point in [bounds.position, bounds.get_center(), bounds.end - Vector2.ONE]:
			check(not panel._title_drag_hit(point), "Result and close button hit areas are excluded from title dragging")
	for point in [Vector2(1, 1), Vector2(160, 28), Vector2(519, 53)]:
		check(panel._title_drag_hit(point), "Empty title positions remain draggable")
	check(not panel._title_drag_hit(Vector2(10, 54)), "Statistics, tabs and rows cannot begin a title drag")
	# These are synthetic signals in a virtual headless viewport, not Input.parse,
	# physical/native keyboard focus or mouse interaction with a desktop window.
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = panel.close_button.get_rect().get_center()
	panel.title_drag_handle.gui_input.emit(event)
	check(not panel.title_dragging, "Close hit cannot activate a title drag")
	event.position = Vector2(160, 28)
	panel.title_drag_handle.gui_input.emit(event)
	check(panel.title_dragging, "An empty-title signal starts only the internal drag flag")
	panel._process(0.05)
	check(panel.position == start_position, "Headless drag never performs native window movement")
	panel.close_button.pressed.emit()
	check(not panel.visible and not panel.title_dragging and not is_queued_for_deletion(), "Internal close hides management and clears the drag; game stays alive")
	shop.open_management()
	await layout()
	check(panel.visible and panel.selected == selected and panel.scroll.scroll_vertical == scroll_value, "Reopening management preserves selected page and scroll")
	check(Compare.equivalent(state_before, shop.state.to_data()) and Compare.equivalent(login_before, shop.login_resume.data), "Title and management hide/reopen preserve economy/RNG and login resume intention")

func run() -> void:
	if DisplayServer.get_name() != "headless":
		push_error("This verification requires headless mode")
		quit(1)
		return
	Engine.max_fps = 60
	server = TextServerManager.get_primary_interface()
	shop = Shop.new()
	root.add_child(shop)
	shop.set_process(false)
	shop.state = owned_fixture()
	shop.open_management()
	panel = shop.management
	panel.set_process(false)
	await layout()
	await verify_header()
	await verify_tabs_rows_sections()
	await verify_details_weather_scroll()
	await verify_recommendation()
	await verify_internal_close_and_title()
	DirAccess.make_dir_recursive_absolute("res://.verification/management-separators")
	var file := FileAccess.open("res://.verification/management-separators/measurements.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"verification": "headless native content geometry plus actual rasterized glyph alpha bounds; no OS inputs", "checks": checks, "failures": failures, "measurements": measured}, "  "))
	if failures == 0:
		print("MANAGEMENT SEPARATORS PASS: %d checks; uniform gold/fame icons/captions/values and actual glyph bounds, transparent divider rows, seven underlined text tabs mapped through TAB_PAGES/separate focus styles, concise section gaps, four 148px/four 188px expedition rows, complete details and 17 read-only statistics plus four separate regular cards, weather accents, short-window per-page scroll, centered native purchase content, held target, title hit areas/internal close-reopen and unchanged economy/RNG/save; headless only; native Windows title bar and movement untested" % checks)
	else:
		print("MANAGEMENT SEPARATORS FAILED: %d of %d checks" % [failures, checks])
	quit(1 if failures > 0 else 0)
