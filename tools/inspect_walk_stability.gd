extends SceneTree
func _initialize() -> void:
	for character in ["traveler", "mage", "elf", "rogue"]:
		var frames: Array[Image] = []
		for index in [1, 2]:
			frames.append(Image.load_from_file("res://assets/characters/animations_v1/%s_walk_%d_48x64.png" % [character, index]))
		var head_changed := 0
		var head_visible := 0
		for y in 34:
			for x in 48:
				var a := frames[0].get_pixel(x, y)
				var b := frames[1].get_pixel(x, y)
				if a.a > 0.5 or b.a > 0.5:
					head_visible += 1
					if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) + absf(a.a - b.a) > 0.15:
						head_changed += 1
		print(character, ": upper 34px changed = ", head_changed, "/", head_visible)
	quit()
