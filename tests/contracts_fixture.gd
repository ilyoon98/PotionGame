extends RefCounted
## Workspace-only, synthetic F18 verification data. Never reads a player save.
const State = preload("res://scripts/shop_state.gd")
const Content = preload("res://scripts/shop_content.gd")
const Rare = preload("res://scripts/rare_recipes.gd")
const Compare = preload("res://tests/state_compare.gd")


static func data(state: RefCounted) -> Dictionary:
	return JSON.parse_string(JSON.stringify(state.to_data()))


static func materials(state: RefCounted) -> Dictionary:
	var result := {}
	for row in Content.DATA.materials:
		result[row.id] = state.material_count(row.id)
	return result


## F26 rows (content_set) are a post-growth expansion. The completed fixtures below
## stay the pre-F26 "original growth complete" store; tools/verify_f26_region_potions.gd
## covers the new region, material and recipes on top of it.
static func original(row: Dictionary) -> bool:
	return not row.has("content_set")


static func original_recipe(id: String) -> bool:
	return original(Content.lookup("potions", id))


static func fill_materials(state: RefCounted) -> void:
	state.herbs = state.herb_capacity()
	state.mushrooms = state.MUSHROOM_CAPACITY
	state.progression.rare_herbs = state.progression.expansion.special_capacity()
	for row in Content.DATA.materials:
		if row.id not in ["herb", "moon_mushroom", "starleaf"] and original(row):
			state.progression.expansion.materials[row.id] = state.progression.expansion.special_capacity()


static func clear_materials(state: RefCounted) -> void:
	state.herbs = 0
	state.mushrooms = 0
	state.progression.rare_herbs = 0
	for row in Content.DATA.materials:
		if row.id not in ["herb", "moon_mushroom", "starleaf"]:
			state.progression.expansion.materials[row.id] = 0


static func completed(seed_value: int = 73129) -> RefCounted:
	var state := State.new()
	var p = state.progression
	var ex = p.expansion
	state.gold = 1000000
	state.level = state.MAX_LEVEL
	state.garden_level = state.MAX_GARDEN_LEVEL
	state.sales_counter_level = Content.SALES_COUNTER_COSTS.size()
	p.seed_value = seed_value
	p.reputation = 100000
	p.filter_owned = true
	p.employee = true
	p.expedition_unlocked = true
	p.expedition_active = true
	p.expedition_count = int(Content.lookup("regions", "forest_edge").complete_returns)
	for id in Content.RECIPES:
		if original_recipe(id): p.owned.append(id)
	for row in Rare.ROWS:
		ex.rare_discovered.append(row.id)
	ex.rare_seed = seed_value
	for row in Content.DATA.regions:
		if not original(row): continue
		ex.regions.append(row.id)
		ex.returns[row.id] = int(row.complete_returns)
	for row in Content.DATA.employees:
		ex.staff.append(row.id)
	for row in Content.DATA.upgrades:
		ex.stages[row.track] = maxi(int(ex.stages.get(row.track, 0)), int(row.stage))
	for row in Content.DATA.materials:
		if row.id not in ["herb", "moon_mushroom", "starleaf"] and original(row):
			ex.plants.append(row.id)
			ex.growth[row.id] = 0.0
	ex.first_batches.clear()
	ex.first_brewed = p.owned.duplicate()
	ex.first_sold = p.owned.duplicate()
	fill_materials(state)
	return state


## UI fixtures that mean "nothing left to buy except the feature under test" also finish
## F26: the dawn lighthouse opened and surveyed, its four recipes owned and dawn bloom
## planted and stocked. Otherwise the region (recommendation score 100) and its recipes
## (90) are the next real purchases for a late store, as they are for a real late save.
static func complete_post_growth(state: RefCounted) -> void:
	var p = state.progression
	var ex = p.expansion
	for row in Content.DATA.regions:
		if original(row): continue
		if not ex.regions.has(row.id): ex.regions.append(row.id)
		ex.returns[row.id] = int(row.complete_returns)
	State.Progression.Expeditions.ensure(p)
	for row in Content.DATA.potions:
		if original(row) or p.owned.has(row.id): continue
		p.owned.append(row.id)
		ex.grant_recipe(row.id)
		ex.first_batches.erase(row.id)
		if not ex.first_brewed.has(row.id): ex.first_brewed.append(row.id)
		if not ex.first_sold.has(row.id): ex.first_sold.append(row.id)
	for row in Content.DATA.materials:
		if not original(row): ex.materials[row.id] = ex.special_capacity()
	ex.pending.clear()


static func opened(seed_value: int = 73129) -> RefCounted:
	var state := State.new()
	state.gold = 100000
	state.progression.seed_value = seed_value
	state.progression.expansion.regions.append("star_garden")
	return state


static func ingredients(kind: Variant) -> Dictionary:
	return Content.lookup("potions", potion_id(kind)).ingredients.duplicate(true)


static func potion_id(kind: Variant) -> String:
	return ("mana" if kind else "health") if kind is bool else str(kind)


static func add_counts(target: Dictionary, source: Dictionary) -> void:
	for id in source:
		target[id] = int(target.get(id, 0)) + int(source[id])


static func stable_equal(a: Variant, b: Variant) -> bool:
	return Compare.equivalent(a, b)


static func write_json(path: String, payload: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "F18 verification output stays in the project workspace")
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
