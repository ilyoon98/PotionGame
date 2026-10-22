extends SceneTree
const State = preload("res://scripts/shop_state.gd")
const F = preload("res://tests/late_investment_fixture.gd")
const M = preload("res://tests/contracts_fixture.gd")
const Compare = preload("res://tests/state_compare.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	assert(DisplayServer.get_name() == "headless")
	var checks := 0
	for scenario in ["normal","scarce_upper"]:
		for stage in 4:
			var s := F.completed_store(73129,"final","both3",scenario); s.gold = 10000000
			for next in range(1,stage+1): assert(s.workshop.purchase(s,next).ok)
			var data: Dictionary = M.data(s); var coarse := State.new(); var fine := State.new()
			assert(coarse.load_data(data) and fine.load_data(data))
			coarse.advance(601.0)
			for i in 601: fine.advance(1.0)
			assert(Compare.equivalent(M.data(coarse),M.data(fine)),"Full recovery/retail/contract state must agree under601s versus601x1s; stage%d %s" % [stage,scenario])
			checks += 1
	M.write_json("res://.verification/f20-recovery-20261020/checks/chunks.json",{"passed":true,"checks":checks,"case":"Actual full-state equivalence with the shop open across repeated recovery cycles, stage0..3 and two supply scenarios"})
	print("F20 RECOVERY CHUNKS PASS ",checks)
	quit()
