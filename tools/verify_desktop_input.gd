extends SceneTree
const Shop = preload("res://scripts/shop.gd")
var shop: Control
const COMMAND := "res://.verification/desktop-input-command.txt"
const STATUS := "res://.verification/desktop-input-status.json"


func _initialize() -> void:
	set_meta("isolated_preview", true)
	set_meta("desktop_input_verification", true)
	call_deferred("_run")


func _run() -> void:
	shop = Shop.new()
	root.add_child(shop)
	shop._set_window_mode(shop.State.WindowMode.WORKSHOP)
	root.position = Vector2i(400, 180)
	root.always_on_top = true
	root.window_input.connect(func(event):
		if event is InputEventMouseButton: print("PROBE mouse: ", event.position, " pressed=", event.pressed)
	)
	shop.state.gold = 1000
	shop.state.purchase("moon")
	shop.state.progression.clock = 190
	var until := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < until:
		if FileAccess.file_exists(COMMAND):
			var command := FileAccess.get_file_as_string(COMMAND).strip_edges()
			DirAccess.remove_absolute(COMMAND)
			if command == "quit": break
			if command == "full": shop._set_window_mode(shop.State.WindowMode.FULL)
			if command == "workshop": shop._set_window_mode(shop.State.WindowMode.WORKSHOP)
		shop._advance_game(0.1)
		shop._update_interface()
		var file := FileAccess.open(STATUS, FileAccess.WRITE)
		file.store_string(JSON.stringify({"window": DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE), "management": shop.management != null and shop.management.visible, "mode": shop.state.window_mode, "bridge_failed": shop.desktop_input.failed, "clock": shop.state.progression.clock}))
		file.close()
		await create_timer(0.1).timeout
	if shop.management != null: shop.management.queue_free()
	print("DESKTOP INPUT FIXTURE: isolated state closed")
	quit()
