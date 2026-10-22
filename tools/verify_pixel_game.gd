extends SceneTree
## Render the real Shop and real economic sale events without player saves/input.
const Shop = preload("res://scripts/shop.gd")
const State = preload("res://scripts/shop_state.gd")
const Catalog = preload("res://scripts/pixel_art_catalog.gd")
var shop: Control
var folder := "res://.verification/pixel-runtime-v1/"
var report := {"status":"running","renderer":"Godot actual Shop/ShopArt","player_save_accessed":false,"cases":[]}
var frame_number := 0

func _initialize() -> void:
	set_meta("isolated_preview",true)
	call_deferred("run")

func freeze(node: Node) -> void:
	node.set_process(false)
	for child in node.get_children(): freeze(child)

func capture(name: String) -> void:
	shop.art._process(0)
	shop.art.queue_redraw()
	shop.workshop_gauges.refresh()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image.get_size() != Vector2i(540,300):
		push_error("Capture size changed: "+str(image.get_size()))
		quit(1)
		return
	assert(image.save_png(folder+name+".png") == OK)

func run() -> void:
	assert(DisplayServer.get_name() != "headless","Use a rendering driver for actual viewport captures")
	Engine.max_fps = 60
	# The render fixture must not react to clicks intended for the visible game.
	root.gui_disable_input = true
	DirAccess.make_dir_recursive_absolute(folder+"frames")
	var backing := ColorRect.new()
	backing.color = Color("4a3c52")
	backing.size = Vector2(540,300)
	root.add_child(backing)
	shop = Shop.new()
	root.add_child(shop)
	assert(shop.test_mode and shop.instance_bypassed)
	shop._set_window_mode(State.WindowMode.WORKSHOP)
	freeze(shop)
	root.always_on_top = false
	root.transparent = false
	root.position = Vector2i(40,40)
	for ci in [0,2,3,4]:
		shop.state = State.new()
		var state: RefCounted = shop.state
		var kind: Variant = {0:false,2:"moon",3:"purify",4:"agility"}[ci]
		var cid: String = state.Content.CUSTOMERS[ci].id
		state.window_mode = State.WindowMode.WORKSHOP
		state.progression.owned = ["moon","purify","agility"]
		state.progression.customer = ci
		state.progression.customer_selected = true
		state.progression.active_recipe = kind
		state.brew_active = true
		state.herbs = 100
		state.gold = 1284
		state.auto_purchase = false
		state.inventory = [false,true,"moon","purify","agility","moon",false,"purify"]
		state.stock = 8
		state.mana_stock = 1
		state.customer_elapsed = state.customer_interval()-0.01
		shop.art.on_shop_closed()
		shop.art.motion.elapsed = 2.0
		shop.art.motion.visit = shop.art.Motion.Visit.WAITING
		shop.art.motion.customer_x = shop.art.motion.counter_x()
		shop._update_interface()
		await capture(cid+"-stock")
		shop.art.motion.visit = shop.art.Motion.Visit.ARRIVING
		shop.art.motion.arrival_elapsed = 0
		shop.art.motion.customer_x = shop.art.motion.offscreen_x()
		for frame in 10:
			shop.art._process(0.1)
			await capture("frames/frame-%03d" % frame_number)
			frame_number += 1
		var old_gold: int = state.gold
		shop._advance_game(0.02)
		shop._update_interface()
		assert(state.total_sold == 1 and state.stock == 7 and state.gold > old_gold)
		assert(shop.art.departing_customer == cid and Catalog.id(shop.art.sold_mana) == Catalog.id(kind))
		assert(shop.art.bottles.inventory_order() == state.inventory_order())
		var duration: float = shop.art.motion.departure_seconds
		var handover: float = shop.art.motion.handover_seconds
		for sample in [["counter",handover*0.4],["flight",handover*0.8],["catch",handover],["hold",handover+0.2],["exit",1.5]]:
			shop.art.motion.departing_elapsed = sample[1]
			shop.art.motion.elapsed = 2.0+sample[1]
			await capture(cid+"-"+sample[0])
		# Playback frames use the actual transaction and actual motion controller.
		shop.art.motion.departing_elapsed = 0
		shop.art.motion.elapsed = 2.0
		for frame in 30:
			shop.art._process(0.1)
			await capture("frames/frame-%03d" % frame_number)
			frame_number += 1
		report.cases.append({"customer":cid,"potion":Catalog.id(kind),"stock_before":8,"stock_after":state.stock,"sold":state.total_sold,"earned":state.gold-old_gold,"handover_seconds":handover,"departure_seconds":duration})
	# Exercise both other playable presentation stages with the same source art.
	shop._set_window_mode(State.WindowMode.FULL)
	shop._update_interface()
	shop.art._process(0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"full-mode.png")
	shop._set_window_mode(State.WindowMode.COMPANION)
	shop.companion.refresh()
	shop.companion.scene.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"companion-mode.png")
	report.status = "passed"
	report.frames = frame_number
	var file := FileAccess.open(folder+"game-render.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("PIXEL GAME RENDER PASS:4real sales/4customers/",frame_number,"viewport frames; full/companion modes")
	shop.queue_free()
	await process_frame
	quit()
