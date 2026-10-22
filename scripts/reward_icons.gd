extends HFlowContainer
## Presentation only: public ranges and completed amounts never roll or pay.
const Content = preload("res://scripts/shop_content.gd")
const ItemArt = preload("res://scripts/item_art.gd")
const ManagementArt = preload("res://scripts/management_art.gd")
var entries: Array = []

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("h_separation", 8)
	add_theme_constant_override("v_separation", 4)

func show_rewards(rewards: Dictionary) -> void:
	var items := []
	for id in rewards:
		if int(rewards[id]) > 0: items.append({"id": id, "kind": "material", "count": int(rewards[id])})
	show_entries(items)

func show_entries(items: Array) -> void:
	if entries == items: return
	entries = items.duplicate(true)
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for item in entries:
		var recipe: bool = item.get("kind", "material") == "recipe"
		var data := Content.lookup("potions" if recipe else "materials", item.id)
		var chip := HBoxContainer.new()
		chip.custom_minimum_size.x = 178
		chip.add_theme_constant_override("separation", 6)
		add_child(chip)
		var icon := TextureRect.new()
		var recipe_path: String = item.get("recipe_path", "")
		icon.texture = load(recipe_path) if recipe and not recipe_path.is_empty() else ManagementArt.icon("basic") if recipe else ItemArt.icon(item.id)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.custom_minimum_size = Vector2(32, 32)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.add_child(icon)
		var label := Label.new()
		label.custom_minimum_size.x = 140
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 14)
		var suffix := " · 특별 발견" if recipe else " ×%d" % int(item.get("count", 0))
		if item.has("min"):
			suffix = " %d~%d개" % [int(item.min), int(item.max)]
			if not item.get("range_only", false): suffix += " · " + ("보장" if item.get("guaranteed", false) else "추첨")
		elif item.has("status"): suffix = " · " + str(item.status)
		label.text = str(item.get("name", data.get("name", "레시피"))) + suffix
		chip.tooltip_text = str(item.get("tooltip", label.text))
		chip.add_child(label)
