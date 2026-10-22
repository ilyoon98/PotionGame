extends SceneTree
## Explicitly isolated UI fixtures. Never loaded by the shipped main scene.
const Shop = preload("res://scripts/shop.gd")
const Trips = preload("res://scripts/parallel_expeditions.gd")
var shop: Control
var case_id := "new"
var audit_elapsed := 0.0
var directory := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fixture="): case_id = arg.trim_prefix("--fixture=")
	set_meta("isolated_preview", true)
	set_meta("desktop_input_verification", true)
	call_deferred("run")

func run() -> void:
	shop = Shop.new()
	root.add_child(shop)
	var s = shop.state
	var p = s.progression
	if case_id == "resume":
		assert(shop.SaveStore.read_into(s, "user://potion_shop.json") == "loaded")
	elif case_id == "legacy":
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.verification/candidate-c-existing-save.json"))
		assert(s.load_data(data))
	elif case_id != "new":
		s.gold = 100000
		p.reputation = 10000
		p.expedition_unlocked = true
		p.expedition_count = 10 if case_id in ["buy", "full", "late"] else 0
		if case_id == "low": s.gold = 31
		if case_id in ["parallel", "full", "late"]:
			for row in Shop.State.Content.DATA["regions"]: p.expansion.regions.append(row["id"])
		if case_id in ["buy", "full", "late"]:
			for row in Shop.State.Content.DATA["regions"]: p.expansion.returns[row["id"]] = int(row["complete_returns"])
		if case_id in ["full", "late"]:
			p.owned = ["moon", "purify", "agility"]
			p.rare_herbs = 12
			for row in Shop.State.Content.DATA["materials"]:
				if row["id"] not in ["herb", "moon_mushroom", "starleaf"]: p.expansion.materials[row["id"]] = 12
		if case_id == "full": p.expansion.pending = {"dewgrass": 2, "starleaf": 2}
		if case_id == "late":
			for potion in Shop.State.Content.DATA["potions"]:
				if not potion["owned_at_start"] and not p.owned.has(potion["id"]): p.owned.append(potion["id"]); p.expansion.grant_recipe(potion["id"])
			for row in Shop.State.Content.DATA["employees"]: p.expansion.staff.append(row["id"])
			p.employee = true
			for row in Shop.State.Content.DATA["upgrades"]: p.expansion.stages[row["track"]] = int(row["stage"])
			s.level = 15
			s.garden_level = 12
			s.sales_counter_level = 10
			p.filter_owned = true
			p.clock = 190.0
	Trips.ensure(p)
	shop._set_window_mode(s.window_mode if case_id == "resume" else Shop.State.WindowMode.FULL if "--full" in OS.get_cmdline_user_args() else Shop.State.WindowMode.WORKSHOP)
	root.title = "달그늘 TEST " + case_id
	root.position = Vector2i(700, 340)
	shop.test_mode = false
	directory = "res://.verification/cu-" + case_id
	DirAccess.make_dir_recursive_absolute(directory)
	root.window_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed: print("CU ROOT CLICK ", event.position)
	)
	print("CU FIXTURE READY ", case_id, " isolated user directory ", OS.get_user_data_dir())

func _process(delta: float) -> bool:
	if shop == null: return false
	audit_elapsed += delta
	if shop.management != null: shop.management.title = "달그늘 TEST " + case_id + " 관리"
	if audit_elapsed < 1.0: return false
	audit_elapsed = 0.0
	var status: Dictionary = shop.state.to_data()
	status["management_visible"] = shop.management != null and shop.management.visible
	status["management_page"] = shop.management.selected if shop.management != null else -1
	status["bridge_failed"] = shop.desktop_input.failed
	status["bridge_enabled"] = shop.desktop_input.enabled
	status["window_position"] = [root.position.x, root.position.y]
	status["window_size"] = [root.size.x, root.size.y]
	var file := FileAccess.open(directory + "/status.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(status, "\t"))
	return false
