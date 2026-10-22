extends SceneTree
## Pure headless routing/configuration checks. Never starts the native bridge.
const Bridge = preload("res://scripts/desktop_input.gd")
const Binary = preload("res://native/windows/desktop_bridge_binary.gd")
const Workshop = preload("res://scripts/workshop_layout.gd")
const Mini = preload("res://scripts/mini_workshop.gd")

class CountingBridge extends Bridge:
	var stop_count := 0
	func _stop() -> void: stop_count += 1

func _initialize() -> void:
	assert(DisplayServer.get_name() == "headless")
	set_meta("isolated_preview", true)
	call_deferred("run")

func run() -> void:
	verify_current_layouts()
	var size := Vector2i(408, 288)
	var regions: Array[Rect2i] = [Rect2i(92, 125, 16, 16), Rect2i(272, 2, 16, 16), Rect2i(290, 194, 16, 16)]
	assert(Bridge.valid_regions(size, 248, regions))
	assert(Bridge.serialize_regions(regions) == "92,125,16,16;272,2,16,16;290,194,16,16")
	assert(Bridge.serialize_regions([]) == "")
	for invalid in [Rect2i(-1, 1, 16, 16), Rect2i(0, -1, 16, 16), Rect2i(393, 1, 16, 16), Rect2i(0, 240, 16, 16), Rect2i(0, 0, 0, 16), Rect2i(0, 0, 16, -1)]:
		var invalid_regions: Array[Rect2i] = [invalid]
		assert(not Bridge.valid_regions(size, 248, invalid_regions))
	var many: Array[Rect2i] = []
	many.resize(33)
	many.fill(Rect2i(0, 0, 1, 1))
	assert(not Bridge.valid_regions(size, 248, many))
	assert(not Bridge.valid_regions(Vector2i(0, 288), 248, []))
	assert(not Bridge.valid_regions(size, 289, []))
	# Button left/top are included, right/bottom excluded. Surrounding art passes.
	for rect in regions:
		assert(not Bridge.passes_picture_input(Vector2(rect.position), size, 248, regions))
		assert(not Bridge.passes_picture_input(Vector2(rect.end) - Vector2(0.01, 0.01), size, 248, regions))
		assert(Bridge.passes_picture_input(Vector2(rect.position) - Vector2(0.01, 0.01), size, 248, regions))
		assert(Bridge.passes_picture_input(Vector2(rect.end), size, 248, regions))
	for point in [Vector2(0, 0), Vector2(407.99, 247.99), Vector2(160, 80)]:
		assert(Bridge.passes_picture_input(point, size, 248, regions))
	for point in [Vector2(-0.01, 100), Vector2(408, 100), Vector2(100, -0.01), Vector2(100, 248), Vector2(100, 287)]:
		assert(not Bridge.passes_picture_input(point, size, 248, regions))
	# Native client pixels normalize both axes, so whitelist boundaries are scale-independent.
	for scale in [1.0, 1.25, 1.5, 2.0]:
		for rect in regions:
			var logical := Vector2(rect.position) + Vector2(8, 8)
			var client: Vector2 = logical * scale
			var normalized := Vector2(client.x * size.x / (size.x * scale), client.y * size.y / (size.y * scale))
			assert(not Bridge.passes_picture_input(normalized, size, 248, regions))
	var bridge := CountingBridge.new()
	bridge.configure(size, 248)
	assert(bridge.stop_count == 1)
	bridge.configure(size, 248, regions)
	assert(bridge.stop_count == 2 and bridge.input_regions == regions)
	bridge.configure(size, 248, regions)
	assert(bridge.stop_count == 2, "Unchanged layout must not restart routing")
	regions[0] = Rect2i(1, 1, 16, 16)
	assert(bridge.input_regions[0] == Rect2i(92, 125, 16, 16), "Routing must retain a value copy")
	bridge.configure(size, 248, regions)
	assert(bridge.stop_count == 3)
	bridge.configure(Vector2i(256, 160), 128)
	assert(bridge.stop_count == 4 and bridge.input_regions.is_empty())
	bridge.configure(Vector2i(256, 160), 128)
	assert(bridge.stop_count == 4)
	assert(Bridge.passes_picture_input(Vector2(128, 64), Vector2i(256, 160), 128, []))
	assert(not Bridge.passes_picture_input(Vector2(128, 128), Vector2i(256, 160), 128, []))
	bridge.free()
	var real := Bridge.new()
	root.add_child(real)
	real.configure(size, 248, regions)
	real.set_enabled(true)
	assert(real.process.is_empty() and real.executable.is_empty(), "Headless checks never extract or execute the native helper")
	real.set_enabled(false)
	real.free()
	assert(Marshalls.base64_to_raw(Binary.BASE64) == FileAccess.get_file_as_bytes("res://native/windows/desktop_passthrough.exe"), "Embedded bridge must match the compiled source artifact")
	var native_source := FileAccess.get_file_as_string("res://native/windows/DesktopPassthrough.cs")
	assert(native_source.contains("NumberStyles.None") and native_source.contains("(long)x + w > width") and native_source.contains("(long)y + h > hudTop"))
	assert(native_source.contains("&& !InRegion(x, y, regions)"))
	assert(native_source.contains("if (!held)") and native_source.contains("BelongsTo(window, owner)"))
	print("DESKTOP REGIONS PASS: strict picture bounds; main540x300/picture248/bar52, mini256x172/picture128/bar44; entire bottom bands retain input; exact 18px buttons and scale-independent boundaries; copies and change-only restart; embedded binary matches; native helper never executed; OS clicking not tested")
	quit()

func verify_current_layouts() -> void:
	assert(Workshop.SIZE == Vector2i(540, 300) and Workshop.ART_HEIGHT == 248 and Workshop.BAR_HEIGHT == 52)
	assert(Mini.SIZE == Vector2i(256, 172) and Mini.ART_HEIGHT == 128 and Mini.BAR_HEIGHT == 44)
	var workshop_regions: Array[Rect2i] = []
	workshop_regions.assign(Workshop.BUTTONS.values())
	assert(workshop_regions.size() == 3)
	for rect in workshop_regions: assert(rect.size == Vector2i(18, 18))
	for entry in [{"size": Workshop.SIZE, "picture": Workshop.ART_HEIGHT, "regions": workshop_regions}, {"size": Mini.SIZE, "picture": Mini.ART_HEIGHT, "regions": []}]:
		var size: Vector2i = entry.size
		var regions: Array[Rect2i] = []
		regions.assign(entry.regions)
		assert(Bridge.valid_regions(size, entry.picture, regions))
		# Every logical point of the enlarged bottom band belongs to the game.
		for y in range(entry.picture, size.y):
			for x in range(size.x): assert(not Bridge.passes_picture_input(Vector2(x, y), size, entry.picture, regions))
		for point in [Vector2(0, 0), Vector2(size.x - 0.01, entry.picture - 0.01)]:
			assert(Bridge.passes_picture_input(point, size, entry.picture, regions))
		for rect in regions:
			assert(not Bridge.passes_picture_input(Vector2(rect.position), size, entry.picture, regions))
			assert(not Bridge.passes_picture_input(Vector2(rect.end) - Vector2(0.01, 0.01), size, entry.picture, regions))
			assert(Bridge.passes_picture_input(Vector2(rect.end), size, entry.picture, regions))
		for scale in [1.0, 1.25, 1.5, 2.0]:
			for point in [Vector2(10, entry.picture - 0.01), Vector2(10, entry.picture), Vector2(size.x - 0.01, size.y - 0.01)]:
				var physical: Vector2 = point * scale
				var normalized := Vector2(physical.x * size.x / (size.x * scale), physical.y * size.y / (size.y * scale))
				assert(Bridge.passes_picture_input(normalized, size, entry.picture, regions) == (point.y < entry.picture))
		var bridge := CountingBridge.new()
		bridge.configure(size, entry.picture, regions)
		var count := bridge.stop_count
		bridge.configure(size, entry.picture, regions)
		assert(bridge.stop_count == count, "Unchanged current layout does not restart routing")
		bridge.free()
