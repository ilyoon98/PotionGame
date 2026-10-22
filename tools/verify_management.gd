extends SceneTree
const Shop = preload("res://scripts/shop.gd")
var shop: Control


func _initialize() -> void:
	set_meta("isolated_preview", true)
	Engine.max_fps = 60 # Preserve wall-time checks in the headless fixture.
	call_deferred("_run")


func capture(path: String, viewport: Viewport) -> Image:
	shop._update_interface()
	shop.art._process(0.0)
	await process_frame
	await process_frame
	if DisplayServer.get_name() == "headless": return null
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.save_png("res://.verification/" + path + ".png")
	return image


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://.verification")
	shop = Shop.new()
	root.add_child(shop)
	root.always_on_top = false
	shop.art.set_process(false)
	shop._set_window_mode(shop.State.WindowMode.WORKSHOP)
	for child in shop.workshop_toolbar.get_children():
		if child is Control:
			assert(Rect2(Vector2.ZERO, shop.workshop_toolbar.size).encloses(child.get_rect()), "Toolbar child exceeds its bounds: %s %s" % [child.name, child.get_rect()])
	shop.state.gold = 2500
	shop.state.progression.reputation = 40
	shop.state.stock = 6
	shop.state.mana_stock = 2
	for case in [{"name": "day-clear", "clock": 0.0}, {"name": "night-clear", "clock": 80.0}, {"name": "day-rain", "clock": 240.0}, {"name": "night-rain", "clock": 190.0}]:
		shop.state.progression.clock = case["clock"]
		var picture := await capture("workshop-" + case["name"], root)
		var time_key := "time-night" if shop.state.progression.is_night() else "time-day"
		assert(shop.workshop_time_icon.texture == shop.workshop_weather_icons[time_key])
		var weather_key: String = ["weather-sunny", "weather-cloudy", "weather-rainy"][shop.state.progression.weather()]
		assert(shop.workshop_weather_icon.texture == shop.workshop_weather_icons[weather_key])
		assert(not shop.workshop_time_icon.get_rect().intersects(shop.workshop_weather_icon.get_rect()))
		if picture != null:
			assert(picture.get_pixel(20, 150).a < 0.01, "The real desktop must show between objects")
			assert(picture.get_pixel(200, 264).a > 0.99, "Bottom management controls must remain opaque")
	assert(root.size == Shop.WorkshopAssets.SIZE and not shop.small_hud.visible)
	assert(shop.workshop_gold.is_visible_in_tree() and not shop.small_gold.is_visible_in_tree())
	assert(shop.workshop_weather_icon.texture != null, "The compact bar must show the current weather")
	shop.state.stock = 0
	shop.state.mana_stock = 0
	var empty := await capture("workshop-empty-shelves", root)
	for index in range(shop.art.bottles.visible_capacity()):
		var point: Vector2 = shop.art.bottles.slot_center(index)
		if empty != null: assert(empty.get_pixelv(Vector2i(point)).a < 0.01, "Empty shelves must not show painted sample bottles")
	shop.state.stock = 12
	shop.state.mana_stock = 4
	var full := await capture("workshop-full-shelves", root)
	assert(shop.art.bottles.visible_capacity() == 8 and shop.art.bottles.inventory_order().size() == 12)
	for index in range(shop.art.bottles.visible_capacity()):
		var point: Vector2 = shop.art.bottles.slot_center(index)
		if full != null: assert(full.get_pixelv(Vector2i(point)).a > 0.1, "Eight displayed bottles must fit; remaining inventory stays in reserve")
	var order: Array = shop.state.inventory_order().duplicate()
	shop._set_window_mode(shop.State.WindowMode.FULL)
	shop._set_window_mode(shop.State.WindowMode.WORKSHOP)
	assert(shop.art.bottles.inventory_order() == order, "Changing furniture layout must preserve FIFO inventory")
	shop.open_management()
	var snapshot: Dictionary = shop.state.to_data()
	for index in shop.management.pages.size():
		shop.management.select_page(index)
		await capture("management-page-%d" % index, shop.management)
	assert(shop.state.to_data() == snapshot, "Changing management pages must not change progress or award rewards")
	shop.management.select_page(shop.management.RECIPES)
	shop.management.rows["moon"]["button"].pressed.emit()
	assert(shop.state.progression.owned.has("moon") and shop.state.gold == 2380)
	shop.management.rows["moon"]["button"].pressed.emit()
	assert(shop.state.gold == 2380)
	shop.management.select_page(0)
	shop.state.progression.clock = 0
	shop.management.refresh()
	assert(not shop.management.rows["rare_inventory"]["highlighted"] and not shop.management.rows["potion_moon"]["highlighted"])
	shop.state.progression.clock = 190
	shop.management.refresh()
	assert(shop.management.rows["rare_inventory"]["highlighted"] and shop.management.rows["potion_moon"]["highlighted"])
	assert(not shop.management.rows["potion_health"]["highlighted"])
	await capture("management-environment-highlights", shop.management)
	shop.state.progression.clock = 0
	shop.management.refresh()
	assert(not shop.management.rows["potion_moon"]["highlighted"], "Expired environment effect must remove highlight without reopening")
	shop.management.hide()
	var before_clock: float = shop.state.progression.clock
	shop.test_mode = false # This runner uses its own APPDATA, never the player's save.
	await create_timer(1.2).timeout
	shop.test_mode = true
	assert(shop.state.progression.clock > before_clock + 0.5, "Closing management must leave real process updates running")
	shop._advance_game(90)
	assert(shop.state.total_sold > 0 and shop.state.progression.totals["rare"] > 0)
	shop.open_management()
	assert(shop.state.progression.owned.has("moon"))
	for index in range(5):
		if not shop.State.Content.CUSTOMERS[index].get("enabled", true): continue
		shop.state.progression.customer = index
		shop.art.motion.visit = shop.art.Motion.Visit.WAITING
		shop.art.motion.customer_x = shop.art.Motion.COUNTER_X
		await capture("workshop-customer-%d" % index, root)
	print("MANAGEMENT PASS: workshop node bounds; four environment states; all menu pages; one-time UI purchase; automatic operation while closed; active customer states; GPU pixels untested in headless mode")
	shop.management.queue_free()
	quit()
