extends SceneTree
## Register generated idle concepts to the existing 48x64 sprite format.

const NAMES = ["traveler", "knight", "mage", "elf", "rogue"]
const OUTPUT = "res://assets/customers/idle_v1/"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var original := Image.load_from_file("res://assets/customer_animations.png")
	assert(original.get_size() == Vector2i(96, 128))
	var sprites: Array[Image] = [original.get_region(Rect2i(0, 0, 48, 64))]
	for character in NAMES:
		var source := Image.load_from_file("res://assets/source/customer_idle_v1/" + character + ".png")
		assert(source != null)
		source.convert(Image.FORMAT_RGBA8)
		# Drop only near-transparent generation artifacts when finding the body.
		var minimum := source.get_size()
		var maximum := Vector2i(-1, -1)
		for y in source.get_height():
			for x in source.get_width():
				if source.get_pixel(x, y).a >= 0.5:
					minimum = minimum.min(Vector2i(x, y))
					maximum = maximum.max(Vector2i(x, y))
		assert(maximum.x >= minimum.x)
		var bounds := Rect2i(minimum, maximum - minimum + Vector2i.ONE)
		var body := source.get_region(bounds)
		var factor := minf(44.0 / bounds.size.x, 60.0 / bounds.size.y)
		var fitted := Vector2i(roundi(bounds.size.x * factor), roundi(bounds.size.y * factor))
		body.resize(fitted.x, fitted.y, Image.INTERPOLATE_NEAREST)
		# Match hard pixel edges rather than retaining partial-alpha fringes.
		for y in body.get_height():
			for x in body.get_width():
				var color := body.get_pixel(x, y)
				color.a = 1.0 if color.a >= 0.5 else 0.0
				body.set_pixel(x, y, color)
		var sprite := Image.create(48, 64, false, Image.FORMAT_RGBA8)
		sprite.fill(Color.TRANSPARENT)
		sprite.blit_rect(body, Rect2i(Vector2i.ZERO, fitted), Vector2i((48 - fitted.x) / 2, 62 - fitted.y))
		var filename: String = OUTPUT + character + "_idle_48x64.png"
		assert(sprite.save_png(filename) == OK)
		var saved := Image.load_from_file(filename)
		assert(saved.get_size() == Vector2i(48, 64))
		assert(saved.get_pixel(0, 0).a == 0.0)
		sprites.append(sprite)
		print(character, ": verified 48x64 RGBA, visible body ", fitted, ", feet baseline y=61")
	var atlas := Image.create(240, 64, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	for index in NAMES.size():
		atlas.blit_rect(sprites[index + 1], Rect2i(0, 0, 48, 64), Vector2i(index * 48, 0))
	assert(atlas.save_png(OUTPUT + "customers_idle_strip_240x64.png") == OK)
	var preview := Image.create(344, 72, false, Image.FORMAT_RGBA8)
	preview.fill(Color("292331"))
	for index in sprites.size():
		preview.blend_rect(sprites[index], Rect2i(0, 0, 48, 64), Vector2i(8 + index * 56, 4))
	for scale_factor in [2, 4]:
		var enlarged := preview.duplicate() as Image
		enlarged.resize(344 * scale_factor, 72 * scale_factor, Image.INTERPOLATE_NEAREST)
		assert(enlarged.save_png(OUTPUT + "comparison_" + str(scale_factor) + "x.png") == OK)
	quit()
