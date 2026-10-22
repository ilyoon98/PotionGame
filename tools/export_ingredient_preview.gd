extends "res://tools/export_expedition_cards.gd"
## File proof of the reusable component, not a screenshot of management UI.
const Ingredients = preload("res://scripts/ingredient_icons.gd")
const Content = preload("res://scripts/shop_content.gd")
const ItemArt = preload("res://scripts/item_art.gd")
const Palette = preload("res://scripts/management_palette.gd")
const TITLE_FONT = preload("res://assets/fonts/pretendard/Pretendard-SemiBold.otf")

func _initialize() -> void:
	assert(DisplayServer.get_name() == "headless")
	set_meta("isolated_preview", true)
	server = TextServerManager.get_primary_interface()
	output = "res://.verification/ingredients-rare-20261013/layout"
	call_deferred("run")

func label(parent: Node, value: String, size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = value
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", color)
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(result)
	return result

func make_panel(state: RefCounted, kind: Variant, recipe_known: bool, width: int) -> PanelContainer:
	var boundary := PanelContainer.new()
	var theme := Theme.new()
	theme.default_font = FONT
	theme.default_font_size = 16
	boundary.theme = theme
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.BG
	style.border_color = Palette.LINE
	style.set_border_width_all(1)
	style.set_content_margin_all(12)
	boundary.add_theme_stylebox_override("panel", style)
	boundary.size = Vector2(width, 0)
	root.add_child(boundary)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	boundary.add_child(body)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 10)
	body.add_child(heading)
	var picture := TextureRect.new()
	picture.texture = ItemArt.icon(ItemArt.potion_id(kind)) if recipe_known else ItemArt.unknown_recipe_icon()
	picture.custom_minimum_size = Vector2(48, 48)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	heading.add_child(picture)
	var title: String = str(Content.lookup("potions", ItemArt.potion_id(kind)).name) if recipe_known else "특별 레시피 · 미발견"
	var title_label := label(heading, title, 18, Palette.TEXT)
	title_label.add_theme_font_override("font", TITLE_FONT)
	title_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if recipe_known: label(body, "1병 배합", 16, Palette.MUTED)
	var ingredients := Ingredients.new()
	ingredients.name = "Ingredients"
	body.add_child(ingredients)
	ingredients.show_ingredients(state, kind, recipe_known)
	if recipe_known: label(body, Ingredients.detail_text(ingredients.entries), 16, Palette.MUTED)
	else: label(body, "발견하면 실제 이름과 배합을 확인할 수 있어요.", 16, Palette.MUTED)
	return boundary

func run() -> void:
	assert(DirAccess.make_dir_recursive_absolute(output.path_join("textures")) == OK)
	var cases := []
	for item in [{"id": "health", "kind": false, "width": 380}, {"id": "mana", "kind": true, "width": 380}, {"id": "spirit", "kind": "spirit", "width": 380}, {"id": "sage-four", "kind": "sage_elixir", "width": 380}, {"id": "sage-wrap", "kind": "sage_elixir", "width": 180}, {"id": "forest-special", "kind": "rare_forest_breath", "width": 380}, {"id": "mist-special", "kind": "rare_mist_veil", "width": 380}, {"id": "lunar-special", "kind": "rare_lunar_seal", "width": 380}, {"id": "nebula-special", "kind": "rare_nebula_distillate", "width": 380}, {"id": "mana-reserved", "kind": true, "reserved": true, "width": 380}, {"id": "unknown", "kind": null, "known": false, "width": 380}]:
		var state := State.new()
		for art in ItemArt.RARE_CATALOG.assets: state.progression.expansion.rare_discovered.append(art.id)
		state.herbs = 2
		state.mushrooms = 0
		state.progression.rare_herbs = 0
		state.progression.expansion.materials = {"dewgrass": 1, "silver_moss": 1, "blue_reed": 1, "crystal_herb": 1, "ash_sage": 1, "moonflower": 1, "star_seed": 1}
		if item.get("reserved", false):
			state.brew_active = true
			state.progression.active_recipe = true
			state.herbs = 0
		var before: Dictionary = state.to_data().duplicate(true)
		var recipe_known: bool = item.get("known", true)
		var boundary := make_panel(state, item.kind, recipe_known, int(item.width))
		for frame in range(4): await process_frame
		commands = []
		nodes = []
		export_node(boundary, boundary)
		var ingredients: Control = boundary.find_child("Ingredients", true, false)
		assert(Compare.equivalent(before, state.to_data()))
		if not recipe_known:
			assert(ingredients.entries.is_empty() and ingredients.tooltip_text.is_empty())
			for node in nodes: assert(not str(node.get("text", "")).contains("월광봉인"))
		cases.append({"id": item.id, "size": vector(boundary.size), "commands": commands.duplicate(true), "nodes": nodes.duplicate(true), "known": recipe_known, "entries": ingredients.entries.duplicate(true), "details": ingredients.tooltip_text})
		boundary.free()
	var file := FileAccess.open(output.path_join("ingredients.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"verification": "Standalone actual IngredientIcons controls and TextServer glyphs; 32px textures/16px counts and details; approved source art preserved; no screen or game capture", "font": ProjectSettings.globalize_path(FONT.resource_path), "cases": cases}, "\t"))
	print("INGREDIENT FILE EXPORT PASS: ", cases.size(), " actual-component layouts; bool basics, multi-material, narrow wrap, four special blends, reserved/next shortage and approved unknown-map masking; unchanged state/RNG; headless only: ", ProjectSettings.globalize_path(output))
	quit()
