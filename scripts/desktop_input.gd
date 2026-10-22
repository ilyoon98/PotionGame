extends Node
## Keep workshop artwork visible while its noninteractive area passes OS input.
const Binary = preload("res://native/windows/desktop_bridge_binary.gd")
const Layout = preload("res://scripts/workshop_assets.gd")
var enabled := false
var process := {}
var stopping := false
var failed := false
var executable := ""
var layout_size := Layout.SIZE
var art_height := Layout.ART_HEIGHT
var input_regions: Array[Rect2i] = []
signal unavailable


func configure(size: Vector2i, picture_height: int, clickable_regions: Array[Rect2i] = []) -> void:
	if not valid_regions(size, picture_height, clickable_regions):
		push_error("Desktop input regions must be bounded, nonempty rectangles inside the picture.")
		return
	if layout_size == size and art_height == picture_height and input_regions == clickable_regions: return
	layout_size = size
	art_height = picture_height
	# The caller may reuse its array; keep routing independent of later mutations.
	input_regions.assign(clickable_regions)
	_stop()


static func valid_regions(size: Vector2i, picture_height: int, regions: Array[Rect2i]) -> bool:
	if size.x <= 0 or size.y <= 0 or picture_height <= 0 or picture_height > size.y or regions.size() > 32: return false
	var picture := Rect2i(0, 0, size.x, picture_height)
	for rect in regions:
		if not rect.has_area() or not picture.encloses(rect): return false
	return true


static func serialize_regions(regions: Array[Rect2i]) -> String:
	var pieces := PackedStringArray()
	for rect in regions: pieces.append("%d,%d,%d,%d" % [rect.position.x, rect.position.y, rect.size.x, rect.size.y])
	return ";".join(pieces)


static func passes_picture_input(point: Vector2, size: Vector2i, picture_height: int, regions: Array[Rect2i]) -> bool:
	# Pure logical-coordinate equivalent of the native band and button exceptions.
	if not Rect2(Vector2.ZERO, Vector2(size.x, picture_height)).has_point(point): return false
	for rect in regions:
		if Rect2(rect).has_point(point): return false
	return true


func set_enabled(value: bool) -> void:
	enabled = value
	if not value: _stop()
	elif not failed: _start()


func _start() -> void:
	if not process.is_empty() or OS.get_name() != "Windows" or DisplayServer.get_name() == "headless": return
	if executable.is_empty():
		var bytes := Marshalls.base64_to_raw(Binary.BASE64)
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(bytes)
		var folder := "res://.verification/native" if get_tree().has_meta("isolated_preview") else "user://native"
		if DirAccess.make_dir_recursive_absolute(folder) != OK:
			_fail()
			return
		executable = ProjectSettings.globalize_path(folder.path_join("desktop-input-" + hash.finish().hex_encode().left(16) + ".exe"))
		if not FileAccess.file_exists(executable) or FileAccess.get_file_as_bytes(executable) != bytes:
			var file := FileAccess.open(executable, FileAccess.WRITE)
			if file == null:
				_fail()
				return
			file.store_buffer(bytes)
			file.close()
	var handle := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, get_window().get_window_id())
	# The bottom bar and explicit small buttons receive input; artwork still passes.
	var arguments := [str(handle), str(OS.get_process_id()), str(layout_size.x), str(layout_size.y), "0", str(art_height)]
	if not input_regions.is_empty(): arguments.append(serialize_regions(input_regions))
	process = OS.execute_with_pipe(executable, arguments, false)
	stopping = false
	if process.is_empty(): _fail()


func _process(_delta: float) -> void:
	if process.is_empty(): return
	if OS.is_process_running(process["pid"]): return
	var expected := stopping
	if not expected:
		push_warning("Desktop input bridge exit %s: %s" % [OS.get_process_exit_code(process["pid"]), process["stderr"].get_line()])
	process.clear()
	stopping = false
	if enabled:
		if expected: _start()
		else: _fail()


func _stop() -> void:
	if process.is_empty() or stopping: return
	stopping = true
	process["stdio"].store_line("stop")
	process["stdio"].close()


func _fail() -> void:
	failed = true
	push_warning("Desktop input bridge unavailable; workshop controls remain accessible.")
	unavailable.emit()


func _exit_tree() -> void:
	_stop()
