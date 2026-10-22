extends Control
## Frame animations are visual; inventory and money remain owned by ShopState.

const PixelScene = preload("res://scripts/pixel_shop_scene.gd")
const PixelCatalog = preload("res://scripts/pixel_art_catalog.gd")
const PixelLight = preload("res://scripts/pixel_workshop_light.gd")
const Motion = preload("res://scripts/shop_motion.gd")
const ShopSky = preload("res://scripts/shop_sky.gd")
const PotionDisplay = preload("res://scripts/potion_display.gd")
const Content = preload("res://scripts/shop_content.gd")
const WorkshopAssets = preload("res://scripts/workshop_assets.gd")
const ItemArt = preload("res://scripts/item_art.gd")
const PotionVisual = preload("res://scripts/potion_visual.gd")
const Layout = preload("res://scripts/workshop_layout.gd")
const WindowVisitor = preload("res://scripts/window_visitor.gd")
var window_visitor := WindowVisitor.new()
const CHARACTER_SIZE := Vector2(96, 144)
const SHOPKEEPER_FEET := Vector2(169, 207)
const CUSTOMER_FLOOR := 245.0
const REDESIGNED_CUSTOMERS := ["mage", "elf", "rogue"]

var stock := 0
var brewing := true
var customer_phase := 0.0
var customer_interval := 3.2
var sale_flash := 0.0
var shop_open := true
var lettering: Font = preload("res://assets/fonts/pretendard/Pretendard-Regular.otf")
var room: Texture2D
var cauldron: Texture2D
var potion: Texture2D
var mana_potion: Texture2D
var special_potions := {}
var mana_stock := 0
var active_mana := false
var potion_kind: Variant = false # Last actual batch, supplied by the state projection.
var potion_color := Color("e24372")
var sold_mana: Variant = false
var sold_aged := false
var keeper_rest := "" # "asleep" / "fainted" while resting, supplied by the state projection.
var aging_open := false
var pending_sales: Array[Dictionary] = []
var sale_serial := 0
var active_sale_serial := 0
var keeper_frames: Array[AtlasTexture] = []
var motion := Motion.new()
var harvest_flash := 0.0
var harvested_herbs := 0
var garden_progress := 0.0
var herb_storage_full := false
var herb_frames: Array[AtlasTexture] = []
var sky: Control
var workshop_weather: Control
var bottles := PotionDisplay.new()
var sale_origin := Vector2.ZERO
var workshop := false:
	set(value):
		var changed := workshop != value
		workshop = value
		bottles.set_workshop_layout(value)
		motion.set_workshop_layout(value)
		# Each view has different shelf and hand anchors. Settle only this visual
		# transfer so a cached sale origin cannot fly through the new layout.
		if changed and motion.departing_elapsed >= 0 and motion.departing_elapsed < motion.handover_seconds:
			motion.departing_elapsed = motion.handover_seconds
var workshop_rug: Texture2D
var workshop_props := {}
var world: RefCounted
var object_light := Color.WHITE
var customer_sheets := {}
var current_customer := "traveler"
var departing_customer := "traveler"
var preferred_sale := false
var reward_icons := {}
var rare_flash := 0.0
var harvested_rare := 0
var expedition_notice := 0.0
var returned_trips := 0
var expedition_style: StyleBoxFlat

var pixel_light: ShaderMaterial
var pot_light: ShaderMaterial
var pot_layer: Control
var reward_layer: Control
var hearth: Texture2D
var glow_warm: TextureRect
var glow_pink: TextureRect
var lighting_values := {}


class PotLayer extends Control:
	var view: Control
	func _draw() -> void:
		for command in view.pot_commands(): view.draw_command(self, command)
		if view.brewing and not view.workshop:
			for index in 5:
				var phase := fmod(view.motion.elapsed * 0.4 + index * 0.2, 1.0)
				var px: float = view.pot_rect().position.x + 23 + index * 10 + roundi(sin(view.motion.elapsed + index) * 3) * 2
				var py: float = view.pot_rect().position.y + 18 - roundi(phase * 26) * 2
				var steam: Color = view.potion_color.lerp(Color.WHITE, 0.4)
				steam.a = (1.0 - phase) * 0.65
				draw_rect(Rect2(px, py, 4, 4), steam)


class RewardLayer extends Control:
	var view: Control
	func _draw() -> void:
		view._draw_rewards(self)


func pot_rect() -> Rect2:
	return Layout.rect("pot") if workshop else Rect2(22, 149, 96, 96)


func set_potion_kind(kind: Variant) -> void:
	var actual_kind: Variant = PotionVisual.bottle_kind(kind)
	if PotionVisual.potion_id(actual_kind) == PotionVisual.potion_id(potion_kind) and cauldron != null: return
	potion_kind = actual_kind
	potion_color = PotionVisual.liquid_color(actual_kind)
	cauldron = PotionVisual.cauldron_texture(actual_kind)
	if pot_layer != null: pot_layer.queue_redraw()


func hearth_rect() -> Rect2:
	return Layout.rect("hearth") if workshop else Rect2(pot_rect().position + Vector2(-4, 82), Vector2(104, 24))


func rug_rect() -> Rect2:
	return Layout.rect("rug") if workshop else Rect2(147, 198, 94, 26)


func _refresh_lighting() -> void:
	if pixel_light == null: return
	# The approved24-color art is shown without hue-changing shaders.
	material = null
	pot_layer.material = null
	pot_layer.visible = false
	glow_warm.visible = false
	glow_pink.visible = false
	if workshop:
		reward_layer.queue_redraw()
		return
	var daylight: float = world.daylight() if world != null else sky.daylight()
	var weather: float = float(world.weather()) / 2.0 if world != null else sky.weather_amount(1) * 0.5 + sky.weather_amount(2)
	var effects: float = world.effects if world != null else sky.effects
	var floor_value: float = world.brightness_floor if world != null else 0.6
	var clock: float = world.clock if world != null else sky.elapsed
	lighting_values = PixelLight.environment(daylight, weather, effects, floor_value, clock)
	var pot := pot_rect()
	var logical_pot := Rect2(pot.position / 2.0, pot.size / 2.0)
	PixelLight.apply(pixel_light, self, 2.0, logical_pot, lighting_values, false)
	PixelLight.apply(pot_light, self, 2.0, logical_pot, lighting_values)
	# Cached 128x64 halos are shifted/scaled with the actual pot in each mode.
	glow_warm.position = pot.position - Vector2(34, 22)
	glow_pink.position = glow_warm.position
	glow_warm.show_behind_parent = workshop
	glow_pink.show_behind_parent = workshop
	glow_warm.modulate.a = lighting_values.halo_gain * lighting_values.flicker
	glow_pink.modulate.a = lighting_values.halo_gain * 0.67
	pot_layer.queue_redraw()
	reward_layer.queue_redraw()


func _ready() -> void:
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bottles.pixel_room = true
	motion.pixel_room = true
	# A solid backing and window clip keep weather behind the room, including
	# the generated interior's very slightly translucent wall pixels.
	var backing := ColorRect.new()
	backing.color = Color("211b2d")
	backing.size = Vector2(408, 248)
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backing.show_behind_parent = true
	add_child(backing)
	var window := Control.new()
	window.name = "WindowOpening"
	window.position = Vector2(16, 36)
	window.size = Vector2(104, 80)
	window.clip_contents = true
	window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window.show_behind_parent = true
	add_child(window)
	sky = ShopSky.new()
	sky.name = "OutdoorLayer"
	sky.size = Vector2(408, 248)
	sky.position = -window.position
	window.add_child(sky)
	workshop_weather = ShopSky.new()
	workshop_weather.name = "WorkshopWeather"
	workshop_weather.transparent_scene = true
	workshop_weather.size = Vector2(Layout.SIZE.x, Layout.ART_HEIGHT)
	add_child(workshop_weather)
	for pose in ["idle", "brew_stir_left", "brew_stir_right", "handover_extend"]:
		keeper_frames.append(PixelCatalog.frame("keeper", pose, 0))
	herb_frames = _load_frames("res://assets/herb_growth.png", Vector2i(32, 40))
	room = load("res://assets/room_interior_204.png")
	set_potion_kind(potion_kind)
	potion = load("res://assets/potion_12x16.png")
	mana_potion = load("res://assets/mana_12x16.png")
	for kind in Content.RECIPES:
		special_potions[kind] = ItemArt.bottle(kind)
	workshop_rug = WorkshopAssets.rug()
	for kind in ["stand", "shelf", "poster", "counter"]:
		workshop_props[kind] = WorkshopAssets.wide_prop(kind)
	reward_icons = {"gold": WorkshopAssets.icon("gold-coin"), "herb": ItemArt.icon("herb"), "starleaf": ItemArt.icon("starleaf")}
	expedition_style = _expedition_style()
	for entry in Content.CUSTOMERS:
		if not entry.get("enabled", true): continue
		var id: String = entry["id"]
		customer_sheets[id] = []
		for pose in ["idle", "walk_contact_a", "walk_contact_b", "receive_hold"]:
			customer_sheets[id].append(PixelCatalog.frame(id, pose, 0))

	hearth = PixelLight.make_hearth()
	pixel_light = ShaderMaterial.new()
	pixel_light.shader = PixelLight.SHADER
	material = pixel_light
	pot_light = ShaderMaterial.new()
	pot_light.shader = PixelLight.SHADER
	pot_layer = PotLayer.new()
	pot_layer.view = self
	pot_layer.material = pot_light
	pot_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pot_layer)
	for warm in [true, false]:
		var glow := PixelLight.halo_texture(Vector2(41, 58) if warm else Vector2(41, 25), Vector2(29, 6) if warm else Vector2(23, 11), Color8(255, 169, 67) if warm else Color8(236, 101, 183))
		glow.scale = Vector2(2, 2)
		glow.show_behind_parent = workshop
		add_child(glow)
		if warm: glow_warm = glow
		else: glow_pink = glow
	# Halos sit above the indoor floor but below sprites in the transparent scene.
	move_child(glow_warm, 2)
	move_child(glow_pink, 3)
	reward_layer = RewardLayer.new()
	reward_layer.view = self
	reward_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(reward_layer)


func _load_frames(path: String, frame_size: Vector2i = Vector2i(48, 64)) -> Array[AtlasTexture]:
	var sheet: Texture2D = load(path)
	var frames: Array[AtlasTexture] = []
	for index in range(4):
		var frame := AtlasTexture.new()
		frame.atlas = sheet
		frame.region = Rect2(Vector2i(index % 2, index / 2) * frame_size, frame_size)
		frames.append(frame)
	return frames


func on_sale(gold: int, is_mana: Variant = false, index: int = 0, visitor: String = "", preference: Variant = null) -> void:
	var origin := bottles.take(index)
	sale_serial += 1
	pending_sales.append({"origin":origin,"gold":gold,"kind":is_mana,"customer":departing_customer if visitor.is_empty() else visitor,"preferred":preferred_sale if preference == null else preference,"serial":sale_serial})
	if motion.departing_elapsed < 0: _start_next_sale()


## Aged bottles are not on the retail shelf: the handover starts from the first
## shelf slot without removing a retail bottle and carries the aged seal.
func on_aged_sale(gold: int, kind: Variant, visitor: String, preference: bool) -> void:
	sale_serial += 1
	pending_sales.append({"origin": bottles.slot_center(0), "gold": gold, "kind": kind, "customer": visitor, "preferred": preference, "serial": sale_serial, "aged": true})
	if motion.departing_elapsed < 0: _start_next_sale()


func _start_next_sale() -> void:
	if pending_sales.is_empty(): return
	var sale: Dictionary = pending_sales.pop_front()
	sale_origin = sale.origin
	departing_customer = sale.customer
	preferred_sale = sale.preferred
	sold_mana = sale.kind
	sold_aged = sale.get("aged", false)
	active_sale_serial = sale.serial
	motion.sale(sale.gold)
	sale_flash = 1.0


func on_brew(is_mana: Variant = false) -> void:
	bottles.add(is_mana)


func apply_potion_events(events: Dictionary, final_stock: int, final_mana: int, order: Array = []) -> void:
	var changes: Array = events.get("potion_events", [])
	# A long suspended frame should show current inventory, not replay minutes
	# of overlapping transactions and departed customers.
	if changes.size() > 8:
		bottles.restore(final_stock, final_mana, order)
		motion.close_shop()
		pending_sales.clear()
		sale_flash = 0.0
	else:
		for change in changes:
			if change["kind"] == "brew":
				on_brew(change["mana"])
			elif change["kind"] == "aged_sale":
				on_aged_sale(change["gold"], change["mana"], Content.CUSTOMERS[change.get("customer", 0)]["id"], change.get("preferred", false))
			else:
				on_sale(change["gold"], change["mana"], change.get("index", 0), Content.CUSTOMERS[change.get("customer", 0)]["id"], change.get("preferred", false))
	stock = final_stock
	mana_stock = final_mana
	if order.size() == stock and bottles.inventory_order() != order:
		bottles.restore(stock, mana_stock, order)


func sync_inventory(count: int, mana: int, order: Array) -> void:
	stock = count
	mana_stock = mana
	if not bottles.matches(stock, mana_stock) or bottles.inventory_order() != order:
		bottles.restore(stock, mana_stock, order)


func on_harvest(amount: int) -> void:
	harvest_flash = 1.0
	harvested_herbs = amount


func on_shop_closed() -> void:
	motion.close_shop()
	pending_sales.clear()
	sale_flash = 0.0


func on_rare_harvest(amount: int) -> void:
	rare_flash = 1.4
	harvested_rare = amount


func on_expedition_return(trips: int) -> void:
	expedition_notice = 5.0
	returned_trips = trips


func _process(delta: float) -> void:
	window_visitor.tick(delta)
	if world != null:
		sky.set_process(false)
		sky.elapsed = world.clock
		sky.effects = world.effects
		sky.queue_redraw()
		current_customer = Content.CUSTOMERS[world.customer]["id"]
	workshop_weather.set_process(false)
	workshop_weather.elapsed = sky.elapsed
	workshop_weather.effects = sky.effects
	workshop_weather.preview_phase = sky.preview_phase
	workshop_weather.preview_weather = sky.preview_weather
	workshop_weather.queue_redraw()
	bottles.tick(delta)
	motion.tick(delta, shop_open, customer_phase, customer_interval)
	if not shop_open: pending_sales.clear()
	elif motion.departing_elapsed < 0: _start_next_sale()
	sale_flash = maxf(0.0, sale_flash - delta * 0.7)
	harvest_flash = maxf(0.0, harvest_flash - delta)
	rare_flash = maxf(0.0, rare_flash - delta)
	expedition_notice = maxf(0.0, expedition_notice - delta)
	queue_redraw()


func _character(texture: Texture2D, feet: Vector2, flip: bool = false) -> void:
	draw_command(self, _character_command("character", texture, feet, flip))


func _flying_potion(start: Vector2, finish: Vector2, progress: float, is_mana: Variant = false) -> void:
	_draw_bottle(_handover_position(start, finish, progress), is_mana)


func _handover_position(start: Vector2, finish: Vector2, progress: float) -> Vector2:
	if workshop or bottles.pixel_room:
		return PotionDisplay.handover_position(start, finish, progress, PixelCatalog.bottle_size(sold_mana)*3, Vector2(351,192) if workshop else Vector2(228,197))
	var point := start.lerp(finish, progress)
	point.y -= sin(progress * PI) * 24.0
	return point.round()


func _draw() -> void:
	if room == null:
		return
	get_child(0).visible = not workshop
	get_node("WindowOpening").visible = false
	workshop_weather.visible = false
	_refresh_lighting()
	object_light = Color.WHITE
	if not bottles.matches(stock, mana_stock):
		bottles.restore(stock, mana_stock)
	for command in render_commands(): draw_command(self, command)


func _texture_command(role: String, texture: Texture2D, rect: Rect2, flip_h: bool = false) -> Dictionary:
	return {"role": role, "texture": texture, "rect": rect, "flip_h": flip_h, "color": Color.WHITE}


func _character_command(role: String, texture: Texture2D, feet: Vector2, flip_h: bool = false) -> Dictionary:
	return _texture_command(role, texture, Rect2(feet - Vector2(CHARACTER_SIZE.x / 2, CHARACTER_SIZE.y), CHARACTER_SIZE), flip_h)


func _bottle_command(role: String, center: Vector2, kind: Variant) -> Dictionary:
	var texture := PixelCatalog.bottle(kind)
	var bottle_size := texture.get_size() * 3
	var command := _texture_command(role, texture, Rect2((center-bottle_size/2).round(), bottle_size))
	command["potion_id"] = PotionVisual.potion_id(kind)
	return command


func render_commands() -> Array[Dictionary]:
	if room == null: return []
	return PixelScene.workshop_commands(self) if workshop else PixelScene.room_commands(self)


func pot_commands() -> Array[Dictionary]:
	if cauldron == null or workshop: return []
	cauldron = PotionVisual.cauldron_texture(potion_kind, motion.elapsed)
	var command := _texture_command("cauldron", cauldron, pot_rect())
	command["potion_id"] = PotionVisual.potion_id(potion_kind)
	return [command]


func draw_command(ink: Control, command: Dictionary) -> void:
	var rect: Rect2 = command["rect"]
	if command["texture"] == null:
		ink.draw_rect(rect, command["color"])
	elif command["flip_h"]:
		ink.draw_set_transform(rect.position + Vector2(rect.size.x, 0), 0, Vector2(-1, 1))
		ink.draw_texture_rect(command["texture"], Rect2(Vector2.ZERO, rect.size), false, command["color"])
		ink.draw_set_transform(Vector2.ZERO)
	else:
		ink.draw_texture_rect(command["texture"], rect, false, command["color"])


func _snapshot_command(command: Dictionary) -> Dictionary:
	var result := command.duplicate()
	var texture: Texture2D = result["texture"]
	result.erase("texture")
	result["source"] = (texture.atlas.resource_path if texture is AtlasTexture else texture.resource_path) if texture != null else ""
	result["source_rect"] = (texture.region if texture is AtlasTexture else Rect2(Vector2.ZERO, texture.get_size())) if texture != null else Rect2()
	return result


func render_snapshot() -> Dictionary:
	var commands: Array[Dictionary] = []
	for command in render_commands(): commands.append(_snapshot_command(command))
	var pot: Array[Dictionary] = []
	for command in pot_commands(): pot.append(_snapshot_command(command))
	var uniforms := {}
	if pixel_light != null:
		for key in ["scene_origin", "scene_scale", "pot_rect", "preserve_emissive", "ambient", "local_gain", "flicker"]:
			uniforms[key] = pixel_light.get_shader_parameter(key)
	return {"size": size, "workshop": workshop, "commands": commands, "pot": pot,
		"potion_id": PotionVisual.potion_id(potion_kind), "liquid_color": potion_color,
		"shader": PixelLight.SHADER.resource_path, "shader_uniforms": uniforms,
		"sky": workshop_weather.render_snapshot() if workshop and workshop_weather != null else {}}


func _draw_rewards(ink: Control) -> void:
	if sale_flash > 0.0 and not workshop:
		var sale_text := ("+%d · 선호" if preferred_sale else "+%d") % motion.earned_gold
		var sale_x: float = Layout.rect("counter").position.x if workshop else (264 if preferred_sale else 306)
		_draw_reward(ink, "gold", sale_text, Vector2(sale_x, 178 - (1.0 - sale_flash) * 16 if workshop else 145 - (1.0 - sale_flash) * 16), Color(0.98, 0.84, 0.55, sale_flash))
	if harvest_flash > 0.0:
		_draw_reward(ink, "herb", "+%d" % harvested_herbs, Vector2(52 if workshop else 76, (132 if workshop else 38) - (1.0 - harvest_flash) * 14), Color(0.75, 0.91, 0.56, harvest_flash))
	if rare_flash > 0.0:
		_draw_reward(ink, "starleaf", "+%d" % harvested_rare, Vector2(52 if workshop else 76, (157 if workshop else 63) - (1.4 - rare_flash) * 10), Color(0.85, 0.78, 1.0, minf(1.0, rare_flash)))
	_draw_expedition()


func _draw_reward(ink: Control, kind: String, text: String, baseline: Vector2, color: Color) -> void:
	ink.draw_texture_rect(reward_icons[kind], Rect2(baseline - Vector2(0, 17), Vector2(20, 20)), false, Color(1, 1, 1, color.a))
	ink.draw_string_outline(lettering, baseline + Vector2(24, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 3, Color(0.10, 0.07, 0.15, color.a))
	ink.draw_string(lettering, baseline + Vector2(24, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)


func _draw_expedition() -> void:
	pass # Independent journeys are available from the poster details and management.


func _expedition_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("211b2df2")
	style.border_color = Color("796449")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	return style


func _draw_bottle(center: Vector2, is_mana: Variant) -> void:
	draw_command(self, _bottle_command("bottle", center, is_mana))
