extends Control
## Shared pixel weather: clipped behind the room, floating behind workshop props.
const Content = preload("res://scripts/shop_content.gd")
const WorkshopAssets = preload("res://scripts/workshop_assets.gd")
const Layout = preload("res://scripts/workshop_layout.gd")
const WORKSHOP_WINDOW: Rect2 = Layout.RECTS.window
const TIME_PANE: Rect2 = Layout.RECTS.timePane
const WEATHER_PANE: Rect2 = Layout.RECTS.weatherPane
const DAY_SECONDS := Content.DAY_SECONDS
const WEATHER_SECONDS := Content.WEATHER_SECONDS
enum Weather { CLEAR, CLOUDY, RAIN }
const SUN = preload("res://assets/weather/v1/sun_24x24.png")
const MOON = preload("res://assets/weather/v1/moon_24x32.png")
const STAR = preload("res://assets/weather/v1/star_8x8.png")
const CLEAR_CLOUD = preload("res://assets/weather/v1/cloud_clear_64x24.png")
const RAIN_CLOUD = preload("res://assets/weather/v1/cloud_rain_96x32.png")
const RAIN_SHEET = preload("res://assets/weather/v1/rain_animation_192x192.png")

var elapsed := 0.0
var window_rect := Rect2(20, 40, 94, 72)
var preview_phase := -1.0
var preview_weather := -1
var transparent_scene := false
var effects := 1.0
var workshop_frame: Texture2D
var time_pane: Control
var weather_pane: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	show_behind_parent = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if transparent_scene:
		workshop_frame = WorkshopAssets.window_frame()
		time_pane = _make_workshop_pane(TIME_PANE)
		weather_pane = _make_workshop_pane(WEATHER_PANE)
		time_pane.draw.connect(_draw_time_pane)
		weather_pane.draw.connect(_draw_weather_pane)


func _make_workshop_pane(rect: Rect2) -> Control:
	var pane := Control.new()
	pane.position = rect.position
	pane.size = rect.size
	pane.clip_contents = true
	pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pane)
	return pane


func phase() -> float:
	return preview_phase if preview_phase >= 0.0 else fposmod(0.45 + elapsed / DAY_SECONDS, 1.0)


func daylight() -> float:
	return smoothstep(-0.12, 0.3, sin((phase() - 0.25) * TAU))


func weather_amount(kind: int) -> float:
	if preview_weather >= 0:
		return 1.0 if preview_weather == kind else 0.0
	var index := int(elapsed / WEATHER_SECONDS)
	var current := index % 3
	var previous := maxi(0, index - 1) % 3
	var blend := smoothstep(0.0, 12.0, fmod(elapsed, WEATHER_SECONDS))
	return lerpf(1.0 if previous == kind else 0.0, 1.0 if current == kind else 0.0, blend)


func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()


func _sprite(texture: Texture2D, point: Vector2, scale_factor: float, opacity: float = 1.0) -> void:
	if opacity <= 0.001: return
	draw_texture_rect(texture, Rect2(point.round(), texture.get_size() * scale_factor), false, Color(1, 1, 1, opacity))


func _rain(rect: Rect2, scale_factor: float, opacity: float) -> void:
	if opacity <= 0.001: return
	# The supplied four-frame loop is 8 fps, clipped below the cloud canopy.
	var frame := int(elapsed * 8.0) % 4
	var origin := Vector2(frame % 2, frame / 2) * 96.0
	draw_texture_rect_region(RAIN_SHEET, rect, Rect2(origin, rect.size / scale_factor), Color(1, 1, 1, opacity))


func _draw() -> void:
	if transparent_scene:
		_draw_workshop()
	else:
		_draw_window()


func _draw_workshop() -> void:
	# The panes have no backing fill: the user's desktop remains visible.
	for command in render_commands(): _draw_command(self, command)
	time_pane.queue_redraw()
	weather_pane.queue_redraw()


func _draw_time_pane() -> void:
	for command in pane_commands("time"): _draw_command(time_pane, command)


func celestial_rect(moon: bool) -> Rect2:
	var sprite_size := MOON.get_size() if moon else SUN.get_size()
	# Sunrise is phase .25, sunset .75. The moon follows half a day later.
	var progress := fposmod(phase() - (0.75 if moon else 0.25), 1.0) * 2.0
	if progress > 1.0:
		return Rect2(Vector2(0, TIME_PANE.size.y + sprite_size.y), sprite_size)
	var horizon := TIME_PANE.size.y + sprite_size.y / 2.0
	var center := Vector2(
		lerpf(-sprite_size.x / 2.0, TIME_PANE.size.x + sprite_size.x / 2.0, progress),
		horizon - sin(progress * PI) * (TIME_PANE.size.y - 4.0))
	# The pane clips rising/setting sprites, including partially visible edges.
	return Rect2((center - sprite_size / 2.0).round(), sprite_size)


func _draw_weather_pane() -> void:
	for command in pane_commands("weather"): _draw_command(weather_pane, command)


func render_commands() -> Array[Dictionary]:
	if not transparent_scene or workshop_frame == null: return []
	return [{"role": "window", "texture": workshop_frame, "rect": WORKSHOP_WINDOW, "color": Color.WHITE}]


func pane_commands(kind: String) -> Array[Dictionary]:
	# The same commands feed the live clipped panes and read-only render proofs.
	if kind == "time":
		var light := daylight()
		return [
			{"role": "sun", "texture": SUN, "rect": celestial_rect(false), "color": Color(1, 1, 1, light * effects)},
			{"role": "moon", "texture": MOON, "rect": celestial_rect(true), "color": Color(1, 1, 1, (1.0 - light) * effects)}]
	var rain := weather_amount(Weather.RAIN)
	var cloudy := weather_amount(Weather.CLOUDY)
	var drift := roundf(sin(elapsed * 0.12) * 2.0)
	var frame := int(elapsed * 8.0) % 4
	var origin := Vector2(frame % 2, frame / 2) * 96.0
	return [
		{"role": "cloud", "texture": CLEAR_CLOUD, "rect": Rect2(drift, 14, 40, 15), "color": Color(1, 1, 1, (1.0 - rain) * effects)},
		{"role": "dark_cloud", "texture": RAIN_CLOUD, "rect": Rect2(3 + drift, 17, 36, 12), "color": Color(1, 1, 1, maxf(rain, cloudy * 0.65) * effects)},
		{"role": "rain", "texture": RAIN_SHEET, "rect": Rect2(2, 29, 36, 32), "region": Rect2(origin, Vector2(36, 32)), "color": Color(1, 1, 1, rain * effects)}]


func _draw_command(ink: Control, command: Dictionary) -> void:
	if command.has("region"):
		ink.draw_texture_rect_region(command["texture"], command["rect"], command["region"], command["color"])
	else:
		ink.draw_texture_rect(command["texture"], command["rect"], false, command["color"])


func _snapshot_commands(commands: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for command in commands:
		var item := command.duplicate()
		var texture: Texture2D = item["texture"]
		item.erase("texture")
		item["source"] = texture.atlas.resource_path if texture is AtlasTexture else texture.resource_path
		item["source_rect"] = texture.region if texture is AtlasTexture else Rect2(Vector2.ZERO, texture.get_size())
		result.append(item)
	return result


func render_snapshot() -> Dictionary:
	return {"transparent_scene": transparent_scene, "frame": _snapshot_commands(render_commands()),
		"time_clip": Rect2(time_pane.position, time_pane.size) if time_pane != null else TIME_PANE,
		"weather_clip": Rect2(weather_pane.position, weather_pane.size) if weather_pane != null else WEATHER_PANE,
		"time_commands": _snapshot_commands(pane_commands("time")),
		"weather_commands": _snapshot_commands(pane_commands("weather")),
		"phase": phase(), "weather": preview_weather, "effects": effects,
		"day_seconds": DAY_SECONDS, "weather_seconds": WEATHER_SECONDS}


func _draw_window() -> void:
	var light := daylight()
	var rain := weather_amount(Weather.RAIN)
	var clouds := weather_amount(Weather.CLOUDY) + rain
	var sky_top := Color("202b53").lerp(Color("7caac4"), light)
	var sky_bottom := Color("555373").lerp(Color("d2d6b2"), light)
	var twilight := (1.0 - absf(light * 2.0 - 1.0)) * 0.6
	sky_bottom = sky_bottom.lerp(Color("dcae99"), twilight)
	sky_top = sky_top.lerp(Color("687888"), rain * 0.55)
	sky_bottom = sky_bottom.lerp(Color("9caaa8"), rain * 0.65)
	for band in range(31):
		draw_rect(Rect2(0, band * 8, 408, 8), sky_top.lerp(sky_bottom, minf(1.0, band * 8.0 / 132.0)))
	for point in [Vector2(30, 43), Vector2(78, 42), Vector2(100, 64), Vector2(27, 89)]:
		_sprite(STAR, point, 1, (1.0 - light) * (1.0 - clouds * 0.75))
	var p := phase()
	var travel := (p - 0.25) * 2.0 if p >= 0.25 and p <= 0.75 else fposmod(p + 0.25, 1.0) * 2.0
	var center := Vector2(window_rect.position.x + 12 + travel * 70, 94 - sin(travel * PI) * 38)
	_sprite(SUN, center - Vector2(12, 12), 1, light)
	_sprite(MOON, center - Vector2(12, 16), 1, 1.0 - light)
	var distant := Color("39465a").lerp(Color("7b9c95"), light).lerp(Color("667d85"), rain * 0.4)
	draw_colored_polygon(PackedVector2Array([Vector2(0, 120), Vector2(30, 100), Vector2(64, 113), Vector2(99, 94), Vector2(158, 119), Vector2(408, 119), Vector2(408, 248), Vector2(0, 248)]), distant)
	_rain(Rect2(16, 36, 96, 80), 1, rain * effects)
	var drift := roundf(sin(elapsed * 0.12) * 14.0)
	_sprite(CLEAR_CLOUD, Vector2(26 + drift, 54), 1, (1.0 - rain) * (0.45 + clouds * 0.55))
	_sprite(RAIN_CLOUD, Vector2(14 + drift, 34), 1, rain)
