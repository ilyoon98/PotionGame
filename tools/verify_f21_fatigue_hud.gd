extends SceneTree
## F21 keeper stat row in the workshop HUD and the cask/keeper management icons.
## Isolated test shop; the player save is not used. With a rendering driver it
## also captures the workshop in four keeper states for visual review.
const Shop = preload("res://scripts/shop.gd")
const State = preload("res://scripts/shop_state.gd")
const Gauges = preload("res://scripts/workshop_gauges.gd")
const Layout = preload("res://scripts/workshop_layout.gd")
const ManagementArt = preload("res://scripts/management_art.gd")
const M = preload("res://tests/contracts_fixture.gd")
const Compare = preload("res://tests/state_compare.gd")
const FOLDER := "res://.verification/f21-fatigue-hud-20261022/"
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func _initialize() -> void:
	set_meta("isolated_preview", true); call_deferred("run")
func freeze(node: Node) -> void:
	node.set_process(false)
	for child in node.get_children(): freeze(child)
func role(commands: Array[Dictionary], name: String) -> Dictionary:
	for c in commands:
		if c.get("role", "") == name: return c
	return {}
func run() -> void:
	var shop := Shop.new(); root.add_child(shop)
	await process_frame
	freeze(shop)
	shop.state = State.new(); shop.state.gold = 1000
	shop._set_window_mode(State.WindowMode.WORKSHOP)
	var gauges: Control = shop.workshop_gauges
	# Layout: inside the art area and clear of every existing panel and button.
	var panel := Gauges.KEEPER_PANEL
	check(Rect2(Vector2.ZERO, Vector2(Layout.SIZE.x, Layout.ART_HEIGHT)).encloses(panel), "Keeper row inside the workshop art area")
	for key in ["potPanel", "herbPanel", "shelf", "poster", "counter", "pot", "window"]:
		check(not panel.intersects(Layout.rect(key)), "Keeper row clear of " + key)
	for key in Layout.BUTTONS: check(not panel.intersects(Rect2(Layout.BUTTONS[key])), "Keeper row clear of the %s detail button" % key)
	# The longest captions fit the row at the real font.
	for text in ["한계 · 피로 100", "수면 · 피로 100", "기절 · 피로 100", "상쾌 · 피로 39"]:
		var width: float = shop.body_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, Gauges.KEEPER_CAPTION_SIZE).x
		check(width <= panel.size.x - 10, "'%s' fits the keeper row (%.1fpx)" % [text, width])
	# Text and bar follow the keeper state and fatigue band.
	var cases := [["awake", 12.0, "상쾌 · 피로 12", "718C59"], ["awake", 45.0, "보통 · 피로 45", "E9B95F"], ["awake", 65.5, "피곤 · 피로 65", "F4AC68"], ["awake", 88.0, "한계 · 피로 88", "DE7356"], ["asleep", 30.0, "수면 · 피로 30", "718C59"], ["fainted", 100.0, "기절 · 피로 100", "DE7356"]]
	for c in cases:
		shop.state.keeper.state = c[0]; shop.state.keeper.fatigue = c[1]
		gauges.refresh()
		var commands: Array[Dictionary] = gauges.render_commands()
		var caption := role(commands, "keeper_caption"); var bar := role(commands, "keeper_fatigue")
		check(caption.get("text", "") == c[2], "Caption %s/%.1f = '%s' (%s)" % [c[0], c[1], c[2], caption.get("text", "")])
		check(not bar.is_empty() and absf(float(bar.progress) - float(c[1]) / 100.0) < 0.0001 and bar.color.is_equal_approx(Color(c[3])), "Bar %s/%.1f uses band color %s" % [c[0], c[1], c[3]])
	# Character mode badge shows the same text and band color.
	shop._set_window_mode(State.WindowMode.COMPANION)
	shop.state.keeper.state = "awake"; shop.state.keeper.fatigue = 65.5
	shop.companion.refresh()
	check(shop.companion.keeper_caption.text == "피곤 · 피로 65" and shop.companion.keeper_fill.color.is_equal_approx(Color("F4AC68")) and shop.companion.keeper_fill.size.x == floorf(0.655 * 86.0), "Character badge text, color and bar width")
	var badge_width: float = shop.body_font.get_string_size("한계 · 피로 100", HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	check(badge_width <= shop.companion.KEEPER_BADGE.size.x - 10, "Character badge fits its longest caption (%.1fpx)" % badge_width)
	shop._set_window_mode(State.WindowMode.WORKSHOP)
	shop.state.keeper.state = "fainted"; shop.state.keeper.fatigue = 100.0
	gauges.refresh()
	check(gauges.detail_buttons.is_empty() or gauges.detail_buttons.potions.tooltip_text.contains("주인공 기절 · 피로 100"), "Cauldron tooltip names the keeper stat")
	# Icons: the cask and three keeper frames resolve to real, non-empty pixels.
	for id in ["aging_cask", "keeper", "keeper_sleep", "keeper_faint"]:
		var texture: Texture2D = ManagementArt.icon(id)
		var image: Image = texture.get_image() if texture != null else null
		check(ManagementArt.has_icon(id) and image != null and image.get_used_rect().get_area() > 100, "Icon %s has visible pixels" % id)
	check(ManagementArt.icon("aging_cask").get_size() == Vector2(32, 32) and ManagementArt.icon("keeper").get_size() == Vector2(32, 48), "Cask 32x32, keeper frame 32x48")
	# Management rows use them; the keeper row follows his state.
	shop.open_management()
	var panel_window = shop.management; panel_window.set_process(false)
	shop.state.progression.reputation = 5000
	shop.state.keeper.state = "awake"; shop.state.keeper.fatigue = 10.0
	panel_window.select_page(panel_window.OPERATION); panel_window.refresh()
	for i in 3: await process_frame
	check(panel_window.rows.aging.icon.texture == ManagementArt.readable_icon(ManagementArt.icon("aging_cask")), "Operation aging row shows the cask")
	for track in ["open", "barrels", "cellar", "shelf"]: check(panel_window.rows["aging_" + track].icon.texture == ManagementArt.readable_icon(ManagementArt.icon("aging_cask")), "Aging upgrade %s shows the cask" % track)
	check(panel_window.rows.keeper.icon.texture == ManagementArt.icon("keeper"), "Keeper row shows the awake keeper")
	for s in [["asleep", "keeper_sleep"], ["fainted", "keeper_faint"], ["awake", "keeper"]]:
		shop.state.keeper.state = s[0]
		var before: Dictionary = M.data(shop.state)
		panel_window.refresh_gauges(0.016)
		check(panel_window.rows.keeper.icon.texture == ManagementArt.icon(s[1]), "Keeper row icon follows %s" % s[0])
		check(Compare.equivalent(before, M.data(shop.state)), "Icon refresh is read-only (%s)" % s[0])
	# Statistics page: lifetime keeper and aging totals.
	shop.state.keeper.totals = {"sleeps": 12, "faints": 2, "fatigue_failed": 7}
	shop.state.aging.totals = {"sold": 1234, "revenue": 56789}
	panel_window.select_page(panel_window.REPORT); panel_window.refresh()
	for i in 3: await process_frame
	var expected := {"keeper_sleeps": "12회", "keeper_faints": "2회", "fatigue_failed": "7병", "aged_sold": "1,234병", "aged_revenue": "56,789 G"}
	for key in expected:
		var value: RichTextLabel = panel_window.statistics_values[key]
		check(value.source_text == expected[key], "Statistic %s = %s (%s)" % [key, expected[key], value.source_text])
		check(value.coin_count == (1 if key == "aged_revenue" else 0), "Only aged revenue carries a coin: " + key)
		check(value.get_content_width() <= value.size.x + 1, "Statistic %s fits without clipping" % key)
	panel_window.select_page(panel_window.OPERATION)
	if panel_window.rows.has("keeper_bed"): check(panel_window.rows.keeper_bed.icon.texture == ManagementArt.icon("keeper_sleep"), "Bed upgrade shows the sleeping keeper")
	# Engine captures for visual review.
	if DisplayServer.get_name() != "headless":
		root.always_on_top = false
		shop.state.aging.levels.open = 1
		for c in [["awake", 12.0, 0.4, "rested"], ["awake", 66.0, 0.4, "tired"], ["asleep", 30.0, 0.2, "asleep"], ["fainted", 100.0, 0.8, "fainted"]]:
			shop.state.keeper.state = c[0]; shop.state.keeper.fatigue = c[1]
			for mode in [State.WindowMode.WORKSHOP, State.WindowMode.COMPANION]:
				shop._set_window_mode(mode)
				shop._update_interface()
				gauges.refresh()
				shop.art.motion.elapsed = c[2]
				shop.art.queue_redraw()
				shop.companion.elapsed = c[2]
				shop.companion.refresh()
				shop.companion.scene.queue_redraw()
				await process_frame
				await process_frame
				await RenderingServer.frame_post_draw
				var name: String = ("workshop-" if mode == State.WindowMode.WORKSHOP else "companion-") + c[3]
				check(root.get_texture().get_image().save_png(FOLDER + name + ".png") == OK, "Captured " + name)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	M.write_json(FOLDER + "proof.json", {"checks": checks, "failures": failures, "passed": failures.is_empty(), "captured": DisplayServer.get_name() != "headless"})
	panel_window.free(); shop.free()
	print("F21 FATIGUE HUD %s %d checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)
