extends SceneTree
## Keep the original proportions and detail in a taller 48x64 character cell.

const CELL_SIZE := Vector2i(48, 64)
const INNER_SIZE := Vector2(44, 60)

func _initialize() -> void:
	var source := Image.load_from_file("res://assets/source/characters.png")
	assert(source != null)
	var cell_width := source.get_width() / 2
	for index in range(2):
		var cell := source.get_region(Rect2i(index * cell_width, 0, cell_width, source.get_height()))
		var bounds := _visible_bounds(cell)
		var character := cell.get_region(bounds)
		var factor := minf(INNER_SIZE.x / bounds.size.x, INNER_SIZE.y / bounds.size.y)
		character.resize(maxi(1, roundi(bounds.size.x * factor)), maxi(1, roundi(bounds.size.y * factor)), Image.INTERPOLATE_NEAREST)
		var sprite := Image.create(CELL_SIZE.x, CELL_SIZE.y, false, Image.FORMAT_RGBA8)
		sprite.fill(Color.TRANSPARENT)
		character.convert(Image.FORMAT_RGBA8)
		sprite.blit_rect(character, Rect2i(Vector2i.ZERO, character.get_size()), Vector2i((CELL_SIZE.x - character.get_width()) / 2, CELL_SIZE.y - 2 - character.get_height()))
		var filename := "shopkeeper" if index == 0 else "customer"
		assert(sprite.save_png("res://assets/" + filename + "_48x64.png") == OK)
		print("Prepared ", filename, ": ", sprite.get_size())
	quit()


func _visible_bounds(image: Image) -> Rect2i:
	# Generated alpha can contain almost invisible specks outside the silhouette.
	# Use the visible body for framing, retaining the original alpha when copying.
	var minimum := image.get_size()
	var maximum := Vector2i(-1, -1)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a >= 0.5:
				minimum.x = mini(minimum.x, x)
				minimum.y = mini(minimum.y, y)
				maximum.x = maxi(maximum.x, x)
				maximum.y = maxi(maximum.y, y)
	assert(maximum.x >= minimum.x and maximum.y >= minimum.y)
	return Rect2i(minimum, maximum - minimum + Vector2i.ONE)
