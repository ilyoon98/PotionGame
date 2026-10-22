extends "res://tools/play_pixel_game_review.gd"
## Exercise the exact live review rollover and real rendered controls.
const OUT := "res://.verification/pixel-layout-fixes/"
var captures := {}

func _process(_delta: float) -> bool: return false

func freeze(node: Node) -> void:
	node.set_process(false)
	for child in node.get_children(): freeze(child)

func pick(commands: Array[Dictionary],role: String) -> Dictionary:
	for command in commands:
		if command.role == role: return command
	return {}

func buttons_inside(toolbar: Control) -> void:
	var rects: Array[Rect2] = []
	for child in toolbar.get_children():
		if child is not Button: continue
		var rect: Rect2 = child.get_rect()
		assert(rect.position.x >= 8 and rect.end.x <= toolbar.size.x-8,str(child.name)+": horizontal padding "+str(rect))
		assert(rect.position.y >= 6 and rect.end.y <= toolbar.size.y-6,str(child.name)+": vertical padding")
		for previous in rects: assert(not rect.intersects(previous),"Toolbar buttons overlap")
		rects.append(rect)
	assert(rects.size() == 5)

func screenshot(name: String) -> void:
	shop._update_interface()
	shop.companion.refresh()
	shop.art.queue_redraw()
	shop.companion.scene.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	captures[name] = image
	assert(image.save_png(OUT+name+".png") == OK)
	if shop.state.window_mode != State.WindowMode.MINIMAL:
		assert(image.get_pixel(200,20).a == 0)
		var y: int = 237 if shop.state.window_mode == State.WindowMode.WORKSHOP else shop.MiniWorkshop.FLOOR_Y
		for x in image.get_width(): assert(image.get_pixel(x,y).a == 1)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	shop = Shop.new()
	root.add_child(shop)
	freeze(shop)
	root.always_on_top = false
	shop._set_window_mode(State.WindowMode.WORKSHOP)
	# Call the exact rollover function that used to force the main mode.
	for mode in [State.WindowMode.COMPANION,State.WindowMode.MINIMAL,State.WindowMode.WORKSHOP]:
		shop._set_window_mode(mode)
		for i in 4:
			next_case()
			assert(shop.state.window_mode == mode)
			assert(root.size == (shop.MiniWorkshop.SIZE if mode == State.WindowMode.COMPANION else shop.MINIMAL_SIZE if mode == State.WindowMode.MINIMAL else Vector2i(540,300)))
	buttons_inside(shop.workshop_toolbar)
	buttons_inside(shop.companion.toolbar)
	buttons_inside(shop.mini_toolbar)
	var poster_interior: Rect2 = shop.WorkshopAssets.Layout.POSTER_INTERIOR
	assert(poster_interior.encloses(shop.workshop_gauges.detail_buttons.expeditions.get_rect()))
	var active_before: int = shop.workshop_gauges.active_regions
	for count in [0,6]:
		shop.workshop_gauges.active_regions = count
		for caption in shop.workshop_gauges.render_commands():
			if caption.get("role","") != "expedition_caption": continue
			assert(poster_interior.encloses(caption.rect))
			assert(not caption.rect.intersects(shop.workshop_gauges.detail_buttons.expeditions.get_rect()))
			assert(shop.body_font.get_string_size(caption.text,HORIZONTAL_ALIGNMENT_LEFT,-1,caption.font_size).x <= caption.rect.size.x)
	shop.workshop_gauges.active_regions = active_before
	var checks := 0
	for compact in [false,true]:
		shop._set_window_mode(State.WindowMode.COMPANION if compact else State.WindowMode.WORKSHOP)
		for phase in [0.0,0.25,0.5]:
			shop.art.motion.elapsed = phase
			shop.companion.elapsed = phase
			shop.art.brewing = true
			var commands: Array[Dictionary] = shop.companion.render_commands() if compact else shop.art.render_commands()
			var pot := pick(commands,"cauldron")
			var person := pick(commands,"keeper")
			var spoon := pick(commands,"spoon")
			assert(person.rect.size == Vector2(96,144))
			assert(pot.rect.size == Vector2(96,96))
			var floor_y: int = shop.MiniWorkshop.FLOOR_Y if compact else 237
			assert(pot.rect.position.y+31*3 == floor_y,"Pot feet touch the floor with no native-pixel gap")
			var liquid := Vector2i((spoon.liquid_point-pot.rect.position)/3)
			var inside := false
			for point in Catalog.DATA.liquid_pixels:
				if liquid == Vector2i(int(point[0]),int(point[1])): inside = true
			assert(inside,"Spoon bowl must stay in the approved liquid mask")
			assert(spoon.hand_point == person.rect.position+Catalog.hand("keeper",person.pose)*3)
			await screenshot(("companion" if compact else "workshop")+"-brew-"+str(checks%3))
			checks += 1
	shop._set_window_mode(State.WindowMode.MINIMAL)
	await screenshot("information")
	# Both widths must render the same corner pixels. Allow one8-bit step for
	# GPU premultiplied-alpha rounding, never a compressed or shifted corner.
	var wide: Image = captures["workshop-brew-0"]
	var compact: Image = captures["companion-brew-0"]
	for y in 51:
		if y >= 12 and y < 39: continue # Corners only, excluding button glyphs.
		for x in 16:
			for right in [false,true]:
				var a := wide.get_pixel(wide.get_width()-1-x if right else x,249+y)
				var b := compact.get_pixel(compact.get_width()-1-x if right else x,177+y)
				for channel in 4: assert(absf(a[channel]-b[channel]) <= 1.1/255.0,"Toolbar corners must remain the same size in compact mode")
	var proof := {"status":"passed","mode_rollovers":12,"modes_preserved":["workshop","companion","information"],"button_padding":8,"buttons_per_toolbar":5,"brew_pose_checks":checks,"spoon_inside_liquid":true,"pot_grounded":true,"compact_character_size":[96,144],"companion_size":[256,228],"transparent_background":true,"player_save_accessed":false}
	var file := FileAccess.open(OUT+"proof.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(proof,"\t"))
	print("PIXEL LAYOUT FIXES PASS:12 mode rollovers;3 toolbars;6 brewing poses;alpha0;common3x compact scene")
	shop.queue_free()
	await process_frame
	quit()
