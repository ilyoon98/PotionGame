extends SceneTree
## Real Windows tray/menu/helper, but only fixture saves and fixture-owned windows.
const Shop = preload("res://scripts/shop.gd")
const State = preload("res://scripts/shop_state.gd")
const Compare = preload("res://tests/state_compare.gd")
const OUT := "res://.verification/system-tray/"
var shop: Control

class FixtureShop extends Shop:
	var writes := 0
	var write_allowed := true
	var quit_requested := false
	func _save() -> bool:
		writes += 1
		return write_allowed and SaveStore.write_from(state,"res://.verification/system-tray/progress.json") == OK
	func _request_manual_quit() -> void: quit_requested = true

func _initialize() -> void:
	set_meta("isolated_preview",true)
	set_meta("tray_verification",true)
	call_deferred("run")

func styles_hidden(expected_windows: int) -> void:
	var reply: String = await shop.system_tray.taskbar.inspect()
	assert(reply.begins_with("STATE "),"Native taskbar helper did not respond: "+reply)
	var count := 0
	var main_handle := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE,root.get_window_id())
	for entry in reply.substr(6).split(";",false):
		var fields := entry.split(":")
		var flags := int(fields[1])
		assert((flags & 0x80) != 0 and (flags & 0x40000) == 0,"Toolwindow flag must replace APPWINDOW without affecting transparency")
		if int(fields[0]) == main_handle:
			assert(fields[2] == "1" and fields[3] == "0","Restored root must be natively visible, not only logically visible in Godot")
		count += 1
	assert(count >= expected_windows)

func action(name: String) -> void:
	var tray = shop.system_tray
	var index := NativeMenu.find_item_index_with_tag(tray.menu,name)
	assert(index >= 0)
	NativeMenu.get_item_callback(tray.menu,index).call(name)
	await process_frame
	await process_frame

func run() -> void:
	assert(OS.get_name() == "Windows" and DisplayServer.get_name() != "headless")
	DirAccess.make_dir_recursive_absolute(OUT)
	shop = FixtureShop.new()
	root.add_child(shop)
	root.always_on_top = false
	root.gui_disable_input = true
	shop._set_window_mode(State.WindowMode.WORKSHOP)
	await process_frame
	await process_frame
	var tray = shop.system_tray
	for i in 180:
		if tray.taskbar != null and (tray.taskbar.connected or not tray.taskbar.last_error.is_empty()): break
		await process_frame
	assert(tray.active and tray.indicator >= 0,"Windows tray icon creation failed")
	assert(not tray.taskbar.process.is_empty() and not tray.taskbar.stopping,"Native taskbar hiding failed: "+tray.taskbar.last_error)
	assert(NativeMenu.get_item_count(tray.menu) == 5)
	var tray_rect := DisplayServer.status_indicator_get_rect(tray.indicator)
	# Godot returns an empty rect for some collapsed overflow locations. The
	# helper's READY also verifies the entry through Shell_NotifyIcon(NIM_MODIFY).
	await styles_hidden(1)
	# Use the normal Shop._process in this fixture; save/quit overrides isolate it.
	shop.test_mode = false
	shop.state.herbs = 100
	shop.state.brew_active = true
	shop._update_interface()
	var identity: RefCounted = shop.state
	var checks := 0
	for mode in [State.WindowMode.WORKSHOP,State.WindowMode.COMPANION,State.WindowMode.MINIMAL]:
		shop._set_window_mode(mode)
		var before: Dictionary = shop.state.to_data().duplicate(true)
		tray.hide_game()
		assert(root.mode == Window.MODE_MINIMIZED and tray.hidden_to_tray)
		assert(Compare.equivalent(before,shop.state.to_data()))
		var clock: float = shop.state.progression.clock
		await create_timer(0.4).timeout
		assert(shop.state == identity and shop.state.progression.clock > clock+0.2,"Hidden game must continue using the normal economy loop")
		await action("toggle")
		assert(root.mode == Window.MODE_WINDOWED and not tray.hidden_to_tray and shop.state.window_mode == mode)
		assert(root.transparent and root.transparent_bg)
		await styles_hidden(1)
		checks += 1
	tray.hide_game()
	await action("statistics")
	assert(root.visible and shop.management.visible and shop.management.selected == shop.ManagementPanel.REPORT)
	assert(shop.management.statistics_values.play_time.source_text == shop.Status.lifetime_summary(shop.state).time)
	await styles_hidden(2)
	shop.management.close_requested.emit()
	await action("manage")
	assert(shop.management.visible)
	await styles_hidden(2)
	# Closing Godot secondary windows can invalidate a queued native handle.
	for i in 12:
		shop.management.close_requested.emit()
		shop.open_management()
		await process_frame
	await styles_hidden(2)
	tray.hide_game()
	shop.write_allowed = false
	await action("quit")
	assert(not shop.quit_requested and root.visible,"Save failure must leave the game recoverable")
	var confirmation: ConfirmationDialog
	for child in shop.get_children():
		if child is ConfirmationDialog: confirmation = child
	assert(confirmation != null and confirmation.visible)
	confirmation.canceled.emit()
	await process_frame
	await styles_hidden(1)
	shop.write_allowed = true
	tray.hide_game()
	await action("quit")
	assert(shop.quit_requested and shop.writes >= 2)
	await styles_hidden(1)
	var restored := State.new()
	assert(shop.SaveStore.read_into(restored,OUT+"progress.json") == "loaded")
	assert(restored.progression.clock > 0 and restored.total_sold == shop.state.total_sold)
	var proof := {"status":"passed","real_windows_tray":true,"tray_rect":[tray_rect.position.x,tray_rect.position.y,tray_rect.size.x,tray_rect.size.y],"mode_hide_restore_checks":checks,"native_taskbar_flags_verified":true,"native_menu_callbacks_verified":true,"management_reopen_cycles":12,"hidden_economy_continues":true,"same_game_state":shop.state==identity,"save_failure_keeps_game_open":true,"quit_saves_progress":true,"player_save_accessed":false}
	var helper_pid: int = tray.taskbar.process.pid
	shop.queue_free()
	await process_frame
	for i in 30:
		if not OS.is_process_running(helper_pid): break
		await create_timer(0.05).timeout
	assert(not OS.is_process_running(helper_pid),"Taskbar helper exits when its game closes")
	proof["helper_exits_cleanly"] = true
	var file := FileAccess.open(OUT+"proof.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(proof,"\t"))
	print("SYSTEM TRAY PASS: real Shell icon/native menu/taskbar flags;3 modes;hidden economy;save failure/quit persistence;clean helper exit")
	quit()
