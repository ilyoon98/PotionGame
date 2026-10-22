extends SceneTree
const Shop = preload("res://scripts/shop.gd")
const Art = preload("res://scripts/management_art.gd")


class IconBoard extends Control:
	const ManagementArt = preload("res://scripts/management_art.gd")
	var font := SystemFont.new()
	var textures := {}
	var ids := ["flow", "cauldron", "garden", "filter", "employee", "visitors", "basic", "expedition", "journey"]

	func _ready() -> void:
		font.font_names = PackedStringArray(["Malgun Gothic", "sans-serif"])
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		for id in ids: textures[id] = ManagementArt.icon(id)

	func _text(value: String, point: Vector2, font_size: int, color := Color("f0dfc4")) -> void:
		draw_string(font, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

	func _draw() -> void:
		draw_rect(Rect2(0, 0, 920, 730), Color("211b2d"))
		_text("달그늘 물약상점 · 관리 아이콘", Vector2(30, 46), 25)
		_text("설비 · 고용 · 레시피 · 원정", Vector2(30, 76), 14, Color("b4a4bd"))
		var titles := ["자동 운영", "솥 강화", "화분 강화", "정밀 여과기", "판매 보조 고용", "손님과 명성", "기본 레시피", "숲 원정", "원정 진행"]
		var notes := ["톱니바퀴와 물약", "물약 제조 솥", "약초 화분", "깔때기와 수집 병", "상점 앞치마", "손님과 금빛 별", "물약 제조서", "지도와 나침반", "지도와 나침반"]
		for i in ids.size():
			var x := 30 + (i % 3) * 296
			var y := 108 + (i / 3) * 184
			draw_rect(Rect2(x, y, 280, 168), Color("2c2437"))
			draw_rect(Rect2(x, y, 280, 2), Color("796449"))
			var texture: Texture2D = textures[ids[i]]
			var factor := minf(80.0 / texture.get_width(), 100.0 / texture.get_height())
			var extent := texture.get_size() * floorf(factor)
			draw_texture_rect(texture, Rect2(Vector2(x + 16, y + 30) + (Vector2(80, 100) - extent) / 2, extent), false)
			_text(titles[i], Vector2(x + 112, y + 74), 17)
			_text(notes[i], Vector2(x + 112, y + 104), 12, Color("b4a4bd"))
		_text("모든 관리 카드에 아이콘 적용 · 작은 크기에서 형태로 구분", Vector2(30, 692), 14, Color("efc77c"))
		_text("기존 솥·화분 그림 활용 · 원정 해금과 진행은 같은 지도 아이콘 사용", Vector2(30, 716), 12, Color("b4a4bd"))


func _initialize() -> void:
	set_meta("isolated_preview", true)
	call_deferred("_run")


func _capture(path: String, viewport: Viewport) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().save_png(path) == OK)
	if viewport is Window and viewport.get_script() == preload("res://scripts/management_panel.gd"):
		for id in viewport.rows:
			var row: Dictionary = viewport.rows[id]
			if row.has("icon") and row["panel"].is_visible_in_tree():
				assert(row["icon"].get_parent().size.y >= row["detail"].get_rect().end.y, "Card text overflows: " + id)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://.verification")
	var shop := Shop.new()
	root.add_child(shop)
	shop.set_process(false)
	root.always_on_top = false
	shop.state.gold = 2500
	shop.state.progression.reputation = 40
	shop.open_management()
	var snapshot: Dictionary = shop.state.to_data()
	await process_frame
	for id in Art.DESCRIPTIONS:
		var row: Dictionary = shop.management.rows[id]
		assert(row["icon"] != null and row["icon"].texture != null, "Missing management icon: " + id)
		assert(row["icon"].texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST)
	shop.management.select_page(0)
	await _capture("res://.verification/management-icons-operation.png", shop.management)
	shop.management.scroll.scroll_vertical = int(shop.management.rows["cauldron"]["panel"].position.y)
	await _capture("res://.verification/management-icons-equipment.png", shop.management)
	shop.management.scroll.scroll_vertical = int(shop.management.rows["employee"]["panel"].position.y)
	await _capture("res://.verification/management-icons-employment.png", shop.management)
	shop.management.select_page(1)
	await _capture("res://.verification/management-icons-recipes.png", shop.management)
	shop.management.select_page(2)
	await _capture("res://.verification/management-icons-expedition.png", shop.management)
	assert(shop.state.to_data() == snapshot, "Preview must preserve economy and progress")
	shop.management.hide()
	shop.hide()
	root.content_scale_size = Vector2i(920, 730)
	root.size = Vector2i(920, 730)
	root.transparent = false
	root.transparent_bg = false
	var board := IconBoard.new()
	board.size = Vector2(920, 730)
	root.add_child(board)
	await _capture("res://assets/management_v1/design-preview.png", root)
	print("MANAGEMENT ICONS PASS: nine management cards; all textures; nearest filtering; card text bounds; five native captures; preview preserves progress")
	shop.management.queue_free()
	quit()
