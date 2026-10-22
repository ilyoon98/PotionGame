extends SceneTree
## Exercise the real mode buttons; never inject OS input or touch player saves.
const Shop = preload("res://scripts/shop.gd")
const Compare = preload("res://tests/state_compare.gd")
var shop: Control

func _initialize() -> void:
	assert(DisplayServer.get_name() == "headless", "This check must never open a desktop game window")
	set_meta("isolated_preview", true)
	call_deferred("_run")

func progress() -> Dictionary:
	var data: Dictionary = shop.state.to_data().duplicate(true)
	data.erase("window_mode")
	data.erase("mini_mode")
	return data

func check_stage(mode: int) -> bool:
	var expected: Vector2i = Vector2i(540, 300) if mode == shop.State.WindowMode.WORKSHOP else Vector2i(256, 172) if mode == shop.State.WindowMode.COMPANION else Vector2i(320, 124) if mode == shop.State.WindowMode.MINIMAL else Vector2i(440, 704)
	return shop.state.window_mode == mode \
		and root.size == expected \
		and (DisplayServer.get_name() == "headless" or (root.always_on_top and root.mode != Window.MODE_MINIMIZED)) \
		and shop.companion.visible == (mode == shop.State.WindowMode.COMPANION) \
		and shop.minimal_hud.visible == (mode == shop.State.WindowMode.MINIMAL) \
		and shop.art.visible == (mode in [shop.State.WindowMode.WORKSHOP, shop.State.WindowMode.FULL]) \
		and not shop.desktop_input.enabled

func _run() -> void:
	shop = Shop.new()
	root.add_child(shop)
	shop.set_process(false)
	shop.state.gold = 25458
	shop.state.advance(1.7)
	shop._update_interface()
	for main_mode in [shop.State.WindowMode.WORKSHOP, shop.State.WindowMode.FULL]:
		shop._set_window_mode(main_mode)
		var baseline := progress()
		for repeat in 4:
			var shrink: Button = shop.workshop_minimize if main_mode == shop.State.WindowMode.WORKSHOP else shop.minimize_button
			shrink.pressed.emit()
			assert(check_stage(shop.State.WindowMode.COMPANION))
			shop.companion.minimize_button.pressed.emit()
			assert(check_stage(shop.State.WindowMode.MINIMAL))
			assert(shop.mini_toolbar.position.y == shop.MINIMAL_SIZE.y - shop.WorkshopAssets.BAR_HEIGHT, "Information controls stay at the bottom")
			shop.mini_toolbar.get_node("RestoreButton").pressed.emit()
			assert(check_stage(shop.State.WindowMode.COMPANION))
			shop.companion.restore_button.pressed.emit()
			assert(check_stage(main_mode))
			assert(Compare.equivalent(baseline, progress()), "Mode changes cannot reset ingredients, income, manufacture, inventory, journey fees or RNG")
		# A direct management shortcut still expands in the same two stages.
		shop.open_management()
		shop.management.find_child("InformationOnlyButton", true, false).pressed.emit()
		assert(check_stage(shop.State.WindowMode.MINIMAL))
		assert(not shop.management.visible)
		var snapshot: Dictionary = JSON.parse_string(JSON.stringify(shop.state.to_data()))
		var resumed: RefCounted = shop.State.new()
		assert(resumed.load_data(snapshot) and resumed.main_window_mode == main_mode)
		shop.state = resumed
		shop._apply_window_mode()
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		shop._unhandled_key_input(escape)
		assert(check_stage(shop.State.WindowMode.COMPANION))
		shop._unhandled_key_input(escape)
		assert(check_stage(main_mode))
		assert(Compare.equivalent(baseline, progress()))
	# Loading an older save without a return field remains supported.
	var old: Dictionary = shop.state.to_data().duplicate(true)
	old.window_mode = shop.State.WindowMode.MINIMAL
	old.erase("main_window_mode")
	var legacy: RefCounted = shop.State.new()
	assert(legacy.load_data(old) and legacy.main_window_mode == shop.State.WindowMode.WORKSHOP)
	var before: Dictionary = legacy.to_data().duplicate(true)
	for bad in [shop.State.WindowMode.MINIMAL, shop.State.WindowMode.SMALL, 1.5, "FULL"]:
		var invalid := old.duplicate(true)
		invalid.main_window_mode = bad
		assert(not legacy.load_data(invalid) and Compare.equivalent(before, legacy.to_data()), "Invalid return mode must be rejected atomically")
	# All move/expand/shrink icons share the same sizes, style and asset factory.
	var controls := [shop.workshop_move, shop.workshop_minimize, shop.companion.move_button, shop.companion.minimize_button, shop.companion.restore_button, shop.mini_toolbar.get_node("MoveButton"), shop.mini_toolbar.get_node("RestoreButton")]
	for control in controls:
		assert(control.size == Vector2(28, 32) and control.text.is_empty())
		assert(control.get_theme_constant("icon_max_width") == 18)
		assert(control.get_theme_stylebox("normal").bg_color == controls[0].get_theme_stylebox("normal").bg_color)
	assert(shop.companion.restore_button.icon.resource_path == shop.mini_toolbar.get_node("RestoreButton").icon.resource_path)
	assert(await verify_toolbar_slots())
	shop._set_window_mode(shop.State.WindowMode.WORKSHOP)
	shop._show_companion_view()
	shop.companion.minimize_button.pressed.emit()
	var clock: float = shop.state.progression.clock
	shop._advance_game(3.0)
	shop._update_interface()
	assert(shop.state.progression.clock > clock + 2.9 and not shop.minimal_brew.text.is_empty())
	if "--render" in OS.get_cmdline_user_args(): await render()
	print("THREE STAGE MODES PASS: 540x300/256x172/320x124 flow + 440x704 indoor/save/economy; fixed control spacing, no map control, poster/tab access; management reuse across three toolbars, deferred raise/coalescing, hidden-close cancellation, close/reopen before callback, retained selection/details/scroll/login/economy/RNG; headless only, native minimize/foreground/focus untested")
	quit()

func verify_toolbar_slots() -> bool:
	var reference: Control = shop.workshop_toolbar
	var original: Dictionary = progress()
	var original_mode: int = shop.state.window_mode
	for mode in [shop.State.WindowMode.WORKSHOP, shop.State.WindowMode.COMPANION, shop.State.WindowMode.MINIMAL]:
		shop._set_window_mode(mode)
		await process_frame
		await process_frame
		var toolbar: Control = shop.workshop_toolbar if mode == shop.State.WindowMode.WORKSHOP else shop.companion.toolbar if mode == shop.State.WindowMode.COMPANION else shop.mini_toolbar
		var height := 44.0 if mode == shop.State.WindowMode.COMPANION else 52.0
		var padding := 6.0 if mode == shop.State.WindowMode.COMPANION else 10.0
		assert(toolbar.size.y == height)
		assert(toolbar.position.y == (128.0 if mode == shop.State.WindowMode.COMPANION else 248.0 if mode == shop.State.WindowMode.WORKSHOP else 72.0))
		assert(toolbar.find_child("ExpeditionMapButton", true, false) == null)
		var previous_end := 0.0
		for name in ["MoveButton", "ManageButton", "MinimizeButton", "RestoreButton", "CloseButton"]:
			var button: Button = toolbar.get_node(name)
			var standard: Button = reference.get_node(name)
			if not button.visible or button.size != standard.size or button.position.x < previous_end or not Rect2(Vector2.ZERO, toolbar.size).encloses(button.get_rect()):
				print("TOOLBAR SLOT FAILURE ", mode, "/", name, " rect=", button.get_rect())
				return false
			previous_end = button.get_rect().end.x
			assert(button.size == Vector2(42 if name == "ManageButton" else 28, 32))
			assert(button.position.y == padding and toolbar.size.y - button.get_rect().end.y == padding, "The taller bar leaves equal space above and below every control")
			if name == "ManageButton":
				assert(button.get_theme_font_size("font_size") == 13)
				assert(button.get_theme_font("font").get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x <= button.size.x)
			if name != "MoveButton": assert(is_equal_approx(toolbar.size.x - button.position.x, reference.size.x - standard.position.x))
			if name != "ManageButton": assert(button.icon.resource_path == standard.icon.resource_path)
			assert(button.get_theme_stylebox("normal").bg_color == standard.get_theme_stylebox("normal").bg_color)
		assert(toolbar.get_node("MinimizeButton").disabled == (mode == shop.State.WindowMode.MINIMAL))
		assert(toolbar.get_node("RestoreButton").disabled == (mode == shop.State.WindowMode.WORKSHOP))
		# Inactive buttons retain their slots and cannot trigger a second mode transition.
		var before: Dictionary = shop.state.to_data().duplicate(true)
		if mode == shop.State.WindowMode.MINIMAL: toolbar.get_node("MinimizeButton").pressed.emit()
		if mode == shop.State.WindowMode.WORKSHOP: toolbar.get_node("RestoreButton").pressed.emit()
		assert(Compare.equivalent(before, shop.state.to_data()))
		assert(toolbar.get_node("CloseButton").pressed.is_connected(shop._close_shop))
		assert(toolbar.get_node("ManageButton").pressed.is_connected(shop.open_management))
	assert(shop.companion.gold.get_rect().end.x <= shop.companion.manage_button.position.x)
	for property in shop.get_property_list(): assert(property.name != "map_button", "The removed map does not retain a hidden control or backing property")
	assert(shop.find_child("ExpeditionMapButton", true, false) == null)
	assert(shop.workshop_gold.get_theme_font_size("font_size") == 17)
	assert(shop.minimal_gold.get_theme_font_size("normal_font_size") == 22)
	assert(shop.minimal_income.get_theme_font_size("normal_font_size") == 14 and shop.minimal_brew.get_theme_font_size("font_size") == 14)
	assert(shop.companion.gold.get_theme_font_size("font_size") == 15)
	# Removing the bottom map leaves the actual poster shortcut and management
	# expedition tab available; neither is a purchase or journey reservation.
	shop._set_window_mode(shop.State.WindowMode.WORKSHOP)
	var before_entry: Dictionary = progress()
	shop.workshop_gauges.detail_buttons.expeditions.pressed.emit()
	assert(shop.management.visible and shop.management.selected == shop.ManagementPanel.EXPEDITIONS)
	assert(Compare.equivalent(before_entry, progress()))
	shop.management.tabs[shop.ManagementPanel.OPERATION].pressed.emit()
	shop.management.tabs[shop.ManagementPanel.EXPEDITIONS].pressed.emit()
	assert(shop.management.selected == shop.ManagementPanel.EXPEDITIONS and Compare.equivalent(before_entry, progress()))
	# Every toolbar reopens and reuses management, including deferred raising.
	# Headless cannot represent native minimizing, occlusion, Z order or focus.
	var existing_management: Window = shop.management
	var detail: Dictionary = existing_management.rows.forest_edge
	detail.toggle.button_pressed = true
	await process_frame
	await process_frame
	existing_management.scroll.scroll_vertical = 127
	await process_frame
	var remembered_scroll: int = existing_management.scroll.scroll_vertical
	var login_before: Dictionary = shop.login_resume.snapshot().duplicate(true)
	for mode in [shop.State.WindowMode.WORKSHOP, shop.State.WindowMode.COMPANION, shop.State.WindowMode.MINIMAL]:
		shop._set_window_mode(mode)
		var toolbar: Control = shop.workshop_toolbar if mode == shop.State.WindowMode.WORKSHOP else shop.companion.toolbar if mode == shop.State.WindowMode.COMPANION else shop.mini_toolbar
		var before_restore: Dictionary = progress()
		shop.management.hide()
		toolbar.get_node("ManageButton").pressed.emit()
		assert(shop.management == existing_management and shop.management.visible and shop.management_raise_pending)
		assert(shop.management.selected == shop.ManagementPanel.EXPEDITIONS and Compare.equivalent(before_restore, progress()))
		# Repeated same-frame requests must coalesce and settle after the deferred
		# next-frame boundary rather than recreating/resetting the panel.
		for repeat in 5:
			toolbar.get_node("ManageButton").pressed.emit()
			assert(shop.management_raise_pending and shop.management == existing_management)
		await process_frame
		await process_frame
		assert(not shop.management_raise_pending and existing_management.visible)
		assert(existing_management.selected == shop.ManagementPanel.EXPEDITIONS and detail.toggle.button_pressed and detail.detail_box.visible)
		assert(existing_management.scroll.scroll_vertical == remembered_scroll)
		assert(Compare.equivalent(before_restore, progress()) and Compare.equivalent(login_before, shop.login_resume.snapshot()))
		# Close during the pending request. The delayed raise must neither show a
		# hidden management window nor alter the original page/detail or state.
		toolbar.get_node("ManageButton").pressed.emit()
		assert(shop.management_raise_pending)
		existing_management.close_button.pressed.emit()
		await process_frame
		await process_frame
		assert(not shop.management_raise_pending and not existing_management.visible)
		assert(existing_management.selected == shop.ManagementPanel.EXPEDITIONS and detail.toggle.button_pressed)
		assert(Compare.equivalent(before_restore, progress()) and Compare.equivalent(login_before, shop.login_resume.snapshot()))
		# A genuinely newer reopen before the old callback is still honored; the
		# callback uses the same live visible panel and clears its pending flag.
		toolbar.get_node("ManageButton").pressed.emit()
		existing_management.close_button.pressed.emit()
		toolbar.get_node("ManageButton").pressed.emit()
		assert(shop.management_raise_pending and existing_management.visible)
		await process_frame
		await process_frame
		assert(not shop.management_raise_pending and shop.management == existing_management and existing_management.visible)
		assert(existing_management.selected == shop.ManagementPanel.EXPEDITIONS and detail.toggle.button_pressed and detail.detail_box.visible)
		assert(existing_management.scroll.scroll_vertical == remembered_scroll)
		assert(Compare.equivalent(before_restore, progress()) and Compare.equivalent(login_before, shop.login_resume.snapshot()))
	shop.management.hide()
	detail.toggle.button_pressed = false
	shop._set_window_mode(original_mode)
	assert(Compare.equivalent(original, progress()))
	return true

func render() -> void:
	DirAccess.make_dir_recursive_absolute("res://.verification/three-stage-modes")
	shop.state.gold = 25458
	for mode in [shop.State.WindowMode.WORKSHOP, shop.State.WindowMode.COMPANION, shop.State.WindowMode.MINIMAL]:
		shop._set_window_mode(mode)
		shop._update_interface()
		shop.companion.refresh()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.verification/three-stage-modes/mode-%d.png" % mode)

