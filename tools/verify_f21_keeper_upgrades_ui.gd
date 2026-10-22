extends SceneTree
## F21 bed/herb-tea management rows and the aging/keeper recommendation path:
## locked/unlocked buttons, save-safe gateway with rollback, button purchase,
## recommendation purchase, stale-level refusal and read-only refreshes.
## Isolated preview; never reads or writes a player save.
const Shop = preload("res://scripts/shop.gd")
const State = preload("res://scripts/shop_state.gd")
const Upgrades = preload("res://scripts/shop_keeper_upgrades.gd")
const Aging = preload("res://scripts/shop_aging.gd")
const M = preload("res://tests/contracts_fixture.gd")
const Compare = preload("res://tests/state_compare.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func _initialize() -> void:
	set_meta("isolated_preview", true); call_deferred("run")
func fail_save() -> bool: return false
func ok_save() -> bool: return true
func show(panel: Object, page: int) -> void:
	panel.select_page(page); panel.refresh()
	for i in 3: await process_frame
func run() -> void:
	check(DisplayServer.get_name() == "headless", "Headless controls only")
	var shop := Shop.new(); root.add_child(shop)
	await process_frame
	shop.set_process(false); shop.art.set_process(false); shop.open_management()
	var panel = shop.management; panel.set_process(false)
	shop.state = State.new(); shop.state.gold = 1000000; shop.state.set_shop_open(false)
	await show(panel, panel.UPGRADES)
	var bed: Dictionary = panel.rows.keeper_bed
	var tea: Dictionary = panel.rows.keeper_tea
	check(bed.panel.visible and tea.panel.visible and bed.button.disabled and bed.button.text == "명성 %d 필요" % Upgrades.UNLOCK_REPUTATION and bed.button.icon != null, "Bed row locked by reputation with icon")
	check(bed.title.text == "침대 · 0/4단계" and tea.title.text == "허브차 선반 · 0/3단계", "Row titles show stages (%s / %s)" % [bed.title.text, tea.title.text])
	check(bed.panel.get_index() > panel.rows.aging_shelf.panel.get_index(), "Keeper rows follow the aging section")
	shop.state.progression.reputation = Upgrades.UNLOCK_REPUTATION
	await show(panel, panel.UPGRADES)
	check(not bed.button.disabled and bed.button.get_meta("next_level") == 1 and bed.button.text.contains("10,000"), "Unlocked bed buyable for 10,000 G (%s)" % bed.button.text)
	check(bed.summary.get_parsed_text() == "현재 수면 회복 −5 / 게임시 · 다음: 수면 회복 −6 / 게임시", "Bed summary shows current and next recovery (%s)" % bed.summary.get_parsed_text())
	check(tea.summary.get_parsed_text().ends_with("다음: 깨어 있는 동안 피로 증가 −10%"), "Tea summary shows the next cut (%s)" % tea.summary.get_parsed_text())
	check(bed.extra.text.begins_with("하루 피로(계속 조제 시) · 규칙적 +38/−40 상쾌 유지 · 바쁘게 +43/−30 누적"), "Daily fatigue line per policy (%s)" % bed.extra.text)
	# Failed save restores everything.
	shop.set_meta("keeper_save_fixture", fail_save)
	var before: Dictionary = M.data(shop.state)
	var failed: Dictionary = shop.perform_keeper_action("bed", 1)
	check(not failed.ok and failed.error.begins_with("저장 실패") and Compare.equivalent(before, M.data(shop.state)), "Failed save restores gold, spend and levels")
	shop.set_meta("keeper_save_fixture", ok_save)
	bed.button.button_down.emit(); bed.button.pressed.emit()
	await show(panel, panel.UPGRADES)
	check(shop.state.keeper.upgrades.levels.bed == 1 and shop.state.gold == 1000000 - 10000 and bed.title.text == "침대 · 1/4단계", "Panel button buys one bed stage")
	check(not shop.perform_keeper_action("bed", 1).ok and shop.state.keeper.upgrades.levels.bed == 1, "Stale stage purchase is refused")
	# Recommendation button path for keeper and aging keys.
	check(shop.state.set_keeper_policy("busy"), "Busy policy")
	await show(panel, panel.OPERATION)
	panel.recommend_pressed_action = "keeper:tea"; panel.recommend_pressed_next_level = 1
	panel._recommendation_selected()
	check(shop.state.keeper.upgrades.levels.tea == 1 and panel.recommend_feedback.is_empty(), "Recommendation buys tea through the gateway")
	panel.recommend_pressed_action = "keeper:tea"; panel.recommend_pressed_next_level = 1
	panel._recommendation_selected()
	check(shop.state.keeper.upgrades.levels.tea == 1 and panel.recommend_feedback == "투자 단계가 변경되었어요", "Stale recommendation shows feedback (%s)" % panel.recommend_feedback)
	shop.state.progression.reputation = Aging.UNLOCK_REPUTATION
	panel.recommend_pressed_action = "aging:open"; panel.recommend_pressed_next_level = 1
	panel._recommendation_selected()
	check(shop.state.aging.opened(), "Recommendation buys the aging rack")
	# Keeper operation row lists the daily balance; maxed rows show completion.
	await show(panel, panel.OPERATION)
	check(panel.rows.keeper.extra.text.contains("하루 피로(계속 조제 시)"), "Operation keeper row shows daily fatigue")
	for track in Upgrades.TRACKS:
		while shop.state.keeper.upgrades.view(shop.state, track).can_buy: shop.perform_keeper_action(track, int(shop.state.keeper.upgrades.levels[track]) + 1)
	await show(panel, panel.UPGRADES)
	check(bed.completed and bed.button.disabled and bed.button.text == "최대 단계" and tea.button.text == "최대 단계", "Maxed rows show completed")
	check(bed.extra.text.contains("철야 +34/−36 상쾌 유지"), "Full upgrades keep the allnighter rested (%s)" % bed.extra.text)
	before = M.data(shop.state)
	for page in panel.TAB_PAGES: panel.select_page(page); panel.refresh(); panel.refresh_gauges(0.016)
	panel.select_page(panel.OPERATION)
	check(Compare.equivalent(before, M.data(shop.state)), "Keeper upgrade rows never change the simulation")
	M.write_json("res://.verification/f21-keeper-upgrades-20261021/ui.json", {"checks": checks, "failures": failures, "passed": failures.is_empty(), "bed_extra": bed.extra.text})
	panel.free(); shop.free()
	print("F21 KEEPER UPGRADES UI %s %d checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)
