extends RefCounted
## Optional recipes; provisional balance. No Content preload or UI-side rolls.
const UNFOUND := "UNFOUND"
const DISCOVERED := "DISCOVERED"
const OWNED := "OWNED"
const CHANCE := 0.03
const GUARANTEE := 30
const INITIAL_SEED := 30273129
const ROWS := [
	{"id": "rare_forest_breath", "name": "숲숨결 물약", "region": "forest_edge", "family": "nature", "preferred_customer": "elf", "order": 32, "existing": false, "owned_at_start": false, "unlock": {"rare": "forest_edge"}, "cost": 900, "sale_price": 80, "ingredients": {"dewgrass": 2, "starleaf": 1, "moon_mushroom": 1}, "duration_multiplier": 1.9, "success": 0.90, "environment": "rain", "environment_bonus": 0.08, "grant_sources": [], "icon_candidate": "res://assets/rare_recipes_v1/potions/rare_forest_breath_icon.png", "bottle_candidate": "res://assets/rare_recipes_v1/potions/rare_forest_breath_12x16.png", "recipe_icon_candidate": "res://assets/rare_recipes_v1/recipes/rare_forest_breath_recipe.png"},
	{"id": "rare_mist_veil", "name": "물안개 물약", "region": "mist_valley", "family": "craft", "preferred_customer": "rogue", "order": 33, "existing": false, "owned_at_start": false, "unlock": {"rare": "mist_valley"}, "cost": 2800, "sale_price": 110, "ingredients": {"blue_reed": 2, "silver_moss": 1, "dewgrass": 1}, "duration_multiplier": 2.3, "success": 0.88, "environment": "rain", "environment_bonus": 0.08, "grant_sources": [], "icon_candidate": "res://assets/rare_recipes_v1/potions/rare_mist_veil_icon.png", "bottle_candidate": "res://assets/rare_recipes_v1/potions/rare_mist_veil_12x16.png", "recipe_icon_candidate": "res://assets/rare_recipes_v1/recipes/rare_mist_veil_recipe.png"},
	{"id": "rare_lunar_seal", "name": "월광봉인 물약", "region": "moon_ruins", "family": "arcane", "preferred_customer": "mage", "order": 34, "existing": false, "owned_at_start": false, "unlock": {"rare": "moon_ruins"}, "cost": 11000, "sale_price": 200, "ingredients": {"moonflower": 2, "ash_sage": 1, "starleaf": 1}, "duration_multiplier": 3.1, "success": 0.82, "environment": "night", "environment_bonus": 0.08, "grant_sources": [], "icon_candidate": "res://assets/rare_recipes_v1/potions/rare_lunar_seal_icon.png", "bottle_candidate": "res://assets/rare_recipes_v1/potions/rare_lunar_seal_12x16.png", "recipe_icon_candidate": "res://assets/rare_recipes_v1/recipes/rare_lunar_seal_recipe.png"},
	{"id": "rare_nebula_distillate", "name": "성운 증류액", "region": "star_garden", "family": "arcane", "preferred_customer": "mage", "order": 35, "existing": false, "owned_at_start": false, "unlock": {"rare": "star_garden"}, "cost": 26000, "sale_price": 280, "ingredients": {"star_seed": 2, "moonflower": 1, "crystal_herb": 1}, "duration_multiplier": 3.4, "success": 0.80, "environment": "night_clear", "environment_bonus": 0.08, "grant_sources": [], "icon_candidate": "res://assets/rare_recipes_v1/potions/rare_nebula_distillate_icon.png", "bottle_candidate": "res://assets/rare_recipes_v1/potions/rare_nebula_distillate_12x16.png", "recipe_icon_candidate": "res://assets/rare_recipes_v1/recipes/rare_nebula_distillate_recipe.png"},
]

static func row(id: String) -> Dictionary:
	for item in ROWS:
		if item.id == id: return item
	return {}

static func is_special(id: String) -> bool:
	return not row(id).is_empty()

static func by_region(region: String) -> Dictionary:
	for item in ROWS:
		if item.region == region: return item
	return {}

static func is_discovered(id: String, p: RefCounted) -> bool:
	return is_special(id) and p.expansion.rare_discovered.has(id)

static func is_owned(id: String, p: RefCounted) -> bool:
	return is_discovered(id, p) and p.owned.has(id)

static func state(id: String, p: RefCounted) -> String:
	return OWNED if is_owned(id, p) else DISCOVERED if is_discovered(id, p) else UNFOUND

static func recipe_info(id: String, p: RefCounted) -> Dictionary:
	var item := row(id)
	if item.is_empty(): return {"exists": false}
	var status := state(id, p)
	var known := status != UNFOUND
	return {"exists": true, "region": item.region, "state": status, "known": known, "owned": status == OWNED, "id": id if known else "", "name": item.name if known else "특별 레시피 · 미발견", "icon": item.icon_candidate if known else "", "recipe_icon": item.recipe_icon_candidate if known else "", "ingredients": item.ingredients.duplicate() if known else {}, "cost": item.cost if known else 0, "failures": int(p.expansion.rare_failures.get(id, 0)), "chance": CHANCE, "guarantee": GUARANTEE}

static func preview(region: String, p: RefCounted) -> Dictionary:
	var item := by_region(region)
	return {"exists": false} if item.is_empty() else recipe_info(item.id, p)

static func needs_search(region: String, p: RefCounted) -> bool:
	var item := by_region(region)
	return not item.is_empty() and not is_discovered(item.id, p)

static func reserve(region: String, p: RefCounted) -> Dictionary:
	var item := by_region(region)
	if item.is_empty() or is_discovered(item.id, p): return {"rare_valid": false, "rare_recipe": "", "rare_success": false, "rare_attempt": 0}
	var attempt := int(p.expansion.rare_failures.get(item.id, 0)) + 1
	var success := attempt >= GUARANTEE
	if not success:
		# A separate persisted stream leaves ordinary reward and production RNG intact.
		p.expansion.rare_seed = (p.expansion.rare_seed * 48271) % 2147483647
		success = float(p.expansion.rare_seed) / 2147483647.0 < CHANCE
	return {"rare_valid": true, "rare_recipe": item.id, "rare_success": success, "rare_attempt": attempt}

static func complete(cycle: Dictionary, p: RefCounted) -> void:
	if not cycle.get("rare_valid", false): return
	var id: String = cycle.get("rare_recipe", "")
	if not is_special(id) or is_discovered(id, p): return
	if cycle.rare_success: p.expansion.rare_discovered.append(id)
	else: p.expansion.rare_failures[id] = int(cycle.rare_attempt)
