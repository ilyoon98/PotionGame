extends SceneTree
const OUTPUT = "res://assets/characters/walk_cycles_v3/"
const NAMES = ["traveler", "mage", "elf", "rogue"]
func _initialize() -> void:
	var contact := Image.create(224, 288, false, Image.FORMAT_RGBA8)
	contact.fill(Color("282231"))
	for pose_index in 4:
		var row := Image.create(224, 72, false, Image.FORMAT_RGBA8)
		row.fill(Color("282231"))
		for character_index in NAMES.size():
			var sprite_path: String = "res://assets/characters/animations_v1/traveler_idle_48x64.png" if character_index == 0 else OUTPUT + NAMES[character_index] + "_walk_" + str(pose_index + 1) + "_48x64.png"
			var sprite := Image.load_from_file(sprite_path)
			row.blend_rect(sprite, Rect2i(0, 0, 48, 64), Vector2i(4 + character_index * 56, 4))
			contact.blend_rect(sprite, Rect2i(0, 0, 48, 64), Vector2i(4 + pose_index * 56, 4 + character_index * 72))
		row.resize(896, 288, Image.INTERPOLATE_NEAREST)
		var file := FileAccess.open(OUTPUT + "walk_preview_frame_%d.rgba" % pose_index, FileAccess.WRITE)
		file.store_buffer(row.get_data())
		file.close()
	contact.resize(896, 1152, Image.INTERPOLATE_NEAREST)
	assert(contact.save_png(OUTPUT + "walk_corrections_4x.png") == OK)
	quit()
