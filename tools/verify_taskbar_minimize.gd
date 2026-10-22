extends SceneTree
const Shop = preload("res://scripts/shop.gd")


func _initialize() -> void:
	set_meta("isolated_preview", true)
	call_deferred("_run")


func _run() -> void:
	var shop := Shop.new()
	root.add_child(shop)
	var old_save: Dictionary = shop.state.to_data()
	old_save["pinned"] = true
	var restored := shop.State.new()
	assert(restored.load_data(old_save))
	assert(not restored.pinned and restored.gold == shop.state.gold)
	for mode in [shop.State.WindowMode.WORKSHOP, shop.State.WindowMode.SMALL, shop.State.WindowMode.MINIMAL, shop.State.WindowMode.FULL]:
		shop._set_window_mode(mode)
		shop.open_management()
		assert(root.always_on_top and shop.management.always_on_top)
		var before_size: Vector2i = root.size
		var clock_before: float = shop.state.progression.clock
		# OS-level minimize remains supported; the in-game button opens the compact HUD.
		root.mode = Window.MODE_MINIMIZED
		shop._sync_minimized_state()
		await process_frame
		assert(root.mode == Window.MODE_MINIMIZED)
		assert(not shop.management.visible and not shop.desktop_input.enabled)
		assert(shop.desktop_suspended_for_minimize)
		# Allow the normal game loop to run against an isolated save while minimized.
		shop.test_mode = false
		await create_timer(1.2).timeout
		shop.test_mode = true
		assert(shop.state.progression.clock > clock_before + 0.5, "Minimizing must not pause automatic operation")
		root.mode = Window.MODE_WINDOWED
		await process_frame
		shop._sync_minimized_state()
		assert(not shop.desktop_suspended_for_minimize)
		assert(shop.state.window_mode == mode and root.size == before_size)
		assert(root.always_on_top)
	print("TASKBAR MINIMIZE PASS: topmost stays on without toggle, all four layouts minimize/restore, management hides, game loop continues")
	quit()
