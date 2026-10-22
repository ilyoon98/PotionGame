extends SceneTree
## F21 keeper management row: fatigue gauge, sleep/faint text, locked and
## unlocked policy button, and read-only gauge refreshes. Isolated preview only.
const Shop = preload("res://scripts/shop.gd")
const State = preload("res://scripts/shop_state.gd")
const Keeper = preload("res://scripts/shop_keeper.gd")
const M = preload("res://tests/contracts_fixture.gd")
const Compare = preload("res://tests/state_compare.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func _initialize() -> void:
	set_meta("isolated_preview", true); call_deferred("run")
func show(panel: Object) -> void:
	panel.select_page(panel.OPERATION); panel.refresh()
	for i in 3: await process_frame
func run() -> void:
	check(DisplayServer.get_name() == "headless", "Headless controls only")
	var shop := Shop.new(); root.add_child(shop)
	await process_frame
	shop.set_process(false); shop.art.set_process(false); shop.open_management()
	var panel = shop.management; panel.set_process(false)
	shop.state = State.new(); shop.state.gold = 5000
	shop.state.advance(10.0)
	await show(panel)
	var row: Dictionary = panel.rows.keeper
	check(row.panel.visible and row.title.text == "주인공 · 규칙적", "Keeper row shows the regular policy")
	check(row.detail.text.begins_with("깨어 있음 · 22시 취침") and row.work.box.visible and row.work.caption.text == "피로", "Awake text and fatigue gauge")
	check(row.summary.get_parsed_text() == "컨디션 상쾌 · 제조 속도 +30%", "Rested summary shows the brewing bonus (%s)" % row.summary.get_parsed_text())
	check(row.button.disabled and row.button.text == "명성 %d 필요" % Keeper.POLICY_REPUTATION and row.button.icon != null, "Policy button locked with reputation reason and icon")
	var before: Dictionary = M.data(shop.state)
	panel._cycle_keeper_policy()
	check(Compare.equivalent(before, M.data(shop.state)), "Locked policy click changes nothing")
	# Unlock and cycle: regular -> busy -> allnighter -> regular.
	shop.state.progression.reputation = Keeper.POLICY_REPUTATION
	await show(panel)
	check(not row.button.disabled, "Policy button enabled at reputation %d" % Keeper.POLICY_REPUTATION)
	var seen: Array[String] = []
	for i in 3:
		panel._cycle_keeper_policy()
		await show(panel)
		seen.append(shop.state.keeper.policy)
	check(seen == ["busy", "allnighter", "regular"], "Policy cycles busy -> allnighter -> regular (%s)" % str(seen))
	check(row.title.text == "주인공 · 규칙적", "Title follows the selected policy")
	# Asleep text and paused craft status.
	shop.state.advance(110.0)
	await show(panel)
	check(shop.state.keeper.state == "asleep" and row.detail.text.begins_with("수면 중 · 6시 기상"), "Asleep text with wake hour")
	check(panel.rows.craft.detail.text.begins_with("수면 중"), "Craft row says the keeper is asleep")
	# Penalty summary appears in the tired band.
	shop.state.keeper.fatigue = 65.0
	await show(panel)
	check(row.summary.get_parsed_text().contains("컨디션 피곤") and row.summary.get_parsed_text().contains("성공률 −10%p"), "Tired summary shows the 10%%p cut (%s)" % row.summary.get_parsed_text())
	# Fainted text.
	shop.state.keeper._fall_asleep(shop.state.progression.clock, "fainted")
	await show(panel)
	check(row.detail.text.begins_with("기절 · 회복까지") and panel.rows.craft.detail.text.begins_with("기절"), "Fainted text on keeper and craft rows")
	# Workshop cauldron caption box is 66px at the real body font.
	for text in ["수면 중", "기절", "보관 가득"]:
		var width: float = shop.body_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		check(width <= 66.0, "Workshop caption '%s' fits 66px (%.1fpx)" % [text, width])
	# Gauge refreshes and navigation are read-only.
	before = M.data(shop.state)
	for page in panel.TAB_PAGES: panel.select_page(page); panel.refresh_gauges(0.016)
	panel.select_page(panel.OPERATION)
	check(Compare.equivalent(before, M.data(shop.state)), "Keeper row refreshes never change the simulation")
	M.write_json("res://.verification/f21-keeper-20261021/ui.json", {"checks": checks, "failures": failures, "passed": failures.is_empty(), "detail": row.detail.text, "title": row.title.text})
	panel.free(); shop.free()
	print("F21 KEEPER UI %s %d checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)
