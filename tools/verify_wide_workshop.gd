extends SceneTree
const Shop = preload("res://scripts/shop.gd")
const State = preload("res://scripts/shop_state.gd")
const Layout = preload("res://scripts/workshop_layout.gd")
const Assets = preload("res://scripts/workshop_assets.gd")
const Gauges = preload("res://scripts/workshop_gauges.gd")
const Bridge = preload("res://scripts/desktop_input.gd")
const Status = preload("res://scripts/management_status.gd")
const Content = preload("res://scripts/shop_content.gd")
const Compare = preload("res://tests/state_compare.gd")
const Anchor = preload("res://scripts/window_mode_layout.gd")
var shop: Control
var manifest: Dictionary
var approved: Dictionary
var texture_index := 0
var output_root := "res://.verification/wide-runtime/"

func _initialize() -> void:
	assert(DisplayServer.get_name() == "headless")
	set_meta("isolated_preview", true)
	call_deferred("run")

func rect(values: Array) -> Rect2:
	return Rect2(values[0], values[1], values[2], values[3])

func opaque_overlap(command: Dictionary, area: Rect2) -> bool:
	var bounds: Rect2 = command.rect
	var overlap := bounds.intersection(area)
	if not overlap.has_area(): return false
	var image: Image = command.texture.get_image()
	for y in range(int(overlap.position.y), ceili(overlap.end.y)):
		for x in range(int(overlap.position.x), ceili(overlap.end.x)):
			var sample := Vector2i((Vector2(x, y) - bounds.position) / bounds.size * Vector2(image.get_size()))
			if command.get("flip_h", false): sample.x = image.get_width() - 1 - sample.x
			if image.get_pixelv(sample).a >= 0.2: return true
	return false

func encode(value: Variant) -> Variant:
	if value == null: return null
	if value is Texture2D:
		var path := output_root.path_join("textures/%04d.png" % texture_index)
		texture_index += 1
		assert(value.get_image().save_png(path) == OK)
		return {"image": ProjectSettings.globalize_path(path)}
	if value is Rect2 or value is Rect2i: return [value.position.x, value.position.y, value.size.x, value.size.y]
	if value is Vector2 or value is Vector2i: return [value.x, value.y]
	if value is Vector3: return [value.x, value.y, value.z]
	if value is Vector4: return [value.x, value.y, value.z, value.w]
	if value is Color: return "#" + value.to_html()
	if value is Dictionary:
		var result := {}
		for key in value: result[key] = encode(value[key])
		return result
	if value is Array:
		var result := []
		for item in value: result.append(encode(item))
		return result
	return value

func stock(kinds: Array) -> void:
	shop.state.inventory = kinds.duplicate()
	shop.state.stock = kinds.size()
	shop.state.mana_stock = kinds.count(true)

func setup_case(case_id: String) -> void:
	shop.state = State.new()
	var s: RefCounted = shop.state
	var p: RefCounted = s.progression
	s.gold = 148634
	s.window_mode = State.WindowMode.WORKSHOP
	s.main_window_mode = State.WindowMode.WORKSHOP
	p.clock = 1332.0 if case_id == "night-rain" else 12.0
	p.active_recipe = true
	s.active_mana = true
	s.brew_active = true
	s.brew_elapsed = s.brew_duration() * 0.42
	s.harvest_elapsed = s.harvest_duration() * 0.63
	p.owned = ["vigor", "focus"]
	p.expansion.grant_recipe("vigor")
	p.expansion.grant_recipe("focus")
	p.expansion.regions = ["forest_edge", "abandoned_greenhouse", "mist_valley"]
	p.expansion.parallel_version = 1
	State.Progression.Expeditions.ensure(p)
	State.Progression.Expeditions.tick(s, 0.0)
	stock([false, true, "vigor", "focus", false, true, "vigor", "focus"])
	if case_id == "storage-full":
		var kinds := []
		for i in s.capacity(): kinds.append(false if i % 2 == 0 else true)
		stock(kinds)
	if case_id in ["some-wait", "representative-wait", "zero"]:
		s.herbs = s.herb_capacity()
		p.expedition_count = int(Content.lookup("regions", "forest_edge").complete_returns)
		p.rare_herbs = p.expansion.special_capacity()
		p.expansion.cycles["forest_edge"].running = false
	if case_id == "some-wait": p.expansion.materials.dewgrass = p.expansion.special_capacity()
	if case_id == "maximum":
		for source in Content.DATA.materials:
			if source.id not in ["herb", "moon_mushroom", "starleaf"] and not p.expansion.plants.has(source.id): p.expansion.plants.append(source.id)
		p.owned.append("moon")
		for source in Content.DATA.regions:
			if not p.expansion.regions.has(source.id): p.expansion.regions.append(source.id)
		State.Progression.Expeditions.ensure(p)
		State.Progression.Expeditions.tick(s, 0.0)
	if case_id == "zero":
		s.brew_active = false
		s.brew_elapsed = 0.0
		p.rare_herbs = p.expansion.special_capacity()
		for source in Content.DATA.materials:
			if source.id not in ["herb", "moon_mushroom", "starleaf"]: p.expansion.materials[source.id] = p.expansion.special_capacity()
		p.expansion.cycles.clear()
		p.expansion.regions.clear()
		p.expansion.parallel_version = 1
	shop._apply_window_mode()
	shop._update_interface()
	shop.art.bottles.restore(s.stock, s.mana_stock, s.inventory_order())
	shop.art.motion.close_shop()
	shop.art.motion.visit = shop.art.Motion.Visit.WAITING
	shop.art.motion.customer_x = Layout.point("purchaseFeet").x
	shop.art._process(0.0)
	shop.workshop_gauges.refresh()

func verify_geometry() -> void:
	assert(Assets.SIZE == Vector2i(approved.w, approved.h + 12))
	for key in Layout.RECTS:
		# The user's later font enlargement adds 8px above the herb status panel.
		if key == "herbPanel":
			assert(Layout.rect(key) == Rect2(16, 202, 104, 42))
		elif approved.has(key): assert(Layout.rect(key) == rect(approved[key]), key)
	for key in Layout.BUTTONS:
		assert(Rect2(Layout.button_rect(key)) == rect(approved.buttons[key]))
		assert(shop.workshop_gauges.detail_buttons[key].get_rect() == rect(approved.buttons[key]))
	assert(shop.get_window().content_scale_size == Assets.SIZE)
	assert(shop.art.size == Vector2(approved.w, approved.artHeight))
	assert(shop.workshop_toolbar.get_rect() == Rect2(0, approved.artHeight, approved.w, 52))
	assert(not shop.workshop_toolbar.has_node("ExpeditionMapButton"))
	for id in ["MoveButton", "ManageButton", "MinimizeButton", "RestoreButton", "CloseButton"]:
		var key: String = {"MoveButton": "move", "ManageButton": "manage", "MinimizeButton": "minimize", "RestoreButton": "expand", "CloseButton": "close"}[id]
		var expected := rect(approved.toolbar[key])
		# The later toolbar request keeps x/width and gives 32px controls 10px padding.
		expected.position.y = 10
		expected.size.y = 32
		assert(shop.workshop_toolbar.get_node(id).get_rect() == expected, id)
	assert(shop.desktop_input.layout_size == Assets.SIZE and shop.desktop_input.art_height == 248)
	assert(shop.desktop_input.input_regions == Gauges.click_regions() and shop.desktop_input.process.is_empty())
	for key in Layout.BUTTONS:
		var expected := rect(approved.buttons[key])
		for scale in [1.0, 1.25, 1.5, 2.0]:
			for point in [expected.position, expected.end - Vector2(0.01, 0.01), expected.get_center()]:
				var physical: Vector2 = point * scale
				var normalized := Vector2(physical.x * 540 / (540 * scale), physical.y * 300 / (300 * scale))
				assert(not Bridge.passes_picture_input(normalized, Assets.SIZE, 248, Gauges.click_regions()))
			assert(Bridge.passes_picture_input((expected.end * scale) / scale, Assets.SIZE, 248, Gauges.click_regions()))
	for i in 8: assert(shop.art.bottles.slot_center(i) == Vector2(approved.slots[i][0], approved.slots[i][1]))
	assert(shop.art.motion.counter_x() == approved.motion.purchaseFeet[0])
	assert(shop.art.motion.offscreen_x() - 48 > approved.w)
	for rect_item in [Gauges.POT, Layout.rect("herbPanel"), Gauges.TRIPS[0]]:
		assert(Rect2(0, 0, 540, 248).encloses(rect_item))
		for key in ["window", "pot", "counter", "shelf"]:
			assert(not rect_item.intersects(rect(approved[key])), "%s overlaps %s" % [rect_item, key])
		for command in shop.art.render_commands():
			if command.role in ["keeper", "arriving_customer"]: assert(not opaque_overlap(command, rect_item), command.role)
	for command in shop.workshop_gauges.render_commands():
		if command.kind == "caption":
			assert(command.font_size == 14)
			assert(shop.body_font.get_string_size(command.text, HORIZONTAL_ALIGNMENT_LEFT, -1, command.font_size).x <= command.rect.size.x, command.text)
			assert(shop.body_font.get_height(command.font_size) <= command.rect.size.y, command.text)

func toolbar_snapshot() -> Array:
	var result := []
	for node in shop.workshop_toolbar.get_children():
		if not node is Control or not node.visible: continue
		var item := {"name": node.name, "rect": node.get_rect()}
		if node is TextureRect: item.texture = node.texture
		if node is Label:
			item.text = node.text
			item.font_size = node.get_theme_font_size("font_size")
		if node is Button:
			item.text = node.text
			item.icon = node.icon
			item.disabled = node.disabled
			item.font_size = node.get_theme_font_size("font_size")
		result.append(item)
	return result

func run() -> void:
	var design_path := ProjectSettings.globalize_path("res://").path_join("../output/workshop-wide-design-20261010-v1/manifest.json").simplify_path()
	assert(FileAccess.get_sha256(design_path) == "80ff2b46a4f272ae0836e189ef7136b3b426efdc1f1b8a05eb5043ef95fe3661")
	manifest = JSON.parse_string(FileAccess.get_file_as_string(design_path))
	for entry in manifest.layouts:
		if entry.w == 540: approved = entry
	assert(not approved.is_empty())
	assert(Content.DAY_SECONDS == 240 and Content.WEATHER_SECONDS == 90)
	assert(DirAccess.make_dir_recursive_absolute(output_root.path_join("textures")) == OK)
	shop = Shop.new()
	root.add_child(shop)
	shop.set_process(false)
	shop.art.set_process(false)
	var proof := {"size": [540, 300], "art_height": 248, "kind": "file-only runtime geometry; GPU shader/live input untested", "cases": [], "font": ProjectSettings.globalize_path("res://assets/fonts/pretendard/Pretendard-Regular.otf")}
	for case_id in ["day-crafting", "night-rain", "storage-full", "some-wait", "representative-wait", "maximum", "zero"]:
		setup_case(case_id)
		await process_frame
		verify_geometry()
		var baseline: Dictionary = shop.state.to_data().duplicate(true)
		for i in 5:
			shop.workshop_gauges.refresh()
			shop.art.render_commands()
			shop.art.pot_commands()
		assert(Compare.equivalent(baseline, shop.state.to_data()))
		assert(shop.workshop_gauges.active_herbs == Status.activity_counts(shop.state).herbs)
		assert(shop.workshop_gauges.active_regions == Status.activity_counts(shop.state).regions)
		if case_id == "storage-full":
			assert(not shop.workshop_gauges.craft.running and is_equal_approx(shop.workshop_gauges.craft.progress, 0.42))
		if case_id == "representative-wait": assert(not shop.workshop_gauges.herbs[0].running and shop.workshop_gauges.active_herbs > 0)
		if case_id == "zero": assert(shop.workshop_gauges.active_herbs == 0 and shop.workshop_gauges.active_regions == 0)
		var sky: Control = shop.art.workshop_weather
		proof.cases.append(encode({"id": case_id, "art": shop.art.render_commands(), "pot": shop.art.pot_commands(), "sky_frame": sky.render_commands(), "sky_time": sky.pane_commands("time"), "sky_weather": sky.pane_commands("weather"), "halos": [{"texture": shop.art.glow_warm.texture, "rect": shop.art.glow_warm.get_rect(), "color": shop.art.glow_warm.modulate}, {"texture": shop.art.glow_pink.texture, "rect": shop.art.glow_pink.get_rect(), "color": shop.art.glow_pink.modulate}], "snapshot": shop.art.render_snapshot(), "gauges": shop.workshop_gauges.render_commands(), "toolbar": toolbar_snapshot(), "buttons": Layout.BUTTONS, "craft": shop.workshop_gauges.craft, "herbs": shop.workshop_gauges.herbs, "trips": shop.workshop_gauges.trips}))
		for mode in [State.WindowMode.COMPANION, State.WindowMode.MINIMAL, State.WindowMode.FULL, State.WindowMode.WORKSHOP]:
			var before: Dictionary = shop.state.to_data().duplicate(true)
			shop._set_window_mode(mode)
			var expected_size: Vector2i = {State.WindowMode.COMPANION: Vector2i(256, 172), State.WindowMode.MINIMAL: Vector2i(320, 124), State.WindowMode.FULL: Vector2i(440, 704), State.WindowMode.WORKSHOP: Vector2i(540, 300)}[mode]
			assert(shop.get_window().content_scale_size == expected_size)
			assert(shop.art.size == Vector2(540, 248) if mode == State.WindowMode.WORKSHOP else shop.art.size == Vector2(408, 248))
			before.window_mode = shop.state.window_mode
			before.main_window_mode = shop.state.main_window_mode
			before.mini_mode = shop.state.mini_mode
			assert(Compare.equivalent(before, shop.state.to_data()))
			var restored := State.new()
			assert(restored.load_data(shop.state.to_data()) and restored.window_mode == mode)
			var previous := Rect2i(300, 300, 540, 300)
			var next_bar := 44 if mode == State.WindowMode.COMPANION else 52
			var next_position := Anchor.fixed_toolbar_position(previous, 52, expected_size, next_bar)
			assert(next_position + Vector2i(expected_size.x, expected_size.y - next_bar / 2) == previous.position + Vector2i(540, 274))
	var file := FileAccess.open(output_root.path_join("runtime.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(proof, "\t"))
	file.close()
	print("WIDE WORKSHOP PASS: approved art vs actual 540/248/52 nodes, map absent, padded controls/bridge and DPI125/150/200%; seven true model cases, fixed reps and actual counts, read-only/economy/RNG, expanded compact footers and save restore/right-bottom anchor; file render data exported; GPU/live desktop untested")
	quit()
