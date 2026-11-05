extends SceneTree
## Real renderer and event projection; isolated from the player's progress.
const Art = preload("res://scripts/shop_art.gd")
const Catalog = preload("res://scripts/pixel_art_catalog.gd")
const Scene = preload("res://scripts/pixel_shop_scene.gd")
const State = preload("res://scripts/shop_state.gd")
var art: Control
var cases := 0
var states := 0

func _initialize() -> void: call_deferred("run")

func selected(commands: Array[Dictionary], role: String) -> Dictionary:
	for c in commands:
		if c.role == role: return c
	return {}

func run() -> void:
	set_meta("isolated_preview", true)
	art = Art.new()
	art.workshop = true
	art.size = Vector2(540,249)
	root.add_child(art)
	art.set_process(false)
	assert(Catalog.DATA.potions.size() == State.Content.RECIPES.size() + 2) # 36 + 4 F26 + 4 F27 rows
	assert(art.customer_sheets.size() == 4 and not art.customer_sheets.has("knight"))
	var original := State.new()
	var before := JSON.stringify(original.to_data())
	art.world = original.progression
	for cid in ["traveler","mage","elf","rogue"]:
		for kind in Catalog.DATA.potions:
			art.motion.close_shop()
			art.pending_sales.clear()
			art.motion.trade_interval = 3.2
			var order: Array = [false,true,"moon","purify","agility","vigor","nightwalk",kind]
			art.sync_inventory(8,1,order)
			art.set_potion_kind(kind)
			var board_y := 132.0
			assert(is_equal_approx(art.bottles.position(7).y+Catalog.bottle_size(kind).y*1.5,board_y),"Every bottle rests on the lower board")
			art.on_sale(24,kind,7,cid,true)
			art.stock = 7
			assert(art.bottles.inventory_order() == order.slice(0,7))
			assert(art.sold_mana == kind and art.departing_customer == cid)
			var catch_time: float = art.motion.handover_seconds
			art.motion.departing_elapsed = catch_time * 0.4
			var counter := selected(art.render_commands(),"handover_bottle")
			assert(counter.rect.end.y == 192,"The sale bottle rests exactly on the counter")
			art.motion.departing_elapsed = catch_time-0.000001
			var incoming := selected(art.render_commands(),"handover_bottle")
			art.motion.departing_elapsed = catch_time
			var caught := selected(art.render_commands(),"held_bottle")
			assert(incoming.rect == caught.rect,"No jump at catch")
			for factor in [0.0,0.2,0.4,0.7,1.0,1.08,1.3,1.6,2.0,2.29]:
				art.motion.elapsed = factor+3.6
				art.motion.departing_elapsed = factor
				var commands: Array[Dictionary] = art.render_commands()
				var person := selected(commands,"departing_customer")
				assert(person.character_id == cid and person.rect.size == Vector2(96,144))
				assert(person.native_size == Vector2(32,48) and person.scale == 3)
				assert(selected(commands,"keeper").character_id == "keeper")
				var trace_count := 0
				var stock_count := 0
				for cmd in commands:
					if cmd.role in ["handover_bottle","held_bottle"]:
						trace_count += 1
						assert(cmd.potion_id == kind and cmd.rect.size == Catalog.bottle_size(kind)*3)
					if cmd.role.begins_with("stock_") or cmd.role.begins_with("moving_stock_"): stock_count += 1
				assert(trace_count == 1 and stock_count == 7)
				assert(selected(commands,"cauldron").potion_id == kind and art.potion_color == Catalog.liquid(kind))
				if factor >= catch_time:
					var pose: String = person.pose
					var expected := Scene.bottle_center(art,pose,person.rect.position,person.flip_h)-Catalog.bottle_size(kind)*1.5
					assert(selected(commands,"held_bottle").rect.position == expected.round())
					assert(not selected(commands,"customer_palm").is_empty())
				states += 1
			cases += 1
	assert(JSON.stringify(original.to_data()) == before,"Rendering never consumes materials or changes saves/economy")
	# Multiple events in one update preserve the active person/kind and queue the next.
	art.motion.close_shop()
	art.pending_sales.clear()
	art.sync_inventory(3,1,[false,true,"moon"])
	art.apply_potion_events({"potion_events":[{"kind":"sale","gold":6,"mana":false,"index":0,"customer":0},{"kind":"sale","gold":18,"mana":true,"index":0,"customer":2}]},1,0,["moon"])
	assert(art.departing_customer == "traveler" and art.sold_mana == false and art.pending_sales.size() == 1)
	art.motion.departing_elapsed = art.motion.departure_seconds-0.01
	art._process(0.02)
	assert(art.departing_customer == "mage" and art.sold_mana == true and art.pending_sales.is_empty())
	# Max trading speed still leaves room for catch, hold, exit and the next arrival.
	art.motion.trade_interval = 1.5
	art.motion.sale(6)
	assert(art.motion.walk_start() < art.motion.departure_seconds and art.motion.departure_seconds < 1.5)
	# A sale while the selected stock is still arriving starts at its actual position.
	art.motion.close_shop()
	art.sync_inventory(0,0,[])
	art.on_brew("agility")
	art.bottles.tick(0.17)
	var moving: Vector2 = art.bottles.position(0)
	art.on_sale(6,"agility",0,"elf")
	assert(art.sale_origin == moving and art.bottles.inventory_order().is_empty())
	art.on_shop_closed()
	assert(art.pending_sales.is_empty() and art.motion.departing_elapsed < 0)
	# Mode switches keep transactions and stock, settling only the old coordinate leg.
	art.workshop = false
	art.stock = 1
	art.mana_stock = 0
	art.bottles.restore(1,0,["moon"])
	art.current_customer = "rogue"
	art.motion.visit = art.Motion.Visit.WAITING
	art.motion.customer_x = art.motion.counter_x()
	assert(selected(art.render_commands(),"arriving_customer").rect.size == Vector2(96,144))
	assert(art.bottles.visible_capacity() == 8)
	for kind in Catalog.DATA.potions:
		var order: Array = [kind,kind,kind,kind,kind,kind,kind,kind]
		art.sync_inventory(8,0,order)
		var last: Rect2 = Rect2()
		for i in 8:
			var bottle: Dictionary = art._bottle_command("test",art.bottles.position(i),kind)
			assert(bottle.rect.end.y == (74 if i<4 else 137))
			if i%4 > 0: assert(not last.intersects(bottle.rect),"Native3x bottles fit the normal-room shelf")
			last = bottle.rect
	art.sync_inventory(1,0,["moon"])
	art.workshop = true
	assert(art.bottles.inventory_order() == ["moon"])
	var floor: Image = Catalog.texture(Catalog.DATA.props.floor).get_image()
	for x in 180:
		assert(floor.get_pixel(x,79).a == 1 and floor.get_pixel(x,82).a == 1,"Continuous floor at both map edges")
	var report := {"status":"passed","customer_recipe_cases":cases,"rendered_state_cases":states,"characters":5,"recipes":36,"native_character":[32,48],"common_scale":3,"counter_catch_continuity":true,"queued_sales_preserved":true,"full_width_floor":true,"inventory_order_preserved":true,"economy_unchanged_by_rendering":true}
	var file := FileAccess.open("res://.verification/pixel-runtime-v1/runtime-tests.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("PIXEL RUNTIME PASS: ",cases," customer/recipe pairs; ",states," actual render states; FIFO/queue/catch/exit/floor")
	art.queue_free()
	quit()

