extends Control
## B companion: original sprites, live economy, cached raster halos, GPU pixel light.
const PixelScene = preload("res://scripts/pixel_shop_scene.gd")
const Catalog = preload("res://scripts/pixel_art_catalog.gd")
const PixelLight = preload("res://scripts/pixel_workshop_light.gd")
const Assets = preload("res://scripts/workshop_assets.gd")
const PotionVisual = preload("res://scripts/potion_visual.gd")
const WorkshopGauges = preload("res://scripts/workshop_gauges.gd")
## F21 keeper stat badge: under the time/weather badge, left of the keeper.
const KEEPER_BADGE := Rect2(8, 35, 96, 22)
const SIZE := Vector2i(256, 228)
const ART_HEIGHT := 177
const BAR_HEIGHT := 51
const FLOOR_Y := 165
const POT_ORIGIN := Vector2(24,72)
const KEEPER_ORIGIN := Vector2(117,24)
const GOLD_FONT_SIZE := 15
var host: Control
var scene: Control
var gold: Label
var gauge: ProgressBar
var time_icon: TextureRect
var weather_icon: TextureRect
var light: ShaderMaterial
var glow_warm: TextureRect
var glow_pink: TextureRect
var keeper: Array[Texture2D] = []
var cauldron: Texture2D
var rug: Texture2D
var hearth: Texture2D
var elapsed := 0.0
var frame := 0
var minimize_button: Button
var keeper_badge: Panel
var keeper_caption: Label
var keeper_fill: ColorRect
var move_button: Button
var restore_button: Button
var manage_button: Button
var close_button: Button
var toolbar: Control
var drag: Control
var cached_icons := {}


class SceneArt extends Control:
	var owner_view: Control
	func _draw() -> void:
		for command in owner_view.render_commands():
			owner_view.host.art.draw_command(self,command)

func render_commands() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var view: Control = host.art
	var pose := PixelScene.keeper_pose(view)
	for row in 4:
		out.append({"role":"floor","texture":null,"rect":Rect2(0,FLOOR_Y+row*3,SIZE.x,3),"flip_h":false,"color":[Color("e9b95f"),Color("916047"),Color("50333b"),Color("241c32")][row]})
	out.append(PixelScene.command("fire",Catalog.texture(Catalog.DATA.fire[int(elapsed*8)%4]),POT_ORIGIN+Vector2(30,69)))
	var pot := Catalog.pot(view.potion_kind,elapsed)
	out.append(PixelScene.command("cauldron",pot,POT_ORIGIN))
	if pose.begins_with("brew"):
		out.append_array(PixelScene.spoon_commands(view,POT_ORIGIN,KEEPER_ORIGIN,pose))
		var foreground := AtlasTexture.new()
		foreground.atlas = pot
		foreground.region = Rect2(0,11,32,21)
		out.append(PixelScene.command("cauldron_foreground",foreground,POT_ORIGIN+Vector2(0,33)))
	out.append_array(PixelScene.keeper_commands(pose,elapsed,KEEPER_ORIGIN))
	return out


func _ready() -> void:
	size = Vector2(SIZE)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for path in ["keeper_idle_48x64.png", "keeper_brew_1_48x64.png", "keeper_brew_2_48x64.png"]:
		keeper.append(load("res://assets/characters/animations_v1/" + path))
	cauldron = load("res://assets/cauldron_48.png")
	rug = Assets.rug()
	hearth = PixelLight.make_hearth()
	for id in ["time-day", "time-night", "weather-sunny", "weather-cloudy", "weather-rainy"]: cached_icons[id] = Assets.icon(id)
	var clip := Control.new()
	clip.size = Vector2(SIZE.x, ART_HEIGHT)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(clip)
	scene = SceneArt.new()
	scene.owner_view = self
	scene.size = Vector2(SIZE.x, ART_HEIGHT)
	scene.scale = Vector2.ONE
	scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(scene)
	light = ShaderMaterial.new()
	light.shader = PixelLight.SHADER
	scene.material = null
	glow_warm = PixelLight.halo_texture(Vector2(41, 58), Vector2(29, 6), Color8(255, 169, 67))
	glow_pink = PixelLight.halo_texture(Vector2(41, 25), Vector2(23, 11), Color8(236, 101, 183))
	for glow in [glow_warm, glow_pink]:
		glow.show_behind_parent = true
		scene.add_child(glow)
	var badge := Panel.new()
	badge.position = Vector2(8, 7)
	badge.size = Vector2(42, 24)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_stylebox_override("panel", host._style(Color("302238"), Color("705879"), 0))
	add_child(badge)
	time_icon = icon(badge, "time-day", Rect2(2, 2, 20, 20))
	weather_icon = icon(badge, "weather-cloudy", Rect2(23, 7, 15, 11))
	keeper_badge = Panel.new()
	keeper_badge.position = KEEPER_BADGE.position
	keeper_badge.size = KEEPER_BADGE.size
	keeper_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	keeper_badge.add_theme_stylebox_override("panel", host._style(Color("302238"), Color("705879"), 0))
	add_child(keeper_badge)
	keeper_caption = Label.new()
	keeper_caption.position = Vector2(5, 0)
	keeper_caption.size = Vector2(KEEPER_BADGE.size.x - 10, 16)
	keeper_caption.add_theme_font_override("font", host.body_font)
	keeper_caption.add_theme_font_size_override("font_size", 11)
	keeper_caption.add_theme_color_override("font_color", Color("efc77c"))
	keeper_badge.add_child(keeper_caption)
	var track := ColorRect.new()
	track.color = Color("49364f")
	track.position = Vector2(5, KEEPER_BADGE.size.y - 5)
	track.size = Vector2(KEEPER_BADGE.size.x - 10, 2)
	keeper_badge.add_child(track)
	keeper_fill = ColorRect.new()
	keeper_fill.position = track.position
	keeper_fill.size = Vector2(0, 2)
	keeper_badge.add_child(keeper_fill)
	gauge = ProgressBar.new()
	gauge.position = Vector2(8, ART_HEIGHT-3)
	gauge.size = Vector2(SIZE.x-16, 2)
	gauge.show_percentage = false
	gauge.add_theme_font_size_override("font_size", 1)
	gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for key in ["background", "fill"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("3d2e46") if key == "background" else Color("c1daa2")
		gauge.add_theme_stylebox_override(key, style)
	add_child(gauge)
	gauge.size = Vector2(SIZE.x-16, 2)
	var bar := Control.new()
	bar.position = Vector2(0, ART_HEIGHT)
	bar.size = Vector2(SIZE.x, BAR_HEIGHT)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	toolbar = bar
	host._toolbar_backing(bar)
	drag = Control.new()
	drag.size = Vector2(110, BAR_HEIGHT)
	drag.mouse_default_cursor_shape = Control.CURSOR_MOVE
	drag.tooltip_text = "드래그해서 이동 · 더블 클릭하면 펼치기"
	drag.gui_input.connect(host._mini_input)
	bar.add_child(drag)
	move_button = host._toolbar_move_button(bar, Vector2(8, 9))
	var coin := icon(drag, "gold-coin", Rect2(40, 18, 14, 16))
	coin.name = "GoldCoin"
	gold = Label.new()
	gold.position = Vector2(58, 9)
	gold.size = Vector2(48, 32)
	gold.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gold.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	gold.add_theme_color_override("font_color", Color("f2dbb4"))
	gold.add_theme_color_override("font_outline_color",Color("241c32"))
	gold.add_theme_constant_override("outline_size",3)
	gold.add_theme_font_size_override("font_size", GOLD_FONT_SIZE)
	gold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag.add_child(gold)
	var actions: Dictionary = host._toolbar_actions(bar, true, true, host._show_minimal_view, host._restore_compact_view, "축소 · 정보모드로", "확대 · 본모드로")
	manage_button = actions.manage
	minimize_button = actions.shrink
	restore_button = actions.expand
	close_button = actions.close
	refresh()


func icon(parent: Control, id: String, rect: Rect2) -> TextureRect:
	var node := TextureRect.new()
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.texture = Assets.icon(id)
	node.position = rect.position
	node.size = rect.size
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node


func _process(delta: float) -> void:
	if not visible: return
	elapsed += delta
	refresh()
	scene.queue_redraw()


func _gold_text(amount: int) -> String:
	var value: String = host._compact_number(amount)
	var font := gold.get_theme_font("font")
	if font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, GOLD_FONT_SIZE).x <= gold.size.x:
		return value
	# Keep the type large; abbreviate only amounts that exceed this fixed slot.
	# The exact amount remains available in the toolbar's existing tooltip.
	for unit in [[10000000000000000, "경"], [1000000000000, "조"], [100000000, "억"], [10000, "만"]]:
		if amount < unit[0]: continue
		for precision in ["%.1f%s", "%.0f%s"]:
			value = precision % [float(amount) / float(unit[0]), unit[1]]
			if font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, GOLD_FONT_SIZE).x <= gold.size.x:
				return value
	return host._compact_number(amount)


func refresh() -> void:
	if light == null: return
	var state = host.state
	var world = state.progression
	cauldron = PotionVisual.cauldron_texture(state.progression.active_recipe)
	frame = 1 + int(elapsed * 4.0) % 2 if state.is_brewing() else 0
	gold.text = _gold_text(state.gold)
	drag.tooltip_text = "보유 %s G · %s · 드래그 이동" % [host._number(state.gold), state.recipe_name()]
	var full: bool = state.stock >= state.capacity()
	gauge.value = host.Status.crafting(state).progress * 100.0
	manage_button.tooltip_text = "관리 열기 · " + ("재고 가득 · 판매 대기" if full else "약초 수확 대기" if state.waiting_for_herbs() else "%s 제조 %.1f초 남음" % [state.recipe_name(), state.brew_remaining_seconds()])
	time_icon.texture = cached_icons["time-night" if world.is_night() else "time-day"]
	weather_icon.texture = cached_icons[["weather-sunny", "weather-cloudy", "weather-rainy"][world.weather()]]
	keeper_caption.text = WorkshopGauges.keeper_text(state.keeper)
	keeper_fill.color = WorkshopGauges.fatigue_color(state.keeper.fatigue)
	keeper_fill.size.x = floorf(clampf(state.keeper.fatigue / 100.0, 0.0, 1.0) * (KEEPER_BADGE.size.x - 10))
	var values := PixelLight.environment(world.daylight(), float(world.weather()) / 2.0, world.effects, world.brightness_floor, world.clock)
	PixelLight.apply(light, scene, 1.0, Rect2(17, 11, 48, 48), values)
	glow_warm.visible = false
	glow_warm.modulate.a = values.halo_gain * values.flicker
	glow_pink.visible = false
	glow_pink.modulate.a = values.halo_gain * 0.67
