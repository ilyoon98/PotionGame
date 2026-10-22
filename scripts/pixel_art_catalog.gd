extends RefCounted
## Published pixels and approved color assignments. No gameplay state lives here.
static var DATA: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/pixel_v1/catalog.json"))
static var textures := {}
static var frames := {}

static func id(kind: Variant) -> String:
	var key := ("mana" if kind else "health") if kind is bool else str(kind)
	return key if DATA.potions.has(key) else "health"

static func texture(path: String) -> Texture2D:
	if not textures.has(path): textures[path] = load(path)
	return textures[path]

static func bottle(kind: Variant) -> Texture2D:
	return texture(DATA.potions[id(kind)].bottle)

static func bottle_size(kind: Variant) -> Vector2:
	var value: Array = DATA.potions[id(kind)].bottle_size
	return Vector2(value[0], value[1])

static func liquid(kind: Variant) -> Color:
	return Color(DATA.potions[id(kind)].liquid_color)

static func pot(kind: Variant, elapsed: float = 0.0) -> Texture2D:
	return texture(DATA.potions[id(kind)].pots[int(elapsed * 6.0) % 3])

static func frame(character: String, pose: String, index: int, fine: bool = true) -> AtlasTexture:
	var path: String = DATA.characters[character].poses[pose]["fine" if fine else "native"]
	var key := path + ":" + str(index)
	if not frames.has(key):
		var cell := Vector2(96, 144) if fine else Vector2(32, 48)
		var result := AtlasTexture.new()
		result.atlas = texture(path)
		result.region = Rect2(Vector2(index % 16, index / 16) * cell, cell)
		result.filter_clip = true
		frames[key] = result
	return frames[key]

static func motion_index(elapsed: float, pose: String) -> int:
	var walking := pose.begins_with("walk_") or pose.begins_with("carry_")
	var lift := pose.contains("_pass_") if walking else fmod(elapsed, 3.0) >= 1.5
	var blink := fmod(elapsed, 4.5) >= 3.6 and fmod(elapsed, 4.5) < 3.85
	return int(elapsed * 8.0) % 16 + (16 if lift else 0) + (32 if blink else 0)

static func local_grip(character: String, kind: Variant) -> Vector2:
	var point: Array = DATA.characters[character].bindings[id(kind)].local_grip
	return Vector2(point[0], point[1])

static func hand(character: String, pose: String) -> Vector2:
	var point: Array = DATA.characters[character].grips[pose]
	return Vector2(point[0], point[1])
