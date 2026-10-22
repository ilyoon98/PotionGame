extends SceneTree
const Shop = preload("res://scripts/shop.gd")
const Compare = preload("res://tests/state_compare.gd")


func _initialize() -> void:
	set_meta("isolated_preview", true)
	call_deferred("_run")


func _run() -> void:
	var shop := Shop.new()
	root.add_child(shop)
	shop.state.gold = 1234
	shop.income.advance(1.0, 18)
	for mode in [shop.State.WindowMode.WORKSHOP, shop.State.WindowMode.FULL]:
		shop._set_window_mode(mode)
		shop.open_management()
		var snapshot: Dictionary = shop.state.to_data().duplicate(true)
		var button: Button = shop.management.find_child("InformationOnlyButton", true, false)
		button.pressed.emit()
		assert(shop.state.window_mode == shop.State.WindowMode.MINIMAL and root.content_scale_size == shop.MINIMAL_SIZE)
		assert(shop.minimal_hud.is_visible_in_tree())
		if DisplayServer.get_name() != "headless": assert(root.mode != Window.MODE_MINIMIZED and root.size == shop.MINIMAL_SIZE and root.always_on_top)
		assert(not shop.art.visible and not shop.management.visible and not shop.desktop_input.enabled)
		assert(shop.minimal_gold.source_text == "1,234 G" and shop.minimal_income.source_text == "+18 G / 최근 1분")
		assert(shop.minimal_gold.coin_count == 1 and shop.minimal_income.coin_count == 1)
		assert(shop.minimal_bar.is_visible_in_tree() and shop.shrink_button.visible and shop.shrink_button.disabled)
		shop.mini_toolbar.get_node("RestoreButton").pressed.emit()
		assert(shop.state.window_mode == shop.State.WindowMode.COMPANION)
		if DisplayServer.get_name() != "headless": assert(root.mode != Window.MODE_MINIMIZED)
		shop.companion.restore_button.pressed.emit()
		assert(shop.state.window_mode == mode)
		assert(Compare.equivalent(snapshot, shop.state.to_data()), "Compact/restore must preserve all game progress")
	shop._set_window_mode(shop.State.WindowMode.WORKSHOP)
	shop._show_minimal_view()
	var before_clock: float = shop.state.progression.clock
	shop.test_mode = false
	await create_timer(1.2).timeout
	shop.test_mode = true
	assert(shop.state.progression.clock > before_clock + 0.5)
	assert(not shop.minimal_brew.text.is_empty() and shop.minimal_bar.value > 0.0)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.verification/compact-progress.png")
	shop.mini_toolbar.get_node("RestoreButton").pressed.emit()
	assert(shop.state.window_mode == shop.State.WindowMode.COMPANION)
	shop.companion.restore_button.pressed.emit()
	assert(shop.state.window_mode == shop.State.WindowMode.WORKSHOP and shop.art.visible)
	print("COMPACT PROGRESS PASS: on-screen gold/income/brew gauge, always on top, automatic operation continues, expands information to companion then original main without progress changes")
	quit()
