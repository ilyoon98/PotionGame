extends SceneTree
## Headless geometry only: never move a native window or inject desktop input.
const Layout = preload("res://scripts/window_mode_layout.gd")
const Shop = preload("res://scripts/shop.gd")

func _initialize() -> void:
	assert(DisplayServer.get_name() == "headless")
	var stages := [
		{"size": Shop.WorkshopAssets.SIZE, "bar": Shop.WorkshopAssets.BAR_HEIGHT},
		{"size": Shop.MiniWorkshop.SIZE, "bar": Shop.MiniWorkshop.SIZE.y - Shop.MiniWorkshop.ART_HEIGHT},
		{"size": Shop.MINIMAL_SIZE, "bar": Shop.WorkshopAssets.BAR_HEIGHT},
	]
	assert(stages[0].size == Vector2i(540, 300) and stages[0].bar == 52)
	assert(stages[1].size == Vector2i(256, 172) and stages[1].bar == 44)
	assert(stages[2].size == Vector2i(320, 124) and stages[2].bar == 52)
	# Main -> character -> information -> character -> main, plus direct shortcuts.
	for start in [Vector2i(200, 300), Vector2i(-1400, 400), Vector2i(1280, -700)]:
		for path in [[0, 1, 2, 1, 0], [0, 2, 1, 0], [1, 2, 1], [0, 0]]:
			var position: Vector2i = start
			var first: Dictionary = stages[path[0]]
			var anchor := position + Vector2i(first.size.x, first.size.y - first.bar / 2)
			for i in range(1, path.size()):
				var before: Dictionary = stages[path[i - 1]]
				var after: Dictionary = stages[path[i]]
				var old_position := position
				position = Layout.fixed_toolbar_position(Rect2i(position, before.size), before.bar, after.size, after.bar)
				assert(position + Vector2i(after.size.x, after.size.y - after.bar / 2) == anchor, "Toolbar center/right edge cannot jump during mode changes")
				if after.size.y < before.size.y: assert(position.y > old_position.y, "The top edge moves downward when shrinking")
				if after.size.y > before.size.y: assert(position.y < old_position.y, "Expansion restores upward from the toolbar")
			if path[0] == path[-1]: assert(position == start, "Repeated shrinking/expanding cannot drift")
	# Dragging the smaller screen defines a new anchor instead of snapping back.
	var dragged := Rect2i(Vector2i(700, 650), Shop.MiniWorkshop.SIZE)
	var expanded := Layout.fixed_toolbar_position(dragged, 44, Shop.WorkshopAssets.SIZE, 52)
	assert(expanded + Vector2i(Shop.WorkshopAssets.SIZE.x, 274) == dragged.position + Vector2i(256, 150))
	# Clamp against the actual monitor work area, including negative monitor coordinates.
	for usable in [Rect2i(0, 0, 1920, 1040), Rect2i(-1920, 0, 1920, 1040), Rect2i(0, -1080, 1920, 1040)]:
		for point in [usable.position - Vector2i(100, 100), usable.end + Vector2i(100, 100), usable.position + Vector2i(500, 400)]:
			var clamped := Layout.keep_on_screen(point, Shop.WorkshopAssets.SIZE, usable)
			assert(usable.encloses(Rect2i(clamped, Shop.WorkshopAssets.SIZE)))
			assert(clamped.y >= usable.position.y + 32)
			if usable.encloses(Rect2i(point, Shop.WorkshopAssets.SIZE)) and point.y >= usable.position.y + 32: assert(clamped == point)
	# Information mode is wider than character mode; its right-hand controls still align.
	assert(Layout.fixed_toolbar_position(Rect2i(200, 300, 256, 172), 44, Vector2i(320, 124), 52) == Vector2i(136, 352))
	print("WINDOW MODE ANCHOR PASS: 540x300/256x172/320x124 keep 52/44/52px toolbar center/right anchor; top shrinks downward; restoration/no drift; shortcuts/dragged anchor and monitor bounds; pure headless geometry")
	quit()
