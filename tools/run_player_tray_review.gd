extends SceneTree
## Finite verification in the normal saved player session, then keep playing.
## No fixtures, replacement state, time skipping, or automatic repeated resets.
const Shop = preload("res://scripts/shop.gd")
const State = preload("res://scripts/shop_state.gd")
const Compare = preload("res://tests/state_compare.gd")
const OUT := "res://.verification/tray-player-restart/"
var shop: Control

func _initialize() -> void: call_deferred("run")

func write_proof(name: String,data: Dictionary) -> void:
	var file := FileAccess.open(OUT+name,FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(data,"\t"))
	file.close()

func menu_action(tag: String) -> void:
	var tray = shop.system_tray
	var index := NativeMenu.find_item_index_with_tag(tray.menu,tag)
	assert(index >= 0)
	NativeMenu.get_item_callback(tray.menu,index).call(tag)
	await process_frame
	await process_frame

func snapshot() -> Dictionary:
	return {"clock":shop.state.progression.clock,"sold":shop.state.total_sold,"gold":shop.state.gold,"mode":shop.state.window_mode,"totals":shop.state.progression.totals.duplicate(true)}

func displayed_statistics_follow_clock() -> bool:
	# The UI refreshes every 0.2 seconds while the simulation keeps processing.
	# Read the actual display, allowing a one-second boundary during that refresh.
	var pattern := RegEx.create_from_string("^(\\d+)시간 (\\d+)분 (\\d+)초$")
	var result := pattern.search(shop.management.statistics_values.play_time.source_text)
	if result == null: return false
	var shown := int(result.get_string(1))*3600+int(result.get_string(2))*60+int(result.get_string(3))
	var actual := int(shop.state.progression.clock)
	return shown <= actual and actual-shown <= 1

func run() -> void:
	assert(OS.get_name() == "Windows" and DisplayServer.get_name() != "headless")
	DirAccess.make_dir_recursive_absolute(OUT)
	shop = Shop.new()
	root.add_child(shop)
	if not shop._owns_game_session(): return
	assert(not shop.test_mode and not shop.instance_bypassed)
	var loaded := snapshot()
	print("SAVED PLAYER LOADED: ",JSON.stringify(loaded))
	if "--tray-save-and-exit" in OS.get_cmdline_user_args():
		assert(shop._save(),"Existing player progress must save before restarting")
		write_proof("saved-before-restart.json",loaded)
		shop._close_shop()
		return
	var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUT+"saved-before-restart.json"))
	# JSON proof formatting rounds the final fractional digits of the clock.
	# Integer counters remain exact; use the save comparator's tolerance for time.
	assert(Compare.equivalent(loaded.clock,previous.clock) and loaded.sold == previous.sold and loaded.gold == previous.gold)
	assert(Compare.equivalent(loaded.totals,previous.totals),"Cumulative statistics must survive restart")
	var identity: RefCounted = shop.state
	for i in 180:
		if shop.system_tray.taskbar != null and shop.system_tray.taskbar.connected: break
		await process_frame
	var tray = shop.system_tray
	assert(tray.active and tray.taskbar != null and tray.taskbar.connected,"Real Windows tray registration must succeed")
	# Present this requested review on the primary screen, within its work area.
	root.current_screen = DisplayServer.get_primary_screen()
	var usable := DisplayServer.screen_get_usable_rect(root.current_screen)
	root.position = usable.position+Vector2i(maxi(0,(usable.size.x-root.size.x)/2),maxi(32,usable.size.y-root.size.y-64))
	tray.show_game()
	await process_frame
	var cycles := []
	for i in 3:
		var before := snapshot()
		var exact: Dictionary = shop.state.to_data().duplicate(true)
		tray.hide_game()
		assert(Compare.equivalent(exact,shop.state.to_data()),"Hiding must not mutate player data")
		assert(root.mode == Window.MODE_MINIMIZED)
		await create_timer(3.0).timeout
		assert(shop.state == identity and shop.state.progression.clock > float(before.clock)+2.0)
		# Exercise the same callback as a left click on the notification icon.
		tray._pressed(MOUSE_BUTTON_LEFT,Vector2i.ZERO)
		await process_frame
		await process_frame
		await create_timer(0.25).timeout
		assert(root.mode == Window.MODE_WINDOWED and not tray.hidden_to_tray)
		assert(not shop.desktop_input.failed and not shop.desktop_input.process.is_empty() and OS.is_process_running(shop.desktop_input.process.pid),"Click-through bridge must survive tray restore")
		assert(shop.state.window_mode == int(before.mode) and shop.state.total_sold >= int(before.sold))
		var native: String = await tray.taskbar.inspect()
		assert(native.begins_with("STATE "))
		for entry in native.substr(6).split(";",false):
			var fields := entry.split(":")
			assert((int(fields[1]) & 0x80) != 0 and (int(fields[1]) & 0x40000) == 0)
			var main_handle := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE,root.get_window_id())
			if int(fields[0]) == main_handle:
				assert(fields[2] == "1" and fields[3] == "0","Restored game must be natively visible and not minimized")
		await menu_action("statistics")
		assert(shop.management.visible and shop.state == identity)
		assert(displayed_statistics_follow_clock(),"Statistics must show the retained cumulative time, allowing its normal refresh interval")
		cycles.append({"before":before,"after":snapshot(),"displayed_time":shop.management.statistics_values.play_time.source_text,"native_taskbar_state":native})
		shop.management.close_requested.emit()
	assert(shop._save(),"Actual AppData save must succeed after tray verification")
	var persisted := State.new()
	assert(shop.SaveStore.read_into(persisted,shop.SAVE_PATH) == "loaded")
	assert(Compare.equivalent(persisted.to_data(),shop.state.to_data()))
	await menu_action("statistics")
	await RenderingServer.frame_post_draw
	assert(shop.management.get_texture().get_image().save_png(OUT+"statistics-after.png") == OK)
	assert(root.get_texture().get_image().save_png(OUT+"game-after.png") == OK)
	write_proof("normal-player-proof.json",{"status":"passed","pid":OS.get_process_id(),"execution":"normal saved player game","restart_preserved_exact_stats":true,"loaded":loaded,"after":snapshot(),"tray_registered_in_windows_shell":tray.taskbar.connected,"hide_restore_cycles":cycles,"actual_appdata_save_roundtrip":true,"same_state_instance":shop.state==identity,"periodic_reset":false,"kept_running":true,"window_position":[root.position.x,root.position.y],"primary_screen":root.current_screen})
	print("NORMAL PLAYER TRAY PASS: saved/restarted;3 hide/restore cycles;statistics preserved;real AppData save;game remains running")
