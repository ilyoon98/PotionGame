extends RefCounted
## Shared raster resources and environment lighting for companion and main scenes.
const SHADER = preload("res://scripts/mini_pixel_light.gdshader")


static func environment(daylight: float, weather: float, effects: float, brightness_floor: float, clock: float) -> Dictionary:
	var dark := 1.0 - daylight
	var rain := weather * effects
	var day := Vector3.ONE.lerp(Vector3(0.79, 0.82, 0.91), rain)
	var night := Vector3(brightness_floor, minf(1.0, brightness_floor + 0.06), minf(1.0, brightness_floor + 0.25)).lerp(Vector3(brightness_floor, brightness_floor, minf(1.0, brightness_floor + 0.15)), rain)
	return {
		"ambient": day.lerp(night, dark),
		"local_gain": lerpf(lerpf(0.34, 0.58, rain), lerpf(1.0, 1.12, rain), dark),
		"halo_gain": lerpf(lerpf(0.26, 0.43, rain), lerpf(0.92, 1.0, rain), dark),
		"flicker": [1.0, 0.97, 1.0, 0.98, 1.03, 0.99][int(clock * 3.0) % 6],
	}


static func apply(light: ShaderMaterial, scene: Control, pixel_scale: float, pot: Rect2, values: Dictionary, emissive: bool = true) -> void:
	var transform := scene.get_global_transform()
	light.set_shader_parameter("scene_origin", transform.origin)
	light.set_shader_parameter("scene_scale", transform.get_scale() * pixel_scale)
	light.set_shader_parameter("pot_rect", Vector4(pot.position.x, pot.position.y, pot.size.x, pot.size.y))
	light.set_shader_parameter("preserve_emissive", emissive)
	for key in ["ambient", "local_gain", "flicker"]:
		light.set_shader_parameter(key, values[key])


static func make_hearth() -> Texture2D:
	var image := Image.create(26, 6, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var rows := ["....##################....", "..#aaaa#bbbb#aaa#bbbbbb##..", ".#aAAaa#bBBb#aaA#bBBbbbba#.", "#aaaaaa#bbbb#aaa#bbbbbbbb#", "#cccccc#cccc#ccc#cccccccc#", ".########################."]
	var colors := {"#": Color8(40, 33, 47), "a": Color8(109, 103, 120), "b": Color8(124, 117, 132), "c": Color8(79, 74, 89), "A": Color8(157, 150, 164), "B": Color8(166, 157, 170)}
	for y in 6:
		for x in 26:
			if colors.has(rows[y][x]): image.set_pixel(x, y, colors[rows[y][x]])
	return ImageTexture.create_from_image(image)


static func halo_texture(center: Vector2, radii: Vector2, color: Color, dimensions: Vector2i = Vector2i(128, 64)) -> TextureRect:
	var image := Image.create(dimensions.x, dimensions.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y in dimensions.y:
		for x in dimensions.x:
			var point := Vector2(floorf(x / 2.0) * 2.0, floorf(y / 2.0) * 2.0)
			var distance := ((point - center) / radii).length()
			if distance >= 1.0 or (distance > 0.77 and (int(x / 2) + int(y / 2)) % 2 == 1): continue
			var shade := color
			shade.a = 0.18 if distance < 0.3 else (0.12 if distance < 0.55 else (0.065 if distance < 0.77 else 0.025))
			image.set_pixel(x, y, shade)
	var texture := TextureRect.new()
	texture.texture = ImageTexture.create_from_image(image)
	texture.size = Vector2(dimensions)
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return texture
