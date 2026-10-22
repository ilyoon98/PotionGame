extends SceneTree
## Pure visual fixtures: no window, native bridge, registry or player-save access.
const Motion = preload("res://scripts/shop_motion.gd")
const Display = preload("res://scripts/potion_display.gd")
const Layout = preload("res://scripts/workshop_layout.gd")
const State = preload("res://scripts/shop_state.gd")
const Compare = preload("res://tests/state_compare.gd")
const BOTTLE_SIZE := Vector2(20, 28)
var failures := 0
var traces := {}
var reports := {}

func _initialize() -> void:
	assert(DisplayServer.get_name() == "headless")
	check_motion()
	check_brewing()
	check_sales()
	check_retarget_and_modes()
	check_model()
	var path := ProjectSettings.globalize_path("res://../.verification/wide-motion-paths.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"size": [540, 248], "bottleSize": [20, 28], "traces": traces, "reports": reports}, "\t"))
	print("WIDE WORKSHOP MOTION RESULT: ", failures, " failures")
	if failures == 0: print("WIDE WORKSHOP MOTION PASS")
	quit(1 if failures else 0)

func check(condition: bool, message: String) -> void:
	if condition: print("PASS: ", message)
	else:
		push_error(message)
		failures += 1

func bounds(center: Vector2) -> Rect2: return Rect2(center - BOTTLE_SIZE / 2, BOTTLE_SIZE)

func safe_ui(center: Vector2) -> bool:
	var area := bounds(center)
	if not Rect2(0, 0, 540, 248).encloses(area): return false
	for key in ["potPanel", "herbPanel", "poster"]:
		if area.intersects(Layout.rect(key)): return false
	for key in Layout.BUTTONS:
		if area.intersects(Rect2(Layout.button_rect(key))): return false
	return true

func bottle_collisions(display: RefCounted, held: Vector2 = Vector2(-100, -100)) -> int:
	var areas: Array[Rect2] = []
	for index in range(display.visible_capacity()):
		if display.slots[index].is_empty(): continue
		areas.append(bounds(display.position(index)))
	if held.x > 0: areas.append(bounds(held))
	var hits := 0
	for first in areas.size():
		for second in range(first + 1, areas.size()):
			if areas[first].intersects(areas[second]): hits += 1
	return hits

func collision_detail(display: RefCounted, held: Vector2) -> Array:
	var centers: Array[Vector2] = []
	for index in range(display.visible_capacity()):
		if not display.slots[index].is_empty(): centers.append(display.position(index))
	centers.append(held)
	var result := []
	for first in centers.size():
		for second in range(first + 1, centers.size()):
			if bounds(centers[first]).intersects(bounds(centers[second])):
				result.append([first, second, [centers[first].x, centers[first].y], [centers[second].x, centers[second].y]])
	return result

func check_motion() -> void:
	var motion := Motion.new()
	check(motion.counter_x() == 350 and motion.offscreen_x() == 464 and motion.handover_point() == Vector2(373, 199), "Original indoor endpoints remain 350/464")
	motion.set_workshop_layout(true)
	check(motion.customer_x == 596 and motion.counter_x() == 492 and motion.handover_point() == Vector2(515, 199), "540 workshop uses approved outside, purchase and hand points")
	check(motion.offscreen_x() - 48 > Layout.SIZE.x, "An absent 96-pixel customer is fully outside the wide workshop")
	motion.tick(0.34, true, 0.4)
	var elapsed: float = motion.arrival_elapsed
	var phase: int = motion.visit
	motion.set_workshop_layout(false)
	check(motion.arrival_elapsed == elapsed and motion.visit == phase and motion.customer_x == roundf(lerpf(464, 350, elapsed / motion.arrival_seconds)), "A view switch preserves the visitor and arrival fraction")
	motion.set_workshop_layout(true)
	motion.tick(1.0, true, 0.6, 1.5)
	check(motion.visit == Motion.Visit.WAITING and motion.customer_x == 492, "Workshop arrival stops at approved purchase feet")
	motion.sale(77)
	check(is_equal_approx(motion.handover_seconds, 0.3) and is_equal_approx(motion.departure_seconds, 0.84375), "Fast selling keeps the existing scaled handover and departure times")
	motion.tick(0.15, true, 0.0, 1.5)
	var departure_elapsed: float = motion.departing_elapsed
	motion.set_workshop_layout(false)
	motion.set_workshop_layout(true)
	check(motion.departing_elapsed == departure_elapsed and motion.earned_gold == 77 and motion.departure_x() == 492, "View switches preserve the active sale and handover hold")
	motion.tick(0.4, true, 0.0, 1.5)
	check(motion.departure_x() > 492 and motion.departure_x() < 596, "Workshop departure walks between approved endpoints")
	motion.close_shop()
	check(motion.customer_x == 596 and motion.departing_elapsed < 0 and motion.earned_gold == 0, "Closing clears only visual visitors at the correct outside point")
	var fast_departures := true
	for interval in [3.2, 1.5, 0.1]:
		var fast := Motion.new()
		fast.set_workshop_layout(true)
		fast.tick(0.1, true, 0.9, interval)
		fast.sale(13)
		fast.departing_elapsed = fast.departure_seconds
		fast_departures = fast_departures and fast.departure_x() == 596 and fast.departure_x() - 48 > 540
		fast.departing_elapsed = 0.0
		for step in range(30):
			fast.tick(0.1, true, 0.0, interval)
			if fast.departing_elapsed >= 0:
				fast_departures = fast_departures and fast.departure_x() >= 492 and fast.departure_x() <= 596
		fast_departures = fast_departures and fast.departing_elapsed < 0 and fast.visit == Motion.Visit.ABSENT and fast.customer_x == 596
	check(fast_departures, "100ms ticks at normal, fast and 100ms trade intervals complete departures outside the 540 viewport without a stale visitor")

func check_brewing() -> void:
	var ui_clear := true
	var collision_count := 0
	for index in range(8):
		var display := Display.new()
		display.set_workshop_layout(true)
		display.restore(index, 0)
		display.add("focus")
		var trace := []
		check(display.position(index) == Vector2(188, 160), "Brew %d starts at the approved pot origin" % index)
		for frame in range(221):
			var center: Vector2 = display.position(index)
			ui_clear = ui_clear and safe_ui(center)
			collision_count += bottle_collisions(display)
			if frame % 5 == 0: trace.append([center.x, center.y])
			display.tick(Display.TRAVEL_SECONDS / 220.0)
		check(display.position(index) == Layout.slot_center(index), "Brew %d finishes at its actual display slot" % index)
		traces["brew-%d" % index] = trace
	check(ui_clear, "Every brew stays inside 540×248 and clears the production panel, herb panel, poster and buttons")
	check(collision_count == 0, "All eight fresh-brew routes avoid already displayed bottles")
	reports.brew_bottle_collisions = collision_count

func check_sales() -> void:
	var ui_clear := true
	var shift_collisions := 0
	var held_collisions := 0
	for capacity in [8, 60]:
		for selected in range(8):
			for duration in [0.48, 0.3]:
				var display := Display.new()
				display.set_workshop_layout(true)
				display.restore(capacity, 3)
				var before: Array = display.inventory_order()
				var start: Vector2 = display.take(selected)
				before.remove_at(selected)
				check(display.inventory_order() == before, "Sale %d of %d removes only its actual FIFO/preferred ID" % [selected, capacity])
				var trace := []
				var first_collision := false
				for frame in range(481):
					var p := frame / 480.0
					var center := Display.handover_position(start, Vector2(515, 199), p)
					ui_clear = ui_clear and safe_ui(center)
					for index in range(8):
						if not display.slots[index].is_empty(): ui_clear = ui_clear and safe_ui(display.position(index))
					var moving_hits := bottle_collisions(display)
					shift_collisions += moving_hits
					held_collisions += bottle_collisions(display, center) - moving_hits
					if not first_collision and bottle_collisions(display, center) > 0:
						reports["collision-%d-%d-%s" % [capacity, selected, duration]] = {"frame": frame, "pairs": collision_detail(display, center)}
						first_collision = true
					if capacity == 60 and duration == 0.48 and frame % 10 == 0: trace.append([center.x, center.y])
					display.tick(duration / 480.0)
				if capacity == 60 and duration == 0.48: traces["handover-%d" % selected] = trace
				check(Display.handover_position(start, Vector2(515, 199), 1) == Vector2(515, 199), "Handover ends at the approved customer hand")
	check(ui_clear, "All selected sales and FIFO/reserve shifts clear the panels, poster and buttons")
	check(shift_collisions == 0, "All eight sale selections at 8/60 stock keep remaining bottle rectangles separate")
	check(held_collisions == 0, "Regular and fast handovers avoid remaining bottles during FIFO movement")
	reports.shift_bottle_collisions = shift_collisions
	reports.handover_bottle_collisions = held_collisions
	var reserve := Display.new()
	reserve.set_workshop_layout(true)
	reserve.restore(60, 0)
	check(reserve.take(59) == Vector2(422, 151), "A preferred reserve sale starts at the approved storage point")
	var reserve_clear := true
	for frame in range(101):
		reserve_clear = reserve_clear and safe_ui(Display.handover_position(Vector2(422, 151), Vector2(515, 199), frame / 100.0))
	check(reserve_clear, "Reserve handover clears UI")

func check_retarget_and_modes() -> void:
	var display := Display.new()
	display.set_workshop_layout(true)
	var ids: Array = [false, true, "vigor", "focus", "world_tree", "invisibility", "moonlight"]
	display.restore(ids.size(), 1, ids)
	display.add("vigor")
	display.tick(0.1)
	var incoming: Vector2 = display.position(7)
	display.take()
	check(display.position(6) == incoming, "Selling during brewing retargets the same incoming bottle without teleporting")
	display.tick(0.12)
	var positions := []
	for index in range(1, 7): positions.append(display.position(index))
	display.take()
	var continuous := true
	for index in range(6): continuous = continuous and display.position(index) == positions[index]
	check(continuous, "Repeated sales preserve every visible origin before the next shift")
	var order: Array = display.inventory_order()
	check(order == ["vigor", "focus", "world_tree", "invisibility", "moonlight", "vigor"], "Retargeting keeps actual mixed potion IDs and FIFO order")
	display.set_workshop_layout(false)
	check(display.inventory_order() == order and display.visible_capacity() == 12 and display.brew_origin() == Display.BREW_ORIGIN, "The indoor view preserves stock and its original origin/capacity")
	display.set_workshop_layout(true)
	check(display.inventory_order() == order and display.visible_capacity() == 8, "Returning to the workshop preserves actual IDs")

func check_model() -> void:
	var state := State.new()
	var untouched := State.new()
	var display := Display.new()
	display.set_workshop_layout(true)
	var mode := false
	for frame in range(18000):
		display.tick(0.1)
		var events: Dictionary = state.advance(0.1)
		var same_events: Dictionary = untouched.advance(0.1)
		if not Compare.equivalent(events, same_events):
			check(false, "Visual work must not change economic events or RNG")
			return
		for event in events.potion_events:
			if event.kind == "brew": display.add(event.mana)
			else: display.take(event.get("index", 0))
		if frame % 77 == 0:
			mode = not mode
			display.set_workshop_layout(mode)
		if display.inventory_order() != state.inventory_order():
			check(false, "Thirty-minute mixed-mode inventory must match economic inventory")
			return
	check(Compare.equivalent(state.to_data(), untouched.to_data()), "Thirty-minute visual/mode fixture leaves economic, RNG and saved state identical to an untouched twin")
	check(display.inventory_order() == state.inventory_order(), "Thirty-minute event stream keeps display and model inventory identical")
