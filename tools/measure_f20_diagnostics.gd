extends SceneTree
const Original = preload("res://.verification/f20-20261020/diagnostics/original.gd")
const Protected = preload("res://.verification/f20-20261020/diagnostics/protected.gd")
const F = preload("res://.verification/f20-20261020/initial-model/tests/late_investment_fixture.gd")
const M = preload("res://tests/contracts_fixture.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	for seed_value in [73129,19337,9973]:
		for scenario in ["normal","scarce_upper"]:
			for mode in ["original", "protected"]:
				var source := F.completed_store(seed_value, "final", "both3", scenario)
				var data: Dictionary = M.data(source)
				if mode == "original": data.version = 11
				var state: RefCounted = Original.new() if mode == "original" else Protected.new()
				assert(state.load_data(data))
				var occupied := 0.0; var retail := 0.0; var materials := 0.0; var main_wait := 0.0; var full := 0.0
				var starts := []; var consumed := {}; var supplied := {}; var bought := 0
				var ingredients: Dictionary = M.materials(state)
				for i in 240:
					var event: Dictionary = state.advance(30)
					occupied += float(event.contract_activity); retail += float(event.retail_activity)
					materials += float(event.contract_material_wait); main_wait += float(event.material_wait_seconds); full += float(event.full_seconds)
					for start in event.batch_events:
						M.add_counts(consumed, start.ingredients); starts.append(start)
					for item in event.supply_events: supplied[item.material] = int(supplied.get(item.material, 0)) + int(item.quantity)
					bought += int(event.bought)
				var name := "%d-%s-%s.json" % [seed_value,scenario,mode]
				var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.verification/f20-20261020/A/effects/" + name))
				assert(state.gold == old.cash and state.total_sales_gold-int(data.total_sales_gold) == old.retail_revenue and int(state.contracts.totals.shipped)-int(data.contracts.totals.shipped) == old.shipped, "Extra diagnostics must reproduce initial A economic results exactly")
				var generated := {}
				for id in ingredients:
					generated[id] = state.material_count(id) - int(ingredients[id]) + int(consumed.get(id,0)) - int(supplied.get(id,0)) - (bought if id == "moon_mushroom" else 0)
					assert(generated[id] >= 0)
				M.write_json("res://.verification/f20-20261020/diagnostics/"+name, {"passed": true,"seed":seed_value,"scenario":scenario,"mode":mode,"main_contract_seconds":occupied,"main_retail_seconds":retail,"contract_idle_material_seconds":materials,"retail_material_seconds":main_wait,"full_seconds":full,"starts":starts,"material_start":ingredients,"material_end":M.materials(state),"consumed":consumed,"supplied":supplied,"bought_mushrooms":bought,"generated":generated,"same_initial_A_cash_and_retail_and_shipment":true})
				print("F20 DIAG %s retail%.1f contract%.1f retailMaterial%.1f contractIdleMaterial%.1f" % [name,retail,occupied,main_wait,materials])
				await process_frame
	quit()
