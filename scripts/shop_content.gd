extends RefCounted
## Development balance; approved scope, provisional numbers. See docs/구현-임시값.md.
static var DATA: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content_expansion.json"))
const Rare = preload("res://scripts/rare_recipes.gd")
const RARE_ROWS := Rare.ROWS
static var RECIPES: Dictionary = build_recipes()
static var LOOKUPS: Dictionary = {}
static var TRACKS: Dictionary = {}
const LEGACY_RECIPES := {
	"moon": {"name": "달빛 물약", "cost": 120, "reputation": 0, "price": 26, "duration": 1.5, "success": 0.86, "color": "c6aeed"},
	"purify": {"name": "정화 물약", "cost": 180, "reputation": 10, "price": 24, "duration": 1.4, "success": 0.88, "color": "9addba"},
	"agility": {"name": "민첩 물약", "cost": 240, "reputation": 20, "price": 28, "duration": 1.6, "success": 0.84, "color": "e9c573"},
}


static func build_recipes() -> Dictionary:
	var result := LEGACY_RECIPES.duplicate(true)
	for row in DATA["potions"]:
		if row["existing"]: continue
		result[row["id"]] = {"name": row["name"], "cost": int(row["cost"]), "reputation": 0, "price": int(row["sale_price"]), "duration": float(row["duration_multiplier"]), "success": float(row["success"]), "color": "c6aeed"}
	for row in RARE_ROWS:
		result[row.id] = {"name": row.name, "cost": int(row.cost), "reputation": 0, "price": int(row.sale_price), "duration": float(row.duration_multiplier), "success": float(row.success), "color": "c6aeed"}
	return result


static func lookup(category: String, id: String) -> Dictionary:
	if not LOOKUPS.has(category):
		LOOKUPS[category] = {}
		for row in DATA[category]: LOOKUPS[category][row["id"]] = row
		if category == "potions":
			for row in RARE_ROWS: LOOKUPS[category][row.id] = row
	return LOOKUPS[category].get(id, {})


static func track_rows(track: String) -> Array:
	if TRACKS.is_empty():
		for row in DATA["upgrades"]:
			if not TRACKS.has(row["track"]): TRACKS[row["track"]] = []
			TRACKS[row["track"]].append(row)
	return TRACKS.get(track, [])
const CUSTOMERS := [
	{"id": "traveler", "name": "여행자", "preferences": [false], "base": 5.0, "night": 0.0, "clear": 0.0, "rain": 0.0},
	# Keep this slot for existing saves; excluded from the current roster.
	{"id": "knight", "name": "여기사", "enabled": false, "preferences": [false], "base": 2.0, "night": -1.0, "clear": 3.0, "rain": 0.0},
	{"id": "mage", "name": "여마법사", "preferences": ["moon", true], "base": 2.0, "night": 3.0, "clear": 0.0, "rain": 0.0},
	{"id": "elf", "name": "엘프", "preferences": ["purify"], "base": 2.0, "night": 0.0, "clear": 0.0, "rain": 4.0},
	{"id": "rogue", "name": "고양이 도적", "preferences": ["agility"], "base": 1.0, "night": 4.0, "clear": 2.0, "rain": 0.0},
]
const DAY_SECONDS := 240.0
const WEATHER_SECONDS := 90.0
const SPECIAL_CAPACITY := 12
const FILTER_COST := 300
const EMPLOYEE_COST := 360
const EMPLOYEE_REPUTATION := 20
const EXPEDITION_COST := 400
const EXPEDITION_REPUTATION := 10
const EXPLORE_SECONDS := 60.0
const RETURN_SECONDS := 10.0
## Candidate C. Values are final stage values, not compound multipliers.
const SALES_COUNTER_SECONDS := [3.2, 3.05, 2.8, 2.4, 2.1, 1.9, 1.7, 1.65, 1.6, 1.55, 1.5]
const SALES_COUNTER_COSTS := [240, 480, 800, 1280, 1920, 2880, 4320, 6400, 9600, 14400]
const SALES_COUNTER_REGIONS := [0, 0, 1, 2, 3, 4, 5, 6, 7, 8]
const FOREST_COMPLETION_RETURNS := 10


static func potion_name(kind: Variant) -> String:
	if kind is bool:
		return "마나" if kind else "체력"
	return RECIPES.get(kind, {}).get("name", "물약")


static func valid_kind(kind: Variant) -> bool:
	return kind is bool or (kind is String and RECIPES.has(kind))
