extends SceneTree
## Historical pre-approval candidates, frozen to their original scheduling policy.
## The adopted recovery model is measured separately by measure_f20_recovery.gd.
const State = preload("res://.verification/f20-20261020/payment-fixed-model/scripts/shop_state.gd")
const F = preload("res://.verification/f20-20261020/payment-fixed-model/tests/late_investment_fixture.gd")
const M = preload("res://.verification/f20-20261020/payment-fixed-model/tests/contracts_fixture.gd")
class Recovery extends "res://.verification/f20-20261020/payment-fixed-model/scripts/shop_state.gd":
	func _start_main_batch() -> void:
		if not brew_active and stock_protection.active and stock < capacity() and herbs >= HERBS_PER_POTION:
			# Comparison candidate only: keep the existing fastest basic blend
			# during recovery instead of changing cauldron speed or recipe prices.
			herbs -= HERBS_PER_POTION
			progression.active_recipe = false; progression.batch_chance = 1.0; progression.batch_success = true
			brew_active = true; active_mana = false; brew_elapsed = 0.0
			contracts.clear_batch(); contracts.note_ordinary_start(); _record_batch_start()
		else: super._start_main_batch()
class Earlier extends "res://.verification/f20-20261020/payment-fixed-model/scripts/shop_stock_protection.gd":
	func update(state: RefCounted) -> void:
		var old := active
		if state.stock <= 1: active = true
		elif state.stock >= mini(3, state.capacity()): active = false
		if old != active: state.contracts.ordinary_batches = 0
func _initialize() -> void: call_deferred("run")
func run() -> void:
	for candidate in ["recovery_basic", "earlier_release"]:
		for stage in [0,1,2,3]:
			if candidate == "earlier_release" and stage in [2,3]: continue
			var source := F.completed_store(73129, "final", "both3", "normal")
			var s: RefCounted = Recovery.new() if candidate == "recovery_basic" else State.new()
			assert(s.load_data(M.data(source)))
			if candidate == "earlier_release": s.stock_protection = Earlier.new()
			s.gold = 10000000
			for level in range(1, stage+1): assert(s.workshop.purchase(s, level).ok)
			s.gold = 1000000
			var zero := 0.0; var wait := 0.0; var inventory := 0.0; var auxiliary := 0.0
			var arrivals := []; var batches := []; var partners := {}
			for i in 240:
				var event: Dictionary = s.advance(30)
				zero += float(event.zero_stock_seconds); wait += float(event.customer_wait_seconds)
				inventory += float(event.inventory_seconds); auxiliary += float(event.aux_activity_seconds)
				for item in event.batch_events:
					var entry: Dictionary = item.duplicate(true); entry["time_upper"] = (i+1)*30; batches.append(entry)
				for item in event.contract_events:
					partners[item.partner] = true
					if item.paid > 0: arrivals.append(item.duplicate(true))
				assert(s.gold == 1000000 + s.total_sales_gold-int(source.total_sales_gold) + int(s.contracts.totals.paid)-int(source.contracts.totals.paid) - s.total_spent_materials+int(source.total_spent_materials) - s.total_spent_expeditions+int(source.total_spent_expeditions))
			var report := {"not_adopted": true, "seed": 73129, "scenario": "normal", "candidate": candidate, "stage": stage, "seconds": 7200, "net": s.gold-1000000, "retail_revenue": s.total_sales_gold-int(source.total_sales_gold), "contract_paid": int(s.contracts.totals.paid)-int(source.contracts.totals.paid), "shipped": int(s.contracts.totals.shipped)-int(source.contracts.totals.shipped), "zero_stock_seconds": zero, "customer_wait_seconds": wait, "mean_stock": inventory/7200, "aux_activity_seconds": auxiliary, "partners": partners, "batches": batches, "settlements": arrivals, "passed": true}
			M.write_json("res://.verification/f20-20261020/alternatives/%s-stage%d.json" % [candidate,stage], report)
			print("F20 NON-ADOPTED %s stage%d net%d retail%d shipped%d aux%.1f zero%.1f" % [candidate,stage,report.net,report.retail_revenue,report.shipped,auxiliary,zero])
			await process_frame
	quit()
