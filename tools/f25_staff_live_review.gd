extends SceneTree
## Isolated live review only: run in a fixture containing res://review.json.
## Frames are shown in a 96x144 display area without resampling. item.scale is optional.

const INPUT_PATH := "res://review.json"
const OBSERVATION_PATH := "res://playback-observation.json"
const DISPLAY_SIZE := Vector2(96, 144)
const CONTACT_Y := 141.0
const SAMPLE_SECONDS := 0.5
const FIRST_WRITE_SECONDS := 20.0

var _ready := false
var _playing := true
var _speed := 1.0
var _wall_seconds := 0.0
var _animation_seconds := 0.0
var _sample_at := 0.0
var _write_at := FIRST_WRITE_SECONDS
var _reset_generation := 0
var _space_was_down := false
var _r_was_down := false
var _texture_cache: Dictionary = {}
var _items: Array[Dictionary] = []
var _samples: Array[Dictionary] = []
var _events: Array[Dictionary] = []
var _pause_button: Button
var _status: Label
var _speed_option: OptionButton
var _review_title := "직원 움직임 실제 속도 비교"
var _save_count := 0
var _capture_after := -1.0
var _capture_path := "res://live-review.png"
var _capture_pending := false
var _captured := false
var _quit_after := -1.0


func _initialize() -> void:
	_parse_arguments()
	call_deferred("_build_review")


func _parse_arguments() -> void:
	var arguments := OS.get_cmdline_user_args()
	for index in range(arguments.size()):
		if arguments[index] == "--capture-after" and index + 1 < arguments.size():
			_capture_after = float(arguments[index + 1])
		if arguments[index] == "--capture-path" and index + 1 < arguments.size():
			_capture_path = arguments[index + 1]
		if arguments[index] == "--quit-after" and index + 1 < arguments.size():
			_quit_after = float(arguments[index + 1])


func _build_review() -> void:
	if not FileAccess.file_exists(INPUT_PATH):
		_fail("Missing isolated fixture: " + INPUT_PATH)
		return
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(INPUT_PATH)) != OK:
		_fail("Invalid review.json: " + parser.get_error_message())
		return
	if not parser.data is Dictionary:
		_fail("review.json must be an object.")
		return
	var specification: Dictionary = parser.data
	_review_title = str(specification.get("title", _review_title))
	var groups: Array = specification.get("groups", [])
	if groups.is_empty():
		_fail("review.json has no groups.")
		return
	var window := get_root()
	window.title = _review_title
	window.size = Vector2i(1040, 800)
	window.min_size = Vector2i(900, 720)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	window.close_requested.connect(_close_review)
	var canvas := Panel.new()
	canvas.name = "LiveReview"
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_theme_stylebox_override("panel", _panel_style(Color("f4f2e9")))
	canvas.theme = _review_theme()
	window.add_child(canvas)
	var margins := MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margins.add_theme_constant_override("margin_" + side, 12)
	canvas.add_child(margins)
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 6)
	margins.add_child(main)
	var heading := _label(_review_title, 21)
	heading.add_theme_color_override("font_color", Color("241c32"))
	main.add_child(heading)
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 12)
	main.add_child(toolbar)
	_pause_button = _button("일시정지 · Space", _toggle_play)
	toolbar.add_child(_pause_button)
	toolbar.add_child(_button("처음부터 · R", _restart))
	toolbar.add_child(_label("재생 속도", 14))
	_speed_option = OptionButton.new()
	_speed_option.focus_mode = Control.FOCUS_NONE
	_speed_option.add_item("0.5×", 0)
	_speed_option.add_item("1× · 실제 속도", 1)
	_speed_option.add_item("2×", 2)
	_speed_option.select(1)
	_speed_option.item_selected.connect(_change_speed)
	toolbar.add_child(_speed_option)
	var scale_note := _label("모두 표시 96×144 · 원본 정수 배율 · 발 기준선", 13)
	scale_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	toolbar.add_child(scale_note)
	_status = _label("이미지 불러오는 중…", 12)
	main.add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 8)
	scroll.add_child(rows)
	for group_index in range(groups.size()):
		if not groups[group_index] is Dictionary:
			_fail("Every group must be an object.")
			return
		var group: Dictionary = groups[group_index]
		var group_label := str(group.get("label", "그룹 " + str(group_index + 1)))
		var group_box := VBoxContainer.new()
		group_box.add_theme_constant_override("separation", 2)
		rows.add_child(group_box)
		group_box.add_child(_label(group_label, 15))
		var cards := HBoxContainer.new()
		cards.add_theme_constant_override("separation", 12)
		group_box.add_child(cards)
		var entries: Array = group.get("items", [])
		for entry in entries:
			if not entry is Dictionary:
				_fail("Every item must be an object.")
				return
			var item := _prepare_item(entry, group_index, group_label)
			if item.is_empty():
				return
			_add_card(cards, item)
			_items.append(item)
	_ready = true
	_events.append({"wall_seconds": 0.0, "event": "started", "speed": 1.0})
	_update_sprites(0.0)
	_take_sample()
	_sample_at = SAMPLE_SECONDS
	print("F25_LIVE_REVIEW_READY " + JSON.stringify({"items": _items.size(), "groups": groups.size(), "speed": _speed, "observation": OBSERVATION_PATH}))


func _review_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 14
	var candidates := ["res://assets/fonts/pretendard/Pretendard-Regular.otf", "res://Pretendard-Regular.otf", "res://font.otf"]
	for candidate in candidates:
		if FileAccess.file_exists(candidate):
			var font := FontFile.new()
			if font.load_dynamic_font(candidate) == OK:
				result.default_font = font
				return result
	var fallback := SystemFont.new()
	fallback.font_names = PackedStringArray(["Malgun Gothic", "Noto Sans CJK KR", "sans-serif"])
	result.default_font = fallback
	return result


func _prepare_item(entry: Dictionary, group_index: int, group_label: String) -> Dictionary:
	var id := str(entry.get("id", ""))
	var raw_frames: Array = entry.get("frames", [])
	if id.is_empty() or raw_frames.is_empty():
		_fail("Every item needs id and frames.")
		return {}
	var frames: Array[Dictionary] = []
	var sum_ms := 0.0
	var dimensions := Vector2i.ZERO
	var scale := float(entry.get("scale", 0.0))
	for raw_frame in raw_frames:
		if not raw_frame is Dictionary:
			_fail(id + ": every frame must be an object.")
			return {}
		var frame_path := str(raw_frame.get("path", ""))
		var duration_ms := float(raw_frame.get("duration_ms", 0.0))
		if duration_ms <= 0.0:
			_fail(id + ": duration_ms must be positive.")
			return {}
		var resource := _read_image(frame_path)
		if resource.is_empty():
			return {}
		var frame_size: Vector2i = resource["size"]
		if dimensions == Vector2i.ZERO:
			dimensions = frame_size
			if scale <= 0.0:
				scale = DISPLAY_SIZE.x / float(dimensions.x)
			if not is_equal_approx(scale, roundf(scale)) or scale < 1.0 or Vector2(dimensions) * scale != DISPLAY_SIZE:
				_fail(id + ": image × integer item.scale must equal 96×144.")
				return {}
		elif dimensions != frame_size:
			_fail(id + ": frame dimensions differ.")
			return {}
		frames.append({"path": frame_path, "duration_ms": duration_ms, "start_ms": sum_ms, "end_ms": sum_ms + duration_ms, "resource": resource})
		sum_ms += duration_ms
	var loop_ms := float(entry.get("loop_ms", sum_ms))
	if absf(loop_ms - sum_ms) > 0.1:
		_fail(id + ": loop_ms must equal the sum of frame durations. " + str(loop_ms) + " != " + str(sum_ms))
		return {}
	return {"id": id, "name": str(entry.get("name", id)), "group_index": group_index, "group": group_label,
		"frames": frames, "loop_ms": loop_ms, "scale": scale, "source_size": dimensions,
		"current_frame": -1, "current_loop": 0, "cycles_observed": 0, "seen": {}, "state_seconds": {}, "transitions": 0}


func _read_image(frame_path: String) -> Dictionary:
	if _texture_cache.has(frame_path):
		return _texture_cache[frame_path]
	if not frame_path.begins_with("res://") or not FileAccess.file_exists(frame_path):
		_fail("Frame path must be an existing fixture res:// file: " + frame_path)
		return {}
	var image := Image.new()
	var decode_error := image.load_png_from_buffer(FileAccess.get_file_as_bytes(frame_path))
	if decode_error != OK or image.is_empty():
		_fail("Could not decode " + frame_path)
		return {}
	var used := image.get_used_rect()
	var bottom := -1
	var contacts: Array[int] = []
	if used.size.y > 0:
		bottom = used.end.y - 1
		for x in range(image.get_width()):
			if image.get_pixel(x, bottom).a > 0.0:
				contacts.append(x)
	var resource := {"texture": ImageTexture.create_from_image(image), "size": image.get_size(), "used_rect": [used.position.x, used.position.y, used.size.x, used.size.y], "opaque_bottom": bottom, "contact_columns": contacts}
	_texture_cache[frame_path] = resource
	return resource


func _add_card(parent: HBoxContainer, item: Dictionary) -> void:
	var card := VBoxContainer.new()
	card.custom_minimum_size.x = 164
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_constant_override("separation", 2)
	parent.add_child(card)
	var name_label := _label(str(item["name"]), 14)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(name_label)
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(164, 144)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(stage)
	var background := ColorRect.new()
	background.color = Color("e0e7db")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(background)
	var ground := ColorRect.new()
	ground.color = Color("a9b5a3")
	ground.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	ground.offset_left = 8
	ground.offset_right = -8
	ground.offset_top = CONTACT_Y
	ground.offset_bottom = CONTACT_Y + 1.0
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(ground)
	var sprite := TextureRect.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_SCALE
	sprite.size = DISPLAY_SIZE
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(sprite)
	var frame_label := _label("", 12)
	frame_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(frame_label)
	item["sprite"] = sprite
	item["stage"] = stage
	item["frame_label"] = frame_label


func _process(delta: float) -> bool:
	if not _ready:
		return false
	var space_down := Input.is_physical_key_pressed(KEY_SPACE)
	var r_down := Input.is_physical_key_pressed(KEY_R)
	if space_down and not _space_was_down:
		_toggle_play()
	if r_down and not _r_was_down:
		_restart()
	_space_was_down = space_down
	_r_was_down = r_down
	_wall_seconds += delta
	if _playing:
		_animation_seconds += delta * _speed
	_update_sprites(delta)
	if _wall_seconds >= _sample_at:
		_take_sample()
		_sample_at = _wall_seconds + SAMPLE_SECONDS
	if _wall_seconds >= _write_at:
		_save_observation("periodic")
		_write_at = _wall_seconds + 10.0
	if _capture_after >= 0.0 and _wall_seconds >= _capture_after and not _captured and not _capture_pending:
		_capture_pending = true
		call_deferred("_capture_frame")
	if _quit_after > 0.0 and _wall_seconds >= _quit_after:
		_take_sample()
		_save_observation("timed_finish")
		_ready = false
		quit()
	return false


func _update_sprites(delta: float) -> void:
	for item in _items:
		var frames: Array = item["frames"]
		var loop_ms: float = item["loop_ms"]
		var local_ms := fposmod(_animation_seconds * 1000.0, loop_ms)
		var frame_index := frames.size() - 1
		for index in range(frames.size()):
			if local_ms < float(frames[index]["end_ms"]):
				frame_index = index
				break
		var frame: Dictionary = frames[frame_index]
		var resource: Dictionary = frame["resource"]
		var sprite: TextureRect = item["sprite"]
		var stage: Control = item["stage"]
		sprite.position = Vector2(roundf((stage.size.x - DISPLAY_SIZE.x) / 2.0), 0.0)
		sprite.size = DISPLAY_SIZE
		sprite.texture = resource["texture"]
		var current_loop := int(floor(_animation_seconds * 1000.0 / loop_ms))
		item["cycles_observed"] = int(item["cycles_observed"]) + maxi(0, current_loop - int(item["current_loop"]))
		item["current_loop"] = current_loop
		if int(item["current_frame"]) != frame_index:
			item["transitions"] = int(item["transitions"]) + 1
		item["current_frame"] = frame_index
		var seen: Dictionary = item["seen"]
		seen[str(frame_index)] = true
		var seconds: Dictionary = item["state_seconds"]
		seconds[str(frame_index)] = float(seconds.get(str(frame_index), 0.0)) + delta
		var frame_label: Label = item["frame_label"]
		frame_label.text = "프레임 %d/%d · %.2f / %.2f초" % [frame_index + 1, frames.size(), local_ms / 1000.0, loop_ms / 1000.0]
	_status.text = "%s · %.1f× · 재생 %.2f초 / 관찰 %.1f초 · %s" % ["재생 중" if _playing else "일시정지", _speed, _animation_seconds, _wall_seconds, "20초부터 관찰 기록 저장" if _save_count == 0 else "관찰 기록 저장됨 · 창은 계속 재생"]


func _toggle_play() -> void:
	_playing = not _playing
	_pause_button.text = "일시정지 · Space" if _playing else "재생 · Space"
	_events.append({"wall_seconds": _wall_seconds, "event": "play" if _playing else "pause", "animation_seconds": _animation_seconds})


func _restart() -> void:
	_animation_seconds = 0.0
	_reset_generation += 1
	for item in _items:
		item["current_loop"] = 0
		item["current_frame"] = -1
	_events.append({"wall_seconds": _wall_seconds, "event": "reset", "generation": _reset_generation})
	_update_sprites(0.0)


func _change_speed(index: int) -> void:
	_speed = [0.5, 1.0, 2.0][index]
	_events.append({"wall_seconds": _wall_seconds, "event": "speed", "speed": _speed, "animation_seconds": _animation_seconds})


func _take_sample() -> void:
	var states: Array[Dictionary] = []
	for item in _items:
		var index: int = item["current_frame"]
		var frame: Dictionary = item["frames"][index]
		var resource: Dictionary = frame["resource"]
		var sprite: TextureRect = item["sprite"]
		var stage: Control = item["stage"]
		var scale: float = item["scale"]
		var visible_bottom := (float(resource["opaque_bottom"]) + 1.0) * scale
		states.append({"id": item["id"], "group_index": item["group_index"], "frame_index": index,
			"loop": item["current_loop"], "local_ms": fposmod(_animation_seconds * 1000.0, float(item["loop_ms"])),
			"sprite_global_top_left": [sprite.global_position.x, sprite.global_position.y],
			"pixel_aligned": sprite.global_position.is_equal_approx(sprite.global_position.round()),
			"display_size": [sprite.size.x, sprite.size.y], "scale": scale,
			"source_opaque_bottom": resource["opaque_bottom"], "source_contact_columns": resource["contact_columns"],
			"contact_display_y": visible_bottom, "expected_contact_display_y": CONTACT_Y,
			"contact_matches": is_equal_approx(visible_bottom, CONTACT_Y),
			"global_ground_y": stage.global_position.y + CONTACT_Y})
	_samples.append({"wall_seconds": _wall_seconds, "animation_seconds": _animation_seconds,
		"speed": _speed, "playing": _playing, "reset_generation": _reset_generation, "items": states})
	# Keep ten minutes of compact samples when the review is left open for a long time.
	if _samples.size() > 1200:
		_samples.pop_front()


func _save_observation(reason: String) -> void:
	var summaries: Array[Dictionary] = []
	for item in _items:
		var observed: Array[int] = []
		for key in item["seen"]:
			observed.append(int(key))
		observed.sort()
		var dimensions: Vector2i = item["source_size"]
		summaries.append({"id": item["id"], "name": item["name"], "group": item["group"],
			"group_index": item["group_index"], "source_size": [dimensions.x, dimensions.y],
			"display_size": [96, 144], "integer_scale": item["scale"], "loop_ms": item["loop_ms"],
			"frame_count": item["frames"].size(), "observed_frame_indices": observed,
			"rendered_wall_seconds_by_frame": item["state_seconds"], "transitions_observed": item["transitions"],
			"completed_loops_observed": item["cycles_observed"]})
	var report := {"schema_version": 1, "title": _review_title, "reason": reason,
		"engine": Engine.get_version_info(), "wall_seconds": _wall_seconds, "animation_seconds": _animation_seconds,
		"default_speed": 1.0, "current_speed": _speed, "playing": _playing,
		"requested_sample_interval_seconds": SAMPLE_SECONDS, "first_write_after_seconds": FIRST_WRITE_SECONDS,
		"note": "Live delta-based isolated review. Timed segments are sampled by the actual display loop; this is telemetry, not a claim of artistic approval.",
		"events": _events, "items": summaries, "samples": _samples}
	var file := FileAccess.open(OBSERVATION_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not write isolated playback observation: " + str(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	_save_count += 1
	print("F25_LIVE_OBSERVATION_SAVED " + JSON.stringify({"wall_seconds": _wall_seconds, "samples": _samples.size(), "reason": reason}))


func _capture_frame() -> void:
	await RenderingServer.frame_post_draw
	var screenshot := get_root().get_texture().get_image()
	var result := screenshot.save_png(_capture_path)
	_captured = result == OK
	_capture_pending = false
	_events.append({"wall_seconds": _wall_seconds, "event": "capture", "path": _capture_path, "error": result})
	print("F25_LIVE_CAPTURE " + JSON.stringify({"path": _capture_path, "error": result}))


func _close_review() -> void:
	if _ready:
		_take_sample()
		_save_observation("window_closed")
	quit()


func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	return button


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("344238"))
	return label


func _panel_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	return style


func _fail(message: String) -> void:
	push_error("F25 live review: " + message)
	quit(1)
