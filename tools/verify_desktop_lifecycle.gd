extends SceneTree
## Native, isolated lifecycle test; does not inject mouse or keyboard input.
const Shop = preload("res://scripts/shop.gd")


func _initialize() -> void:
	set_meta("isolated_preview", true)
	set_meta("desktop_input_verification", true)
	call_deferred("_run")


func _run() -> void:
	assert(OS.get_name() == "Windows" and DisplayServer.get_name() != "headless")
	var shop := Shop.new()
	root.add_child(shop)
	root.title = "클릭 통과 수명 검증 · 저장하지 않음"
	root.always_on_top = false
	var bridge: Node = shop.desktop_input
	for mode in [shop.State.WindowMode.FULL, shop.State.WindowMode.SMALL, shop.State.WindowMode.MINIMAL]:
		shop._set_window_mode(shop.State.WindowMode.WORKSHOP)
		await create_timer(0.3).timeout
		assert(not bridge.failed and not bridge.process.is_empty())
		var pid: int = bridge.process["pid"]
		assert(OS.is_process_running(pid), "Workshop must start the native bridge")
		shop._set_window_mode(mode)
		await create_timer(0.3).timeout
		assert(not OS.is_process_running(pid) and bridge.process.is_empty(), "Leaving workshop must stop the bridge")
	# Rapid off/on must wait for the old process and start exactly one replacement.
	shop._set_window_mode(shop.State.WindowMode.WORKSHOP)
	await create_timer(0.3).timeout
	var first_pid: int = bridge.process["pid"]
	shop._set_window_mode(shop.State.WindowMode.FULL)
	shop._set_window_mode(shop.State.WindowMode.WORKSHOP)
	await create_timer(0.5).timeout
	assert(not bridge.failed and not bridge.process.is_empty())
	assert(not OS.is_process_running(first_pid))
	var final_pid: int = bridge.process["pid"]
	assert(final_pid != first_pid and OS.is_process_running(final_pid))
	shop._show_companion_view()
	await create_timer(0.4).timeout
	assert(bridge.layout_size == Shop.MiniWorkshop.SIZE and bridge.art_height == 128)
	assert(not OS.is_process_running(final_pid) and not bridge.failed and not bridge.process.is_empty())
	final_pid = bridge.process["pid"]
	shop.companion.minimize_button.pressed.emit()
	await create_timer(0.3).timeout
	assert(shop.state.window_mode == shop.State.WindowMode.MINIMAL and not OS.is_process_running(final_pid) and bridge.process.is_empty())
	shop.mini_toolbar.get_node("RestoreButton").pressed.emit()
	await create_timer(0.3).timeout
	assert(shop.state.window_mode == shop.State.WindowMode.COMPANION and bridge.art_height == 128 and not bridge.failed and not bridge.process.is_empty())
	final_pid = bridge.process["pid"]
	shop._restore_compact_view()
	await create_timer(0.4).timeout
	assert(bridge.layout_size == Shop.WorkshopAssets.SIZE and bridge.art_height == 248)
	assert(not OS.is_process_running(final_pid) and not bridge.failed and not bridge.process.is_empty())
	final_pid = bridge.process["pid"]
	shop.queue_free()
	await create_timer(0.3).timeout
	assert(not OS.is_process_running(final_pid), "Closing the shop must not leave a native helper behind")
	print("DESKTOP LIFECYCLE PASS: full/small/information, rapid toggles, main/character/information/character/main helper routing, shutdown")
	quit()
