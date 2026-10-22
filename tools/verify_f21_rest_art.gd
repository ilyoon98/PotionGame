extends SceneTree
## F21 rest/aging art in the real renderer: published pixels, poses, effects,
## wall cask and the aged seal. Isolated test shop; the player save is not used.
const Shop = preload("res://scripts/shop.gd")
const State = preload("res://scripts/shop_state.gd")
const Art = preload("res://scripts/shop_art.gd")
const Catalog = preload("res://scripts/pixel_art_catalog.gd")
const Scene = preload("res://scripts/pixel_shop_scene.gd")
const FOLDER := "res://.verification/f21-rest-art-20261021/"
const ART := "res://art/characters/rest-v1/keeper/frames/"

func _initialize() -> void:
	set_meta("isolated_preview", true)
	call_deferred("run")

func selected(commands: Array[Dictionary], role: String) -> Dictionary:
	for c in commands:
		if c.role == role: return c
	return {}

func index_of(commands: Array[Dictionary], role: String) -> int:
	for i in commands.size():
		if commands[i].role == role: return i
	return -1

func count(commands: Array[Dictionary], role: String) -> int:
	return commands.filter(func(c): return c.role == role).size()

func source(name: String) -> Image:
	# art/ is excluded from import (.gdignore); read the reviewed PNG directly.
	var image := Image.load_from_file(ProjectSettings.globalize_path(ART + name + ".png"))
	image.convert(Image.FORMAT_RGBA8)
	return image

func same(a: Image, b: Image) -> bool:
	a.convert(Image.FORMAT_RGBA8)
	b.convert(Image.FORMAT_RGBA8)
	return a.get_size() == b.get_size() and a.get_data() == b.get_data()

func freeze(node: Node) -> void:
	node.set_process(false)
	for child in node.get_children(): freeze(child)

func run() -> void:
	var report := {"status": "running", "player_save_accessed": false, "checks": {}}
	# 1. Published atlases are exactly the approved frames in the 64-cell layout.
	var rest := {"sleep": ["sleep_sit", "sleep_sit_breath"], "faint": ["faint", "faint"]}
	for pose in rest:
		for index in 64:
			var lifted := (index / 16) % 2 == 1
			var native := Catalog.frame("keeper", pose, index, false).get_image()
			assert(same(native, source(rest[pose][1 if lifted else 0])), "%s native cell %d matches approved art" % [pose, index])
			var fine := Catalog.frame("keeper", pose, index).get_image()
			var expected := source(rest[pose][1 if lifted else 0])
			expected.resize(96, 144, Image.INTERPOLATE_NEAREST)
			assert(same(fine, expected), "%s fine cell %d is the exact 3x frame" % [pose, index])
	assert(Catalog.motion_index(0.0, "sleep") < 16 and Catalog.motion_index(1.6, "sleep") >= 16, "3 s breathing uses the lift half")
	report.checks["atlases"] = "sleep/faint 64 cells native+fine equal approved frames"

	# 2. Poses and effects on the real ShopArt projection.
	var art: Control = Art.new()
	art.workshop = true
	art.size = Vector2(540, 249)
	root.add_child(art)
	art.set_process(false)
	var original := State.new()
	art.world = original.progression
	art.brewing = true
	assert(Scene.keeper_pose(art).begins_with("brew"))
	art.keeper_rest = "asleep"
	assert(Scene.keeper_pose(art) == "sleep", "Sleep overrides brewing")
	art.sync_inventory(8, 1, [false, true, "moon", "purify", "agility", "vigor", "nightwalk", "health"])
	art.on_sale(24, "moon", 7, "elf", false)
	art.motion.departing_elapsed = art.motion.handover_seconds * 0.5
	assert(Scene.keeper_pose(art) == "sleep", "Sleep overrides the handover gesture")
	var commands: Array[Dictionary] = art.render_commands()
	assert(selected(commands, "keeper").pose == "sleep" and selected(commands, "keeper").rect == Rect2(216, 96, 96, 144))
	assert(selected(commands, "handover_bottle").size() > 0, "The sold bottle still flies while the keeper sleeps")
	assert(count(commands, "handover_seal") == 0, "Retail sales carry no aged seal")
	for step in 8:
		art.motion.elapsed = step * 0.375 + 0.01
		commands = art.render_commands()
		assert(count(commands, "sleep_z") == 2 and index_of(commands, "sleep_z") > index_of(commands, "keeper"))
		var s: int = step
		assert(selected(commands, "sleep_z").rect.position == Vector2(216, 96) + Vector2(22 + floori(s / 2.0), 16 - s) * 3)
	art.keeper_rest = "fainted"
	var behind := 0
	for step in 8:
		art.motion.elapsed = step * 0.375 + 0.01
		commands = art.render_commands()
		assert(selected(commands, "keeper").pose == "faint" and count(commands, "dizzy_star") == 2 and count(commands, "sleep_z") == 0)
		if index_of(commands, "dizzy_star") < index_of(commands, "keeper"): behind += 1
	assert(behind >= 3, "Back half of the star orbit is drawn behind the keeper")
	art.keeper_rest = ""
	commands = art.render_commands()
	assert(count(commands, "sleep_z") + count(commands, "dizzy_star") == 0 and selected(commands, "keeper").pose != "sleep")
	report.checks["poses_effects"] = "sleep/faint override brew+handover; 2 Z / 2 stars per step; stars behind %d/8 steps" % behind

	# 3. Wall cask only once aging is opened.
	assert(count(art.render_commands(), "aging_cask") == 0)
	art.aging_open = true
	var cask := selected(art.render_commands(), "aging_cask")
	assert(cask.rect == Rect2(219, 0, 96, 96), "Cask at the approved wall spot")
	report.checks["cask"] = cask.rect

	# 4. Aged sale: seal follows the bottle, behind the shelf at first, then into the hand.
	art.motion.close_shop()
	art.pending_sales.clear()
	art.motion.departing_elapsed = -1.0
	art.shop_open = true
	art.on_aged_sale(240, "moon", "mage", false)
	assert(art.sold_aged)
	for factor: float in [0.1, 0.5, 0.99, 1.0, 1.6]:
		art.motion.departing_elapsed = art.motion.handover_seconds * factor
		commands = art.render_commands()
		var caught := factor >= 1.0
		var bottle := selected(commands, "held_bottle" if caught else "handover_bottle")
		var seal := selected(commands, "held_seal" if caught else "handover_seal")
		assert(seal.rect.position == bottle.rect.position + (bottle.rect.size / 3.0 - Vector2(3, 6)) * 3 and seal.rect.size == Vector2(15, 15))
		assert(index_of(commands, seal.role) == index_of(commands, bottle.role) + 1, "Seal drawn right after its bottle")
	art.motion.close_shop()
	art.pending_sales.clear()
	art.on_sale(24, "moon", 0, "elf", false)
	assert(not art.sold_aged)
	report.checks["aged_seal"] = "seal tracks handover/held bottle; retail sale has none"
	art.queue_free()

	# 5. Engine captures (needs a rendering driver).
	if DisplayServer.get_name() != "headless":
		var shop := Shop.new()
		root.add_child(shop)
		assert(shop.test_mode and shop.instance_bypassed)
		freeze(shop)
		root.always_on_top = false
		shop.state.aging.levels.open = 1
		for case in [["asleep", 0.2, "sleep"], ["asleep", 1.7, "sleep-breath"], ["fainted", 0.8, "faint"]]:
			shop.state.keeper.state = case[0]
			for mode in [State.WindowMode.WORKSHOP, State.WindowMode.COMPANION]:
				shop._set_window_mode(mode)
				shop._update_interface()
				shop.art.motion.elapsed = case[1]
				shop.art.queue_redraw()
				shop.companion.elapsed = case[1]
				shop.companion.refresh()
				shop.companion.scene.queue_redraw()
				await process_frame
				await process_frame
				await RenderingServer.frame_post_draw
				var name: String = ("workshop-" if mode == State.WindowMode.WORKSHOP else "companion-") + case[2]
				assert(root.get_texture().get_image().save_png(FOLDER + name + ".png") == OK)
		shop.queue_free()
		report["captures"] = "workshop/companion × sleep, sleep-breath, faint"
	report.status = "passed"
	var file := FileAccess.open(FOLDER + "proof.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("F21 REST ART PASS: ", JSON.stringify(report.checks))
	await process_frame
	quit()
