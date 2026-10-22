extends "res://tools/measure_random_expansion.gd"
## Experiment only: the live game has no new multiplier or effect.
class CandidateState extends State:
	func customer_interval() -> float:
		return super.customer_interval() * (0.8 if sales_counter_level >= 3 else 1.0)
func _run() -> void:
	assert(DisplayServer.get_name() == "headless")
	var runs := []
	for seed in [73129, 19337, 9973]:
		for policy in ["recipe_first", "equipment_first", "return_15m"]:
			var state := CandidateState.new()
			state.progression.seed_value = seed
			var result := measure(state, "%s_%d" % [policy, seed], 28800, policy)
			runs.append(result)
			print("COUNTER CANDIDATE ", policy, " ", seed, " completion ", result.completion_minutes, " backlog ", result.longest_backlog_minutes)
	var file := FileAccess.open("res://docs/balance/runtime-random-counter-candidate-8h.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"candidate": "Stage 3..10 sales interval x0.8, all prices/material pools/purchases unchanged; test subclass only, not shipped", "engine": Engine.get_version_info().string, "runs": runs}, "\t"))
	print("COUNTER CANDIDATE PASS: nine isolated eight-hour measurements with exact ledger; live balance unchanged")
	quit()
