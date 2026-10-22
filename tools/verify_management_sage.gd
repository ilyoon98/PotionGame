extends SceneTree
## Isolated headless style inspection only; never native input or player saves.
const Shop = preload("res://scripts/shop.gd")
const State = preload("res://scripts/shop_state.gd")
const Content = preload("res://scripts/shop_content.gd")
const Currency = preload("res://scripts/currency_text.gd")
const Compare = preload("res://tests/state_compare.gd")
const Palette = preload("res://scripts/management_palette.gd")
const EXPECTED := {"BG": "1d242b", "SURFACE": "263139", "LINE": "40545a", "TEXT": "f3ede0", "MUTED": "abb9be", "ACCENT": "aacbb0", "ACTION": "e5ba73", "ACTION_TEXT": "272b2d", "TRIP": "a7b9d6"}
const OLD := ["211b2d", "f0dfc4", "b4a4bd", "342b41", "69516d", "4a3953", "efc77c", "ffe2a0", "d9a554", "423446", "6a5865", "b9833f", "302331", "53405b", "a8c99f", "493b51", "a2b5d5", "9b87ac", "bde3ac", "796449", "7d654a", "a99aad", "30273c", "44354e", "463650", "3e3448", "55455e", "66596e"]
const BUTTON_STATES := {"normal": "font_color", "hover": "font_hover_color", "pressed": "font_pressed_color", "hover_pressed": "font_hover_pressed_color", "disabled": "font_disabled_color"}
var shop: Control
var panel: Window
var checks := 0
var failures := 0
var color_count := 0
var contrast_count := 0
var control_count := 0
var minimum_ratio := 100.0
var minimum_case := ""
var contrasts := []
var checked_styles := {}
var checked_icons := {}
var default_theme: Theme

func _initialize() -> void:
	set_meta("isolated_preview", true)
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func channel(value: float) -> float:
	return value / 12.92 if value <= 0.04045 else pow((value + 0.055) / 1.055, 2.4)

func luminance(color: Color) -> float:
	return 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b)

func contrast(a: Color, b: Color) -> float:
	var first := luminance(a)
	var second := luminance(b)
	return (maxf(first, second) + 0.05) / (minf(first, second) + 0.05)

func readable(foreground: Color, background: Color, name: String, threshold: float = 4.5) -> void:
	var actual := contrast(background.blend(foreground), background)
	contrast_count += 1
	if actual < minimum_ratio:
		minimum_ratio = actual
		minimum_case = name
	check(actual >= threshold, "%s contrast %.3f is below %.1f (%s / %s)" % [name, actual, threshold, foreground.to_html(), background.to_html()])
	contrasts.append({"name": name, "foreground": foreground.to_html(), "background": background.to_html(), "ratio": actual, "threshold": threshold})

func sage_color(color: Color, name: String) -> void:
	color_count += 1
	if color.a <= 0.001: return
	check(not color.to_html(false) in OLD, "Old palette color remains in " + name + ": #" + color.to_html(false))
	# State colors may be derived from the fixed dark/sage/gold/blue roles.
	# Neutral icon masks/shadows remain neutral; purple UI hues must disappear.
	check(color.s < 0.06 or color.h < 0.69 or color.h > 0.96, "Unconverted purple theme color in " + name + ": #" + color.to_html(false))

func style_colors(style: StyleBox, name: String) -> void:
	if checked_styles.has(style.get_instance_id()): return
	checked_styles[style.get_instance_id()] = true
	for property in style.get_property_list():
		if property.type == TYPE_COLOR: sage_color(style.get(property.name), name + "/" + property.name)

func style_background(style: StyleBox, parent: Color = Color("1d242b")) -> Color:
	return parent.blend(style.bg_color) if style is StyleBoxFlat else parent

func inherited_background(node: Node) -> Color:
	var colors: Array[Color] = []
	var current: Node = node
	while current != null and current != panel:
		if current is Panel or current is PanelContainer:
			var style: StyleBox = current.get_theme_stylebox("panel")
			if style is StyleBoxFlat: colors.push_front(style.bg_color)
		current = current.get_parent()
	var result := Color("1d242b")
	for color in colors: result = result.blend(color)
	return result

func theme_names(theme: Theme, method: String, type: String) -> Array[String]:
	var result: Array[String] = []
	while not type.is_empty():
		for item in theme.call(method, type):
			if not result.has(item): result.append(item)
		type = ClassDB.get_parent_class(type)
	result.sort()
	return result

func native_icon(texture: Texture2D, name: String) -> void:
	# Default scrollbar arrows may deliberately be empty; there are no colors
	# to audit. Disabled native icons can also be translucent at every pixel.
	if texture == null or texture.get_width() == 0 or texture.get_height() == 0: return
	if checked_icons.has(texture.get_instance_id()): return
	checked_icons[texture.get_instance_id()] = true
	var image := texture.get_image()
	check(image != null and not image.is_empty(), "Native settings icon has real pixels: " + name)
	if image == null or image.is_empty(): return
	var solid := 0
	var rejected := false
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if color.a < 0.05: continue
			solid += 1
			if color.to_html(false) in OLD or (color.s >= 0.06 and color.h >= 0.69 and color.h <= 0.96): rejected = true
	check(solid > 0 and not rejected, "Native settings icon contains no old purple pixels: " + name)

func inspect_theme(theme: Theme) -> void:
	check(theme != shop.theme and theme.default_font == shop.body_font and theme.default_font_size == 16, "Management has a separate theme and the unchanged Pretendard font/body size")
	for type in theme.get_type_list():
		for name in theme.get_color_list(type): sage_color(theme.get_color(name, type), "Theme/" + type + "/" + name)
		for name in theme.get_stylebox_list(type): style_colors(theme.get_stylebox(name, type), "Theme/" + type + "/" + name)
		if type in ["CheckButton", "CheckBox", "HSlider", "VSlider", "Slider", "HScrollBar", "VScrollBar", "ScrollBar"]:
			for name in theme.get_icon_list(type): native_icon(theme.get_icon(name, type), "Theme/" + type + "/" + name)
	# Tooltip lookup without opening a tooltip or changing pointer/focus.
	var root_control: Control = panel.get_child(0)
	check(root_control.get_theme_color("font_color", "TooltipLabel") == Color("f3ede0"), "Tooltip text inherits sage")
	var tooltip_style := root_control.get_theme_stylebox("panel", "TooltipPanel")
	style_colors(tooltip_style, "TooltipPanel/panel")
	readable(root_control.get_theme_color("font_color", "TooltipLabel"), style_background(tooltip_style), "Tooltip text")
	for type in ["RichTextLabel", "LineEdit", "TextEdit"]:
		readable(root_control.get_theme_color("font_selected_color", type), Color("1d242b").blend(root_control.get_theme_color("selection_color", type)), type + "/selected text")

func inspect_control(node: Node) -> void:
	if node is Control:
		control_count += 1
		var context := str(panel.get_path_to(node))
		var type: String = node.get_class()
		for name in theme_names(default_theme, "get_color_list", type): sage_color(node.get_theme_color(name), context + "/" + name)
		for name in theme_names(default_theme, "get_stylebox_list", type): style_colors(node.get_theme_stylebox(name), context + "/" + name)
		for property in node.get_property_list():
			var key := str(property.name)
			if key.begins_with("theme_override_colors/"):
				var value: Variant = node.get(property.name)
				if value is Color: sage_color(value, context + "/" + key)
			elif key.begins_with("theme_override_styles/"):
				var value: Variant = node.get(property.name)
				if value is StyleBox: style_colors(value, context + "/" + key)
		if node is Label and not node.text.is_empty():
			readable(node.get_theme_color("font_color"), inherited_background(node), context + "/Label")
		elif node is RichTextLabel and not node.get_parsed_text().is_empty():
			readable(node.get_theme_color("default_color"), inherited_background(node), context + "/RichTextLabel")
		elif node is Button:
			var background := inherited_background(node.get_parent())
			for state in BUTTON_STATES:
				if state == "hover_pressed" and not node.has_theme_color(BUTTON_STATES[state]): continue
				var style: StyleBox = node.get_theme_stylebox(state)
				readable(node.get_theme_color(BUTTON_STATES[state]), style_background(style, background), context + "/Button/" + state)
			readable(node.get_theme_color("font_focus_color"), style_background(node.get_theme_stylebox("normal"), background), context + "/Button/focus text")
			var focus: StyleBox = node.get_theme_stylebox("focus")
			if focus is StyleBoxFlat:
				check(focus.border_width_top > 0 and focus.border_width_left > 0, "Native button focus remains visible: " + context)
				check(focus.border_color != Color("40545a"), "Focus cannot use the dim divider: " + context)
				readable(focus.border_color, background, context + "/focus outline", 3.0)
			if node is CheckButton:
				for name in theme_names(default_theme, "get_icon_list", type):
					if node.has_theme_icon(name): native_icon(node.get_theme_icon(name), context + "/" + name)
		elif node is Slider:
			var focus: StyleBox = node.get_theme_stylebox("grabber_area_highlight")
			if focus is StyleBoxFlat: readable(focus.bg_color, inherited_background(node), context + "/slider highlight", 3.0)
			for name in ["grabber", "grabber_highlight", "grabber_disabled"]: native_icon(node.get_theme_icon(name), context + "/" + name)
		elif node is ScrollBar:
			for name in ["grabber", "grabber_highlight", "grabber_pressed"]:
				var style: StyleBox = node.get_theme_stylebox(name)
				if style is StyleBoxFlat: readable(style.bg_color, style_background(node.get_theme_stylebox("scroll")), context + "/scrollbar/" + name, 3.0)
	for child in node.get_children(): inspect_control(child)

func resource_properties(resource: Resource) -> Dictionary:
	var result := {}
	for item in resource.get_property_list():
		if not (int(item.usage) & PROPERTY_USAGE_STORAGE): continue
		if item.name in ["resource_name", "resource_path", "resource_local_to_scene", "script"]: continue
		var value: Variant = resource.get(item.name)
		result[str(item.name)] = value.get_instance_id() if value is Resource else value
	return result

func theme_hash(theme: Theme) -> String:
	var snapshot := {"default_font": theme.default_font.get_instance_id(), "font_size": theme.default_font_size, "types": {}}
	var types := theme.get_type_list()
	types.sort()
	for type in types:
		var data := {}
		for kind in [Theme.DATA_TYPE_COLOR, Theme.DATA_TYPE_CONSTANT, Theme.DATA_TYPE_FONT, Theme.DATA_TYPE_FONT_SIZE, Theme.DATA_TYPE_ICON, Theme.DATA_TYPE_STYLEBOX]:
			var names := theme.get_theme_item_list(kind, type)
			names.sort()
			for name in names:
				var item: Variant = theme.get_theme_item(kind, name, type)
				data["%d/%s" % [kind, name]] = resource_properties(item) if item is StyleBox else item.get_instance_id() if item is Resource else item
		snapshot.types[type] = data
	return var_to_bytes(snapshot).hex_encode().sha256_text()

func main_style_data() -> Dictionary:
	var snapshot := {}
	var queue: Array[Node] = [shop]
	while not queue.is_empty():
		var node: Node = queue.pop_back()
		if node == panel: continue
		if node is CanvasItem:
			var data := {"modulate": node.modulate, "self_modulate": node.self_modulate}
			if node is Control:
				data["position"] = node.position
				data["size"] = node.size
				data["minimum"] = node.custom_minimum_size
			if node is ColorRect: data["color"] = node.color
			if node is TextureRect and node.texture != null: data["texture"] = node.texture.get_instance_id()
			for item in node.get_property_list():
				if not str(item.name).begins_with("theme_override_"): continue
				var value: Variant = node.get(item.name)
				if value != null: data[item.name] = resource_properties(value) if value is StyleBox else value.get_instance_id() if value is Resource else value
			snapshot[str(shop.get_path_to(node))] = data
		for child in node.get_children(): queue.append(child)
	return snapshot

func fixture() -> RefCounted:
	var state := State.new()
	state.gold = 1000000
	state.progression.reputation = 10000
	state.purchase("moon")
	state.purchase("expedition")
	state.progression.clock = 190.0
	state.progression.effects = 0.0
	return state

func freeze_fixture(node: Node) -> void:
	# Pause only newly constructed virtual actors. Unrelated candle flicker
	# changes alpha every frame and is not a management palette mutation.
	node.set_process(false)
	for child in node.get_children(): freeze_fixture(child)

func layout() -> void:
	panel.refresh()
	await process_frame
	await process_frame

func verify_palette_and_views() -> void:
	var palette_source: Script = load("res://scripts/management_palette.gd")
	var constants: Dictionary = palette_source.get_script_constant_map()
	for role in EXPECTED: check(constants.get(role) == Color(EXPECTED[role]), "Palette role matches the approved specification: " + role)
	var background: StyleBoxFlat = panel.get_child(0).get_theme_stylebox("panel")
	check(background.bg_color == Color("1d242b"), "Actual management uses the chosen background")
	inspect_theme(panel.get_child(0).theme)
	var before: Dictionary = shop.state.to_data().duplicate(true)
	# Hidden rows are inspected too: later purchases cannot reveal stale styles.
	inspect_control(panel)
	var reward_labels := 0
	for page in panel.pages.size():
		panel.select_page(page)
		await layout()
		for row: Dictionary in panel.rows.values():
			if row.page == page: row.toggle.button_pressed = true
		await layout()
		for row: Dictionary in panel.rows.values():
			if row.page != page: continue
			if row.has("detail_box"):
				for list in [row.guaranteed_list, row.reward_list, row.recipe_list]:
					for chip in list.get_children():
						var label: Label = chip.get_child(1)
						check(label.get_theme_color("font_color") == Color("f3ede0") and not label.has_theme_color_override("font_color"), "Dynamic material/recipe labels inherit the isolated sage theme")
						check(label.get_theme_font_size("font_size") == 16 and chip.get_child(0).custom_minimum_size == Vector2(32, 32), "Reward/recipe fonts and icons remain unchanged")
						reward_labels += 1
			row.toggle.button_pressed = false
		if page == panel.REPORT:
			check(panel.statistics_values.size() == 12 and panel.pages[page].find_children("*", "Button", true, false).is_empty(), "The read-only twelve statistics preserve the no-ledger/reset controls")
			for value in panel.statistics_values.values():
				readable(value.get_theme_color("default_color"), inherited_background(value), "Statistics/" + value.name)
		panel.scroll.scroll_vertical = 55 + page
		await process_frame
		var remembered: int = panel.scroll.scroll_vertical
		panel.select_page((page + 1) % panel.pages.size())
		await layout()
		panel.select_page(page)
		await layout()
		check(panel.scroll.scroll_vertical == remembered, "Palette refresh preserves each page's scroll")
	check(reward_labels >= 32, "Guaranteed, optional and recipe labels were inspected")
	check(Compare.equivalent(before, shop.state.to_data()), "Theme/view inspections preserve economy, RNG, reservations and serialized progress")
	panel.select_page(panel.EXPEDITIONS)
	await layout()
	for region in Content.DATA.regions: check(panel.rows[region.id].panel.size.y == 148, "All eight regions preserve collapsed 148px")

func verify_held_purchase() -> void:
	shop.state = fixture()
	shop.state.herbs = 3
	panel.select_page(panel.OPERATION)
	await layout()
	var key: String = panel.recommend_button.get_meta("purchase_key", "")
	check(panel.recommend_button.get_theme_stylebox("normal").bg_color == Color("e5ba73") and panel.recommend_button.get_theme_color("font_color") == Color("272b2d"), "Actual purchase uses the approved gold/dark-text pair")
	check(panel.recommend_button.icon == Currency.COIN, "Original coin texture remains untouched")
	panel.recommend_button.button_down.emit()
	shop.state.stock = shop.state.capacity()
	shop.state.inventory.clear()
	for i in shop.state.stock: shop.state.inventory.append(false)
	await layout()
	check(panel.recommend_button.get_meta("purchase_key", "") != key, "A real bottleneck changes the displayed recommendation")
	var control := State.new()
	check(control.load_data(shop.state.to_data().duplicate(true)) and control.purchase(key), "Reference model accepts the original target")
	panel.recommend_button.pressed.emit()
	await layout()
	check(panel.selected == panel.OPERATION and Compare.equivalent(control.to_data(), shop.state.to_data()), "Palette preserves the exact held purchase and single charge")

func run() -> void:
	if DisplayServer.get_name() != "headless":
		push_error("Palette verification requires isolated headless mode")
		quit(1)
		return
	Engine.max_fps = 60
	default_theme = ThemeDB.get_default_theme()
	shop = Shop.new()
	root.add_child(shop)
	freeze_fixture(shop)
	shop.state = fixture()
	shop._update_interface()
	# Let the first virtual draw/container layout allocate existing main actors.
	# Their initial glow alpha is set in _draw even with _process disabled.
	await process_frame
	await process_frame
	var host_theme := theme_hash(shop.theme)
	var host_styles := main_style_data()
	var font_regular := FileAccess.get_sha256(shop.body_font.resource_path)
	var font_semibold := FileAccess.get_sha256(shop.title_font.resource_path)
	shop.open_management()
	panel = shop.management
	panel.set_process(false)
	await layout()
	await verify_palette_and_views()
	var styles_after := main_style_data()
	for key in host_styles:
		if host_styles[key] != styles_after.get(key):
			print("HOST PAINT DIFF ", key, " BEFORE=", host_styles[key], " AFTER=", styles_after.get(key))
	check(theme_hash(shop.theme) == host_theme and styles_after == host_styles, "Management never mutates host theme/styles/main-mini colors/source textures")
	check(FileAccess.get_sha256(shop.body_font.resource_path) == font_regular and FileAccess.get_sha256(shop.title_font.resource_path) == font_semibold, "Pretendard files remain byte-identical")
	check(shop.INK == Color("f0dfc4") and shop.MUTED == Color("b4a4bd") and shop.BG == Color("211b2d") and shop.GOLD == Color("efc77c"), "Main game's original palette remains unchanged")
	await verify_held_purchase()
	DirAccess.make_dir_recursive_absolute("res://.verification/management-sage")
	var file := FileAccess.open("res://.verification/management-sage/contrast.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "controls": control_count, "colors": color_count, "contrast_cases": contrast_count, "minimum_ratio": minimum_ratio, "minimum_case": minimum_case, "pairs": contrasts}, "  "))
	if failures == 0:
		print("MANAGEMENT SAGE PASS: %d checks, %d controls, %d color roles and %d actual style/text contrast cases; all states/settings/scrollbar/tooltip/reward-recipe colors, separate focus accent, unchanged host/fonts/icons/economy/RNG, scroll/detail and exact held purchase; isolated headless only" % [checks, control_count, color_count, contrast_count])
	else: print("MANAGEMENT SAGE FAILED: %d of %d checks" % [failures, checks])
	quit(1 if failures > 0 else 0)
