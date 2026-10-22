extends Node
## Owned-window taskbar flags only. Input transparency remains DesktopInput's job.
const Binary = preload("res://native/windows/tray_taskbar_binary.gd")
var process := {}
var stopping := false
var connected := false
var buffer := ""
var last_error := ""
signal unavailable

func _reply(timeout_ms: int = 5000) -> String:
	var deadline := Time.get_ticks_msec()+timeout_ms
	while not process.is_empty() and Time.get_ticks_msec() < deadline:
		var available: int = process.stdio.get_length()
		if available > 0: buffer += process.stdio.get_buffer(available).get_string_from_utf8()
		var line_end := buffer.find("\n")
		if line_end >= 0:
			var line := buffer.substr(0,line_end).strip_edges()
			buffer = buffer.substr(line_end+1)
			return line
		if not OS.is_process_running(process.pid): break
		# Shell taskbar calls can synchronously query this window. Keep pumping
		# the Godot/Windows event loop rather than blocking it while waiting.
		await get_tree().process_frame
		if not is_inside_tree(): return ""
	return ""

func start_for(window: Window,indicator: int) -> bool:
	if OS.get_name() != "Windows" or DisplayServer.get_name() == "headless": return false
	if not process.is_empty(): return connected and register_window(window)
	var handle := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE,window.get_window_id())
	if handle == 0: return false
	var bytes := Marshalls.base64_to_raw(Binary.BASE64)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	var folder := "res://.verification/native" if get_tree().has_meta("isolated_preview") else "user://native"
	if DirAccess.make_dir_recursive_absolute(folder) != OK: return false
	var path := folder.path_join("tray-taskbar-"+hash.finish().hex_encode().left(16)+".exe")
	if not FileAccess.file_exists(path) or FileAccess.get_file_as_bytes(path) != bytes:
		var file := FileAccess.open(path,FileAccess.WRITE)
		if file == null: return false
		file.store_buffer(bytes)
		file.close()
	process = OS.execute_with_pipe(ProjectSettings.globalize_path(path),[str(OS.get_process_id()),str(handle),str(indicator)],false)
	stopping = false
	if process.is_empty(): return false
	var reply: String = await _reply()
	if process.is_empty(): return false
	if reply == "READY":
		connected = true
		return true
	last_error = "reply=%s / process_running=%s / exit=%s" % [reply,OS.is_process_running(process.pid),OS.get_process_exit_code(process.pid)]
	stop()
	return false

func register_window(window: Window) -> bool:
	if process.is_empty() or stopping or not connected or window.get_window_id() < 0: return false
	var handle := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE,window.get_window_id())
	if handle == 0: return false
	process.stdio.store_line("add "+str(handle))
	return true

func inspect() -> String:
	if process.is_empty() or stopping: return ""
	process.stdio.store_line("inspect")
	return await _reply()

func restore_main() -> void:
	if connected and not stopping: process.stdio.store_line("restore")

func stop() -> void:
	if process.is_empty() or stopping: return
	stopping = true
	connected = false
	process.stdio.store_line("stop")
	process.stdio.close()

func _process(_delta: float) -> void:
	if process.is_empty() or OS.is_process_running(process.pid): return
	var expected := stopping
	if not expected:
		last_error = process.stdio.get_line().strip_edges()
		if last_error.is_empty(): last_error = "Helper exited: "+str(OS.get_process_exit_code(process.pid))
	for pipe in ["stdio","stderr"]:
		if process.get(pipe) != null: process[pipe].close()
	process.clear()
	buffer = ""
	connected = false
	stopping = false
	if not expected: unavailable.emit()

func _exit_tree() -> void: stop()
