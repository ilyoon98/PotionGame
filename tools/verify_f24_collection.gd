extends SceneTree
## F24 collection record on the statistics page: per-category counts, the
## completion line, and read-only viewing. Isolated preview only.
const Shop = preload("res://scripts/shop.gd")
const State = preload("res://scripts/shop_state.gd")
const Status = preload("res://scripts/management_status.gd")
const Content = preload("res://scripts/shop_content.gd")
const Rare = preload("res://scripts/rare_recipes.gd")
const M = preload("res://tests/contracts_fixture.gd")
const Compare = preload("res://tests/state_compare.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func _initialize() -> void:
	set_meta("isolated_preview", true); call_deferred("run")
func counts(state: RefCounted) -> Dictionary:
	var result := {}
	for row in Status.collection(state): result[row.key] = [row.have, row.total]
	return result
## Everything the current content offers, owned.
func complete(state: RefCounted) -> void:
	var p: RefCounted = state.progression
	for row in Content.DATA.potions:
		if not row.get("owned_at_start", false) and not p.owned.has(row.id): p.owned.append(row.id)
	for row in Rare.ROWS:
		if not p.expansion.rare_discovered.has(row.id): p.expansion.rare_discovered.append(row.id)
		if not p.owned.has(row.id): p.owned.append(row.id)
	p.expedition_unlocked = true
	for region in Content.DATA.regions:
		if region.id == "forest_edge": p.expedition_count = int(region.complete_returns)
		else:
			if not p.expansion.regions.has(region.id): p.expansion.regions.append(region.id)
			p.expansion.returns[region.id] = int(region.complete_returns)
	for id in state.regulars.ids(): state.regulars.points[id] = 60
	state.decor.owned = ["decor_teacup", "decor_dried_vase"]
func run() -> void:
	check(get_meta("isolated_preview", false), "Isolated preview; no player save")
	var fresh := State.new()
	var c := counts(fresh)
	check(c.recipes == [0, 30] and c.specials == [0, 4] and c.regions == [0, 8] and c.souvenirs == [0, 4] and c.decor == [0, 2], "New game counts every category from zero (%s)" % str(c))
	check(not Status.collection_complete(fresh), "New game is not complete")
	var partial := State.new()
	partial.progression.owned.append("moon")
	partial.regulars.points["elf"] = 60
	partial.decor.owned = ["decor_teacup"]
	c = counts(partial)
	check(c.recipes == [1, 30] and c.souvenirs == [1, 4] and c.decor == [1, 2], "Counts follow owned recipes, received souvenirs and bought props")
	var done := State.new()
	complete(done)
	c = counts(done)
	check(c.recipes == [30, 30] and c.specials == [4, 4] and c.regions == [8, 8] and c.souvenirs == [4, 4] and c.decor == [2, 2], "A completed shop fills every category (%s)" % str(c))
	check(Status.collection_complete(done), "A completed shop is complete")
	var before: Dictionary = M.data(done)
	Status.collection(done); Status.collection_complete(done)
	check(Compare.equivalent(before, M.data(done)), "Counting never changes the model")
	# Statistics page.
	var shop := Shop.new(); root.add_child(shop)
	await process_frame
	shop.set_process(false); shop.art.set_process(false); shop.open_management()
	var panel = shop.management; panel.set_process(false)
	shop.state = partial
	panel.select_page(panel.REPORT); panel.refresh()
	for i in 3: await process_frame
	check(panel.collection_values.size() == 5 and panel.collection_values.recipes.text == "1 / 30" and panel.collection_values.decor.text == "1 / 2", "Collection rows show have / total")
	check(not panel.collection_done.visible, "Completion line hidden while incomplete")
	check(panel.pages[panel.REPORT].find_children("*", "Button", true, false).is_empty(), "Statistics page stays free of buttons")
	shop.state = done
	var viewed: Dictionary = M.data(shop.state)
	panel.refresh()
	await process_frame
	check(panel.collection_values.regions.text == "8 / 8 · 완료" and panel.collection_done.visible and panel.collection_done.is_visible_in_tree(), "A complete shop shows every row done and the completion line")
	check(Compare.equivalent(viewed, M.data(shop.state)), "Viewing the record never changes the model")
	var result := {"checks": checks, "failures": failures, "passed": failures.is_empty()}
	M.write_json("res://.verification/f24-collection-20261105/collection.json", result)
	print("F24 COLLECTION %s %d checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)
