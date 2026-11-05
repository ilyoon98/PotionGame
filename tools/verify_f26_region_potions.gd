extends SceneTree
## F26 dawn lighthouse (approved 2026-11-05, "새 지역 제안대로"): catalog rows and the plan's numbers, the
## opening gate/cost, real trips and the guaranteed dawn bloom, unlock order (returns 1/3/5, survey + three
## recipes), brewing/sales (prices, preferred customers, environment), published pixels = approved sprites,
## catalog rows, collection totals, save round trip, supply-support exclusion, unchanged pre-F26 content, and
## the read-only copy of a real late save. Isolated: never reads or writes the player's AppData save.
const Shop = preload("res://scripts/shop.gd")
const State = preload("res://scripts/shop_state.gd")
const Content = preload("res://scripts/shop_content.gd")
const Rewards = preload("res://scripts/expedition_rewards.gd")
const Trips = preload("res://scripts/parallel_expeditions.gd")
const Rare = preload("res://scripts/rare_recipes.gd")
const Late = preload("res://scripts/shop_late_investments.gd")
const Catalog = preload("res://scripts/pixel_art_catalog.gd")
const ItemArt = preload("res://scripts/item_art.gd")
const Status = preload("res://scripts/management_status.gd")
const M = preload("res://tests/contracts_fixture.gd")
const Compare = preload("res://tests/state_compare.gd")
const MOCK := "res://art/mockups/f26-region-potions-v1/"
const PLAYER_COPY := "res://.verification/real-save-check-20261105/player-copy.json"
const OUT := "res://.verification/f26-region-potions-20261105/result.json"
const REGION := "dawn_lighthouse"
const MATERIAL := "dawn_bloom"
const NEW := ["sunrise", "beacon", "sea_spray", "sun_moon_elixir"]
## docs/새-원정-지역과-물약-F26-기획안.md §2 (approved as proposed).
const PLAN := {
	"sunrise": {"name": "해돋이", "family": "vitality", "customer": "traveler", "order": 36, "returns": 1, "recipes": [], "cost": 250000, "price": 200, "ingredients": {"herb": 2, "dawn_bloom": 1, "dewgrass": 1}, "duration": 3.1, "success": 0.82, "retail": [238, 281]},
	"beacon": {"name": "등대불", "family": "craft", "customer": "rogue", "order": 37, "returns": 3, "recipes": [], "cost": 350000, "price": 215, "ingredients": {"herb": 2, "dawn_bloom": 1, "mist_mushroom": 1}, "duration": 3.2, "success": 0.8, "retail": [256, 301]},
	"sea_spray": {"name": "물보라", "family": "nature", "customer": "elf", "order": 38, "returns": 5, "recipes": [], "cost": 450000, "price": 230, "ingredients": {"herb": 2, "dawn_bloom": 1, "blue_reed": 1}, "duration": 3.3, "success": 0.8, "retail": [274, 322]},
	"sun_moon_elixir": {"name": "일월의 물약", "family": "arcane", "customer": "mage", "order": 39, "returns": 8, "recipes": ["sunrise", "beacon", "sea_spray"], "cost": 800000, "price": 320, "ingredients": {"herb": 2, "dawn_bloom": 1, "moonflower": 1, "star_seed": 1}, "duration": 3.6, "success": 0.78, "retail": [381, 445]},
}
## Hashes of the pre-F26 rows, computed from commit 6721912 before any F26 change (same expressions below).
const BEFORE := {
	"potions32": "d888996900aef26346496d541bcb7456b150ad0ca08bafac8df445a7ea39761b",
	"regions8": "fd52f22f2570a47611762b57189ada6187d322200c6181fd0d633b556d21b587",
	"materials11": "24f20ce9123c064293ed8eb60447ed7a57af6c4be2d93033226ea4244336294e",
	"upgrades": "3554111897d1c0ebeee0c2462e854bdd9694f61de6d5f9115968ff6000334b4b",
	"recipes": "39c74cc2ea0ffdcd9be28d8b6ac315e20b79f264185e6d6d2f0a0b8201cb3fd8",
	"pools8": "82ef3f799ce789f7d9f6b8054fff84b67081d7e7dde1167f7362f2a1bc7d55bb",
	"catalog36": "c9e92ee2a3ae439d0d33c3f0e743c5e780688afe74fd4a6733eb0a2cbc11838b",
}
const CUSTOMER_INDEX := {"traveler": 0, "mage": 2, "elf": 3, "rogue": 4}
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

## Owns the region, a finished survey and all four recipes, with plenty of every ingredient.
func f26_complete(base: RefCounted) -> RefCounted:
	var s := clone(base)
	var ex: RefCounted = s.progression.expansion
	if not ex.regions.has(REGION): ex.regions.append(REGION)
	ex.returns[REGION] = 8
	Trips.ensure(s.progression)
	for id in NEW:
		if not s.progression.owned.has(id):
			s.progression.owned.append(id)
			ex.grant_recipe(id)
	for id in ["dawn_bloom", "dewgrass", "mist_mushroom", "blue_reed", "moonflower", "star_seed", "silver_moss", "crystal_herb", "ash_sage", "starleaf"]:
		if id == "starleaf": s.progression.rare_herbs = 30
		else: ex.materials[id] = 30
	s.herbs = s.herb_capacity()
	return s

func test_data() -> void:
	var region := Content.lookup("regions", REGION)
	check(Content.DATA.regions.size() == 9 and Content.DATA.regions[-1].id == REGION, "Nine regions; the dawn lighthouse is ninth")
	check(region.name == "새벽 등대" and int(region.cost) == 400000 and int(region.explore_seconds) == 450 and int(region.return_seconds) == 90 and int(region.departure_cost) == 150 and int(region.complete_returns) == 8 and region.previous_region == "star_garden" and int(region.reputation) == 0, "Region values follow the plan (400,000 G, 450+90 s, 150 G, 8 returns, after the star garden)")
	check(region.material == MATERIAL and int(region.repeat_material_quantity) == 7 and Compare.equivalent(region.rewards, {"dawn_bloom": 7}), "Region's main material is dawn bloom")
	var pool: Dictionary = Rewards.POOLS[REGION]
	check(pool.main == MATERIAL and int(pool.min) == 6 and int(pool.max) == 8 and pool.extra == ["star_seed", "moonflower", "dewgrass"], "Reward pool: dawn bloom 6-8 + star seed/moonflower/dewgrass (60/30/10)")
	check(Rare.by_region(REGION).is_empty(), "No special recipe for the dawn lighthouse")
	var material := Content.lookup("materials", MATERIAL)
	check(Content.DATA.materials.size() == 12 and material.name == "여명초" and material.source == "recipe_granted_garden" and material.region == REGION and int(material.growth_seconds) == 26 and material.environment == "clear" and float(material.favored_growth_multiplier) == 1.5 and int(material.seed_quantity) == 2, "Dawn bloom: garden 26 s, clear ×1.5, two seeds, region dawn lighthouse")
	check(Content.DATA.potions.size() == 36 and Content.RECIPES.size() + 2 == 40, "36 ordinary rows (32 + 4) and 40 recipes with the four specials")
	for id in NEW:
		var row := Content.lookup("potions", id)
		var plan: Dictionary = PLAN[id]
		var unlock: Dictionary = row.unlock
		check(row.name == plan.name and row.family == plan.family and row.preferred_customer == plan.customer and int(row.order) == plan.order and not row.existing and not row.owned_at_start, "%s identity/family/customer/order" % id)
		check(Compare.equivalent(unlock.discovery, {"region": REGION, "returns": plan.returns}) and unlock.get("recipes", []) == plan.recipes, "%s unlock: dawn lighthouse return %d%s" % [id, plan.returns, " + three recipes" if not plan.recipes.is_empty() else ""])
		check(int(row.cost) == plan.cost and int(row.sale_price) == plan.price and Compare.equivalent(row.ingredients, plan.ingredients) and is_equal_approx(float(row.duration_multiplier), plan.duration) and is_equal_approx(float(row.success), plan.success) and row.environment == "clear" and is_equal_approx(float(row.environment_bonus), 0.08), "%s cost %d, price %d, ingredients, ×%.1f, %d%%, clear +8%%p" % [id, plan.cost, plan.price, plan.duration, int(plan.success * 100)])
		var recipe: Dictionary = Content.RECIPES[id]
		check(recipe.name == plan.name and int(recipe.cost) == plan.cost and int(recipe.price) == plan.price and is_equal_approx(float(recipe.duration), plan.duration) and is_equal_approx(float(recipe.success), plan.success), "%s recipe table" % id)
		check(row.grant_sources == plan.ingredients.keys().filter(func(m): return m != "herb") and row.grant_sources.has(MATERIAL), "%s grants the dawn bloom planter" % id)

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
	var now := {
		"potions32": JSON.stringify(Content.DATA.potions.slice(0, 32)).sha256_text(),
		"regions8": JSON.stringify(Content.DATA.regions.slice(0, 8)).sha256_text(),
		"materials11": JSON.stringify(Content.DATA.materials.slice(0, 11)).sha256_text(),
		"upgrades": JSON.stringify(Content.DATA.upgrades).sha256_text(),
		"recipes": JSON.stringify(recipes).sha256_text(),
		"pools8": JSON.stringify(pools).sha256_text(),
		"catalog36": JSON.stringify(catalog_rows).sha256_text(),
	}
	for key in BEFORE: check(now[key] == BEFORE[key], "Pre-F26 %s unchanged" % key)
	check(Late.SPECIAL_IDS == ["starleaf", "dewgrass", "silver_moss", "blue_reed", "crystal_herb", "mist_mushroom", "ash_sage", "moonflower", "star_seed"], "Supply support list unchanged (no dawn bloom)")

func test_player_copy(base: RefCounted) -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PLAYER_COPY))
	check(int(raw.version) == 17 and State.SAVE_VERSION == 17, "Save format stays v17")
	var p: RefCounted = base.progression
	check(p.completed_regions() == 8 and p.owned.size() + 2 == 36 and base.gold == int(raw.gold), "Copy is the late state: 8 surveys, 36 potions, gold preserved")
	check(not Trips.opened(REGION, p) and not p.expansion.cycles.has(REGION), "Dawn lighthouse is not open in the old save")
	check(p.expansion.region_reason(REGION, p) == "" and base.purchase_reason("region:" + REGION) == "", "Dawn lighthouse can be opened right away")
	check(Status.growth_candidates(base).any(func(item): return item.purchase_key == "region:" + REGION), "Growth recommendations offer the new region")
	for id in NEW: check(base.purchase_reason(id) == "새벽 등대 귀환 %d회 필요" % int(PLAN[id].returns), "%s waits for dawn lighthouse returns" % id)
	var c := {}
	for row in Status.collection(base): c[row.key] = [row.have, row.total]
	check(c.recipes == [30, 34] and c.regions == [8, 9], "Collection shows recipes 30/34 and surveys 8/9 (%s)" % str(c))
	check(Late.new().growth_view(base).recipes == 32, "Late-investment gate counts the original 32 recipes")
	var again := clone(base)
	check(Compare.equivalent(M.data(base), M.data(again)), "The loaded copy round-trips unchanged")

func test_opening(base: RefCounted) -> void:
	var early := clone(base)
	early.progression.expansion.returns["star_garden"] = 5
	check(early.purchase_reason("region:" + REGION) == "별의 정원 조사 필요", "Needs the star garden survey first")
	var poor := clone(base)
	poor.gold = 399999
	check(poor.purchase_reason("region:" + REGION) == "1 G 부족", "Exactly 400,000 G")
	var s := clone(base)
	s.gold = 1000000
	var spent: int = s.progression.totals.manual_spent
	var fees: int = s.total_spent_expeditions
	check(s.purchase("region:" + REGION), "Region purchase succeeds")
	var cycle: Dictionary = s.progression.expansion.cycles.get(REGION, {})
	check(s.progression.expansion.regions.has(REGION) and s.progression.totals.manual_spent - spent == 400000 and s.purchase_reason("region:" + REGION) == "개방 완료", "Opening costs 400,000 G once")
	var reduction := minf(0.3, s.progression.expansion.effect("expedition_path", "trip_time_reduction") + s.progression.expansion.effect("expedition_guide", "trip_time_reduction"))
	check(cycle.get("running", false) and int(cycle.fee) == 150 and is_equal_approx(float(cycle.duration), 540.0 * (1.0 - reduction)) and s.total_spent_expeditions - fees >= 150, "First paid trip leaves at once: 150 G, (450+90)×(1−%.2f) s" % reduction)
	var reward: Dictionary = cycle.get("rewards", {})
	check(int(reward.get(MATERIAL, 0)) >= 6 and int(reward.get(MATERIAL, 0)) <= 8, "Guaranteed dawn bloom 6-8 (%s)" % str(reward))
	var before_bloom: int = int(s.progression.expansion.reward_totals.get(MATERIAL, 0))
	var waited := 0.0
	while s.progression.expansion.region_returns(REGION, s.progression) < 1 and waited < 2000.0:
		s.advance(5.0)
		waited += 5.0
	check(s.progression.expansion.region_returns(REGION, s.progression) == 1 and waited <= float(cycle.duration) + 5.0, "First return after the trip time (%.0f s)" % waited)
	check(int(s.progression.expansion.reward_totals.get(MATERIAL, 0)) - before_bloom == int(reward[MATERIAL]) and Compare.equivalent(s.progression.expansion.latest_returns.get(REGION, {}), reward), "The rolled dawn bloom is delivered on return")
	check(s.purchase_reason("sunrise") == "" and s.purchase_reason("beacon") == "새벽 등대 귀환 3회 필요", "One return unlocks sunrise only")
	check(Status.region(s, REGION).available and Status.region_preview(s, REGION).size() == 4 + 4, "Region card: guaranteed + three extras + four recipes")

func test_rolls() -> void:
	var p: RefCounted = State.new().progression
	p.seed_value = 4242
	var seen := {}
	var extras := {"star_seed": 0, "moonflower": 0, "dewgrass": 0}
	var ok := true
	for i in 3000:
		var r: Dictionary = Rewards.roll(REGION, p)
		var main := int(r.get(MATERIAL, 0))
		seen[main] = true
		if main < 6 or main > 8 or r.size() < 2 or r.size() > 3: ok = false
		for key in r:
			if key == MATERIAL: continue
			if not extras.has(key) or int(r[key]) < 1 or int(r[key]) > 2: ok = false
			else: extras[key] += 1
	check(ok and seen.size() == 3, "3,000 rolls: dawn bloom always 6-8 (all three values) with one or two extras of 1-2")
	check(extras.star_seed > extras.moonflower and extras.moonflower > extras.dewgrass and extras.dewgrass > 0, "Extra weights 60/30/10 order (%s)" % str(extras))

func test_unlocks(base: RefCounted) -> void:
	var s := clone(base)
	s.gold = 5000000
	s.progression.expansion.regions.append(REGION)
	Trips.ensure(s.progression)
	var expected := {0: [], 1: ["sunrise"], 2: ["sunrise"], 3: ["sunrise", "beacon"], 5: ["sunrise", "beacon", "sea_spray"], 7: ["sunrise", "beacon", "sea_spray"]}
	for returns in expected:
		s.progression.expansion.returns[REGION] = returns
		var open := NEW.filter(func(id): return s.progression.expansion.recipe_reason(id, s.progression) == "")
		check(open == expected[returns], "After %d returns: %s" % [returns, str(open)])
	s.progression.expansion.returns[REGION] = 8
	check(s.purchase_reason("sun_moon_elixir") == "해돋이 레시피 필요", "Survey complete still needs the three recipes")
	check(s.progression.completed_regions() == 9, "Eight returns complete the ninth survey")
	var gold: int = s.gold
	for id in ["sunrise", "beacon", "sea_spray"]:
		check(s.purchase(id), "%s purchase" % id)
	check(gold - s.gold == 250000 + 350000 + 450000, "Recipe costs 25/35/45만 G")
	check(s.progression.expansion.plants.has(MATERIAL) and s.progression.expansion.first_batches.has("sunrise"), "Buying sunrise starts the dawn bloom planter and a first batch")
	check(s.purchase_reason("sun_moon_elixir") == "" and s.purchase("sun_moon_elixir") and gold - s.gold == 1850000, "Sun-moon elixir after survey + three recipes (80만 G)")
	# Survey done: repeats only at or below half storage, like every other region.
	var ex: RefCounted = s.progression.expansion
	var row := Content.lookup("regions", REGION)
	ex.pending.erase(MATERIAL)
	ex.materials[MATERIAL] = ex.special_capacity() / 2 + 1
	check(Trips.storage_reason(row, s.progression) == "재료 충분 · 자동 대기" and Trips.departure_mode(REGION, s.progression) == "", "Above half storage the completed region waits (no special search)")
	ex.materials[MATERIAL] = ex.special_capacity() / 2
	check(Trips.storage_reason(row, s.progression) == "", "At half storage it repeats")

func test_brewing_and_sales(base: RefCounted) -> void:
	var s := f26_complete(base)
	var ex: RefCounted = s.progression.expansion
	ex.first_batches.clear()
	s.stock_protection.active = false
	var tops := {}
	for item in s.production_candidates():
		if not item.is_rare and not item.first_batch: tops[item.family] = item.id
	check(tops == {"vitality": "sunrise", "arcane": "sun_moon_elixir", "nature": "sea_spray", "craft": "beacon"}, "With dawn bloom each family brews its new top potion (%s)" % str(tops))
	ex.materials[MATERIAL] = 0
	tops.clear()
	for item in s.production_candidates():
		if not item.is_rare and not item.first_batch: tops[item.family] = item.id
	check(not tops.values().any(func(id): return id in NEW) and tops.get("vitality", "") == "eternity" and tops.get("craft", "") == "shadow_elixir", "Without dawn bloom it falls back to the old top potions (%s)" % str(tops))
	ex.materials[MATERIAL] = 30
	var clock: float = s.progression.clock
	for id in NEW:
		var factor: float = ex.effect("brewing_assistant", "new_recipe_time_multiplier", 1.0)
		check(is_equal_approx(s.brew_duration_for(id), maxf(0.8, s.base_brew_duration() * float(PLAN[id].duration) * factor)), "%s brew time ×%.1f" % [id, PLAN[id].duration])
		var filter: float = ex.effect("precision_filter", "success_bonus", 0.05 if s.progression.filter_owned else 0.0)
		s.progression.clock = 10.0 # weather 0 = clear
		check(s.progression.weather() == 0 and is_equal_approx(s.progression.success_chance(id), minf(1.0, float(PLAN[id].success) + 0.08 + filter)), "%s clear weather +8%%p" % id)
		s.progression.clock = 100.0 # weather 1 = cloudy
		check(s.progression.weather() == 1 and is_equal_approx(s.progression.success_chance(id), minf(1.0, float(PLAN[id].success) + filter)), "%s no bonus when cloudy" % id)
	s.progression.clock = clock
	# Preferred customer and the real retail formula.
	var q: float = ex.effect("cauldron", "quality_sale_bonus") + ex.effect("brewing_assistant", "new_recipe_quality_bonus")
	var flat := int(ex.effect("sales_assistant", "preferred_sale_flat", 2 if s.progression.employee else 0))
	var finished: bool = is_equal_approx(ex.effect("cauldron", "quality_sale_bonus"), 0.12) and is_equal_approx(ex.effect("brewing_assistant", "new_recipe_quality_bonus"), 0.07) and flat == 7
	for id in NEW:
		var plan: Dictionary = PLAN[id]
		s.progression.customer = CUSTOMER_INDEX[plan.customer]
		check(s.progression.is_preferred(id) and s.progression.sale_index(["eternity", id, "sage_elixir"]) == 1, "%s is what the %s buys first" % [id, plan.customer])
		var family: float = ex.effect("family_" + str(plan.family), "preferred_sale_bonus")
		check(s._retail_price(id, false) == int(round(plan.price * (1.0 + q))) and s._retail_price(id, true) == int(round(plan.price * (1.0 + q) * (1.0 + family))) + flat, "%s retail price formula" % id)
		if finished and is_equal_approx(family, 0.15): check([s._retail_price(id, false), s._retail_price(id, true)] == plan.retail, "%s finished-store prices %s (plan table)" % [id, str(plan.retail)])
	# Real advance: the new potions are brewed, sold and consume dawn bloom.
	var sold_before := {}
	for id in NEW: sold_before[id] = int(s.progression.by_potion.get(PLAN[id].name, 0))
	var used_before: int = int(ex.materials[MATERIAL])
	for i in 120: s.advance(5.0)
	var sold := 0
	for id in NEW: sold += int(s.progression.by_potion.get(PLAN[id].name, 0)) - int(sold_before[id])
	check(sold > 0, "Ten minutes of real play sells new potions (%d)" % sold)
	check(int(ex.materials[MATERIAL]) <= ex.special_capacity() and int(ex.materials[MATERIAL]) < used_before + 30, "Dawn bloom stays inside shared special storage")
	check(not s.late_investments.totals.has(MATERIAL), "Supply support never delivers dawn bloom")
	check(not s.late_investments.supply_candidates(s).has(MATERIAL), "Dawn bloom is never a supply candidate")
	# Garden: 26 s, ×1.5 in clear weather (with the store's growth multipliers).
	var g := f26_complete(base)
	var gx: RefCounted = g.progression.expansion
	gx.materials[MATERIAL] = 0
	gx.growth[MATERIAL] = 0.0
	g.progression.clock = 100.0
	var rate: float = gx.effect("drying_rack", "new_material_growth_multiplier", 1.0) * gx.effect("cultivation_assistant", "new_material_growth_multiplier", 1.0)
	gx.grow(g.progression)
	check(is_equal_approx(float(gx.growth[MATERIAL]), rate), "Cloudy growth ×1")
	g.progression.clock = 10.0
	gx.grow(g.progression)
	check(is_equal_approx(float(gx.growth[MATERIAL]), rate * 2.5), "Clear growth ×1.5")
	check(Status.material(g, MATERIAL).duration == 26.0 and Status.material(g, MATERIAL).supplied, "Management shows a 26 s planter")

func test_art() -> void:
	var approval: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MOCK + "approval.json"))
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MOCK + "validation.json"))
	check(approval.status == "approved" and approval.approved_by_user and report.status == "passed", "Only user-approved, validated art is published")
	for id in NEW:
		var row: Dictionary = Catalog.DATA.potions.get(id, {})
		var colours: Dictionary = report.liquid_colours.new[id]
		check(Catalog.id(id) == id and row.liquid_color == colours.liquid and row.liquid_ramp == colours.ramp and Catalog.liquid(id) == Color(colours.liquid), "%s catalog liquid %s (%s ramp)" % [id, colours.liquid, colours.ramp])
		check(row.bottle == "res://assets/pixel_v1/potions/%s.png" % id and Catalog.bottle(id).resource_path == row.bottle and row.bottle_size == report.sprites[id + "_bottle"].native_size and Catalog.bottle_size(id) == Vector2(row.bottle_size[0], row.bottle_size[1]), "%s bottle path and %s size" % [id, str(row.bottle_size)])
		check(pixels(row.bottle) == pixels(MOCK + "sprites/%s_bottle.png" % id), "%s published bottle pixels = approved sprite" % id)
		check(Catalog.bottle(id).get_size() == Vector2(row.bottle_size[0], row.bottle_size[1]), "%s bottle texture size" % id)
		for index in 3:
			var path := "res://assets/pixel_v1/pots/%s-%d.png" % [id, index]
			check(row.pots[index] == path and pixels(path) == pixels(MOCK + "pots/%s-%d.png" % [id, index]), "%s pot frame %d pixels = approved frame" % [id, index])
			check(Catalog.DATA.sources["pots/%s-%d.png" % [id, index]].sha256 == FileAccess.get_sha256(path), "%s pot frame %d source hash" % [id, index])
		check(Catalog.pot(id, 0.0).resource_path == row.pots[0] and Catalog.pot(id, 1.0 / 6.0 + 0.01).resource_path == row.pots[1], "Cauldron shows the brewing potion's frames")
		check(Catalog.DATA.sources["potions/%s.png" % id].sha256 == FileAccess.get_sha256(row.bottle) and Catalog.DATA.sources["potions/%s.png" % id].source == "art/mockups/f26-region-potions-v1/sprites/%s_bottle.png" % id, "%s bottle source hash" % id)
		# Customers catch and carry the bottle by a solved grip (same rule as the existing 144 bindings).
		for cid in CUSTOMER_INDEX:
			var binding: Dictionary = Catalog.DATA.characters[cid].bindings.get(id, {})
			check(not binding.is_empty() and binding.checks.size() == 10 and binding.checks.all(func(c): return c.passed and int(c.bottle_bottom_row) <= 43 and int(c.visible_liquid_pixels) > 0) and Catalog.local_grip(cid, id) == Vector2(binding.local_grip[0], binding.local_grip[1]), "%s: %s hand grip %s passes all 10 pose/facing checks" % [cid, id, str(binding.get("local_grip", []))])
		var icon := ItemArt.icon(id)
		check(icon.resource_path == "res://assets/content_expansion_v1/potions/%s_icon.png" % id and texture_pixels(icon) == pixels(MOCK + "sprites/%s_icon.png" % id) and icon.get_size() == Vector2(32, 40), "%s 32x40 potion icon = approved" % id)
		var recipe := ItemArt.recipe_icon(id)
		check(recipe.resource_path == "res://assets/content_expansion_v1/recipes/%s_recipe.png" % id and texture_pixels(recipe) == pixels(MOCK + "sprites/%s_recipe.png" % id), "%s 32x40 recipe icon = approved" % id)
	for pair in [[MATERIAL, "materials/dawn_bloom_icon.png", "dawn_bloom_icon"], [REGION, "regions/dawn_lighthouse_icon.png", "dawn_lighthouse_icon"]]:
		var texture := ItemArt.icon(pair[0])
		check(texture.resource_path == "res://assets/content_expansion_v1/" + pair[1] and texture_pixels(texture) == pixels(MOCK + "sprites/%s.png" % pair[2]), "%s icon = approved" % pair[0])
	# The 64x80 planter growth sheet v2 was approved separately (2026-11-05) and is published byte for byte.
	const GROWTH := "res://assets/content_expansion_v1/materials/dawn_bloom_growth.png"
	check(ItemArt.growth_path(MATERIAL) == GROWTH and FileAccess.get_file_as_bytes(GROWTH) == FileAccess.get_file_as_bytes("res://art/mockups/f26-dawn-bloom-growth-v2/sheets/dawn_bloom_growth.png"), "Dawn bloom growth sheet = approved v2 file")
	var sheet: Texture2D = load(GROWTH)
	check(sheet.get_size() == Vector2(64, 80) and visible_pixels(texture_pixels(sheet)) == visible_pixels(pixels("res://art/mockups/f26-dawn-bloom-growth-v2/sheets/dawn_bloom_growth.png")), "Growth sheet 64x80, visible pixels unchanged")
	var frames := [0.0, 0.4, 0.8].map(func(phase): return ItemArt.growth_frame(MATERIAL, phase))
	check(frames.all(func(frame): return frame is AtlasTexture and frame.atlas.resource_path == GROWTH and frame.region.size == Vector2(32, 40)) and frames[0].region != frames[2].region, "Garden shows three 32x40 growth stages")
	check(Catalog.DATA.potions.size() == 40, "Catalog has 36 + 4 potion rows")

func test_collection() -> void:
	var fresh := State.new()
	var c := {}
	for row in Status.collection(fresh): c[row.key] = [row.have, row.total]
	check(c.recipes == [0, 34] and c.regions == [0, 9], "New game: recipes 0/34, surveys 0/9 (%s)" % str(c))

func test_save(base: RefCounted) -> void:
	var s := f26_complete(base)
	var ex: RefCounted = s.progression.expansion
	ex.returns[REGION] = 3
	ex.pending[MATERIAL] = 5
	ex.reward_totals[MATERIAL] = 41
	ex.materials[MATERIAL] = 12
	ex.growth[MATERIAL] = 7.5
	ex.cycles[REGION].merge({"id": 4, "fee": 150, "paid": true, "running": true, "elapsed": 100.0, "duration": 378.0, "rewards": {"dawn_bloom": 7, "star_seed": 2}}, true)
	ex.latest_returns[REGION] = {"dawn_bloom": 8, "moonflower": 1}
	for index in s.inventory.size():
		if s.inventory[index] is String:
			s.inventory[index] = "sun_moon_elixir"
			break
	var data: Dictionary = JSON.parse_string(JSON.stringify(s.to_data()))
	check(int(data.version) == 17, "Saved as v17")
	var restored := State.new()
	check(restored.load_data(data), "Region/material/recipe progress loads through the existing structures")
	check(Compare.equivalent(M.data(s), M.data(restored)), "Save round trip is lossless")
	var rp: RefCounted = restored.progression
	check(rp.expansion.regions.has(REGION) and int(rp.expansion.returns[REGION]) == 3 and int(rp.expansion.pending[MATERIAL]) == 5 and rp.expansion.cycles[REGION].running and NEW.all(func(id): return rp.owned.has(id)), "Restored region, trip, dawn bloom and recipes")
	var tampered: Dictionary = data.duplicate(true)
	tampered.progression.expansion.materials[MATERIAL] = 43
	check(not State.new().load_data(tampered), "Dawn bloom obeys the shared 42 storage bound")

func test_late_gate(base: RefCounted) -> void:
	var s := f26_complete(base)
	var late := Late.new()
	var view := late.growth_view(s)
	check(view.recipes == 32 and view.regions >= 8, "Owning the new recipes does not change the original-recipe count")
	s.progression.owned.erase("fortune")
	check(late.growth_view(s).recipes == 31 and late.growth_view(s).missing.has("일반 레시피 32종 보유 필요 · 31/32"), "A new recipe never stands in for a missing original one")

func test_ui(base: RefCounted) -> void:
	var shop := Shop.new()
	root.add_child(shop)
	await process_frame
	shop.set_process(false)
	shop.art.set_process(false)
	shop.state = clone(base)
	shop.open_management()
	var panel = shop.management
	panel.set_process(false)
	panel.select_page(panel.EXPEDITIONS)
	panel.refresh()
	await process_frame
	var row: Dictionary = panel.rows.get(REGION, {})
	check(not row.is_empty() and row.button.visible and not row.button.disabled and row.button.get_meta("currency_source", "") == "원정 열기 · 400000 G", "Expedition tab: the dawn lighthouse can be opened (%s)" % str(row.get("button").get_meta("currency_source", "") if not row.is_empty() else ""))
	panel.select_page(panel.RECIPES)
	panel.refresh()
	await process_frame
	var recipe: Dictionary = panel.rows.get("sunrise", {})
	check(not recipe.is_empty() and recipe.icon.texture.resource_path == "res://assets/content_expansion_v1/recipes/sunrise_recipe.png" and recipe.title.text == "해돋이", "Recipe tab shows the approved sunrise recipe icon")
	var eternity: Dictionary = panel.rows.get("eternity", {})
	check(not eternity.is_empty() and eternity.icon.texture is AtlasTexture, "Older ordinary recipes keep their trimmed potion icons")
	panel.select_page(panel.HERBS)
	panel.refresh()
	await process_frame
	var herb: Dictionary = panel.rows.get(panel.material_row(MATERIAL), {})
	check(not herb.is_empty() and herb.has("growth_preview") and herb.growth_preview.texture is AtlasTexture and herb.growth_preview.texture.atlas.resource_path == ItemArt.growth_path(MATERIAL), "Herb tab shows the approved dawn bloom growth sheet")
	shop.queue_free()
	await process_frame

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
	await test_ui(base)
	M.write_json(OUT, {"checks": checks, "failures": failures, "passed": failures.is_empty()})
	print("F26 REGION POTIONS %s %d checks%s" % ["PASS" if failures.is_empty() else "FAIL", checks, "" if failures.is_empty() else " · " + "; ".join(failures)])
	quit(0 if failures.is_empty() else 1)
