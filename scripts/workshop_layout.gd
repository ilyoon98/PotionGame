extends RefCounted
## Approved 540 layout. The design manifest is checked by verify_wide_workshop.gd.
const SIZE := Vector2i(540, 300)
const ART_HEIGHT := 249
const BAR_HEIGHT := 51
const POSTER_INTERIOR := Rect2(477,39,36,45)
const RECTS := {
	"window": Rect2(12, 15, 96, 96),
	"stand": Rect2(12, 225, 96, 15),
	"growth": Rect2(12, 144, 96, 96),
	"pot": Rect2(123, 144, 96, 96),
	"hearth": Rect2(153, 213, 36, 24),
	"keeper": Rect2(216, 96, 96, 144),
	"rug": Rect2(228, 198, 94, 26),
	"shelf": Rect2(315, 3, 144, 144),
	"counter": Rect2(315, 192, 144, 48),
	"poster": Rect2(459, 3, 72, 96),
	"customer": Rect2(444, 96, 96, 144),
	"herbPanel": Rect2(6, 114, 102, 24),
	"potPanel": Rect2(111, 66, 108, 24),
	"timePane": Rect2(24, 42, 40, 62),
	"weatherPane": Rect2(70, 42, 40, 62),
}
const BUTTONS := {
	"herbs": Rect2i(86, 117, 18, 18),
	"potions": Rect2i(114, 69, 18, 18),
	"expeditions": Rect2i(487, 68, 16, 16),
}
const TOOLBAR := {
	"move": Rect2(8, 258, 28, 32), "coin": Rect2(44, 265, 16, 18),
	"gold": Rect2(68, 258, 100, 32), "time": Rect2(184, 262, 20, 24),
	"weather": Rect2(220, 262, 22, 24),
	"manage": Rect2(394, 258, 42, 32), "minimize": Rect2(440, 258, 28, 32),
	"expand": Rect2(472, 258, 28, 32), "close": Rect2(504, 258, 28, 32),
}
const POINTS := {
	"purchaseFeet": Vector2(492, 240), "offscreenFeet": Vector2(600, 240),
	"hand": Vector2(468, 189), "brewOrigin": Vector2(171, 165),
	"reserve": Vector2(447, 159),
}
const SLOTS := [Vector2(339, 51), Vector2(369, 51), Vector2(399, 51), Vector2(429, 51),
	Vector2(339, 114), Vector2(369, 114), Vector2(399, 114), Vector2(429, 114)]

static func rect(key: String) -> Rect2: return RECTS[key]
static func point(key: String) -> Vector2: return POINTS[key]
static func slot_center(index: int) -> Vector2: return SLOTS[index] if index < SLOTS.size() else POINTS.reserve
static func button_rect(kind: String) -> Rect2i: return BUTTONS[kind]
static func toolbar_rect(kind: String) -> Rect2:
	var result: Rect2 = TOOLBAR[kind]
	result.position.y -= ART_HEIGHT
	return result
