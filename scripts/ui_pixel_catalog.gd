extends RefCounted
## Presentation-only overrides. Missing files keep the previous art available.
const PATH := "res://assets/ui_pixel_v2/catalog.json"
static var DATA: Dictionary = _read_catalog()
static var textures := {}

static func _read_catalog() -> Dictionary:
	if not FileAccess.file_exists(PATH): return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return value if value is Dictionary else {}

static func _texture(path: String) -> Texture2D:
	if textures.has(path): return textures[path]
	if path.is_empty() or not ResourceLoader.exists(path): return null
	textures[path] = load(path) as Texture2D
	return textures[path]

static func icon(id: String) -> Texture2D:
	return _texture(str(DATA.get("icons", {}).get(id, "")))

static func equipment(track: String, tier: int) -> Texture2D:
	var paths: Array = DATA.get("equipment", {}).get(track, [])
	return _texture(str(paths[clampi(tier, 0, paths.size() - 1)])) if not paths.is_empty() else null

static func owns(texture: Texture2D) -> bool:
	return texture != null and texture.resource_path.begins_with("res://assets/ui_pixel_v2/")
