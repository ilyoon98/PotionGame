extends SceneTree
## Synthetic completed shop only. Measure real model flow without player saves.
const State = preload("res://scripts/shop_state.gd")
const Content = preload("res://scripts/shop_content.gd")
const Rare = preload("res://scripts/rare_recipes.gd")
const Status = preload("res://scripts/management_status.gd")
const STEP := 0.1
const SECONDS := 600.0
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	assert(value, message)

func _initialize() -> void:
	assert(DisplayServer.get_name() == "headless")
	set_meta("isolated_preview", true)
	call_deferred("run")

func fixture(special: bool) -> RefCounted:
	var state := State.new()
	state.gold = 1000000
	state.level = state.MAX_LEVEL
	state.garden_level = state.MAX_GARDEN_LEVEL
	state.sales_counter_level = Content.SALES_COUNTER_COSTS.size()
	var p: RefCounted = state.progression
	var ex: RefCounted = p.expansion
	p.reputation = 100000
	p.expedition_unlocked = true
	p.employee = true
	p.filter_owned = true
	for row in Content.DATA.regions:
		ex.regions.append(row.id)
		if row.id == "forest_edge": p.expedition_count = int(row.complete_returns)
		else: ex.returns[row.id] = int(row.complete_returns)
	for row in Content.DATA.upgrades: ex.stages[row.track] = int(row.stage)
	for row in Content.DATA.employees: ex.staff.append(row.id)
	for id in Content.RECIPES:
		if Rare.is_special(id): continue
		p.owned.append(id)
		ex.grant_recipe(id)
	if special:
		for row in Rare.ROWS:
			ex.rare_discovered.append(row.id)
			p.owned.append(row.id)
	# Completed first manufacture, not a synthetic queue of new purchases.
	ex.first_batches.clear()
	ex.first_brewed = p.owned.duplicate()
	ex.first_sold = p.owned.duplicate()
	state.herbs = state.herb_capacity()
	state.mushrooms = state.MUSHROOM_CAPACITY
	p.rare_herbs = ex.special_capacity()
	for row in Content.DATA.materials:
		if row.id not in ["herb", "moon_mushroom", "starleaf"]: ex.materials[row.id] = ex.special_capacity()
	return state

func counts(state: RefCounted) -> Dictionary:
	var result := {}
	for row in Content.DATA.materials: result[row.id] = state.material_count(row.id)
	return result

func ingredients(kind: Variant) -> Dictionary:
	return Content.lookup("potions", Status.kind_id(kind)).ingredients

func measure(special: bool) -> Dictionary:
	var state := fixture(special)
	var starting := counts(state)
	var consumed := {}
	var manufactured := {}
	var sold := {}
	var family_manufactured := {}
	var zero_stock_seconds := {}
	var zero_material_seconds := {}
	var occupancy := 0.0
	var full := 0.0
	var missing := 0.0
	var started_batches := 0
	var family_owned_top := {}
	for row in Content.DATA.potions:
		if not family_owned_top.has(row.family) or row.order > family_owned_top[row.family].order: family_owned_top[row.family] = row
	for step in int(SECONDS / STEP):
		var before_active: bool = state.brew_active
		var finishes: int = int(state.progression.totals.brewed) + int(state.progression.totals.failed)
		var events: Dictionary = state.advance(STEP)
		var finished: bool = int(state.progression.totals.brewed) + int(state.progression.totals.failed) > finishes
		# At most one finish fits in0.1s (actual durations are >=0.8s).
		if state.brew_active and (not before_active or finished):
			started_batches += 1
			for id in ingredients(state.progression.active_recipe): consumed[id] = int(consumed.get(id, 0)) + int(ingredients(state.progression.active_recipe)[id])
		for event in events.potion_events:
			var id := Status.kind_id(event.mana)
			if event.kind == "brew":
				manufactured[id] = int(manufactured.get(id, 0)) + 1
				var family: String = Content.lookup("potions", id).family
				family_manufactured[family] = int(family_manufactured.get(family, 0)) + 1
			elif event.kind == "sale": sold[id] = int(sold.get(id, 0)) + 1
		var inventory_counts := {}
		for kind in state.inventory_order():
			var id := Status.kind_id(kind)
			inventory_counts[id] = int(inventory_counts.get(id, 0)) + 1
		for row in Content.DATA.potions:
			if int(inventory_counts.get(row.id, 0)) == 0: zero_stock_seconds[row.id] = float(zero_stock_seconds.get(row.id, 0.0)) + STEP
		for row in Content.DATA.materials:
			if state.material_count(row.id) == 0: zero_material_seconds[row.id] = float(zero_material_seconds.get(row.id, 0.0)) + STEP
		occupancy += float(state.stock) / state.capacity() * STEP
		full += STEP if state.stock >= state.capacity() else 0.0
		missing += STEP if not state.brew_active and state.stock < state.capacity() and state.production_preview().selected == null else 0.0
	var ending := counts(state)
	var made_total := 0
	var sold_total := 0
	for value in manufactured.values(): made_total += int(value)
	for value in sold.values(): sold_total += int(value)
	check(made_total == int(state.progression.totals.brewed), "Real brew event counts match persistent successes")
	check(sold_total == state.total_sold, "Real sale events match persistent sales")
	check(made_total - sold_total == state.stock, "Successful bottles reconcile with FIFO inventory")
	check(started_batches == made_total + int(state.progression.totals.failed) + int(state.brew_active), "Started ingredient reservations reconcile with completed and active attempts")
	check(state.stock <= state.capacity(), "Shared potion storage remains within capacity")
	for family in family_owned_top: check(int(family_manufactured.get(family, 0)) > 0, "Each ordinary family continues manufacture")
	if special:
		for row in Rare.ROWS:
			check(int(manufactured.get(row.id, 0)) > 0, "Every owned special recipe actually manufactures")
			check(int(sold.get(row.id, 0)) > 0, "Every owned special bottle actually sells")
	var generated := {}
	for id in ending:
		generated[id] = int(ending[id]) - int(starting[id]) + int(consumed.get(id, 0))
		check(generated[id] >= 0 and ending[id] >= 0, "Material delta and detected reservations remain nonnegative")
	var top := {}
	for family in family_owned_top:
		var row: Dictionary = family_owned_top[family]
		top[family] = {"id": row.id, "name": row.name, "manufactured": int(manufactured.get(row.id, 0)), "sold": int(sold.get(row.id, 0)), "zero_stock_seconds": zero_stock_seconds.get(row.id, 0.0), "ingredients": row.ingredients}
	var scarce := {}
	for row in Content.DATA.materials: scarce[row.id] = {"name": row.name, "start": starting[row.id], "generated_and_deposited": generated[row.id], "consumed_in_started_batches": int(consumed.get(row.id, 0)), "end": ending[row.id], "zero_seconds": zero_material_seconds.get(row.id, 0.0), "pending": int(state.progression.expansion.pending.get(row.id, 0))}
	return {"all_special_owned": special, "seconds": SECONDS, "step": STEP, "top_ordinary_families": top, "manufactured": manufactured, "sold": sold, "manufactured_by_family": family_manufactured, "materials": scarce, "shared_capacity": state.capacity(), "stock_end": state.stock, "average_occupancy": occupancy / SECONDS, "full_seconds": full, "no_affordable_recipe_seconds": missing, "gross_sales": state.total_sales_gold, "material_cost": state.total_spent_materials, "departure_cost": state.total_spent_expeditions, "failures": state.progression.totals.failed, "ordinary_completed_regions": state.progression.expansion.completed_regions(state.progression), "new_special_discovered": state.progression.expansion.rare_discovered.duplicate()}

func run() -> void:
	var result := {"scope": "Synthetic ordinary32/max16tracks/4staff; actual600s model, not player data or final balance approval", "cases": [measure(false), measure(true)]}
	var path := "res://.verification/endgame-supply-20261013.json"
	DirAccess.make_dir_recursive_absolute("res://.verification")
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("ENDGAME SUPPLY MEASUREMENT PASS: ", checks, " conservation/counter/capacity/manufacture/sale checks; two600s real-model fixtures; ", ProjectSettings.globalize_path(path))
	quit()
