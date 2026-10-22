extends RefCounted
## Exact approved palette, shared by brewing, stock and the sold bottle.
const Catalog = preload("res://scripts/pixel_art_catalog.gd")
static func potion_id(kind: Variant) -> String: return Catalog.id(kind)
static func bottle_kind(kind: Variant) -> Variant:
	var key := potion_id(kind)
	return false if key == "health" else true if key == "mana" else key
static func liquid_color(kind: Variant) -> Color: return Catalog.liquid(kind)
static func cauldron_texture(kind: Variant, elapsed: float = 0.0) -> Texture2D: return Catalog.pot(kind, elapsed)
