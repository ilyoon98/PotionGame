extends SceneTree
## F22 regulars: points per completed sale (1 ordinary / 3 preferred), stages,
## stories and souvenirs, economy independence, frame independence, report lines,
## saves and v15 migration, and the statistics-page cards. Isolated preview only;
## never reads a player save.
const Shop = preload("res://scripts/shop.gd")
const State = preload("res://scripts/shop_state.gd")
const Regulars = preload("res://scripts/shop_regulars.gd")
const Catalog = preload("res://scripts/pixel_art_catalog.gd")
const M = preload("res://tests/contracts_fixture.gd")
const Compare = preload("res://tests/state_compare.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func _initialize() -> void:
	set_meta("isolated_preview", true); call_deferred("run")
func total_points(state: RefCounted) -> int:
	var sum := 0
	for id in Regulars.ids(): sum += state.regulars.points_of(id)
	return sum
func without_regulars(state: RefCounted) -> Dictionary:
	var data: Dictionary = M.data(state); data.erase("regulars"); return data
func run() -> void:
	check(get_meta("isolated_preview", false), "Isolated preview; no player save")
	check(Regulars.ids() == ["traveler", "mage", "elf", "rogue"], "Current four customers, no knight")
	# Stage thresholds.
	var expected := {0: 0, 1: 1, 149: 1, 150: 2, 2499: 2, 2500: 3, 6999: 3, 7000: 4, 100000: 4}
	for value in expected: check(Regulars.stage_for(value) == expected[value], "Stage of %d points is %d" % [value, expected[value]])
	# Recording.
	var r := Regulars.new()
	var first := r.record("traveler", false)
	check(r.points_of("traveler") == 1 and first.get("stage") == 1 and first.get("souvenir") == "", "First ordinary sale: 1 point, stage 1 event")
	check(r.record("traveler", false).is_empty(), "No event without a stage change")
	r.record("mage", true)
	check(r.points_of("mage") == 3, "Preferred sale adds 3 points")
	check(r.record("knight", true).is_empty() and not r.points.has("knight"), "Retired knight slot is ignored")
	r.points["elf"] = 2499
	var souvenir := r.record("elf", false)
	check(souvenir.get("stage") == 3 and souvenir.get("souvenir") == "souvenir_leaf_brooch" and r.has_souvenir("elf"), "2,500 points give the elf souvenir")
	check(r.souvenirs() == ["souvenir_leaf_brooch"], "Souvenir list follows stage")
	check(r.lines("elf").size() == 3 and r.lines("elf")[2].contains("잎사귀 브로치"), "Stage 3 shows intro, story and souvenir line")
	r.points["rogue"] = 7000
	check(r.lines("rogue").size() == 4 and r.next_threshold("rogue") == 0 and r.view("rogue").fraction == 1.0, "Stage 4 is the last stage")
	r.points["rogue"] = Regulars.MAX_POINTS; r.record("rogue", true)
	check(r.points_of("rogue") == Regulars.MAX_POINTS, "Points are capped")
	# "New" means reached during the current report period.
	check(r.is_new("elf") and r.view("elf").new, "Stages above the period baseline are new")
	r.start_report()
	check(not r.is_new("elf") and not r.is_new("traveler"), "A new period clears the new marks")
	# Actual sales through the economy.
	var live := State.new(); live.gold = 100000
	var before_sold: int = live.progression.totals.sold
	var regular_events := 0
	for i in 900:
		var result: Dictionary = live.advance(1.0)
		regular_events += result.get("regular_events", []).size()
	var sold: int = live.progression.totals.sold - before_sold
	check(sold > 0 and total_points(live) == sold + 2 * int(live.progression.totals.preferred), "Points = ordinary sales + 3 x preferred sales (%d sold)" % sold)
	check(regular_events > 0, "Stage events are returned from advance")
	var visits := 0
	for id in live.progression.by_customer: visits += int(live.progression.by_customer[id])
	check(visits >= sold, "Visits are counted separately from sales")
	# Economy independence: a full record changes nothing else.
	var plain := State.new(); var rich := State.new()
	for id in Regulars.ids(): rich.regulars.points[id] = 6999
	plain.advance(1200.0); rich.advance(1200.0)
	check(Compare.equivalent(without_regulars(plain), without_regulars(rich)), "Regulars never change the economy")
	# Frame independence.
	var coarse := State.new(); var fine := State.new()
	coarse.advance(601.0)
	for i in 601: fine.advance(1.0)
	check(coarse.regulars.points == fine.regulars.points, "601 s at once equals 601 x 1 s")
	# Report period.
	var report := State.new()
	report.start_report_period()
	check(not report.report_text().contains("단골 ·"), "No regular lines before a stage change")
	report.regulars.points["traveler"] = 2499; report.regulars.record("traveler", false)
	var text: String = report.report_text()
	check(text.contains("단골 · 여행자 단골") and text.contains("기념품 낡은 나침반"), "Report shows the stage and souvenir")
	report.start_report_period()
	check(not report.report_text().contains("단골 ·"), "A new period starts from the current stages")
	# Saves.
	var saved := State.new()
	saved.regulars.points = {"traveler": 2501, "mage": 151}; saved.regulars.report_stages = {"mage": 1}
	var restored := State.new()
	check(restored.load_data(M.data(saved)) and Compare.equivalent(M.data(saved), M.data(restored)), "Roundtrip keeps points and report stages")
	check(M.data(saved).version == State.SAVE_VERSION and State.SAVE_VERSION >= 16, "Saves as the current version (v16 or later)")
	var base: Dictionary = M.data(saved)
	var bad_cases := [
		func(d): d.regulars.points.traveler = -1,
		func(d): d.regulars.points.traveler = 1.5,
		func(d): d.regulars.points["knight"] = 3,
		func(d): d.regulars.points["traveler"] = Regulars.MAX_POINTS + 1,
		func(d): d.regulars.report_stages.traveler = 4,
		func(d): d.regulars.report_stages["elf"] = 1,
		func(d): d.regulars.version = 2,
		func(d): d.regulars = [],
		func(d): d.erase("regulars"),
	]
	for i in bad_cases.size():
		var broken: Dictionary = base.duplicate(true); bad_cases[i].call(broken)
		var target := State.new(); check(target.load_data(base), "Load base"); var before: Dictionary = M.data(target)
		check(not target.load_data(broken) and Compare.equivalent(before, M.data(target)), "Reject invalid regulars case %d atomically" % i)
	var legacy: Dictionary = M.data(State.new()); legacy.version = 15; legacy.erase("regulars")
	legacy.progression.by_customer = {"traveler": 40}
	var migrated := State.new()
	check(migrated.load_data(legacy) and total_points(migrated) == 0 and migrated.to_data().version == State.SAVE_VERSION, "v15 save starts at zero; visits are not converted to sales")
	# Statistics page cards.
	var shop := Shop.new(); root.add_child(shop)
	await process_frame
	shop.set_process(false); shop.art.set_process(false); shop.open_management()
	var panel = shop.management; panel.set_process(false)
	shop.state = State.new(); shop.state.set_shop_open(false)
	shop.state.regulars.points = {"traveler": 2500, "mage": 150, "elf": 1}
	panel.select_page(panel.OPERATION); panel.refresh()
	await process_frame
	check(panel.regular_dot.visible, "Statistics button shows a dot for new stages")
	var state_before: Dictionary = M.data(shop.state)
	panel.select_page(panel.REPORT); panel.refresh()
	for i in 3: await process_frame
	check(panel.regular_cards.size() == 4, "Four regular cards")
	var traveler: Dictionary = panel.regular_cards.traveler
	check(traveler.panel.is_visible_in_tree() and traveler.title.text == "여행자 · 단골" and traveler.badge.visible, "Traveler card shows stage and new badge")
	shop.state.regulars.points.mage = 7000
	panel.refresh()
	check(panel.regular_cards.mage.title.text == "여마법사 · 믿고 찾는 손님 ★", "Last stage shows the record mark")
	shop.state.regulars.points.mage = 150
	panel.refresh()
	check(traveler.story.text.contains("낡은 나침반") and traveler.progress.text.contains("2500 / 7000"), "Traveler card shows souvenir and progress")
	check(panel.regular_cards.mage.habits.text == "방문 0회 · 선호 마나 물약", "Mage habits include mana, owned from the start")
	check(traveler.habits.text == "방문 0회 · 선호 체력 물약" and panel.regular_cards.elf.habits.text == "방문 0회 · 선호 물약을 아직 갖추지 않았어요", "Habits show visits and owned preferred potions only")
	shop.state.progression.owned.append("purify"); shop.state.progression.by_customer["elf"] = 7
	panel.refresh()
	check(panel.regular_cards.elf.habits.text == "방문 7회 · 선호 정화 물약", "Owned recipe appears in elf habits")
	shop.state.progression.owned.erase("purify"); shop.state.progression.by_customer.erase("elf")
	check(not panel.regular_cards.rogue.badge.visible and panel.regular_cards.rogue.story.text == "아직 거래 기록이 없어요.", "Rogue without sales has no badge")
	panel.select_page(panel.OPERATION); panel.refresh()
	await process_frame
	check(not panel.regular_dot.visible, "Dot clears after reading")
	check(Compare.equivalent(state_before, M.data(shop.state)), "Viewing statistics never changes the model")
	shop.state.regulars.record("rogue", false)
	panel.refresh()
	await process_frame
	check(panel.regular_dot.visible, "A stage reached after viewing shows the dot again")
	for id in panel.regular_cards:
		var portrait: TextureRect = panel.regular_cards[id].portrait
		check(portrait.texture != null and portrait.texture.get_size() == Vector2(32, 48), "%s portrait is the approved 32x48 idle frame" % id)
		# Approved souvenir (2026-10-23): shown at native 1x only from the souvenir stage.
		var icon: TextureRect = panel.regular_cards[id].souvenir
		var souvenir_id: String = Regulars.STORIES[id].souvenir
		check(icon.texture != null and icon.texture.get_size() == Vector2(32, 32) and icon.custom_minimum_size == Vector2(32, 32), "%s souvenir is 32x32 at 1x" % id)
		check(icon.visible == shop.state.regulars.has_souvenir(id), "%s souvenir visible only from the souvenir stage" % id)
		check(Catalog.DATA.souvenirs[souvenir_id] == "res://assets/pixel_v1/souvenirs/%s.png" % souvenir_id, "%s souvenir is in the catalog" % id)
		var approved := Image.load_from_file(ProjectSettings.globalize_path("res://art/mockups/f22-regulars-souvenirs-v1/sprites/%s.png" % souvenir_id))
		var published: Image = icon.texture.get_image()
		approved.convert(Image.FORMAT_RGBA8); published.convert(Image.FORMAT_RGBA8)
		check(approved.get_data() == published.get_data(), "%s published pixels equal the approved sprite" % id)
	# Engine capture of the statistics page for visual review (rendering driver only).
	var captured := false
	if DisplayServer.get_name() != "headless":
		shop.state.regulars.points = {"traveler": 7100, "mage": 2510, "elf": 160, "rogue": 0}
		shop.state.regulars.report_stages = {"traveler": 3}
		panel.select_page(panel.REPORT); panel.refresh()
		for i in 3: await process_frame
		panel.scroll.scroll_vertical = int(panel.scroll.get_v_scroll_bar().max_value)
		for i in 3: await process_frame
		await RenderingServer.frame_post_draw
		for id in panel.regular_cards:
			var story: Label = panel.regular_cards[id].story
			check(story.get_line_count() <= 8 and story.size.x <= panel.CONTENT_WIDTH, "%s story wraps inside the card" % id)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.verification/f22-regulars-20261022/"))
		captured = panel.get_texture().get_image().save_png("res://.verification/f22-regulars-20261022/statistics-regulars.png") == OK
		check(captured, "Captured the statistics page")
	var result := {"checks": checks, "failures": failures, "passed": failures.is_empty(), "sold_900s": sold, "points_900s": total_points(live), "captured": captured}
	M.write_json("res://.verification/f22-regulars-20261022/regulars.json", result)
	print("F22 REGULARS %s %d checks sold=%d points=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, sold, total_points(live)])
	quit(0 if failures.is_empty() else 1)
