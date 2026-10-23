extends SceneTree
## F23 counter props: buy once (never auto-equipped), free equip/swap/remove,
## failed-save rollback, saves and v16 migration, economy independence, the
## approved layout-A draw command, management rows, and (with a rendering driver)
## workshop captures. Isolated preview only; never reads a player save.
const Shop = preload("res://scripts/shop.gd")
const State = preload("res://scripts/shop_state.gd")
const Decor = preload("res://scripts/shop_decor.gd")
const Catalog = preload("res://scripts/pixel_art_catalog.gd")
const ManagementArt = preload("res://scripts/management_art.gd")
const M = preload("res://tests/contracts_fixture.gd")
const Compare = preload("res://tests/state_compare.gd")
const FOLDER := "res://.verification/f23-decor-20261023/"
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func _initialize() -> void:
	set_meta("isolated_preview", true); call_deferred("run")
func fail_save() -> bool: return false
func freeze(node: Node) -> void:
	node.set_process(false)
	for child in node.get_children(): freeze(child)
func role(commands: Array[Dictionary], name: String) -> int:
	for i in commands.size():
		if commands[i].role == name: return i
	return -1
func without_decor(state: RefCounted) -> Dictionary:
	var data: Dictionary = M.data(state); data.erase("decor"); return data
func run() -> void:
	check(get_meta("isolated_preview", false), "Isolated preview; no player save")
	# Model.
	var s := State.new(); s.gold = 1000
	check(not s.decor.act(s, "nonexistent").ok, "Unknown decoration is refused")
	var bought: Dictionary = s.decor.act(s, "decor_teacup")
	check(bought.ok and bought.action == "bought" and s.gold == 880 and s.progression.totals.manual_spent == 120, "Teacup costs 120 G once and counts as direct spending")
	check(s.decor.owns("decor_teacup") and s.decor.counter_prop().is_empty(), "Buying never equips automatically")
	check(s.decor.view(s, "decor_teacup").action == "장착", "Owned teacup offers equip")
	check(s.decor.act(s, "decor_teacup").action == "equipped" and s.decor.counter_prop() == "decor_teacup" and s.gold == 880, "Equipping is free")
	check(s.decor.act(s, "decor_dried_vase").action == "bought" and s.gold == 640 and s.decor.counter_prop() == "decor_teacup", "Buying the vase keeps the equipped teacup")
	check(s.decor.act(s, "decor_dried_vase").action == "equipped" and s.decor.counter_prop() == "decor_dried_vase" and s.decor.owns("decor_teacup"), "Swapping keeps ownership of the old prop")
	check(s.decor.act(s, "decor_dried_vase").action == "removed" and s.decor.counter_prop().is_empty() and s.gold == 640, "Removing is free and empties the slot")
	var poor := State.new(); poor.gold = 100
	check(not poor.decor.act(poor, "decor_teacup").ok and poor.gold == 100 and poor.decor.view(poor, "decor_teacup").reason == "20 G 부족", "Not enough gold is refused without charging")
	# Economy independence: an equipped prop changes nothing else.
	var plain := State.new(); var decorated := State.new()
	decorated.decor.owned = ["decor_teacup"]; decorated.decor.equipped = {"counter": "decor_teacup"}
	plain.advance(900.0); decorated.advance(900.0)
	check(Compare.equivalent(without_decor(plain), without_decor(decorated)), "Decoration never changes the economy")
	# Saves.
	s.decor.act(s, "decor_teacup")
	var restored := State.new()
	check(restored.load_data(M.data(s)) and Compare.equivalent(M.data(s), M.data(restored)) and restored.decor.counter_prop() == "decor_teacup", "Roundtrip keeps ownership and the equipped prop")
	check(M.data(s).version == State.SAVE_VERSION and State.SAVE_VERSION == 17, "Saves as v17")
	var base: Dictionary = M.data(s)
	var bad_cases := [
		func(d): d.decor.owned.append("decor_teacup"),
		func(d): d.decor.owned.append("decor_unknown"),
		func(d): d.decor.owned = ["decor_dried_vase"],
		func(d): d.decor.equipped = {},
		func(d): d.decor.equipped.counter = 3,
		func(d): d.decor.version = 2,
		func(d): d.decor = [],
		func(d): d.erase("decor"),
	]
	for i in bad_cases.size():
		var broken: Dictionary = base.duplicate(true); bad_cases[i].call(broken)
		var target := State.new(); check(target.load_data(base), "Load base"); var before: Dictionary = M.data(target)
		check(not target.load_data(broken) and Compare.equivalent(before, M.data(target)), "Reject invalid decor case %d atomically" % i)
	var legacy: Dictionary = M.data(State.new()); legacy.version = 16; legacy.erase("decor")
	var migrated := State.new()
	check(migrated.load_data(legacy) and migrated.decor.owned.is_empty() and migrated.decor.counter_prop().is_empty() and migrated.to_data().version == 17, "v16 save starts with no decoration")
	# Shop gateway and workshop drawing.
	var shop := Shop.new(); root.add_child(shop)
	await process_frame
	freeze(shop)
	shop.state = State.new(); shop.state.gold = 1000
	shop.set_meta("decor_save_fixture", fail_save)
	var before_fail: Dictionary = M.data(shop.state)
	check(not shop.perform_decor_action("decor_teacup").ok and Compare.equivalent(before_fail, M.data(shop.state)), "Failed save restores gold, spending and ownership")
	shop.remove_meta("decor_save_fixture")
	check(shop.perform_decor_action("decor_teacup").ok and shop.perform_decor_action("decor_teacup").ok and shop.state.decor.counter_prop() == "decor_teacup", "Shop buys then equips through the save gateway")
	shop._set_window_mode(State.WindowMode.WORKSHOP)
	shop._update_interface()
	var commands: Array[Dictionary] = shop.art.render_commands()
	var prop := role(commands, "counter_prop")
	check(prop >= 0 and commands[prop].rect == Rect2(288, 120, 96, 96), "Equipped prop draws at approved layout A (288,120) at 3x")
	check(prop > role(commands, "counter") and (role(commands, "shelf") < 0 or prop < role(commands, "shelf")), "Prop sits on the counter, behind stock, shelf and people")
	var approved := Image.load_from_file(ProjectSettings.globalize_path("res://art/mockups/f23-decor-v1/sprites/decor_teacup.png"))
	var published: Image = commands[prop].texture.get_image()
	approved.convert(Image.FORMAT_RGBA8); published.convert(Image.FORMAT_RGBA8)
	check(approved.get_data() == published.get_data(), "Published teacup pixels equal the approved sprite")
	check(Catalog.DATA.decor.decor_dried_vase == "res://assets/pixel_v1/decor/decor_dried_vase.png", "Vase is in the catalog")
	shop.perform_decor_action("decor_teacup")
	shop._update_interface()
	check(role(shop.art.render_commands(), "counter_prop") < 0, "Removed prop is not drawn")
	# Management rows.
	shop.open_management()
	var panel = shop.management; panel.set_process(false)
	shop.state.gold = 1000
	panel.select_page(panel.UPGRADES); panel.refresh()
	for i in 3: await process_frame
	var vase: Dictionary = panel.rows.decor_dried_vase
	var teacup: Dictionary = panel.rows.decor_teacup
	check(vase.panel.is_visible_in_tree() and vase.title.text == "말린 꽃병" and vase.button.text.contains("구매") and vase.button.text.contains("240") and not vase.button.disabled, "Unowned vase offers purchase for 240 G")
	check(teacup.button.text == "장착" and teacup.detail.text.contains("소장"), "Owned teacup offers equip")
	vase.button.pressed.emit()
	check(shop.state.decor.owns("decor_dried_vase") and shop.state.decor.counter_prop().is_empty() and vase.button.text == "장착", "Row purchase buys without equipping")
	vase.button.pressed.emit()
	check(shop.state.decor.counter_prop() == "decor_dried_vase" and vase.button.text == "해제" and vase.detail.text == "판매대에 놓여 있어요", "Row equips the vase")
	for id in ["decor_teacup", "decor_dried_vase"]:
		var icon: Texture2D = ManagementArt.icon(id)
		check(icon != null and icon.get_size() == Vector2(16, 16), "%s list icon is a 16x16 crop (3x in the 48px slot)" % id)
	check(not shop.companion.get_script().source_code.contains("counter_prop"), "Character mode does not draw counter props")
	# Engine captures for visual review (rendering driver only).
	var captured := 0
	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
		root.always_on_top = false
		panel.hide()
		for id in ["decor_teacup", "decor_dried_vase"]:
			shop.state.decor.equipped.counter = id
			shop._update_interface()
			shop.art.queue_redraw()
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			if root.get_texture().get_image().save_png(FOLDER + "workshop-%s.png" % id) == OK: captured += 1
		check(captured == 2, "Captured the workshop with each prop")
	M.write_json(FOLDER + "decor.json", {"checks": checks, "failures": failures, "passed": failures.is_empty(), "captured": captured})
	print("F23 DECOR %s %d checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)
