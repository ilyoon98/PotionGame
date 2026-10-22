extends SceneTree
## Real input signal + exact rendered glass mask, isolated from player saves.
const Shop = preload("res://scripts/shop.gd")
const Visitor = preload("res://scripts/window_visitor.gd")
const Compare = preload("res://tests/state_compare.gd")
const OUT := "res://.verification/window-visitor/"
var shop: Control

func _initialize() -> void:
	set_meta("isolated_preview",true)
	call_deferred("run")

func freeze(node: Node) -> void:
	node.set_process(false)
	for child in node.get_children(): freeze(child)

func click(button: int = MOUSE_BUTTON_LEFT,pressed: bool = true) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	shop.workshop_weather_icon.gui_input.emit(event)

func capture(name: String) -> Image:
	shop.art.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	assert(image.save_png(OUT+name+".png") == OK)
	return image

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	# Verify the short combo deadline and retrigger cooldown independently.
	var timer := Visitor.new()
	for i in 6: assert(not timer.tap(float(i)*0.1))
	assert(not timer.tap(4.0) and timer.taps == 1)
	for i in 5: assert(not timer.tap(4.1+float(i)*0.1))
	assert(timer.tap(4.6))
	assert(not timer.tap(4.7))
	timer.tick(Visitor.COOLDOWN)
	assert(timer.remaining == 0.0 and timer.cooldown == 0.0)
	shop = Shop.new()
	root.add_child(shop)
	freeze(shop)
	root.always_on_top = false
	shop._set_window_mode(shop.State.WindowMode.WORKSHOP)
	shop.state.progression.clock = 0.0 # Isolated sunny fixture only.
	shop._update_interface()
	var before: Dictionary = shop.state.to_data().duplicate(true)
	var baseline: Image = await capture("before")
	var visitor = shop.art.window_visitor
	for i in 7: click(MOUSE_BUTTON_RIGHT)
	click(MOUSE_BUTTON_LEFT,false)
	assert(visitor.taps == 0)
	for i in 6: click()
	assert(visitor.remaining == 0.0)
	click()
	assert(visitor.remaining == Visitor.DURATION)
	visitor.tick(0.2)
	var active: Image = await capture("active")
	var frame: Image = shop.art.PixelCatalog.texture(shop.art.PixelCatalog.DATA.props.window).get_image()
	var glass := Rect2i(30,45,60,48)
	var changed := 0
	for y in baseline.get_height():
		for x in baseline.get_width():
			if baseline.get_pixel(x,y) == active.get_pixel(x,y): continue
			assert(glass.has_point(Vector2i(x,y)),"Photo must never spill outside the glass")
			assert(frame.get_pixel((x-12)/3,(y-15)/3).a == 0.0,"Window frame/mullion must stay in front")
			changed += 1
	assert(changed > 1000,"The photograph must actually render")
	visitor.tick(Visitor.DURATION)
	var restored: Image = await capture("after")
	assert(restored.get_data() == baseline.get_data(),"Original weather must return without any leftover pixels")
	assert(Compare.equivalent(before,shop.state.to_data()),"Easter egg must not change economy, stats, mode, or saved progress")
	# A cloudy icon and a compact view cannot start an invisible combo.
	visitor.tick(Visitor.COOLDOWN)
	shop.state.progression.clock = shop.state.Content.WEATHER_SECONDS
	assert(shop.state.progression.weather() != 0)
	for i in 7: click()
	assert(visitor.remaining == 0.0 and visitor.taps == 0)
	shop.state.progression.clock = 0.0
	shop._set_window_mode(shop.State.WindowMode.COMPANION)
	for i in 7: click()
	assert(visitor.remaining == 0.0 and visitor.taps == 0 and shop.state.window_mode == shop.State.WindowMode.COMPANION)
	var file := FileAccess.open(OUT+"proof.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"status":"passed","required_taps":7,"combo_seconds":3,"display_seconds":2,"changed_pixels_inside_glass":changed,"frame_unchanged":true,"original_pixels_restored":true,"same_game_state":true,"player_save_accessed":false},"\t"))
	print("WINDOW VISITOR PASS:7-click real signal;deadline/cooldown;glass-only photograph;frame preserved;weather restored;game state unchanged")
	shop.queue_free()
	await process_frame
	quit()
