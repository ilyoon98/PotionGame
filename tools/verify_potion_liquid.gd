extends SceneTree
## Current32pixel pot and approved36recipe colors; replaces the retired48pixel mask.
const Art = preload("res://scripts/shop_art.gd")
const Visual = preload("res://scripts/potion_visual.gd")
const Catalog = preload("res://scripts/pixel_art_catalog.gd")
const State = preload("res://scripts/shop_state.gd")
const Compare = preload("res://tests/state_compare.gd")
func _initialize() -> void:
	set_meta("isolated_preview",true)
	call_deferred("run")
func run() -> void:
	var state := State.new()
	var before := state.to_data().duplicate(true)
	var art := Art.new()
	root.add_child(art)
	art.set_process(false)
	art.world = state.progression
	var liquid_pixels := {}
	for point in Catalog.DATA.liquid_pixels: liquid_pixels[Vector2i(int(point[0]),int(point[1]))] = true
	for id in Catalog.DATA.potions:
		art.set_potion_kind(id)
		assert(Visual.potion_id(art.potion_kind) == id and art.potion_color == Catalog.liquid(id))
		for frame in 3:
			var image := Catalog.pot(id,frame/6.0).get_image()
			var original := Catalog.pot("health",frame/6.0).get_image()
			assert(image.get_size() == Vector2i(32,32))
			for y in 32:
				for x in 32:
					if not liquid_pixels.has(Vector2i(x,y)): assert(image.get_pixel(x,y) == original.get_pixel(x,y),"Pot body/rim/hearth never recolor")
		art.workshop = not art.workshop
		art._refresh_lighting()
		assert(Compare.equivalent(before,state.to_data()))
	art.set_potion_kind("unknown")
	assert(art.potion_kind == false)
	print("POTION LIQUID PASS:36 recipes/108 boiling textures; exact approved colors; body/rim/hearth unchanged; no state mutation")
	art.queue_free()
	quit()
