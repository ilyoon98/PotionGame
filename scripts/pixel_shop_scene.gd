extends RefCounted
## Same published character poses as the approved full-scene preview.
const Catalog = preload("res://scripts/pixel_art_catalog.gd")
const Layout = preload("res://scripts/workshop_layout.gd")

static func command(role: String, tex: Texture2D, point: Vector2, scale_factor: int = 3, flip: bool = false) -> Dictionary:
	return {"role": role, "texture": tex, "rect": Rect2(point.round(), tex.get_size() * scale_factor), "flip_h": flip, "color": Color.WHITE}

static func keeper_pose(view: Control) -> String:
	# A resting keeper neither brews nor gestures; the sale bottle still flies.
	if view.keeper_rest == "asleep": return "sleep"
	if view.keeper_rest == "fainted": return "faint"
	var m = view.motion
	if m.departing_elapsed >= 0 and m.departing_elapsed < m.handover_seconds:
		return "handover_extend"
	if m.departing_elapsed >= 0 and m.departing_elapsed < m.handover_seconds + m.hold_seconds * 0.5:
		return "handover_return"
	if view.brewing:
		return ["brew_reach", "brew_stir_left", "brew_stir_right", "brew_stir_left"][int(m.elapsed * 4.0) % 4]
	return "idle"

static func actor(role: String, cid: String, pose: String, elapsed: float, origin: Vector2, flip: bool = false) -> Dictionary:
	# Fine atlases already contain an exact3x frame, including1display-pixel details.
	var result := command(role, Catalog.frame(cid, pose, Catalog.motion_index(elapsed, pose)), origin, 1, flip)
	result.merge({"character_id": cid, "pose": pose, "native_size": Vector2(32,48), "scale": 3})
	return result

## Approved F21 effects in an 8-step, 3 s loop: two rising Zs while asleep,
## two stars orbiting the hat while fainted (the back half passes behind him).
static func rest_effects(pose: String, elapsed: float, origin: Vector2) -> Dictionary:
	var result := {"back": [], "front": []}
	var step := int(elapsed / 0.375) % 8
	if pose == "sleep":
		for lead: int in [0, 4]:
			var s: int = (step + lead) % 8
			var point := Vector2(22 + lead + floori(s / 2.0), 16 - s)
			result.front.append(command("sleep_z", Catalog.texture(Catalog.DATA.effects.sleep_z), origin + point * 3))
	elif pose == "faint":
		for phase: float in [0.0, PI]:
			var angle: float = step / 8.0 * TAU + phase
			var point := Vector2(11 + roundf(10 * cos(angle)), 13 + roundf(2 * sin(angle)))
			result["front" if sin(angle) >= 0 else "back"].append(command("dizzy_star", Catalog.texture(Catalog.DATA.effects.dizzy_star), origin + point * 3))
	return result

static func keeper_commands(pose: String, elapsed: float, origin: Vector2) -> Array[Dictionary]:
	var effects := rest_effects(pose, elapsed, origin)
	var out: Array[Dictionary] = []
	out.append_array(effects.back)
	out.append(actor("keeper", "keeper", pose, elapsed, origin))
	out.append_array(effects.front)
	return out

## The 5x5 aged seal sits on the bottle's lower-right shoulder, 2 px past its edge.
static func aged_seal_command(role: String, bottle: Dictionary) -> Dictionary:
	var native: Vector2 = bottle.rect.size / 3.0
	return command(role, Catalog.texture(Catalog.DATA.props.aged_seal), bottle.rect.position + (native - Vector2(3, 6)) * 3)

static func departing_pose(view: Control) -> String:
	var m = view.motion
	if m.departing_elapsed < m.handover_seconds + m.hold_seconds * 0.35: return "receive_extend"
	if m.departing_elapsed < m.walk_start(): return "receive_hold"
	return ["carry_contact_a", "carry_pass_a", "carry_contact_b", "carry_pass_b"][int(m.elapsed * 6.0) % 4]

static func customer_origin(view: Control, departing: bool = false) -> Vector2:
	var x: float = view.motion.departure_x() if departing else view.motion.customer_x
	return Vector2(x - 48, 96 if view.workshop else 101)

static func keeper_origin(view: Control) -> Vector2:
	return Vector2(216,96) if view.workshop else Vector2(100,101)

static func spoon_commands(view: Control, pot_origin: Vector2, person_origin: Vector2, pose: String) -> Array[Dictionary]:
	# Reuse the approved bowl pixels; put its end in the liquid and connect the
	# actual palm with a shaft drawn on the same native pixel grid.
	var out: Array[Dictionary] = []
	var bowl_point: Vector2 = {"brew_reach":Vector2(20,8),"brew_stir_left":Vector2(18,9),"brew_stir_right":Vector2(21,10)}[pose]
	var grip := ((person_origin-pot_origin)/3.0+Catalog.hand("keeper",pose)).round()
	var count := int(maxf(absf(grip.x-bowl_point.x),absf(grip.y-bowl_point.y)))
	for i in count+1:
		var point := bowl_point.lerp(grip,float(i)/maxi(count,1)).round()
		out.append({"role":"spoon_shaft","texture":null,"rect":Rect2(pot_origin+point*3,Vector2(3,3)),"flip_h":false,"color":Color("241c32")})
	var bowl := AtlasTexture.new()
	bowl.atlas = Catalog.texture(Catalog.DATA.spoon)
	bowl.region = Rect2(0,9,4,3)
	var result := command("spoon",bowl,pot_origin+(bowl_point-Vector2(1,1))*3)
	result["liquid_point"] = pot_origin+bowl_point*3
	result["hand_point"] = person_origin+Catalog.hand("keeper",pose)*3
	out.append(result)
	return out

static func bottle_center(view: Control, pose: String, origin: Vector2, flip: bool) -> Vector2:
	var g := Catalog.hand(view.departing_customer, pose)
	if flip: g.x = 31 - g.x
	return origin + (g - Catalog.local_grip(view.departing_customer, view.sold_mana) + Catalog.bottle_size(view.sold_mana) / 2.0) * 3.0

static func character_commands(view: Control) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var m = view.motion
	var kp := keeper_pose(view)
	var ko := keeper_origin(view)
	out.append_array(keeper_commands(kp, m.elapsed, ko))
	if not view.shop_open: return out
	if m.visit != m.Visit.ABSENT:
		var pose: String = ["walk_contact_a", "walk_pass_a", "walk_contact_b", "walk_pass_b"][int(m.elapsed * 6.0) % 4] if m.visit == m.Visit.ARRIVING else "idle"
		out.append(actor("arriving_customer", view.current_customer, pose, m.elapsed, customer_origin(view)))
	if m.departing_elapsed >= 0:
		var pose := departing_pose(view)
		var origin := customer_origin(view, true)
		var flip: bool = m.departing_elapsed >= m.walk_start()
		out.append(actor("departing_customer", view.departing_customer, pose, m.elapsed, origin, flip))
		var center := bottle_center(view, pose, origin, flip)
		var caught: bool = m.departing_elapsed >= m.handover_seconds
		if not caught:
			var target := bottle_center(view, "receive_extend", Vector2(m.counter_x()-48, origin.y), false)
			center = view._handover_position(view.sale_origin, target, m.departing_elapsed / m.handover_seconds)
		var bottle: Dictionary = view._bottle_command("held_bottle" if caught else "handover_bottle", center, view.sold_mana)
		bottle["transaction_id"] = view.active_sale_serial
		out.append(bottle)
		if view.sold_aged: out.append(aged_seal_command("held_seal" if caught else "handover_seal", bottle))
		if caught:
			var palm_path: String = Catalog.DATA.characters[view.departing_customer].palms[pose]
			out.append(command("customer_palm", Catalog.texture(palm_path), origin, 3, flip))
	return out

static func workshop_commands(view: Control) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var elapsed: float = view.motion.elapsed
	var night: bool = view.world.is_night() if view.world != null else view.sky.daylight() < 0.5
	var rain: bool = view.world.weather() == 2 if view.world != null else view.sky.weather_amount(2) > 0.5
	var weather := ("night" if night else "day") + ("_rain" if rain else "_clear")
	out.append(command("weather", Catalog.texture(Catalog.DATA.weather[weather][int(elapsed*8) % 12]), Vector2(12,15)))
	out.append_array(view.window_visitor.commands(Vector2(12,15)))
	for key in ["floor", "window", "herb", "poster", "counter"]:
		var origin: Vector2 = {"floor":Vector2.ZERO,"window":Vector2(12,15),"herb":Vector2(12,144),"poster":Vector2(459,3),"counter":Vector2(315,192)}[key]
		out.append(command(key, Catalog.texture(Catalog.DATA.props[key]), origin))
	# Wall aging cask between the cauldron panel and the shelf, above the keeper's hat.
	if view.aging_open: out.append(command("aging_cask", Catalog.texture(Catalog.DATA.props.aging_cask), Vector2(219,0)))
	# F23 approved layout A: counter-top prop at the keeper end, behind bottles and people.
	if not view.counter_prop.is_empty(): out.append(command("counter_prop", Catalog.texture(Catalog.DATA.decor[view.counter_prop]), Vector2(288,120)))
	# F23 approved spot A (2026-11-05): the small souvenir stands on the window frame.
	if not view.souvenir.is_empty(): out.append(command("souvenir", Catalog.texture(Catalog.DATA.souvenirs_mini[view.souvenir + "_mini"]), Vector2(42,0)))
	var stock_start := out.size()
	for i in view.bottles.visible_capacity():
		if not view.bottles.slots[i].is_empty():
			out.append(view._bottle_command(("moving_stock_" if view.bottles.is_moving(i) else "stock_")+str(i), view.bottles.position(i), view.bottles.slots[i].mana))
	# Shelf boards and people mask incoming stock; extracted bottles aren't baked in.
	out.append(command("shelf", Catalog.texture(Catalog.DATA.props.shelf), Vector2(315,3)))
	out.append(command("fire", Catalog.texture(Catalog.DATA.fire[int(elapsed*8) % 4]), Layout.rect("hearth").position))
	var pot := Catalog.pot(view.potion_kind, elapsed)
	var pot_origin := Layout.rect("pot").position
	var pc := command("cauldron", pot, pot_origin)
	pc["potion_id"] = Catalog.id(view.potion_kind)
	out.append(pc)
	var kp := keeper_pose(view)
	if kp.begins_with("brew"):
		out.append_array(spoon_commands(view,pot_origin,keeper_origin(view),kp))
		var foreground := AtlasTexture.new()
		foreground.atlas = pot
		foreground.region = Rect2(0,11,32,21)
		out.append(command("cauldron_foreground", foreground, pot_origin+Vector2(0,33)))
	var actors := character_commands(view)
	if view.motion.departing_elapsed >= 0 and view.motion.departing_elapsed < view.motion.handover_seconds * 0.27:
		for i in range(actors.size()-1,-1,-1):
			if actors[i].role in ["handover_bottle", "handover_seal"]:
				# Shelf extraction goes behind stocked bottles, boards and people.
				out.insert(stock_start, actors[i])
				actors.remove_at(i)
	out.append_array(actors)
	return out


static func room_commands(view: Control) -> Array[Dictionary]:
	var out: Array[Dictionary] = [{"role":"room","texture":null,"rect":Rect2(0,0,408,248),"flip_h":false,"color":Color("4a3c52")}]
	# The narrower main view uses the same approved props, not the retired
	# room's baked-in bottles. The planter sits on a wall ledge above the keeper.
	var night: bool = view.world.is_night() if view.world != null else view.sky.daylight() < 0.5
	var rain: bool = view.world.weather() == 2 if view.world != null else view.sky.weather_amount(2) > 0.5
	var weather := ("night" if night else "day") + ("_rain" if rain else "_clear")
	out.append(command("weather",Catalog.texture(Catalog.DATA.weather[weather][int(view.motion.elapsed*8)%12]),Vector2(12,15)))
	out.append_array(view.window_visitor.commands(Vector2(12,15)))
	out.append(command("window",Catalog.texture(Catalog.DATA.props.window),Vector2(12,15)))
	out.append(command("herb",Catalog.texture(Catalog.DATA.props.herb),Vector2(132,12)))
	out.append({"role":"planter_ledge","texture":null,"rect":Rect2(129,108,102,3),"flip_h":false,"color":Color("916047")})
	out.append(command("counter",Catalog.texture(Catalog.DATA.props.counter),Vector2(192,197)))
	for i in view.bottles.visible_capacity():
		if not view.bottles.slots[i].is_empty():
			out.append(view._bottle_command(("moving_stock_" if view.bottles.is_moving(i) else "stock_")+str(i),view.bottles.position(i),view.bottles.slots[i].mana))
	out.append(command("shelf",Catalog.texture(Catalog.DATA.props.shelf),Vector2(258,8)))
	var elapsed: float = view.motion.elapsed
	out.append(command("fire",Catalog.texture(Catalog.DATA.fire[int(elapsed*8)%4]),Vector2(52,218)))
	var pot := Catalog.pot(view.potion_kind,elapsed)
	var pc := command("cauldron",pot,view.pot_rect().position)
	pc["potion_id"] = Catalog.id(view.potion_kind)
	out.append(pc)
	var kp := keeper_pose(view)
	if kp.begins_with("brew"):
		out.append_array(spoon_commands(view,view.pot_rect().position,keeper_origin(view),kp))
		var foreground := AtlasTexture.new()
		foreground.atlas = pot
		foreground.region = Rect2(0,11,32,21)
		out.append(command("cauldron_foreground",foreground,view.pot_rect().position+Vector2(0,33)))
	var actors := character_commands(view)
	if view.motion.departing_elapsed >= 0 and view.motion.departing_elapsed < view.motion.handover_seconds*0.27:
		for i in range(actors.size()-1,-1,-1):
			if actors[i].role in ["handover_bottle", "handover_seal"]:
				out.insert(6,actors[i])
				actors.remove_at(i)
	out.append_array(actors)
	for row in 4:
		out.append({"role":"floor","texture":null,"rect":Rect2(0,242+row*3,408,3),"flip_h":false,"color":[Color("e9b95f"),Color("916047"),Color("50333b"),Color("241c32")][row]})
	return out
