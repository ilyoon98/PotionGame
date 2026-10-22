extends RefCounted
## Visual state only. Sales and brewing are always decided by ShopState.

enum Visit { ABSENT, ARRIVING, WAITING }
const Layout = preload("res://scripts/workshop_layout.gd")
const OFFSCREEN_X := 464.0
const COUNTER_X := 350.0
const ARRIVAL_SECONDS := 0.85
const HANDOVER_SECONDS := 0.48
const DEPARTURE_SECONDS := 1.35

var elapsed := 0.0
var visit: Visit = Visit.ABSENT
var arrival_elapsed := 0.0
var customer_x := OFFSCREEN_X
var departing_elapsed := -1.0
var earned_gold := 0
var trade_interval := 3.2
var arrival_seconds := ARRIVAL_SECONDS
var departure_seconds := DEPARTURE_SECONDS
var handover_seconds := HANDOVER_SECONDS
var workshop_layout := false
var hold_seconds := 0.0
var pixel_room := false


func counter_x() -> float:
	return Layout.point("purchaseFeet").x if workshop_layout else 360.0 if pixel_room else COUNTER_X


func offscreen_x() -> float:
	return Layout.point("offscreenFeet").x if workshop_layout else OFFSCREEN_X


func handover_point() -> Vector2:
	return Layout.point("hand") if workshop_layout else Vector2(COUNTER_X + 23, 199)


func set_workshop_layout(enabled: bool) -> void:
	if workshop_layout == enabled: return
	workshop_layout = enabled
	# Keep the same visitor, transaction and animation time across view changes.
	if visit == Visit.ABSENT: customer_x = offscreen_x()
	elif visit == Visit.WAITING: customer_x = counter_x()
	else:
		customer_x = roundf(lerpf(offscreen_x(), counter_x(), clampf(arrival_elapsed / arrival_seconds, 0, 1)))


func sale(gold: int) -> void:
	var speed := minf(1.0, trade_interval / (3.2 if workshop_layout or pixel_room else 2.4))
	departure_seconds = (2.3 if workshop_layout or pixel_room else DEPARTURE_SECONDS) * speed
	handover_seconds = (0.85 if workshop_layout or pixel_room else HANDOVER_SECONDS) * speed
	hold_seconds = 0.35 * speed if workshop_layout or pixel_room else 0.0
	departing_elapsed = 0.0
	earned_gold = gold
	visit = Visit.ABSENT
	arrival_elapsed = 0.0
	customer_x = offscreen_x()


func close_shop() -> void:
	visit = Visit.ABSENT
	customer_x = offscreen_x()
	arrival_elapsed = 0.0
	departing_elapsed = -1.0
	earned_gold = 0


func tick(delta: float, is_open: bool, customer_phase: float, interval: float = 3.2) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	elapsed += delta
	trade_interval = interval
	if not is_open:
		close_shop()
		return
	if departing_elapsed >= 0.0:
		departing_elapsed += delta
		if departing_elapsed >= departure_seconds:
			departing_elapsed = -1.0
	if visit == Visit.ABSENT and departing_elapsed < 0.0 and customer_phase >= 0.34:
		visit = Visit.ARRIVING
		arrival_elapsed = 0.0
		arrival_seconds = ARRIVAL_SECONDS * minf(1.0, trade_interval / (3.2 if workshop_layout or pixel_room else 2.4))
	if visit == Visit.ARRIVING:
		arrival_elapsed = minf(arrival_seconds, arrival_elapsed + delta)
		customer_x = roundf(lerpf(offscreen_x(), counter_x(), arrival_elapsed / arrival_seconds))
		if arrival_elapsed >= arrival_seconds:
			visit = Visit.WAITING
	# WAITING persists across an empty-stock purchase attempt until a real sale.


func keeper_frame(is_brewing: bool) -> int:
	# animations_v1: idle, brew_1, brew_2, sell.
	if departing_elapsed >= 0.0 and departing_elapsed < handover_seconds + 0.2:
		return 3
	return 1 + (int(elapsed * 4.0) % 2) if is_brewing else 0


func visitor_frame() -> int:
	return 1 + (int(elapsed * 6.0) % 2) if visit == Visit.ARRIVING else 0


func departure_frame() -> int:
	return 3 if departing_elapsed < handover_seconds else 1 + (int(elapsed * 6.0) % 2)


func walk_start() -> float:
	return handover_seconds + hold_seconds


func departure_x() -> float:
	var progress := clampf((departing_elapsed - walk_start()) / (departure_seconds - walk_start()), 0.0, 1.0)
	return roundf(lerpf(counter_x(), offscreen_x(), progress))
