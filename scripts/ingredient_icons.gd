extends HFlowContainer
## Display-only recipe quantities. The current batch has already reserved stock.
const Status = preload("res://scripts/management_status.gd")
const ItemArt = preload("res://scripts/item_art.gd")
const Palette = preload("res://scripts/management_palette.gd")
const ICON_SIZE := 32
const COUNT_SIZE := 16
var entries: Array = []
var known := false
var initialized := false

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("h_separation", 8)
	add_theme_constant_override("v_separation", 4)
	mouse_filter = Control.MOUSE_FILTER_PASS

func show_ingredients(state: RefCounted, kind: Variant, recipe_known: bool = true) -> void:
	# Mask first: an unknown recipe must not even resolve names or ingredients.
	if not recipe_known:
		show_entries([], false)
		return
	var items: Array = Status.ingredients(state, kind)
	show_entries(items, not items.is_empty())

func show_entries(items: Array, recipe_known: bool = true) -> void:
	var next: Array = items.duplicate(true) if recipe_known else []
	if initialized and known == recipe_known and entries == next: return
	# Stock and reservation details change during play; the displayed recipe
	# usually does not. Keep its Controls and update their data in place.
	var same_recipe := initialized and known == recipe_known and entries.size() == next.size()
	if same_recipe:
		for index in next.size():
			if entries[index].id != next[index].id:
				same_recipe = false
				break
	initialized = true
	known = recipe_known
	entries = next
	visible = known and not entries.is_empty()
	tooltip_text = detail_text(entries)
	set_meta("recipe_known", known)
	set_meta("actual_names_visible", known and not entries.is_empty())
	set_meta("ingredient_entries", entries.duplicate(true))
	set_meta("ingredient_detail", tooltip_text)
	if same_recipe:
		for index in entries.size():
			var item: Dictionary = entries[index]
			var chip := get_child(index)
			chip.tooltip_text = detail_text([item])
			chip.set_meta("ingredient", item.duplicate(true))
			var quantity: Label = chip.get_node("RequiredQuantity")
			var text := "× %d" % int(item.required)
			if quantity.text != text: quantity.text = text
		return
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for index in entries.size():
		var item: Dictionary = entries[index]
		var chip := HBoxContainer.new()
		chip.name = "Ingredient_" + str(item.id)
		chip.add_theme_constant_override("separation", 4)
		chip.tooltip_text = detail_text([item])
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		chip.set_meta("ingredient", item.duplicate(true))
		add_child(chip)
		if index > 0:
			var separator := Label.new()
			separator.text = "+"
			separator.add_theme_font_size_override("font_size", COUNT_SIZE)
			separator.add_theme_color_override("font_color", Palette.MUTED)
			separator.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chip.add_child(separator)
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.texture = ItemArt.icon(str(item.id))
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(icon)
		var quantity := Label.new()
		quantity.name = "RequiredQuantity"
		quantity.text = "× %d" % int(item.required)
		quantity.add_theme_font_size_override("font_size", COUNT_SIZE)
		quantity.add_theme_color_override("font_color", Palette.TEXT)
		quantity.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		quantity.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(quantity)

static func detail_text(items: Array) -> String:
	var lines := PackedStringArray()
	for item: Dictionary in items:
		var missing: int = maxi(0, int(item.get("missing", 0)))
		var next_missing: int = maxi(0, int(item.get("next_missing", missing)))
		var line := "%s · 1병당 %d개 필요 · 현재 %d개" % [item.name, int(item.required), int(item.owned)]
		if item.get("reserved", false):
			line += " · 현재 배치 재료 예약 완료"
			line += " · 다음 병 %d개 부족" % next_missing if next_missing > 0 else " · 다음 병 재료 준비 완료"
		else:
			line += " · %d개 부족" % missing if missing > 0 else " · 재료 준비 완료"
		lines.append(line)
	return "\n".join(lines)
