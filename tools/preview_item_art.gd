extends SceneTree
const ItemArt = preload("res://scripts/item_art.gd")
const Shop = preload("res://scripts/shop.gd")
var shop: Control


class DesignBoard extends Control:
	const Art = preload("res://scripts/item_art.gd")
	var font := SystemFont.new()
	var textures := {}
	var growth: Texture2D

	func _ready() -> void:
		font.font_names = PackedStringArray(["Malgun Gothic", "sans-serif"])
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		for id in ["health", "mana", "moon", "purify", "agility", "herb", "starleaf", "mushroom"]:
			textures[id] = Art.icon(id)
		growth = load("res://assets/items_v1/starleaf_growth.png")

	func _text(value: String, point: Vector2, font_size: int, color := Color("f0dfc4")) -> void:
		draw_string(font, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

	func _sprite(id: String, rect: Rect2) -> void:
		var texture: Texture2D = textures[id]
		var factor := minf(rect.size.x / texture.get_width(), rect.size.y / texture.get_height())
		var extent := texture.get_size() * factor
		draw_texture_rect(texture, Rect2(rect.position + (rect.size - extent) / 2, extent), false)

	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1040, 740), Color("211b2d"))
		_text("달그늘 물약상점", Vector2(36, 52), 30)
		_text("물약 5종 · 재료 3종", Vector2(36, 82), 14, Color("b4a4bd"))
		var potions := ["health", "mana", "moon", "purify", "agility"]
		var titles := ["체력 물약", "마나 물약", "달빛 물약", "정화 물약", "민첩 물약"]
		var notes := ["분홍 · 하트", "파랑 · 별", "보라 · 초승달", "민트 · 잎", "금빛 · 번개"]
		for i in potions.size():
			var x := 36 + i * 196
			draw_rect(Rect2(x, 110, 184, 252), Color("2c2437"))
			draw_rect(Rect2(x, 110, 184, 3), Color(["ee82ac", "78b5ed", "c6aeed", "9addba", "e9c573"][i]))
			_sprite(potions[i], Rect2(x + 44, 132, 96, 120))
			_text(titles[i], Vector2(x + 20, 294), 18)
			_text(notes[i], Vector2(x + 20, 324), 13, Color("b4a4bd"))
		var materials := ["herb", "mushroom", "starleaf"]
		var names := ["기본 약초", "달빛 버섯", "별잎"]
		var captions := ["모든 물약에 쓰는 녹색 잎", "마나 물약의 추가 재료", "특수 물약 3종의 공통 재료"]
		for i in materials.size():
			var x := 36 + i * 328
			draw_rect(Rect2(x, 388, 316, 256), Color("2c2437"))
			_sprite(materials[i], Rect2(x + 18, 408, 96, 120))
			_text(names[i], Vector2(x + 132, 455), 19)
			_text("자동 재배" if i != 1 else "자동 발주", Vector2(x + 132, 484), 13, Color("efc77c"))
			_text(captions[i], Vector2(x + 18, 560), 13, Color("b4a4bd"))
			if i == 2:
				for frame in range(4):
					draw_texture_rect_region(growth, Rect2(x + 22 + frame * 68, 582, 32, 40), Rect2((frame % 2) * 32, (frame / 2) * 40, 32, 40))
			else:
				_text("약초 2 + 버섯 1 → 마나" if i == 1 else "약초 2 → 체력", Vector2(x + 18, 601), 14)
		_text("특수 레시피: 기본 약초 2 + 별잎 1", Vector2(36, 694), 16, Color("efc77c"))
		_text("기존 체력·마나·버섯 아트 유지 · 신규 달빛·정화·민첩·약초·별잎 디자인", Vector2(36, 720), 12, Color("b4a4bd"))


func _initialize() -> void:
	set_meta("isolated_preview", true)
	call_deferred("_run")


func _capture(path: String, viewport: Viewport) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().save_png(path) == OK)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://.verification")
	for kind in [false, true, "moon", "purify", "agility"]:
		var texture := ItemArt.bottle(kind)
		assert(texture != null and texture.get_size() == Vector2(12, 16))
		assert(texture.get_image().get_pixel(0, 0).a < 0.01)
	shop = Shop.new()
	root.add_child(shop)
	shop.set_process(false)
	shop.art.set_process(false)
	root.always_on_top = false
	shop.state.gold = 2500
	shop.state.progression.reputation = 40
	shop.state.progression.owned = ["moon", "purify", "agility"]
	shop.state.progression.rare_herbs = 6
	shop.state.progression.rare_growth = 9.0
	shop.state.stock = 10
	shop.state.mana_stock = 2
	shop.state.inventory = [false, true, "moon", "purify", "agility", false, true, "moon", "purify", "agility"]
	shop._set_window_mode(shop.State.WindowMode.WORKSHOP)
	shop._update_interface()
	shop.art._process(0.0)
	await _capture("res://.verification/items-workshop.png", root)
	assert(shop.art.bottles.inventory_order() == shop.state.inventory_order())
	shop.open_management()
	shop.management.select_page(1)
	await _capture("res://.verification/items-recipes.png", shop.management)
	shop.management.select_page(0)
	shop.management.scroll.scroll_vertical = 190
	await _capture("res://.verification/items-inventory.png", shop.management)
	shop.management.hide()
	shop.hide()
	root.content_scale_size = Vector2i(1040, 740)
	root.size = Vector2i(1040, 740)
	root.transparent = false
	root.transparent_bg = false
	var board := DesignBoard.new()
	board.size = Vector2(1040, 740)
	root.add_child(board)
	await _capture("res://assets/items_v1/design-preview.png", root)
	print("ITEM ART PREVIEW PASS: all five bottle textures; transparency; mixed FIFO; recipe, material and inventory icons; isolated screenshots")
	shop.management.queue_free()
	quit()
