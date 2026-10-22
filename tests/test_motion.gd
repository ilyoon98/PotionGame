extends SceneTree

const Motion = preload("res://scripts/shop_motion.gd")
var failures := 0

func _initialize() -> void:
	var motion := Motion.new()
	motion.tick(0.1, true, 0.1)
	check(motion.visit == Motion.Visit.ABSENT, "No visitor teleports to the counter at opening")
	motion.tick(0.3, true, 0.4)
	check(motion.visit == Motion.Visit.ARRIVING and motion.customer_x > Motion.COUNTER_X, "Visitor walks in from outside")
	motion.tick(0.6, true, 0.6)
	check(motion.visit == Motion.Visit.WAITING and motion.customer_x == Motion.COUNTER_X, "Arrival reaches the counter")
	motion.tick(0.4, true, 0.0)
	check(motion.visit == Motion.Visit.WAITING and motion.departing_elapsed < 0, "Empty-stock attempt leaves customer waiting without a fake purchase")
	motion.sale(6)
	check(motion.keeper_frame(true) == 3 and motion.departure_frame() == 3 and motion.earned_gold == 6, "Real sale starts handover and happy customer frames")
	motion.tick(0.2, true, 0.1)
	check(motion.departure_x() == Motion.COUNTER_X, "Customer stays until the handover finishes")
	motion.tick(0.4, true, 0.2)
	check(motion.departure_x() > Motion.COUNTER_X and motion.departure_frame() in [1, 2], "Purchased customer walks away")
	motion.tick(0.8, true, 0.45)
	check(motion.departing_elapsed < 0.0 and motion.visit == Motion.Visit.ARRIVING, "Next visitor starts after departure")
	motion.sale(6)
	motion.tick(0.1, false, 0.0)
	check(motion.visit == Motion.Visit.ABSENT and motion.departing_elapsed < 0 and motion.earned_gold == 0, "Closing cancels visitors and sale effects")
	motion.tick(0.1, true, 0.0)
	check(motion.visit == Motion.Visit.ABSENT, "Reopening has no stale visitor")
	motion.elapsed = 4.15
	check(motion.keeper_frame(false) == 0, "Idle uses the new neutral pose")
	motion.elapsed = 0.1
	check(motion.keeper_frame(true) == 1 and motion.keeper_frame(false) == 0, "Manufacturing pose stops when the shelf is full")
	motion.elapsed = 0.3
	check(motion.keeper_frame(true) == 2, "Both new brewing poses loop at four frames per second")
	print("MOTION RESULT: ", failures, " failures")
	quit(1 if failures else 0)


func check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		push_error(description)
		failures += 1
