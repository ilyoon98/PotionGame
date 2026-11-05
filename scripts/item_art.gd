extends RefCounted
## Shared item identity for inventory, recipes, shelf and handover animations.
const ROOT := "res://assets/items_v1/"
const Content = preload("res://scripts/shop_content.gd")
const UiPixel = preload("res://scripts/ui_pixel_catalog.gd")
static var CATALOG: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/content_expansion_v1/catalog.json"))
static var RARE_CATALOG: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/rare_recipes_v1/catalog.json"))
static var GROWTH_FRAMES := {}
const UNKNOWN_RECIPE_PATH := "res://assets/rare_discovery_ui_v1/unknown_recipe_map.png"

static func unknown_recipe_icon() -> Texture2D:
	var replacement := UiPixel.icon("unknown_recipe")
	if replacement != null: return replacement
	return load(UNKNOWN_RECIPE_PATH)

static func rare_art(id: String) -> Dictionary:
	# Approved files are selected by their supplied IDs; never recolor or resize.
	for row in RARE_CATALOG.assets:
		if row.id == id: return row
	return {}

static func recipe_icon(id: String) -> Texture2D:
	var replacement := UiPixel.icon("recipe:" + id)
	if replacement == null: replacement = UiPixel.icon(id)
	if replacement != null: return replacement
	var rare := rare_art(id)
	if not rare.is_empty(): return load(rare.recipe_path)
	var source := Content.lookup("potions", id)
	var path: String = source.get("recipe_candidate", "")
	return load(path) if not path.is_empty() else icon(id)

static func growth_frame(id: String, progress: float, full: bool = false) -> Texture2D:
	var path := growth_path(id)
	if path.is_empty(): return icon(id)
	if not GROWTH_FRAMES.has(id):
		var sheet: Texture2D = load(path)
		var frames := []
		for i in 4:
			var frame := AtlasTexture.new()
			frame.atlas = sheet
			frame.region = Rect2((i % 2) * 32, (i / 2) * 40, 32, 40)
			frame.filter_clip = true
			frames.append(frame)
		GROWTH_FRAMES[id] = frames
	return GROWTH_FRAMES[id][2 if full else mini(2, int(clampf(progress, 0, 1) * 3))]

static func growth_path(id: String) -> String:
	for row in CATALOG["assets"]:
		if row["id"] == id and row["category"] == "materials": return row.get("growth_path", "")
	return ""

static func equipment_icon(track: String, stage: int) -> Texture2D:
	var maximum := maxi(1, Content.track_rows(track).size())
	var tier := mini(2, int(float(stage) / maximum * 3.0))
	var replacement := UiPixel.equipment(track, tier)
	if replacement != null: return replacement
	return load("res://assets/content_expansion_v1/equipment/%s_%s.png" % [track, ["basic", "improved", "premium"][tier]])
const ICONS := {
	"health": "health_icon.png", "mana": "mana_icon.png",
	"moon": "moon_icon.png", "purify": "purify_icon.png", "agility": "agility_icon.png",
	"herb": "herb_icon.png", "starleaf": "starleaf_icon.png",
}
const DESCRIPTIONS := {
	"health": "체력 · 분홍빛 둥근 병", "mana": "마나 · 푸른 별 문양",
	"moon": "달빛 · 보라빛 둥근 병과 초승달", "purify": "정화 · 민트빛 각진 병과 잎 문양",
	"agility": "민첩 · 금빛 가느다란 병과 번개", "herb": "기본 약초 · 넓은 녹색 잎",
	"starleaf": "별잎 · 은보라색 별 모양 잎",
}


static func potion_id(kind: Variant) -> String:
	return ("mana" if kind else "health") if kind is bool else str(kind)


static func bottle(kind: Variant) -> Texture2D:
	return preload("res://scripts/pixel_art_catalog.gd").bottle(kind)


static func has_icon(id: String) -> bool:
	if UiPixel.icon(id) != null: return true
	if ICONS.has(id) or id == "mushroom": return true
	if not rare_art(id).is_empty(): return true
	for category in ["potions", "materials", "regions", "employees"]:
		if not Content.lookup(category, id).is_empty(): return true
	return id.begins_with("growth:")


static func icon(id: String) -> Texture2D:
	var replacement := UiPixel.icon(id)
	if replacement != null: return replacement
	if id == "mushroom":
		replacement = UiPixel.icon("moon_mushroom")
		if replacement != null: return replacement
	if id == "mushroom": return load("res://assets/mushroom_24.png")
	if ICONS.has(id): return load(ROOT + ICONS[id])
	var rare := rare_art(id)
	if not rare.is_empty(): return load(rare.potion_path)
	for category in ["potions", "materials", "regions", "employees"]:
		var row := Content.lookup(category, id)
		if not row.is_empty(): return load(row["icon_candidate"])
	if id.begins_with("growth:"):
		var track := id.trim_prefix("growth:")
		replacement = UiPixel.icon(track)
		if replacement == null: replacement = UiPixel.equipment(track, 0)
		if replacement != null: return replacement
		if track.begins_with("family_"): return load("res://assets/content_expansion_v1/families/" + track.trim_prefix("family_") + "_icon.png")
		if not Content.lookup("employees", track).is_empty(): return icon(track)
		return load("res://assets/content_expansion_v1/equipment/" + track + "_basic.png")
	return null
