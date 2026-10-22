extends SceneTree
## Offscreen design sheets; no shared shop scripts or player saves are loaded.
const ROOT := "res://assets/content_expansion_v1/"
var catalog: Dictionary


class Board extends Control:
	var entries: Array = []
	var heading := ""
	var columns := 4
	var equipment := false
	var growth := false
	var font := SystemFont.new()
	var images := {}

	func _ready() -> void:
		font.font_names = PackedStringArray(["Malgun Gothic", "sans-serif"])
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		for entry in entries:
			for path in [entry["icon_path"]] + entry.get("tier_paths", []) + ([entry["bottle_path"]] if entry.has("bottle_path") else []) + ([entry["growth_path"]] if entry.has("growth_path") else []):
				if FileAccess.file_exists(path): images[path] = ImageTexture.create_from_image(Image.load_from_file(path))

	func _text(value: String, point: Vector2, font_size: int, color := Color("f0dfc4")) -> void:
		draw_string(font, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

	func _sprite(path: String, position: Vector2, scale: int) -> void:
		if images.has(path):
			var texture: Texture2D = images[path]
			draw_texture_rect(texture, Rect2(position, texture.get_size() * scale), false)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("211b2d"))
		_text("달그늘 · " + heading, Vector2(24, 38), 23)
		_text("확장 디자인 후보 · 게임 미적용 · 신규/재사용은 catalog.json에 기록", Vector2(24, 64), 12, Color("b4a4bd"))
		var width := (size.x - 48) / columns
		var height := 204 if equipment or growth else 176
		for i in entries.size():
			var entry: Dictionary = entries[i]
			var x := 24 + (i % columns) * width
			var y := 88 + (i / columns) * height
			draw_rect(Rect2(x, y, width - 8, height - 8), Color("2c2437"))
			_text(entry["name"], Vector2(x + 12, y + 25), 13)
			var status_text := "재사용" if entry.get("reused", false) else "신규"
			if entry.has("base_source"): status_text = "기본 재사용 · 상위 신규"
			var status_width := font.get_string_size(status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			_text(status_text, Vector2(x + (12 if columns >= 8 else width - status_width - 18), y + (142 if columns >= 8 else 25)), 10, Color("efc77c"))
			if equipment:
				for tier in 3:
					_sprite(entry["tier_paths"][tier], Vector2(x + 20 + tier * 120, y + 43), 3)
					_text(["기본", "개량", "고급"][tier], Vector2(x + 43 + tier * 120, y + 180), 11)
			elif growth:
				_sprite(entry["icon_path"], Vector2(x + 8, y + 48), 2)
				if images.has(entry.get("growth_path", "")):
					var texture: Texture2D = images[entry["growth_path"]]
					for frame in 4:
						draw_texture_rect_region(texture, Rect2(x + 80 + (frame % 2) * 40, y + 42 + (frame / 2) * 55, 32, 40), Rect2((frame % 2) * 32, (frame / 2) * 40, 32, 40))
				_text("재료 / 성장 4단계", Vector2(x + 12, y + 179), 11, Color("b4a4bd"))
			else:
				_sprite(entry["icon_path"], Vector2(x + 12, y + 39), 2)
				if entry.has("bottle_path"):
					_sprite(entry["bottle_path"], Vector2(x + 83, y + 63), 1)
					_sprite(entry["bottle_path"], Vector2(x + 78, y + 92), 2)
					_text("1× / 2×", Vector2(x + 74, y + 139), 10, Color("b4a4bd"))
				_text(entry["id"].left(22), Vector2(x + 10, y + 158), 9, Color("b4a4bd"))


func _initialize() -> void:
	call_deferred("_run")


func _sheet(entries: Array, heading: String, filename: String, columns: int, equipment := false, growth := false) -> void:
	if entries.is_empty(): return
	var height := 204 if equipment or growth else 176
	var rows := ceili(float(entries.size()) / columns)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1040, 96 + rows * height)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var board := Board.new()
	board.entries = entries
	board.heading = heading
	board.columns = columns
	board.equipment = equipment
	board.growth = growth
	board.size = viewport.size
	viewport.add_child(board)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().save_png(ROOT + "previews/" + filename + ".png") == OK)
	viewport.queue_free()
	await process_frame


func _run() -> void:
	root.size = Vector2i(64, 64)
	root.always_on_top = false
	catalog = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "catalog.json"))
	var available: Array = catalog["assets"].filter(func(e): return FileAccess.file_exists(e["icon_path"]))
	var first_ids := ["vigor", "antidote", "fortune", "focus", "restoration", "growth", "dewgrass", "silver_moss"]
	await _sheet(available.filter(func(e): return e["id"] in first_ids), "첫 묶음 · 숲과 온실", "first-batch", 4)
	for category in ["potions", "materials", "regions", "equipment", "employees", "families"]:
		var entries := available.filter(func(e): return e["category"] == category)
		await _sheet(entries, {"potions":"물약 32종", "materials":"재료 11종", "regions":"원정 8지역", "equipment":"설비 8계열 · 외형 3단계", "employees":"직원 4역할", "families":"물약 강화 4계열"}[category], category, 8 if category == "potions" else (2 if category == "equipment" else 4), category == "equipment")
	await _sheet(available.filter(func(e): return e["category"] == "materials" and e.has("growth_path")), "재배 품종 · 성장 외형", "growth", 4, false, true)
	print("EXPANSION PREVIEW: offscreen comparison sheets saved; native icon/bottle sizes included")
	quit()
