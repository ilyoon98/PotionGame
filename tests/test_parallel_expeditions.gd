extends SceneTree
const State = preload("res://scripts/shop_state.gd")
const Trips = preload("res://scripts/parallel_expeditions.gd")
const Compare = preload("res://tests/state_compare.gd")

func _initialize() -> void: call_deferred("run")

func fixture(all_regions: bool = false) -> RefCounted:
	var s := State.new()
	s.gold = 100000
	s.progression.reputation = 10000
	s.progression.expedition_unlocked = true
	if all_regions:
		for row in State.Content.DATA["regions"]: s.progression.expansion.regions.append(row["id"])
	Trips.ensure(s.progression)
	return s

func clone(s: RefCounted) -> RefCounted:
	var next := State.new()
	assert(next.load_data(JSON.parse_string(JSON.stringify(s.to_data()))))
	return next

func run() -> void:
	assert(State.Content.DATA["revision"] == "candidate-d-multi-expedition")
	for category in ["potions", "materials", "regions", "employees"]:
		var seen := []
		for row in State.Content.DATA[category]:
			assert(not seen.has(row["id"]))
			seen.append(row["id"])
			assert(ResourceLoader.exists(row["icon_candidate"]))
	assert(State.Content.DATA["potions"].size() == 32 and State.Content.DATA["materials"].size() == 11 and State.Content.DATA["regions"].size() == 8 and State.Content.DATA["upgrades"].size() == 125 and State.Content.DATA["employees"].size() == 4)
	var s := fixture(true)
	Trips.tick(s, 0)
	assert(Trips.active_count(s.progression) == 8 and s.total_spent_expeditions == 355 and s.gold == 99645)
	var copy := clone(s)
	for key in s.to_data():
		if not Compare.equivalent(s.to_data()[key], copy.to_data()[key]): print("DIFF ", key, " ", s.to_data()[key], " / ", copy.to_data()[key])
	assert(Compare.equivalent(s.to_data(), copy.to_data()))
	Trips.tick(copy, 0)
	assert(copy.gold == s.gold and copy.total_spent_expeditions == 355, "Restore never repeats a departure charge")
	var frozen: Dictionary = s.progression.expansion.cycles["star_garden"].duplicate(true)
	s.progression.expansion.stages["expedition_path"] = 10
	s.progression.expansion.staff.append("expedition_guide")
	s.progression.expansion.stages["expedition_guide"] = 5
	assert(s.progression.expansion.cycles["star_garden"] == frozen, "Upgrades only affect future legs")
	var early := fixture()
	early.gold = 37
	Trips.tick(early, 0)
	assert(Trips.active_count(early.progression) == 0 and early.gold == 37 and Trips.status("forest_edge", early.progression).contains("출발비 부족"))
	early.gold += 1
	Trips.tick(early, 0)
	assert(early.gold == 30 and early.total_spent_expeditions == 8 and Trips.active_count(early.progression) == 1)
	var budget := fixture(true)
	budget.gold = 100
	Trips.tick(budget, 0)
	assert(budget.gold >= 30 and budget.total_spent_expeditions == 70 and Trips.active_count(budget.progression) == 4)
	# Expensive incomplete investigations are protected from cheap completed repeats.
	var protect := fixture()
	protect.progression.expedition_count = 10
	protect.progression.expansion.regions.append("star_garden")
	Trips.ensure(protect.progression)
	protect.gold = 129
	Trips.tick(protect, 0)
	assert(protect.gold == 129 and Trips.active_count(protect.progression) == 0)
	protect.gold += 1
	Trips.tick(protect, 0)
	assert(protect.gold == 30 and protect.progression.expansion.cycles["star_garden"]["running"])
	# Incomplete investigation and discoveries proceed through full stores.
	var full := fixture()
	# Isolate ordinary storage repeats from optional discovery-only searches.
	full.progression.expansion.rare_discovered.append("rare_forest_breath")
	full.progression.rare_herbs = 12
	full.progression.expansion.materials["dewgrass"] = 12
	Trips.tick(full, 0)
	for index in 700:
		full.progression.clock += 1
		Trips.tick(full)
	assert(full.progression.expedition_count == 10)
	assert(int(full.progression.expansion.pending.get("dewgrass", 0)) == int(full.progression.expansion.reward_totals.dewgrass), "A full main store retains every rolled reward")
	assert(int(full.progression.expansion.pending.get("starleaf", 0)) == int(full.progression.expansion.reward_totals.get("starleaf", 0)), "Full optional stores retain every rolled reward")
	assert(full.progression.expansion.recipe_reason("vigor", full.progression).is_empty())
	assert(Trips.status("forest_edge", full.progression) == "보관 공간 대기")
	var held := clone(full)
	Trips.tick(held, 0)
	assert(held.progression.expedition_count == 10 and Compare.equivalent(held.progression.expansion.pending, full.progression.expansion.pending) and held.total_spent_expeditions == full.total_spent_expeditions)
	held.progression.expansion.stages["herb_storage"] = 10
	var expected_star: int = 12 + int(held.progression.expansion.pending.get("starleaf", 0))
	var expected_dew: int = 12 + int(held.progression.expansion.pending.get("dewgrass", 0))
	Trips.deposit(held.progression, held)
	assert(held.progression.rare_herbs == expected_star and held.material_count("dewgrass") == expected_dew)
	assert(not held.progression.expansion.pending.has("starleaf") and not held.progression.expansion.pending.has("dewgrass"))
	assert(Trips.status("forest_edge", held.progression) == "재료 충분 · 자동 대기")
	held.progression.rare_herbs = 21
	held.progression.expansion.materials["dewgrass"] = 21
	Trips.tick(held, 0)
	assert(held.progression.expansion.cycles["forest_edge"]["running"], "Consumption resumes without a send button")
	# Receiving rewards before ownership must not be overwritten by the seed grant.
	var grant := fixture()
	grant.progression.expedition_count = 3
	grant.progression.expansion.materials["dewgrass"] = 6
	assert(grant.purchase("vigor") and grant.material_count("dewgrass") == 8)
	var paid: int = grant.gold
	assert(not grant.purchase("vigor") and grant.gold == paid)
	var seed_full := fixture()
	seed_full.progression.expedition_count = 3
	seed_full.progression.expansion.materials["dewgrass"] = 12
	assert(seed_full.purchase("vigor") and seed_full.material_count("dewgrass") == 12 and seed_full.progression.expansion.pending["dewgrass"] == 2, "Full stores retain the first source grant as well")
	# Versions 1..7 preserve old progress. v5+ old forest legs finish free once.
	for version in range(1, 8):
		var old := State.new().to_data()
		old["version"] = version
		old["gold"] = 777
		old["brew_elapsed"] = 2.0
		old["brew_active"] = true
		old["auto_purchase"] = false
		old["shop_open"] = false
		old.erase("total_spent_expeditions")
		for key in ["parallel_version", "cycles", "reward_totals", "report_returns", "report_rewards"]: old["progression"]["expansion"].erase(key)
		if version < 7: old["progression"].erase("expansion")
		old["progression"]["expedition_unlocked"] = true
		old["progression"]["expedition_elapsed"] = 69.0
		old["progression"]["expedition_active"] = false
		old["progression"]["expedition_count"] = 2
		var migrated := State.new()
		assert(migrated.load_data(JSON.parse_string(JSON.stringify(old))))
		assert(migrated.gold == 777 and migrated.brew_elapsed == 2.0 and migrated.auto_purchase and migrated.shop_open and migrated.total_spent_expeditions == 0)
		assert(migrated.progression.expansion.regions.is_empty() and migrated.progression.expansion.staff.is_empty())
		if version >= 5:
			assert(not migrated.progression.expansion.cycles["forest_edge"]["paid"] and migrated.progression.expansion.cycles["forest_edge"]["elapsed"] == 69)
			Trips.tick(migrated)
			print("LEGACY ", version, " ", migrated.progression.expedition_count, " ", migrated.progression.rare_herbs, " ", migrated.material_count("dewgrass"), " fees ", migrated.total_spent_expeditions)
			assert(migrated.progression.expedition_count == 3 and migrated.progression.rare_herbs == 2 and migrated.material_count("dewgrass") == 0)
			assert(migrated.total_spent_expeditions == 8, "Only the next new leg is charged")
	var old_pending: Dictionary = fixture().to_data()
	old_pending["version"] = 6
	old_pending["progression"].erase("expansion")
	old_pending["progression"]["expedition_pending"] = 2
	old_pending["progression"]["rare_herbs"] = 12
	var pending := State.new()
	assert(pending.load_data(old_pending))
	Trips.tick(pending, 0)
	assert(pending.progression.expansion.pending.get("starleaf") == 2 and pending.progression.expedition_pending == 0)
	# Exact same-time returns and per-cycle payment survive coarse/fine frames.
	var coarse := fixture(true)
	Trips.tick(coarse, 0)
	for cycle in coarse.progression.expansion.cycles.values(): cycle["duration"] = 30.0
	var fine := clone(coarse)
	coarse.advance(300.0)
	for frame in 9000: fine.advance(1.0 / 30)
	assert(Compare.equivalent(coarse.to_data(), fine.to_data()))
	assert(coarse.gold == 100000 + coarse.total_sales_gold - coarse.total_spent_materials - coarse.total_spent_expeditions)
	var before: Dictionary = coarse.to_data()
	for i in 4: assert(coarse.report_text().contains("원정 출발비"))
	assert(Compare.equivalent(before, coarse.to_data()))
	var bad: Dictionary = before.duplicate(true)
	bad["progression"]["expansion"]["cycles"]["forest_edge"]["paid"] = "yes"
	assert(not fine.load_data(bad) and Compare.equivalent(fine.to_data(), before))
	print("PARALLEL PASS: data/assets; 8 independent legs; once-only fees/reserve/protection; full-store investigation and pending; repeat recovery; seed preservation; v1-v7 migration/free legacy leg; coarse/fine returns; ledger; readonly reports; atomic invalid-cycle rejection")
	quit()
