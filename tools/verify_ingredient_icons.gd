extends SceneTree
## Isolated layout and pure projection checks; no game/desktop/save operations.
const Ingredients = preload("res://scripts/ingredient_icons.gd")
const Content = preload("res://scripts/shop_content.gd")
const ItemArt = preload("res://scripts/item_art.gd")
const State = preload("res://scripts/shop_state.gd")
const Compare = preload("res://tests/state_compare.gd")
const FONT = preload("res://assets/fonts/pretendard/Pretendard-Regular.otf")
var checks := 0

func _initialize() -> void:
	assert(DisplayServer.get_name() == "headless")
	set_meta("isolated_preview", true)
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	assert(value, message)

func run() -> void:
	var host := Control.new()
	var theme := Theme.new()
	theme.default_font = FONT
	theme.default_font_size = 16
	host.theme = theme
	root.add_child(host)
	var box := Ingredients.new()
	box.size = Vector2(336, 120)
	host.add_child(box)
	var state := State.new()
	box.show_ingredients(null, "never_disclose_this_recipe", false)
	check(not box.visible and box.get_meta("ingredient_entries").is_empty(), "First-ever unknown display is masked too")
	for entry in ItemArt.RARE_CATALOG.assets: state.progression.expansion.rare_discovered.append(entry.id)
	var kinds: Array = [false, true] + Content.RECIPES.keys()
	for kind in kinds:
		var before: Dictionary = state.to_data().duplicate(true)
		box.show_ingredients(state, kind)
		await process_frame
		await process_frame
		var id: String = "mana" if kind is bool and kind else "health" if kind is bool else str(kind)
		var actual: Dictionary = Content.lookup("potions", id).ingredients
		check(box.entries.size() == actual.size(), "Every actual recipe ingredient is shown")
		for index in box.entries.size():
			var item: Dictionary = box.entries[index]
			var chip: HBoxContainer = box.get_child(index)
			var icon: TextureRect = chip.get_node("Icon")
			var label: Label = chip.get_node("RequiredQuantity")
			check(int(item.required) == int(actual[item.id]), "Required quantity is the real recipe amount")
			check(label.text == "× %d" % int(actual[item.id]), "Visible count stays required count even with zero stock")
			check(icon.texture != null and icon.size == Vector2(32, 32), "Original material texture and 32px icon are present")
			check(label.get_theme_font_size("font_size") == 16, "Counts never shrink below body text size")
			check(chip.tooltip_text.contains(item.name) and chip.tooltip_text.contains("현재"), "Tooltip preserves material identity and current amount")
		check(Compare.equivalent(before, state.to_data()), "Reading and rendering all ingredients changes no economy, cursor, RNG or save fields")
	# Force a multi-line display without shrinking either texture or text.
	box.size.x = 150
	box.show_ingredients(state, "sage_elixir")
	await process_frame
	await process_frame
	var rows := {}
	for chip in box.get_children(): rows[int(chip.position.y)] = true
	check(rows.size() > 1, "Four ingredient kinds wrap in narrow allocated width")
	for chip in box.get_children():
		check(chip.get_node("Icon").size == Vector2(32, 32), "Wrapped icons retain 32px size")
	# A running batch has already consumed the ingredients; only the next bottle lacks them.
	state.brew_active = true
	state.progression.active_recipe = true
	state.herbs = 0
	state.mushrooms = 0
	var reserved_before: Dictionary = state.to_data().duplicate(true)
	box.show_ingredients(state, true)
	for item in box.entries:
		check(item.reserved and item.missing == 0 and item.next_missing == item.required, "Current reservation and next-bottle shortage are separate")
	check(Ingredients.detail_text(box.entries).contains("현재 배치 재료 예약 완료") and Ingredients.detail_text(box.entries).contains("다음 병"), "Details explain reservation rather than a current batch failure")
	check(Compare.equivalent(reserved_before, state.to_data()), "Reservation details do not reserve ingredients a second time")
	# Real stock updates must preserve the laid-out Controls, including their
	# quantity labels, while keeping tooltips/metadata current.
	var chips := box.get_children()
	state.herbs = 1
	state.mushrooms = 2
	box.show_ingredients(state, true)
	check(box.get_children() == chips, "Stock changes reuse the same ingredient Controls")
	check(box.get_child(0).get_meta("ingredient").owned == 1 and box.get_child(1).get_meta("ingredient").owned == 2, "Reused Controls receive current stock metadata")
	check(box.get_child(1).tooltip_text.contains("현재 2개"), "Reused tooltips show current stock")
	state.brew_active = false
	box.show_ingredients(state, true)
	check(box.get_children() == chips and not box.entries[0].reserved, "Reservation transitions reuse Controls and update status")
	var changed: Array = box.entries.duplicate(true)
	changed[0].required += 1
	box.show_entries(changed)
	check(box.get_children() == chips and box.get_child(0).get_node("RequiredQuantity").text == "× %d" % int(changed[0].required), "A required quantity change updates the existing label")
	# Unknown masking happens before even calling the data projection.
	box.show_ingredients(null, "never_disclose_this_recipe", false)
	check(not box.visible and box.entries.is_empty() and box.get_child_count() == 0, "Unknown ingredients have no remaining visible children")
	check(box.tooltip_text.is_empty() and not box.get_meta("actual_names_visible") and box.get_meta("ingredient_entries").is_empty(), "Unknown tooltips and metadata cannot leak names or quantities")
	box.show_entries([{ "id": "secret_material", "name": "Secret", "required": 999, "owned": 7 }], false)
	check(box.get_child_count() == 0 and box.entries.is_empty(), "Masked raw entries are discarded without art lookup")
	host.free()
	print("INGREDIENT ICONS PASS: ", checks, " checks; ", kinds.size(), " actual recipes; 32px/16px quantities, wrapping, reserved/next shortage, masked metadata, unchanged state/RNG; headless only")
	quit()
