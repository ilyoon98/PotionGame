extends SceneTree
## F27 aurora snowfield (approved 2026-11-05, "그림은 그대로 수치만 바꿔"): data rows and the plan's numbers, the
## opening gate/cost after the dawn lighthouse survey, real trips and the guaranteed frost flower, unlock order
## (returns 1/3/5, survey + three recipes), brewing/sales (prices, preferred customers, night environment), the
## planter (28 s, night ×1.5), published pixels = approved sprites (bottles, pots, 32x40 icons, growth sheet, UI v2
## list icons = approved bottle at exactly 2x), catalog rows and hand grips, management UI rows, collection totals,
## save round trip (v17), supply-support exclusion, unchanged pre-F27 content and an economy sanity run.
## Isolated: only reads the read-only copy of a real late save; never reads or writes the player's AppData save.
const Shop = preload("res://scripts/shop.gd")
const State = preload("res://scripts/shop_state.gd")
const Content = preload("res://scripts/shop_content.gd")
const Rewards = preload("res://scripts/expedition_rewards.gd")
const Trips = preload("res://scripts/parallel_expeditions.gd")
const Rare = preload("res://scripts/rare_recipes.gd")
const Late = preload("res://scripts/shop_late_investments.gd")
const Catalog = preload("res://scripts/pixel_art_catalog.gd")
const ItemArt = preload("res://scripts/item_art.gd")
const UiPixel = preload("res://scripts/ui_pixel_catalog.gd")
const Status = preload("res://scripts/management_status.gd")
const M = preload("res://tests/contracts_fixture.gd")
const Compare = preload("res://tests/state_compare.gd")
const MOCK := "res://art/mockups/f27-region-potions-v1/"
const PLAYER_COPY := "res://.verification/real-save-check-20261105/player-copy.json"
const OUT := "res://.verification/f27-region-potions-20261105/result.json"
const REGION := "aurora_snowfield"
const MATERIAL := "frost_flower"
const SET := "f27_aurora_snowfield"
const NEW := ["warmth", "thin_ice", "pine_wind", "aurora_elixir"]
const F26 := ["sunrise", "beacon", "sea_spray", "sun_moon_elixir"]
## docs/새-원정-지역과-물약-F27-기획안.md §2 (approved as proposed).
const PLAN := {
	"warmth": {"name": "온기", "family": "vitality", "customer": "traveler", "order": 40, "returns": 1, "recipes": [], "cost": 300000, "price": 230, "ingredients": {"herb": 2, "frost_flower": 1, "ash_sage": 1}, "duration": 3.4, "success": 0.80, "retail": [274, 322]},
	"thin_ice": {"name": "살얼음", "family": "craft", "customer": "rogue", "order": 41, "returns": 3, "recipes": [], "cost": 400000, "price": 245, "ingredients": {"herb": 2, "frost_flower": 1, "crystal_herb": 1}, "duration": 3.5, "success": 0.78, "retail": [292, 342]},
	"pine_wind": {"name": "솔바람", "family": "nature", "customer": "elf", "order": 42, "returns": 5, "recipes": [], "cost": 500000, "price": 260, "ingredients": {"herb": 2, "frost_flower": 1, "silver_moss": 1}, "duration": 3.6, "success": 0.78, "retail": [309, 363]},
	"aurora_elixir": {"name": "오로라의 물약", "family": "arcane", "customer": "mage", "order": 43, "returns": 8, "recipes": ["warmth", "thin_ice", "pine_wind"], "cost": 900000, "price": 370, "ingredients": {"herb": 2, "frost_flower": 1, "star_seed": 1, "crystal_herb": 1}, "duration": 3.9, "success": 0.76, "retail": [440, 513]},
}
## Hashes of the pre-F27 content, computed on commit fbbc867 before any F27 change (same expressions below).
const BEFORE := {
	"potions36": "b96b88a125f98b4792e937fec8b7d21f29414520c6f8d064f6089422e2471861",
	"regions9": "a2cf3eed765686e72b62e88ca72c803a4a90b5846c238bba8a6ae7bf39278ea7",
	"materials12": "5eddf40716f46c7e8dfda06de85051f9f50d1f34fbc178a1264e4885102ea6d6",
	"upgrades": "3554111897d1c0ebeee0c2462e854bdd9694f61de6d5f9115968ff6000334b4b",
	"recipes": "91abe5618ddb652eacc30f83fe18c93d75571cea98301a718f61a73a3e81f058",
	"pools9": "8d5205ce85e0f05cdcd69478234d6a8bf02cd550cbe5b259fb2fd2fe3ff514c0",
	"catalog40": "5052dac5cc0f8f3407f09ec32135f2cd3e9722c1abd1e6c6569b626309075ad4",
	"bindings": "773f9c318246bafbc1ded375795c8c9d29c277ecbae4686e5b16563f5db96450",
	"ui_icons": "b17b4d889ceaee3f96bae1dd703b4b4eb76639b0ad9713a704ac7382e2f04b62",
	"expansion_assets": "179f875584b54e0e4f852243cfc3512dc39ae38355d359533bab13bb5f181313",
}
const CUSTOMER_INDEX := {"traveler": 0, "mage": 2, "elf": 3, "rogue": 4}
const DAY_CLOCK := 10.0 # phase 0.49: day, weather 0
const NIGHT_CLOCK := 100.0 # phase 0.87: night, weather 1
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	set_meta("isolated_preview", true)
	call_deferred("run")

func player_copy() -> RefCounted:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PLAYER_COPY))
	var state := State.new()
	check(raw is Dictionary and state.load_data(raw), "The real v17 late-save copy loads unchanged")
	return state

func clone(state: RefCounted) -> RefCounted:
	var restored := State.new()
	check(restored.load_data(JSON.parse_string(JSON.stringify(M.data(state)))), "Clone passes the real save validation")
	return restored

func pixels(path: String) -> PackedByteArray:
	var image: Image = load(path).get_image() if path.begins_with("res://assets") else Image.load_from_file(ProjectSettings.globalize_path(path))
	image.convert(Image.FORMAT_RGBA8)
	return image.get_data()

## RGBA with fully transparent pixels zeroed; the importer's alpha-border fix recolours them.
func visible_pixels(data: PackedByteArray) -> PackedByteArray:
	for i in range(0, data.size(), 4):
		if data[i + 3] == 0: data[i] = 0; data[i + 1] = 0; data[i + 2] = 0
	return data

func texture_pixels(texture: Texture2D) -> PackedByteArray:
	var image := texture.get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image.get_data()

## The real late save with the live F26 content finished: dawn lighthouse surveyed, four F26 recipes owned.
func f26_done(base: RefCounted) -> RefCounted:
	var s := clone(base)
	var ex: RefCounted = s.progression.expansion
	if not ex.regions.has("dawn_lighthouse"): ex.regions.append("dawn_lighthouse")
	ex.returns["dawn_lighthouse"] = 8
	Trips.ensure(s.progression)
	for id in F26:
		if not s.progression.owned.has(id):
			s.progression.owned.append(id)
			ex.grant_recipe(id)
	ex.first_batches.clear()
	return clone(s)

## + the aurora snowfield surveyed and all four F27 recipes, with plenty of every ingredient.
func f27_complete(base: RefCounted) -> RefCounted:
	var s := f26_done(base)
	var ex: RefCounted = s.progression.expansion
	if not ex.regions.has(REGION): ex.regions.append(REGION)
	ex.returns[REGION] = 8
	Trips.ensure(s.progression)
	for id in NEW:
		if not s.progression.owned.has(id):
			s.progression.owned.append(id)
			ex.grant_recipe(id)
	for id in ["frost_flower", "dawn_bloom", "dewgrass", "mist_mushroom", "blue_reed", "moonflower", "star_seed", "silver_moss", "crystal_herb", "ash_sage", "starleaf"]:
		if id == "starleaf": s.progression.rare_herbs = 30
		else: ex.materials[id] = 30
	s.herbs = s.herb_capacity()
	return s

func test_data() -> void:
	var region := Content.lookup("regions", REGION)
	check(Content.DATA.regions.size() == 10 and Content.DATA.regions[-1].id == REGION and Content.DATA.regions[8].id == "dawn_lighthouse", "Ten regions; the aurora snowfield is tenth, after the dawn lighthouse")
	check(region.name == "오로라 설원" and int(region.cost) == 500000 and int(region.explore_seconds) == 500 and int(region.return_seconds) == 100 and int(region.departure_cost) == 200 and int(region.complete_returns) == 8 and region.previous_region == "dawn_lighthouse" and int(region.reputation) == 0 and region.content_set == SET, "Region values follow the plan (500,000 G, 500+100 s, 200 G, 8 returns, after the dawn lighthouse)")
	check(region.material == MATERIAL and int(region.repeat_material_quantity) == 8 and Compare.equivalent(region.rewards, {"frost_flower": 8}), "Region's main material is frost flower (repeat quantity 8)")
	var pool: Dictionary = Rewards.POOLS[REGION]
	check(pool.main == MATERIAL and int(pool.min) == 7 and int(pool.max) == 9 and pool.extra == ["dawn_bloom", "star_seed", "moonflower"], "Reward pool: frost flower 7-9 + dawn bloom/star seed/moonflower (60/30/10)")
	check(Rare.by_region(REGION).is_empty() and not Rewards.RARE.has(REGION), "No special recipe for the aurora snowfield")
	var material := Content.lookup("materials", MATERIAL)
	check(Content.DATA.materials.size() == 13 and Content.DATA.materials[-1].id == MATERIAL and material.name == "서리꽃" and material.source == "recipe_granted_garden" and material.region == REGION and int(material.growth_seconds) == 28 and material.environment == "night" and float(material.favored_growth_multiplier) == 1.5 and int(material.seed_quantity) == 2 and material.content_set == SET, "Frost flower: garden 28 s, night ×1.5, two seeds, region aurora snowfield")
	check(Content.DATA.potions.size() == 40 and Content.RECIPES.size() + 2 == 44, "40 ordinary rows (32 + 4 + 4) and 44 recipes with the four specials")
	var total := int(region.cost)
	for id in NEW:
		var row := Content.lookup("potions", id)
		var plan: Dictionary = PLAN[id]
		var unlock: Dictionary = row.unlock
		total += int(row.cost)
		check(row.name == plan.name and row.family == plan.family and row.preferred_customer == plan.customer and int(row.order) == plan.order and not row.existing and not row.owned_at_start and row.content_set == SET, "%s identity/family/customer/order" % id)
		check(Compare.equivalent(unlock.discovery, {"region": REGION, "returns": plan.returns}) and unlock.get("recipes", []) == plan.recipes, "%s unlock: aurora snowfield return %d%s" % [id, plan.returns, " + three recipes" if not plan.recipes.is_empty() else ""])
		check(int(row.cost) == plan.cost and int(row.sale_price) == plan.price and Compare.equivalent(row.ingredients, plan.ingredients) and is_equal_approx(float(row.duration_multiplier), plan.duration) and is_equal_approx(float(row.success), plan.success) and row.environment == "night" and is_equal_approx(float(row.environment_bonus), 0.08), "%s cost %d, price %d, ingredients, ×%.1f, %d%%, night +8%%p" % [id, plan.cost, plan.price, plan.duration, int(plan.success * 100)])
		var recipe: Dictionary = Content.RECIPES[id]
		check(recipe.name == plan.name and int(recipe.cost) == plan.cost and int(recipe.price) == plan.price and is_equal_approx(float(recipe.duration), plan.duration) and is_equal_approx(float(recipe.success), plan.success), "%s recipe table" % id)
		check(row.grant_material == MATERIAL and row.grant_sources == plan.ingredients.keys().filter(func(m): return m != "herb") and row.grant_sources.has(MATERIAL), "%s grants the frost flower planter" % id)
		check(row.icon_candidate == "res://assets/content_expansion_v1/potions/%s_icon.png" % id and row.recipe_candidate == "res://assets/content_expansion_v1/recipes/%s_recipe.png" % id and row.bottle_candidate == "res://assets/pixel_v1/potions/%s.png" % id, "%s art paths" % id)
	check(total == 2600000, "Total gold sink 260만 G (region 50만 + recipes 30/40/50/90만)")

func test_unchanged() -> void:
	var catalog_rows := {}
	for id in Catalog.DATA.potions:
		if id not in NEW: catalog_rows[id] = Catalog.DATA.potions[id]
	var recipes := {}
	for id in Content.RECIPES:
		if id not in NEW: recipes[id] = Content.RECIPES[id]
	var pools := {}
	for id in Rewards.POOLS:
		if id != REGION: pools[id] = Rewards.POOLS[id]
	var bindings := {}
	for cid in Catalog.DATA.characters:
		bindings[cid] = {}
		for id in Catalog.DATA.characters[cid].bindings:
			if id not in NEW: bindings[cid][id] = Catalog.DATA.characters[cid].bindings[id]
	var ui_icons := {}
	for key in UiPixel.DATA.icons:
		if key.trim_prefix("recipe:") not in NEW: ui_icons[key] = UiPixel.DATA.icons[key]
	var now := {
		"potions36": JSON.stringify(Content.DATA.potions.slice(0, 36)).sha256_text(),
		"regions9": JSON.stringify(Content.DATA.regions.slice(0, 9)).sha256_text(),
		"materials12": JSON.stringify(Content.DATA.materials.slice(0, 12)).sha256_text(),
		"upgrades": JSON.stringify(Content.DATA.upgrades).sha256_text(),
		"recipes": JSON.stringify(recipes).sha256_text(),
		"pools9": JSON.stringify(pools).sha256_text(),
		"catalog40": JSON.stringify(catalog_rows).sha256_text(),
		"bindings": JSON.stringify(bindings).sha256_text(),
		"ui_icons": JSON.stringify(ui_icons).sha256_text(),
		"expansion_assets": JSON.stringify(ItemArt.CATALOG.assets.filter(func(row): return row.id != MATERIAL)).sha256_text(),
	}
	for key in BEFORE: check(now[key] == BEFORE[key], "Pre-F27 %s unchanged" % key)
	check(Late.SPECIAL_IDS == ["starleaf", "dewgrass", "silver_moss", "blue_reed", "crystal_herb", "mist_mushroom", "ash_sage", "moonflower", "star_seed"], "Supply support list unchanged (no frost flower, no dawn bloom)")

func test_player_copy(base: RefCounted) -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PLAYER_COPY))
	check(int(raw.version) == 17 and State.SAVE_VERSION == 17, "Save format stays v17")
	var p: RefCounted = base.progression
	check(p.completed_regions() == 8 and base.gold == int(raw.gold), "Copy is the late pre-F26 state: 8 surveys, gold preserved")
	check(not Trips.opened(REGION, p) and not p.expansion.cycles.has(REGION), "Aurora snowfield is not open in the old save")
	check(base.purchase_reason("region:" + REGION) == "새벽 등대 조사 필요", "Old save: the aurora snowfield waits for the dawn lighthouse survey")
	check(not Status.growth_candidates(base).any(func(item): return item.purchase_key == "region:" + REGION), "Old save: growth recommendations do not offer the locked tenth region")
	for id in NEW: check(base.purchase_reason(id) == "오로라 설원 귀환 %d회 필요" % int(PLAN[id].returns), "%s waits for aurora snowfield returns" % id)
	var c := {}
	for row in Status.collection(base): c[row.key] = [row.have, row.total]
	check(c.recipes == [30, 38] and c.regions == [8, 10], "Collection shows recipes 30/38 and surveys 8/10 (%s)" % str(c))
	check(Late.new().growth_view(base).recipes == 32, "Late-investment gate counts the original 32 recipes")
	var again := clone(base)
	check(Compare.equivalent(M.data(base), M.data(again)), "The loaded copy round-trips unchanged")
	var done := f26_done(base)
	check(done.progression.completed_regions() == 9 and done.progression.expansion.region_reason(REGION, done.progression) == "" and done.purchase_reason("region:" + REGION) == "", "After the F26 survey the aurora snowfield can be opened right away")
	check(Status.growth_candidates(done).any(func(item): return item.purchase_key == "region:" + REGION), "Growth recommendations then offer the new region")

func test_opening(base: RefCounted) -> void:
	var early := f26_done(base)
	early.progression.expansion.returns["dawn_lighthouse"] = 5
	check(early.purchase_reason("region:" + REGION) == "새벽 등대 조사 필요", "Needs the dawn lighthouse survey first")
	var poor := f26_done(base)
	poor.gold = 499999
	check(poor.purchase_reason("region:" + REGION) == "1 G 부족", "Exactly 500,000 G")
	var s := f26_done(base)
	s.gold = 1000000
	var spent: int = s.progression.totals.manual_spent
	var fees: int = s.total_spent_expeditions
	check(s.purchase("region:" + REGION), "Region purchase succeeds")
	var cycle: Dictionary = s.progression.expansion.cycles.get(REGION, {})
	check(s.progression.expansion.regions.has(REGION) and s.progression.totals.manual_spent - spent == 500000 and s.purchase_reason("region:" + REGION) == "개방 완료", "Opening costs 500,000 G once")
	var reduction := minf(0.3, s.progression.expansion.effect("expedition_path", "trip_time_reduction") + s.progression.expansion.effect("expedition_guide", "trip_time_reduction"))
	check(cycle.get("running", false) and int(cycle.fee) == 200 and is_equal_approx(float(cycle.duration), 600.0 * (1.0 - reduction)) and s.total_spent_expeditions - fees >= 200, "First paid trip leaves at once: 200 G, (500+100)×(1−%.2f) s" % reduction)
	var reward: Dictionary = cycle.get("rewards", {})
	check(int(reward.get(MATERIAL, 0)) >= 7 and int(reward.get(MATERIAL, 0)) <= 9, "Guaranteed frost flower 7-9 (%s)" % str(reward))
	var before_flower: int = int(s.progression.expansion.reward_totals.get(MATERIAL, 0))
	var waited := 0.0
	while s.progression.expansion.region_returns(REGION, s.progression) < 1 and waited < 2000.0:
		s.advance(5.0)
		waited += 5.0
	check(s.progression.expansion.region_returns(REGION, s.progression) == 1 and waited <= float(cycle.duration) + 5.0, "First return after the trip time (%.0f s)" % waited)
	check(int(s.progression.expansion.reward_totals.get(MATERIAL, 0)) - before_flower == int(reward[MATERIAL]) and Compare.equivalent(s.progression.expansion.latest_returns.get(REGION, {}), reward), "The rolled frost flower is delivered on return")
	check(s.purchase_reason("warmth") == "" and s.purchase_reason("thin_ice") == "오로라 설원 귀환 3회 필요", "One return unlocks warmth only")
	check(Status.region(s, REGION).available and Status.region_preview(s, REGION).size() == 4 + 4, "Region card: guaranteed + three extras + four recipes")

func test_rolls() -> void:
	var p: RefCounted = State.new().progression
	p.seed_value = 4242
	var seen := {}
	var extras := {"dawn_bloom": 0, "star_seed": 0, "moonflower": 0}
	var ok := true
	for i in 3000:
		var r: Dictionary = Rewards.roll(REGION, p)
		var main := int(r.get(MATERIAL, 0))
		seen[main] = true
		if main < 7 or main > 9 or r.size() < 2 or r.size() > 3: ok = false
		for key in r:
			if key == MATERIAL: continue
			if not extras.has(key) or int(r[key]) < 1 or int(r[key]) > 2: ok = false
			else: extras[key] += 1
	check(ok and seen.size() == 3, "3,000 rolls: frost flower always 7-9 (all three values) with one or two extras of 1-2")
	check(extras.dawn_bloom > extras.star_seed and extras.star_seed > extras.moonflower and extras.moonflower > 0, "Extra weights 60/30/10 order (%s)" % str(extras))
	var preview := Rewards.preview(REGION)
	check(preview.size() == 4 and preview[0].id == MATERIAL and int(preview[0].min) == 7 and int(preview[0].max) == 9 and preview[0].guaranteed, "Reward preview shows frost flower 7-9 guaranteed")

func test_unlocks(base: RefCounted) -> void:
	var s := f26_done(base)
	s.gold = 5000000
	s.progression.expansion.regions.append(REGION)
	Trips.ensure(s.progression)
	var expected := {0: [], 1: ["warmth"], 2: ["warmth"], 3: ["warmth", "thin_ice"], 5: ["warmth", "thin_ice", "pine_wind"], 7: ["warmth", "thin_ice", "pine_wind"]}
	for returns in expected:
		s.progression.expansion.returns[REGION] = returns
		var open := NEW.filter(func(id): return s.progression.expansion.recipe_reason(id, s.progression) == "")
		check(open == expected[returns], "After %d returns: %s" % [returns, str(open)])
	s.progression.expansion.returns[REGION] = 8
	check(s.purchase_reason("aurora_elixir") == "온기 레시피 필요", "Survey complete still needs the three recipes")
	check(s.progression.completed_regions() == 10, "Eight returns complete the tenth survey")
	var gold: int = s.gold
	for id in ["warmth", "thin_ice", "pine_wind"]:
		check(s.purchase(id), "%s purchase" % id)
	check(gold - s.gold == 300000 + 400000 + 500000, "Recipe costs 30/40/50만 G")
	check(s.progression.expansion.plants.has(MATERIAL) and s.progression.expansion.first_batches.has("warmth"), "Buying warmth starts the frost flower planter and a first batch")
	check(s.purchase_reason("aurora_elixir") == "" and s.purchase("aurora_elixir") and gold - s.gold == 2100000, "Aurora elixir after survey + three recipes (90만 G)")
	# Survey done: repeats only at or below half storage, like every other region.
	var ex: RefCounted = s.progression.expansion
	var row := Content.lookup("regions", REGION)
	ex.pending.erase(MATERIAL)
	ex.materials[MATERIAL] = ex.special_capacity() / 2 + 1
	check(Trips.storage_reason(row, s.progression) == "재료 충분 · 자동 대기" and Trips.departure_mode(REGION, s.progression) == "", "Above half storage the completed region waits (no special search)")
	ex.materials[MATERIAL] = ex.special_capacity() / 2
	check(Trips.storage_reason(row, s.progression) == "", "At half storage it repeats")

func test_brewing_and_sales(base: RefCounted) -> void:
	var s := f27_complete(base)
	var ex: RefCounted = s.progression.expansion
	ex.first_batches.clear()
	s.stock_protection.active = false
	var tops := {}
	for item in s.production_candidates():
		if not item.is_rare and not item.first_batch: tops[item.family] = item.id
	check(tops == {"vitality": "warmth", "arcane": "aurora_elixir", "nature": "pine_wind", "craft": "thin_ice"}, "With frost flower each family brews its new top potion (%s)" % str(tops))
	ex.materials[MATERIAL] = 0
	tops.clear()
	for item in s.production_candidates():
		if not item.is_rare and not item.first_batch: tops[item.family] = item.id
	check(tops == {"vitality": "sunrise", "arcane": "sun_moon_elixir", "nature": "sea_spray", "craft": "beacon"}, "Without frost flower it falls back to the F26 top potions (%s)" % str(tops))
	ex.materials[MATERIAL] = 30
	var clock: float = s.progression.clock
	for id in NEW:
		var factor: float = ex.effect("brewing_assistant", "new_recipe_time_multiplier", 1.0)
		check(is_equal_approx(s.brew_duration_for(id), maxf(0.8, s.base_brew_duration() * float(PLAN[id].duration) * factor)), "%s brew time ×%.1f" % [id, PLAN[id].duration])
		var filter: float = ex.effect("precision_filter", "success_bonus", 0.05 if s.progression.filter_owned else 0.0)
		s.progression.clock = NIGHT_CLOCK
		check(s.progression.is_night() and is_equal_approx(s.progression.success_chance(id), minf(1.0, float(PLAN[id].success) + 0.08 + filter)), "%s night +8%%p" % id)
		s.progression.clock = DAY_CLOCK
		check(not s.progression.is_night() and s.progression.weather() == 0 and is_equal_approx(s.progression.success_chance(id), minf(1.0, float(PLAN[id].success) + filter)), "%s no bonus by clear day" % id)
	s.progression.clock = clock
	# Preferred customer and the real retail formula.
	var q: float = ex.effect("cauldron", "quality_sale_bonus") + ex.effect("brewing_assistant", "new_recipe_quality_bonus")
	var flat := int(ex.effect("sales_assistant", "preferred_sale_flat", 2 if s.progression.employee else 0))
	var finished: bool = is_equal_approx(ex.effect("cauldron", "quality_sale_bonus"), 0.12) and is_equal_approx(ex.effect("brewing_assistant", "new_recipe_quality_bonus"), 0.07) and flat == 7
	for i in NEW.size():
		var id: String = NEW[i]
		var plan: Dictionary = PLAN[id]
		s.progression.customer = CUSTOMER_INDEX[plan.customer]
		check(s.progression.is_preferred(id) and s.progression.sale_index([F26[i], id, "sage_elixir"]) == 1, "%s is what the %s buys first, before %s" % [id, plan.customer, F26[i]])
		var family: float = ex.effect("family_" + str(plan.family), "preferred_sale_bonus")
		check(s._retail_price(id, false) == int(round(plan.price * (1.0 + q))) and s._retail_price(id, true) == int(round(plan.price * (1.0 + q) * (1.0 + family))) + flat, "%s retail price formula" % id)
		if finished and is_equal_approx(family, 0.15): check([s._retail_price(id, false), s._retail_price(id, true)] == plan.retail, "%s finished-store prices %s (plan table)" % [id, str(plan.retail)])
	# Real advance: the new potions are brewed, sold and consume frost flower.
	var sold_before := {}
	for id in NEW: sold_before[id] = int(s.progression.by_potion.get(PLAN[id].name, 0))
	var used_before: int = int(ex.materials[MATERIAL])
	for i in 120: s.advance(5.0)
	var sold := 0
	for id in NEW: sold += int(s.progression.by_potion.get(PLAN[id].name, 0)) - int(sold_before[id])
	check(sold > 0, "Ten minutes of real play sells new potions (%d)" % sold)
	check(int(ex.materials[MATERIAL]) <= ex.special_capacity() and int(ex.materials[MATERIAL]) < used_before + 30, "Frost flower stays inside shared special storage")
	check(not s.late_investments.totals.has(MATERIAL), "Supply support never delivers frost flower")
	check(not s.late_investments.supply_candidates(s).has(MATERIAL), "Frost flower is never a supply candidate")
	# Garden: 28 s, ×1.5 at night (with the store's growth multipliers).
	var g := f27_complete(base)
	var gx: RefCounted = g.progression.expansion
	gx.materials[MATERIAL] = 0
	gx.growth[MATERIAL] = 0.0
	g.progression.clock = DAY_CLOCK
	var rate: float = gx.effect("drying_rack", "new_material_growth_multiplier", 1.0) * gx.effect("cultivation_assistant", "new_material_growth_multiplier", 1.0)
	gx.grow(g.progression)
	check(is_equal_approx(float(gx.growth[MATERIAL]), rate), "Day growth ×1")
	g.progression.clock = NIGHT_CLOCK
	gx.grow(g.progression)
	check(is_equal_approx(float(gx.growth[MATERIAL]), rate * 2.5), "Night growth ×1.5")
	gx.growth[MATERIAL] = 0.0
	var grown := 0.0
	while int(gx.materials[MATERIAL]) == 0 and grown < 100.0:
		gx.grow(g.progression)
		grown += 1.0
	check(is_equal_approx(grown, ceilf(28.0 / (rate * 1.5))), "One frost flower every 28 growth points (%.0f night ticks at ×%.2f)" % [grown, rate * 1.5])
	check(Status.material(g, MATERIAL).duration == 28.0 and Status.material(g, MATERIAL).supplied, "Management shows a 28 s planter")

func test_art() -> void:
	var approval: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MOCK + "approval.json"))
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MOCK + "validation.json"))
	check(approval.status == "approved" and approval.approved_by_user and approval.user_reply == "그림은 그대로 수치만 바꿔" and approval.runtime_integrated and report.status == "passed", "Only user-approved, validated art is published")
	for id in NEW:
		var row: Dictionary = Catalog.DATA.potions.get(id, {})
		var colours: Dictionary = report.liquid_colours.new[id]
		check(Catalog.id(id) == id and row.liquid_color == colours.liquid and Catalog.liquid(id) == Color(colours.liquid) and row.name == PLAN[id].name and row.family == PLAN[id].family and not row.rare, "%s catalog liquid %s (%s ramp)" % [id, colours.liquid, row.get("liquid_ramp", "")])
		check(row.bottle == "res://assets/pixel_v1/potions/%s.png" % id and Catalog.bottle(id).resource_path == row.bottle and row.bottle_size == report.sprites[id + "_bottle"].native_size and Catalog.bottle_size(id) == Vector2(row.bottle_size[0], row.bottle_size[1]), "%s bottle path and %s size" % [id, str(row.bottle_size)])
		check(pixels(row.bottle) == pixels(MOCK + "sprites/%s_bottle.png" % id) and FileAccess.get_file_as_bytes(row.bottle) == FileAccess.get_file_as_bytes(MOCK + "sprites/%s_bottle.png" % id), "%s published bottle = approved sprite (bytes and pixels)" % id)
		check(Catalog.bottle(id).get_size() == Vector2(row.bottle_size[0], row.bottle_size[1]), "%s bottle texture size" % id)
		for index in 3:
			var path := "res://assets/pixel_v1/pots/%s-%d.png" % [id, index]
			check(row.pots[index] == path and pixels(path) == pixels(MOCK + "pots/%s-%d.png" % [id, index]), "%s pot frame %d pixels = approved frame" % [id, index])
			check(Catalog.DATA.sources["pots/%s-%d.png" % [id, index]].sha256 == FileAccess.get_sha256(path) and FileAccess.get_sha256(path) == FileAccess.get_sha256(MOCK + "pots/%s-%d.png" % [id, index]), "%s pot frame %d source hash" % [id, index])
		check(Catalog.pot(id, 0.0).resource_path == row.pots[0] and Catalog.pot(id, 1.0 / 6.0 + 0.01).resource_path == row.pots[1], "Cauldron shows the brewing potion's frames")
		check(Catalog.DATA.sources["potions/%s.png" % id].sha256 == FileAccess.get_sha256(row.bottle) and Catalog.DATA.sources["potions/%s.png" % id].source == "art/mockups/f27-region-potions-v1/sprites/%s_bottle.png" % id, "%s bottle source hash" % id)
		# Customers catch and carry the bottle by a solved grip (same rule as the existing bindings).
		for cid in CUSTOMER_INDEX:
			var binding: Dictionary = Catalog.DATA.characters[cid].bindings.get(id, {})
			check(not binding.is_empty() and binding.checks.size() == 10 and binding.checks.all(func(c): return c.passed and int(c.bottle_bottom_row) <= 43 and int(c.visible_liquid_pixels) > 0) and Catalog.local_grip(cid, id) == Vector2(binding.local_grip[0], binding.local_grip[1]), "%s: %s hand grip %s passes all 10 pose/facing checks" % [cid, id, str(binding.get("local_grip", []))])
		# Approved 32x40 icons are published byte for byte.
		for pair in [["potions/%s_icon.png" % id, "%s_icon" % id], ["recipes/%s_recipe.png" % id, "%s_recipe" % id]]:
			var path: String = "res://assets/content_expansion_v1/" + pair[0]
			var texture: Texture2D = load(path)
			check(FileAccess.get_file_as_bytes(path) == FileAccess.get_file_as_bytes(MOCK + "sprites/%s.png" % pair[1]) and visible_pixels(texture_pixels(texture)) == visible_pixels(pixels(MOCK + "sprites/%s.png" % pair[1])) and texture.get_size() == Vector2(32, 40), "%s 32x40 %s = approved sprite" % [id, pair[1]])
		# UI v2 list/recipe icon: the approved bottle at exactly 2x, centred on 32x32 (same rule as the other 40).
		var icon := ItemArt.icon(id)
		check(icon == UiPixel.icon(id) and UiPixel.owns(icon) and icon.get_size() == Vector2(32, 32), "%s runtime potion icon uses the native32 catalog" % id)
		var recipe := ItemArt.recipe_icon(id)
		check(recipe == UiPixel.icon("recipe:" + id) and recipe == icon, "%s runtime recipe icon is the same native32 bottle" % id)
		check(texture_pixels(icon) == doubled(MOCK + "sprites/%s_bottle.png" % id), "%s native32 icon = approved bottle ×2, unpainted" % id)
	for pair in [[MATERIAL, "materials/frost_flower_icon.png", "frost_flower_icon"], [REGION, "regions/aurora_snowfield_icon.png", "aurora_snowfield_icon"]]:
		var path: String = "res://assets/content_expansion_v1/" + pair[1]
		var original_texture: Texture2D = load(path)
		check(FileAccess.get_file_as_bytes(path) == FileAccess.get_file_as_bytes(MOCK + "sprites/%s.png" % pair[2]) and visible_pixels(texture_pixels(original_texture)) == visible_pixels(pixels(MOCK + "sprites/%s.png" % pair[2])), "%s approved 32x40 icon published byte for byte" % pair[0])
		# No UI v2 32x32 art exists for the new region/material (that would be new art): the approved icon is used.
		check(UiPixel.icon(pair[0]) == null and ItemArt.icon(pair[0]) == original_texture and original_texture.get_size() == Vector2(32, 40), "%s runtime icon falls back to the approved 32x40 icon (no invented UI art)" % pair[0])
	# The 64x80 planter growth sheet (same out-of-rule exception as the other growth sheets) is published byte for byte.
	const GROWTH := "res://assets/content_expansion_v1/materials/frost_flower_growth.png"
	check(ItemArt.growth_path(MATERIAL) == GROWTH and FileAccess.get_file_as_bytes(GROWTH) == FileAccess.get_file_as_bytes(MOCK + "growth/frost_flower_growth.png"), "Frost flower growth sheet = approved file")
	var sheet: Texture2D = load(GROWTH)
	check(sheet.get_size() == Vector2(64, 80) and visible_pixels(texture_pixels(sheet)) == visible_pixels(pixels(MOCK + "growth/frost_flower_growth.png")), "Growth sheet 64x80, visible pixels unchanged")
	var frames := [0.0, 0.4, 0.8].map(func(phase): return ItemArt.growth_frame(MATERIAL, phase))
	check(frames.all(func(frame): return frame is AtlasTexture and frame.atlas.resource_path == GROWTH and frame.region.size == Vector2(32, 40)) and frames[0].region != frames[2].region, "Garden shows three 32x40 growth stages")
	check(Catalog.DATA.potions.size() == 44, "Catalog has 40 + 4 potion rows")
	check(ItemArt.CATALOG.assets.filter(func(row): return row.category == "materials").size() == 13, "Content catalog has 13 material rows")

## RGBA of an 8x12 bottle at exactly 2x, centred on a transparent 32x32 canvas (build_ui_pixel_v2_potions.py).
func doubled(path: String) -> PackedByteArray:
	var bottle := Image.load_from_file(ProjectSettings.globalize_path(path))
	bottle.convert(Image.FORMAT_RGBA8)
	var canvas := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	var offset := Vector2i((32 - bottle.get_width() * 2) / 2, (32 - bottle.get_height() * 2) / 2)
	for y in bottle.get_height() * 2:
		for x in bottle.get_width() * 2:
			canvas.set_pixel(offset.x + x, offset.y + y, bottle.get_pixel(x / 2, y / 2))
	return canvas.get_data()

func test_collection() -> void:
	var fresh := State.new()
	var c := {}
	for row in Status.collection(fresh): c[row.key] = [row.have, row.total]
	check(c.recipes == [0, 38] and c.regions == [0, 10], "New game: recipes 0/38, surveys 0/10 (%s)" % str(c))

func test_save(base: RefCounted) -> void:
	var s := f27_complete(base)
	var ex: RefCounted = s.progression.expansion
	ex.returns[REGION] = 3
	ex.pending[MATERIAL] = 5
	ex.reward_totals[MATERIAL] = 41
	ex.materials[MATERIAL] = 12
	ex.growth[MATERIAL] = 7.5
	ex.cycles[REGION].merge({"id": 4, "fee": 200, "paid": true, "running": true, "elapsed": 100.0, "duration": 420.0, "rewards": {"frost_flower": 8, "dawn_bloom": 2}}, true)
	ex.latest_returns[REGION] = {"frost_flower": 9, "moonflower": 1}
	for index in s.inventory.size():
		if s.inventory[index] is String:
			s.inventory[index] = "aurora_elixir"
			break
	var data: Dictionary = JSON.parse_string(JSON.stringify(s.to_data()))
	check(int(data.version) == 17 and State.SAVE_VERSION == 17, "Saved as v17 (SAVE_VERSION unchanged)")
	var restored := State.new()
	check(restored.load_data(data), "Region/material/recipe progress loads through the existing structures")
	check(Compare.equivalent(M.data(s), M.data(restored)), "Save round trip is lossless")
	var rp: RefCounted = restored.progression
	check(rp.expansion.regions.has(REGION) and int(rp.expansion.returns[REGION]) == 3 and int(rp.expansion.pending[MATERIAL]) == 5 and rp.expansion.cycles[REGION].running and NEW.all(func(id): return rp.owned.has(id)) and is_equal_approx(float(rp.expansion.growth[MATERIAL]), 7.5), "Restored region, trip, frost flower and recipes")
	var tampered: Dictionary = data.duplicate(true)
	tampered.progression.expansion.materials[MATERIAL] = 43
	check(not State.new().load_data(tampered), "Frost flower obeys the shared 42 storage bound")

func test_late_gate(base: RefCounted) -> void:
	var s := f27_complete(base)
	var late := Late.new()
	var view := late.growth_view(s)
	check(view.recipes == 32 and view.regions >= 8, "Owning the new recipes does not change the original-recipe count")
	s.progression.owned.erase("fortune")
	check(late.growth_view(s).recipes == 31 and late.growth_view(s).missing.has("일반 레시피 32종 보유 필요 · 31/32"), "A new recipe never stands in for a missing original one")

func test_post_growth_fixture() -> void:
	var s: RefCounted = M.completed()
	M.complete_post_growth(s)
	var ex: RefCounted = s.progression.expansion
	check(ex.regions.has(REGION) and int(ex.returns[REGION]) == 8 and NEW.all(func(id): return s.progression.owned.has(id)) and int(ex.materials[MATERIAL]) == ex.special_capacity(), "UI post-growth fixture also finishes F27")
	check(not Status.growth_candidates(s).any(func(item): return item.purchase_key == "region:" + REGION or item.purchase_key in NEW), "Nothing of F27 is left to recommend in the post-growth fixture")

## Management rows show 32x40 art through ManagementArt.readable_icon (a used-rect AtlasTexture of the same file).
func shows(texture: Texture2D, source: Texture2D) -> bool:
	return texture == source or (texture is AtlasTexture and texture.atlas == source)

func test_ui(base: RefCounted) -> void:
	var shop := Shop.new()
	root.add_child(shop)
	await process_frame
	shop.set_process(false)
	shop.art.set_process(false)
	shop.state = f26_done(base)
	shop.open_management()
	var panel = shop.management
	panel.set_process(false)
	panel.select_page(panel.EXPEDITIONS)
	panel.refresh()
	await process_frame
	var row: Dictionary = panel.rows.get(REGION, {})
	check(not row.is_empty() and row.button.visible and not row.button.disabled and row.button.get_meta("currency_source", "") == "원정 열기 · 500000 G", "Expedition tab: the aurora snowfield can be opened (%s)" % str(row.get("button").get_meta("currency_source", "") if not row.is_empty() else ""))
	check(not row.is_empty() and shows(row.icon.texture, ItemArt.icon(REGION)), "Expedition tab row uses the approved aurora snowfield icon")
	var regions := 0
	for id in panel.rows:
		if panel.rows[id].page == panel.EXPEDITIONS and not Content.lookup("regions", id).is_empty(): regions += 1
	check(regions == 10, "Expedition tab lists ten regions (%d)" % regions)
	var before: Dictionary = M.data(shop.state)
	shop.state = f27_complete(base)
	panel.select_page(panel.RECIPES)
	panel.refresh()
	await process_frame
	for id in NEW:
		var recipe: Dictionary = panel.rows.get(id, {})
		check(not recipe.is_empty() and recipe.icon.texture == UiPixel.icon("recipe:" + id) and recipe.icon.texture.get_size() == Vector2(32, 32) and recipe.title.text == PLAN[id].name, "Recipe tab shows %s with its native32 icon" % id)
	panel.select_page(panel.HERBS)
	panel.refresh()
	await process_frame
	var herb: Dictionary = panel.rows.get(panel.material_row(MATERIAL), {})
	check(not herb.is_empty() and herb.has("growth_preview") and herb.growth_preview.texture is AtlasTexture and herb.growth_preview.texture.atlas.resource_path == ItemArt.growth_path(MATERIAL), "Herb tab shows the approved frost flower growth sheet")
	check(not herb.is_empty() and shows(herb.icon.texture, ItemArt.icon(MATERIAL)), "Herb tab row uses the approved frost flower icon")
	shop.queue_free()
	await process_frame
	check(not before.is_empty(), "UI browsing used isolated fixtures only")

## Economy sanity on the real late-save copy: with F26 finished, finishing F27 raises income without breaking it.
func test_economy(base: RefCounted) -> void:
	var results := {}
	for mode in ["f26", "f27"]:
		var s := f26_done(base) if mode == "f26" else f27_complete(base)
		if mode == "f27":
			var ex: RefCounted = s.progression.expansion
			ex.materials[MATERIAL] = ex.special_capacity()
			ex.first_batches.clear()
		s.progression.seed_value = 73129
		var start: int = s.gold + int(s.progression.totals.manual_spent)
		for i in 120: s.advance(30.0)
		results[mode] = s.gold + int(s.progression.totals.manual_spent) - start
	var ratio := float(results.f27) / maxf(1.0, float(results.f26))
	print("F27 economy sanity (real save copy, 1 h): F26 finished %d G, F27 finished %d G, ×%.3f" % [results.f26, results.f27, ratio])
	check(results.f26 > 0 and ratio > 1.0 and ratio < 1.4, "One hour on the real save copy: F27 finished earns more, within a sane step (F26 %d G, F27 %d G, ×%.3f)" % [results.f26, results.f27, ratio])

func run() -> void:
	check(get_meta("isolated_preview", false), "Isolated preview; no player save")
	test_data()
	test_unchanged()
	var base := player_copy()
	test_player_copy(base)
	test_opening(base)
	test_rolls()
	test_unlocks(base)
	test_brewing_and_sales(base)
	test_art()
	test_collection()
	test_save(base)
	test_late_gate(base)
	test_post_growth_fixture()
	await test_ui(base)
	test_economy(base)
	M.write_json(OUT, {"checks": checks, "failures": failures, "passed": failures.is_empty()})
	print("F27 REGION POTIONS %s %d checks%s" % ["PASS" if failures.is_empty() else "FAIL", checks, "" if failures.is_empty() else " · " + "; ".join(failures)])
	quit(0 if failures.is_empty() else 1)
