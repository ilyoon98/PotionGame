extends SceneTree
const State = preload("res://scripts/shop_state.gd")
const A = preload("res://tools/verify_f20_recovery.gd").Reference
const F = preload("res://tests/late_investment_fixture.gd")
const M = preload("res://tests/contracts_fixture.gd")
const Compare = preload("res://tests/state_compare.gd")
var checks := 0
func same(current: RefCounted, previous: RefCounted) -> void:
	var data: Dictionary = M.data(current); data.erase("workshop")
	# Desktop placement prefs (2026-10-21) postdate the frozen reference.
	data.erase("window_position"); data.erase("management_position"); data.erase("audio")
	data.erase("keeper"); data.erase("aging"); data.erase("keeper_upgrades"); data.erase("report_f21"); data.erase("regulars"); data.version = 12
	assert(Compare.equivalent(data, M.data(previous)), "Unpurchased expansion preserves approved free recovery policy including actual timers/RNG/economy")
	checks += 1
func _initialize() -> void: call_deferred("run")
func run() -> void:
	for seed_value in [73129,19337,9973]:
		var state := State.new(); state.gold = 100000; state.keeper.enabled = false
		state.progression.seed_value = seed_value; state.progression.expansion.rare_seed = seed_value; state.contracts.seed = seed_value
		var old := A.new(); assert(old.load_data(A.legacy(state)))
		for i in 400:
			state.advance(0.25); old.advance(0.25)
			if i in [1,3,7,15,29,61,127]:
				assert(state.upgrade() == old.upgrade())
				assert(state.upgrade_garden() == old.upgrade_garden())
			same(state, old)
		var mature := F.completed_store(seed_value,"final","both3","normal")
		mature.keeper.enabled = false
		var mature_a := A.new(); assert(mature_a.load_data(A.legacy(mature)))
		for i in 20:
			mature.advance(30); mature_a.advance(30); same(mature,mature_a)
		# Purchase in the middle freezes exactly the existing main duration and
		# elapsed. No intermediate new brew is required for correct validation.
		mature.shop_open = false; mature.stock = 16; mature.mana_stock = 0; mature.inventory.clear()
		for i in 16: mature.inventory.append(false)
		mature._start_batch(); mature.gold = 10000000
		var duration: float = mature.brew_duration(); var elapsed: float = mature.brew_elapsed
		var contract: bool = mature.contracts.batch.get("purpose") == "contract"
		assert(mature.workshop.purchase(mature,1).ok)
		assert(mature.workshop.main_duration == (0.0 if contract else duration) and mature.brew_elapsed == elapsed and mature.brew_duration() == duration)
		assert(State.new().load_data(M.data(mature)))
		checks += 3
	M.write_json("res://.verification/f20-recovery-20261020/checks/unpurchased.json", {"passed":true,"checks":checks})
	print("F20 UNPURCHASED PASS ",checks," whole-state comparisons/transition checks")
	quit()
