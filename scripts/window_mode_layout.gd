extends RefCounted
## Pure geometry: keep the right-hand toolbar buttons under the same screen point.

static func fixed_toolbar_position(previous: Rect2i, previous_toolbar_height: int, next_size: Vector2i, next_toolbar_height: int) -> Vector2i:
	var anchor := previous.position + Vector2i(previous.size.x, previous.size.y - previous_toolbar_height / 2)
	return anchor - Vector2i(next_size.x, next_size.y - next_toolbar_height / 2)

static func keep_on_screen(position: Vector2i, size: Vector2i, usable: Rect2i) -> Vector2i:
	var maximum := usable.end - size
	return Vector2i(clampi(position.x, usable.position.x, maxi(usable.position.x, maximum.x)), clampi(position.y, usable.position.y + 32, maxi(usable.position.y + 32, maximum.y)))
