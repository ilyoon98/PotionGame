extends RefCounted
## Each owned bottle has exactly one visual location, including while moving.
const PixelCatalog = preload("res://scripts/pixel_art_catalog.gd")
const Layout = preload("res://scripts/workshop_layout.gd")
const CAPACITY := 12
const MAX_CAPACITY := 60
const WORKSHOP_VISIBLE_CAPACITY := 8
const RESERVE_POSITION := Vector2(386, 137)
const TRAVEL_SECONDS := 0.55
const SHIFT_SECONDS := 0.28
const SHIFT_DELAY := 0.08
const BREW_ORIGIN := Vector2(92, 149)
const BOTTLE_SIZE := Vector2(24, 32)
var slots: Array[Dictionary] = []
var workshop_layout := false
var pixel_room := false


func _init() -> void:
	for index in range(MAX_CAPACITY):
		slots.append({})


func slot_center(index: int) -> Vector2:
	if index >= visible_capacity(): return reserve_position()
	if workshop_layout or pixel_room:
		var center := Layout.slot_center(index) + (Vector2.ZERO if workshop_layout else Vector2(-57,5))
		if not slots[index].is_empty(): center.y -= (PixelCatalog.bottle_size(slots[index].mana).y - 12) * 1.5
		return center
	return Vector2(282 + (index % 6) * 20, 40 + (index / 6) * 26)


func brew_origin() -> Vector2:
	return Layout.point("brewOrigin") if workshop_layout else Vector2(70,170) if pixel_room else BREW_ORIGIN


func reserve_position() -> Vector2:
	return Layout.point("reserve") if workshop_layout else Vector2(390,164) if pixel_room else RESERVE_POSITION


static func handover_position(start: Vector2, finish: Vector2, progress: float, bottle_size: Vector2 = Vector2(24,36), table_anchor: Vector2 = Vector2(351,192)) -> Vector2:
	# Selected stock moves behind shelf boards to the sales counter, rests,
	# then flies below the face into the actual receiving palm.
	var p := clampf(progress, 0.0, 1.0)
	var table := Vector2(table_anchor.x, table_anchor.y - bottle_size.y / 2.0)
	if p < 0.27:
		return start.bezier_interpolate(Vector2(start.x, 165), table+Vector2(27,-12), table, p / 0.27).round()
	if p < 0.54: return table.round()
	return table.bezier_interpolate(table+Vector2(51,-18), finish+Vector2(-21,12), finish, (p-0.54)/0.46).round()


static func _brew_position(origin: Vector2, target: Vector2, progress: float) -> Vector2:
	# Keep incoming stock below both rows until it reaches its empty column.
	var staging := Vector2(target.x, 165)
	if progress < 0.68:
		return origin.bezier_interpolate(origin + Vector2(104, 8), staging - Vector2(32, 0), staging, smoothstep(0, 1, progress / 0.68))
	return staging.lerp(target, smoothstep(0, 1, (progress - 0.68) / 0.32))


static func _wrap_position(origin: Vector2, target: Vector2, progress: float, shelf_left: float = 315.0) -> Vector2:
	# A lower-row bottle goes around the shelf, rather than through either row.
	var left := shelf_left - 12
	var above := Vector2(left, -24)
	if origin.y > 34:
		var gap := Vector2(left, origin.y)
		if progress < 0.25: return origin.lerp(gap, smoothstep(0, 1, progress / 0.25))
		if progress < 0.55: return gap.lerp(above, smoothstep(0, 1, (progress - 0.25) / 0.30))
		if progress < 0.85: return above.lerp(Vector2(target.x, -24), smoothstep(0, 1, (progress - 0.55) / 0.30))
		return Vector2(target.x, -24).lerp(target, smoothstep(0, 1, (progress - 0.85) / 0.15))
	var aligned := Vector2(target.x, minf(origin.y, -24))
	if progress < 0.7: return origin.lerp(aligned, smoothstep(0, 1, progress / 0.7))
	return aligned.lerp(target, smoothstep(0, 1, (progress - 0.7) / 0.3))


static func _reserve_position(origin: Vector2, target: Vector2, progress: float) -> Vector2:
	# Rise beside the last column while that column's previous bottle moves left.
	var aligned := Vector2(origin.x, target.y)
	if progress < 0.75: return origin.lerp(aligned, smoothstep(0, 1, progress / 0.75))
	return aligned.lerp(target, smoothstep(0, 1, (progress - 0.75) / 0.25))


func visible_capacity() -> int:
	return WORKSHOP_VISIBLE_CAPACITY if workshop_layout or pixel_room else CAPACITY


func set_workshop_layout(enabled: bool) -> void:
	if workshop_layout == enabled: return
	var order := inventory_order()
	workshop_layout = enabled
	# A view change settles visual transfers, never changes the owned inventory.
	restore(order.size(), 0, order)


func position(index: int) -> Vector2:
	if index >= visible_capacity():
		return reserve_position()
	var bottle := slots[index]
	var progress := clampf((float(bottle["elapsed"]) - bottle["delay"]) / bottle["duration"], 0.0, 1.0)
	var eased := smoothstep(0.0, 1.0, progress)
	var origin: Vector2 = bottle["origin"]
	var target := slot_center(index)
	var point: Vector2
	if (workshop_layout or pixel_room) and bottle.get("path", "linear") == "brew":
		point = _brew_position(origin, target, progress)
	elif (workshop_layout or pixel_room) and bottle.get("path", "linear") == "wrap":
		point = _wrap_position(origin, target, progress, 315.0 if workshop_layout else 258.0)
	elif (workshop_layout or pixel_room) and bottle.get("path", "linear") == "reserve":
		point = _reserve_position(origin, target, progress)
	else:
		point = origin.lerp(target, eased)
		point.y -= sin(progress * PI) * bottle["arc"]
	return point.round()


func is_moving(index: int) -> bool:
	var bottle := slots[index]
	return not bottle.is_empty() and bottle["elapsed"] < bottle["delay"] + bottle["duration"]


func add(is_mana: Variant, animate: bool = true) -> void:
	for index in range(MAX_CAPACITY):
		if slots[index].is_empty():
			slots[index] = {"mana": is_mana, "elapsed": 0.0 if animate else TRAVEL_SECONDS,
				"origin": brew_origin(), "duration": TRAVEL_SECONDS, "delay": 0.0, "arc": 16.0,
				"path": "brew" if workshop_layout or pixel_room else "linear"}
			return


func take(selected: int = 0) -> Vector2:
	if selected < 0 or selected >= MAX_CAPACITY or slots[selected].is_empty():
		return brew_origin()
	var origin := position(selected)
	# Compact logical inventory immediately, but preserve each visible position.
	# Retargeting from that point also handles a sale during arrival or sliding.
	for index in range(selected + 1, MAX_CAPACITY):
		if slots[index].is_empty():
			slots[index - 1] = {}
			continue
		var previous_position := position(index)
		var bottle := slots[index]
		var remaining := maxf(0.0, bottle["duration"] + bottle["delay"] - bottle["elapsed"])
		var path := "linear"
		if (workshop_layout or pixel_room) and remaining > 0.0 and bottle.get("path", "linear") == "brew": path = "brew"
		elif (workshop_layout or pixel_room) and index < visible_capacity() and ((index == 4) or (remaining > 0.0 and bottle.get("path", "linear") == "wrap")):
			path = "wrap"
		elif (workshop_layout or pixel_room) and index == visible_capacity(): path = "reserve"
		bottle["origin"] = previous_position
		bottle["duration"] = maxf(SHIFT_SECONDS, remaining)
		bottle["delay"] = SHIFT_DELAY
		bottle["elapsed"] = 0.0
		bottle["arc"] = 0.0
		bottle["path"] = path
		slots[index - 1] = bottle
	slots[MAX_CAPACITY - 1] = {}
	return origin


func inventory_order() -> Array:
	var order: Array = []
	for bottle in slots:
		if not bottle.is_empty():
			order.append(bottle["mana"])
	return order


func tick(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	for bottle in slots:
		if not bottle.is_empty():
			bottle["elapsed"] = minf(bottle["duration"] + bottle["delay"], bottle["elapsed"] + delta)


func matches(stock: int, mana_stock: int) -> bool:
	var count := 0
	var mana := 0
	for bottle in slots:
		if not bottle.is_empty():
			count += 1
			mana += int(bottle["mana"] is bool and bottle["mana"])
	return count == stock and mana == mana_stock


func restore(stock: int, mana_stock: int, order: Array = []) -> void:
	for index in range(MAX_CAPACITY):
		slots[index] = {}
	for index in range(clampi(stock, 0, MAX_CAPACITY)):
		add(order[index] if order.size() == stock else index < mana_stock, false)
