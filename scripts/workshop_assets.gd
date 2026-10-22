extends RefCounted
## Atlas regions keep the supplied source artwork intact; trim export padding only.
const ROOT := "res://assets/workshop_v1/"
const Layout = preload("res://scripts/workshop_layout.gd")
const SIZE := Layout.SIZE
const ART_HEIGHT := Layout.ART_HEIGHT
const BAR_HEIGHT := Layout.BAR_HEIGHT
static var _toolbar_frame: ImageTexture

static func wide_prop(kind: String) -> Texture2D:
	return load("res://assets/workshop_wide_v1/" + kind + ".png")


static func region(path: String, rect: Rect2) -> AtlasTexture:
	var result := AtlasTexture.new()
	result.atlas = load(ROOT + path)
	result.region = rect
	return result


static func rug() -> AtlasTexture:
	return region("moon-rug.png", Rect2(137, 153, 1748, 495))


static func plant() -> AtlasTexture:
	return region("moon-herb-pot.png", Rect2(326, 189, 648, 832))


static func bar() -> AtlasTexture:
	return region("management-bar-empty.png", Rect2(54, 258, 2038, 176))


static func toolbar_frame() -> Texture2D:
	if _toolbar_frame == null:
		# Rasterize the existing UI at its display scale once. A standalone,
		# power-of-two texture avoids atlas UV rounding at the right corners.
		var image := bar().get_image()
		image.resize(512,44,Image.INTERPOLATE_NEAREST)
		_toolbar_frame = ImageTexture.create_from_image(image)
	return _toolbar_frame


static func window_frame() -> AtlasTexture:
	return region("window-frame.png", Rect2(151, 173, 1156, 746))


static func icon(kind: String) -> AtlasTexture:
	var regions := {
		"gold-coin": Rect2(411, 324, 501, 522),
		"time-day": Rect2(263, 193, 797, 887),
		"time-night": Rect2(268, 179, 767, 865),
		"weather-cloudy": Rect2(432, 316, 608, 326),
		"weather-rainy": Rect2(433, 317, 604, 490),
		"weather-sunny": Rect2(175, 172, 904, 885),
	}
	return region("icons/" + kind + ".png", regions[kind])
