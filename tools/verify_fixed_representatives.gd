extends SceneTree
## Isolated model and headless signal checks; no player save or desktop input.
const Shop = preload("res://scripts/shop.gd")
const State = preload("res://scripts/shop_state.gd")
const Status = preload("res://scripts/management_status.gd")
const Content = preload("res://scripts/shop_content.gd")
const Trips = preload("res://scripts/parallel_expeditions.gd")
const ItemArt = preload("res://scripts/item_art.gd")
const PotionVisual = preload("res://scripts/potion_visual.gd")
const Desktop = preload("res://scripts/desktop_input.gd")
const Compare = preload("res://tests/state_compare.gd")
var shop: Control
var overlay: Control

func _initialize() -> void:
	set_meta("isolated_preview", true)
	call_deferred("run")

func set_stock(state: RefCounted, amount: int) -> void:
	state.stock = amount
	state.mana_stock = 0
	state.inventory.clear()
	for i in amount: state.inventory.append(false)

func apply_state(state: RefCounted) -> void:
	state.window_mode = State.WindowMode.WORKSHOP
	state.main_window_mode = State.WindowMode.WORKSHOP
	shop.state = state
	shop._update_interface()
	overlay.refresh()

func verify_identity(state: RefCounted) -> void:
	var craft := Status.crafting(state)
	assert(overlay.herb_ids == ["herb"] and overlay.region_ids == ["forest_edge"])
	assert(overlay.herbs.size() == 1 and overlay.trips.size() == 1)
	assert(overlay.craft.icon == craft.icon and overlay.craft.kind == craft.kind)
	assert(overlay.craft.name == craft.name and overlay.craft.status == craft.status)
	assert(is_equal_approx(overlay.craft.progress, craft.progress))
	assert(overlay.craft.running == state.is_brewing())
	for bar in [shop.brew_bar, shop.small_bar, shop.minimal_bar]:
		assert(is_equal_approx(bar.value, craft.progress * 100.0))
	assert(ItemArt.potion_id(shop.art.potion_kind) == craft.icon)
	assert(shop.art.potion_color == PotionVisual.liquid_color(craft.kind))
	var counts := Status.activity_counts(state)
	assert(overlay.active_herbs == counts.herbs and overlay.active_regions == counts.regions)
	var expected: AtlasTexture = ItemArt.growth_frame("herb", overlay.herbs[0].progress, false)
	assert(overlay.growth_texture.atlas.resource_path == expected.atlas.resource_path)
	assert(overlay.growth_texture.region == expected.region)

func assert_readonly(state: RefCounted) -> void:
	var saved: Dictionary = state.to_data().duplicate(true)
	for i in 12:
		Status.crafting(state)
		Status.activity_counts(state)
		shop._update_interface()
		overlay.refresh()
	assert(Compare.equivalent(saved, state.to_data()), "Rendering must not advance, reserve, pay, roll or award")

func verify_fixed_activity() -> void:
	var zero := State.new()
	zero.gold = 1000
	zero.herbs = zero.herb_capacity()
	zero.harvest_elapsed = 2.0
	zero.progression.expansion.materials["blue_reed"] = 2
	apply_state(zero)
	verify_identity(zero)
	assert(Status.material(zero, "moon_mushroom").running, "Exclude a funded automatic purchase from cultivation")
	assert(overlay.active_herbs == 0 and overlay.active_regions == 0)
	assert(overlay.herb_summary == "재배 대기" and overlay.region_summary == "원정 대기")
	assert(not overlay.trips[0].available and not overlay.trips[0].running and overlay.trips[0].status == "잠김")
	assert(not Status.material(zero, "blue_reed").supplied)
	assert(is_equal_approx(overlay.herbs[0].progress, zero.harvest_elapsed / zero.harvest_duration()))
	assert_readonly(zero)
	# A waiting fixed representative does not conceal other active suppliers.
	zero.progression.owned = ["moon", "vigor"]
	zero.progression.expansion.grant_recipe("vigor")
	apply_state(zero)
	verify_identity(zero)
	assert(not overlay.herbs[0].running and overlay.herbs[0].status == "보관 가득")
	assert(overlay.active_herbs == 2, "Starleaf and dewgrass run independently of the full base herb")
	assert(overlay.herb_summary == "2종 재배 중")
	for clock in [0.0, 120.0, 190.0, 280.0]:
		zero.progression.clock = clock
		apply_state(zero)
		verify_identity(zero)
		assert(overlay.active_herbs == 2)
	zero.progression.rare_herbs = zero.progression.expansion.special_capacity()
	zero.progression.expansion.materials["dewgrass"] = zero.progression.expansion.special_capacity()
	apply_state(zero)
	assert(overlay.active_herbs == 0)
	# Inactive supplied jobs keep their actual accumulated work, not a fake 100%.
	assert(overlay.herbs[0].progress < 1 and overlay.growth_texture.region == ItemArt.growth_frame("herb", overlay.herbs[0].progress, false).region)
	var poor := State.new()
	poor.gold = 37
	poor.progression.expedition_unlocked = true
	Trips.ensure(poor.progression)
	Trips.tick(poor, 0.0)
	apply_state(poor)
	verify_identity(poor)
	assert(overlay.active_regions == 0 and overlay.trips[0].status.contains("출발비 부족"))
	assert(poor.gold == 37 and poor.total_spent_expeditions == 0)
	assert_readonly(poor)
	# Completed/full forest waits while the greenhouse's paid investigation runs.
	var others := State.new()
	others.gold = 1000
	others.progression.expedition_unlocked = true
	others.progression.expedition_count = 10
	others.progression.expansion.regions = ["forest_edge", "abandoned_greenhouse"]
	others.progression.expansion.materials["dewgrass"] = others.progression.expansion.special_capacity()
	Trips.ensure(others.progression)
	Trips.tick(others, 0.0)
	apply_state(others)
	verify_identity(others)
	assert(overlay.active_regions == 1 and not overlay.trips[0].running)
	assert(overlay.region_summary == "1곳 탐사 중")
	assert(overlay.trips[0].status.contains("보관") and overlay.trips[0].status.contains("대기"))
	var greenhouse: Dictionary = others.progression.expansion.cycles.abandoned_greenhouse
	greenhouse.elapsed = greenhouse.duration * 0.95
	apply_state(others)
	assert(Trips.status("abandoned_greenhouse", others.progression) == "귀환 중")
	assert(Status.region(others, "abandoned_greenhouse").action == "재료 가져오는")
	assert(overlay.active_regions == 1, "Count the return leg, without switching the fixed forest representative")
	assert_readonly(others)
	# Forest activity returns only after actual material use permits a departure.
	others.progression.expansion.materials.dewgrass = 0
	Trips.tick(others, 0.0)
	apply_state(others)
	verify_identity(others)
	assert(overlay.active_regions == 2 and overlay.trips[0].running)
	assert_readonly(others)

func verify_storage_resume() -> void:
	var state := State.new()
	state.auto_purchase = false
	state.set_shop_open(false)
	state.advance(2.0)
	var reserved_herbs: int = state.herbs
	var original_kind: Variant = state.progression.active_recipe
	set_stock(state, state.capacity())
	var held_events: Dictionary = state.advance(2.0)
	apply_state(state)
	verify_identity(state)
	assert(state.brew_active and is_equal_approx(state.brew_elapsed, 2.0))
	assert(overlay.craft.status == "보관 가득" and not overlay.craft.running)
	assert(is_equal_approx(overlay.craft.progress, 0.4), "A paused active batch keeps its real progress")
	assert(state.herbs == reserved_herbs + int(held_events.harvested) and state.progression.active_recipe == original_kind)
	var held_herbs: int = state.herbs
	assert_readonly(state)
	var restored := State.new()
	assert(restored.load_data(JSON.parse_string(JSON.stringify(state.to_data()))))
	apply_state(restored)
	verify_identity(restored)
	assert(restored.brew_active and is_equal_approx(restored.brew_elapsed, 2.0))
	assert(restored.progression.active_recipe == original_kind and restored.herbs == held_herbs)
	assert_readonly(restored)
	# Use a real purchase to free storage. No UI action may reserve again.
	state.set_shop_open(true)
	var events: Dictionary = state.advance(state.customer_interval() + 0.1)
	apply_state(state)
	verify_identity(state)
	assert(events.sold == 1 and state.stock == state.capacity() - 1)
	assert(state.is_brewing() and state.brew_elapsed > 2.0 and state.brew_elapsed < 2.2)
	assert(state.progression.active_recipe == original_kind and state.herbs == held_herbs + int(events.harvested))
	# An inactive full batch preserves the actual last special potion across save.
	var last := State.new()
	last.auto_purchase = false
	last.set_shop_open(false)
	last.progression.owned = ["moon"]
	last.progression.rare_herbs = 1
	last.herbs = State.HERBS_PER_POTION
	set_stock(last, last.capacity() - 1)
	last.advance(0.01)
	assert(last.progression.active_recipe == "moon" and last.brew_active and last.progression.batch_success)
	last.advance(last.brew_duration())
	apply_state(last)
	verify_identity(last)
	assert(last.stock == last.capacity() and not last.brew_active)
	assert(overlay.craft.icon == "moon" and overlay.craft.status == "보관 가득" and overlay.craft.progress == 0)
	var last_copy := State.new()
	assert(last_copy.load_data(JSON.parse_string(JSON.stringify(last.to_data()))))
	apply_state(last_copy)
	verify_identity(last_copy)
	assert(last_copy.progression.active_recipe == "moon" and not last_copy.brew_active)
	assert_readonly(last_copy)
	# Storage and materials gate the next real batch; picture slots do not.
	last.set_shop_open(true)
	last.advance(last.customer_interval() + 0.1)
	apply_state(last)
	verify_identity(last)
	assert(last.is_brewing() and last.progression.active_recipe == false)
	assert(overlay.craft.icon == "health", "Change the last display only after the next actual batch starts")
	var shortage := State.new()
	shortage.progression.active_recipe = "moon"
	shortage.herbs = 0
	apply_state(shortage)
	verify_identity(shortage)
	assert(overlay.craft.status == "재료 부족" and overlay.craft.icon == "moon" and overlay.craft.progress == 0)
	assert_readonly(shortage)

func verify_navigation() -> void:
	var state: RefCounted = shop.state
	var saved: Dictionary = state.to_data().duplicate(true)
	assert(overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	assert(overlay.detail_buttons.size() == 3)
	for key in ["potions", "herbs", "expeditions"]:
		var button: Button = overlay.detail_buttons[key]
		assert(button.mouse_filter == Control.MOUSE_FILTER_STOP)
		assert(button.get_rect().has_area() and Rect2(0, 0, shop.WorkshopAssets.SIZE.x, 248).encloses(button.get_rect()))
		button.pressed.emit()
		shop.management.set_process(false)
		var pages := {"potions": shop.management.POTIONS, "herbs": shop.management.HERBS, "expeditions": shop.management.EXPEDITIONS}
		assert(shop.management.selected == pages[key])
		assert(Compare.equivalent(saved, state.to_data()))
	# The native helper remains stopped in headless mode. Its pure routing
	# projection must receive only the three buttons, never their artwork.
	assert(shop.desktop_input.process.is_empty() and shop.desktop_input.input_regions.size() == 3)
	for button in overlay.detail_buttons.values():
		assert(not Desktop.passes_picture_input(button.get_rect().get_center(), shop.desktop_input.layout_size, shop.desktop_input.art_height, shop.desktop_input.input_regions))
	assert(Desktop.passes_picture_input(shop.art.pot_rect().get_center(), shop.desktop_input.layout_size, shop.desktop_input.art_height, shop.desktop_input.input_regions), "The pot artwork must still pass input")
	for mode in [State.WindowMode.COMPANION, State.WindowMode.MINIMAL, State.WindowMode.WORKSHOP]:
		shop._set_window_mode(mode)
		overlay.refresh()
		assert(overlay.visible == (mode == State.WindowMode.WORKSHOP))
		assert(overlay.herb_ids == ["herb"] and overlay.region_ids == ["forest_edge"])
		assert(shop.desktop_input.process.is_empty())
		if mode == State.WindowMode.WORKSHOP:
			assert(shop.desktop_input.input_regions.size() == 3)
		else:
			assert(shop.desktop_input.input_regions.is_empty())
	# Window selection changes only UI settings, never economic state or RNG.
	var after: Dictionary = state.to_data().duplicate(true)
	for key in ["window_mode", "main_window_mode"]: after[key] = saved[key]
	assert(Compare.equivalent(saved, after))

func run() -> void:
	assert(DisplayServer.get_name() == "headless")
	shop = Shop.new()
	root.add_child(shop)
	shop.set_process(false)
	shop._set_window_mode(State.WindowMode.WORKSHOP)
	overlay = shop.workshop_gauges
	await process_frame
	await process_frame
	verify_fixed_activity()
	verify_storage_resume()
	verify_navigation()
	print("FIXED REPRESENTATIVES PASS: actual last batch ID/icon/liquid/work; fixed herb/forest and real active counts incl return; unlocked/inventory-only/purchase/full/poor cases; actual pause-sale-resume and once-only reservations; real progress growth frames; save/restore and UI/RNG invariance; direct tab signals and logical button-only click exceptions; compact modes; actual desktop interaction not tested")
	quit()
