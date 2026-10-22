extends RefCounted
## Plain, single-line Button content only. Keep native input, text and icon drawing.
const STATES := ["normal", "hover", "pressed", "disabled", "hover_pressed"]
const STYLE_META := "_centered_content_styles"
const SIZE_META := "_centered_content_size"
const APPLY_META := "_centering_content"

static func apply(button: Button, min_padding: float = 14.0, gap: int = 8) -> void:
	if button.get_meta(APPLY_META, false): return
	button.set_meta(APPLY_META, true)
	# Button text changes can temporarily expand its minimum size using the
	# previous text's centering margins. Keep this fixed CTA's allocated size.
	var allocated: Vector2 = button.get_meta(SIZE_META, button.size)
	button.set_meta(SIZE_META, allocated)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	button.expand_icon = true
	button.clip_text = false
	button.autowrap_mode = TextServer.AUTOWRAP_OFF
	button.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	if button.get_theme_constant("icon_max_width") != 16: button.add_theme_constant_override("icon_max_width", 16)
	if button.get_theme_constant("h_separation") != gap: button.add_theme_constant_override("h_separation", gap)
	var owned: Dictionary = button.get_meta(STYLE_META, {})
	for state in STATES:
		for suffix in ["", "_mirrored"]:
			var name: String = state + suffix
			if not button.has_theme_stylebox(name): continue
			var style := button.get_theme_stylebox(name)
			if owned.get(name) != style:
				style = style.duplicate() as StyleBox
				owned[name] = style
				button.add_theme_stylebox_override(name, style)
			# Measure from the allocated width below. Resetting horizontal margins
			# here emits theme changes even when the final padding is unchanged.
	button.set_meta(STYLE_META, owned)
	button.size = allocated
	var text_size := _text_size(button)
	var margins := _margins(button)
	# Compute the natural capped icon at this actual content height. The real
	# draw can still report insufficient width through rects().fits.
	var icon_size := _icon_size(button, Vector2(1000000.0, button.size.y - margins.y - margins.w), text_size, maxi(0, gap))
	var block_width := text_size.x + (icon_size.x + maxi(0, gap) if _icon(button) != null and not button.text.is_empty() else icon_size.x)
	var padding := maxf(min_padding, (allocated.x - block_width) * 0.5)
	for style in owned.values():
		if not is_equal_approx(style.get_content_margin(SIDE_LEFT), padding): style.set_content_margin(SIDE_LEFT, padding)
		if not is_equal_approx(style.get_content_margin(SIDE_RIGHT), padding): style.set_content_margin(SIDE_RIGHT, padding)
	button.size = allocated
	button.set_meta(APPLY_META, false)

static func rects(button: Button) -> Dictionary:
	# Godot 4.6 Button::_notification(DRAW): use the currently effective
	# margins/font/icon and its floor/round rules, not a synthetic centered box.
	var margins := _margins(button)
	var inner := Rect2(Vector2(margins.x, margins.y), button.size - Vector2(margins.x + margins.z, margins.y + margins.w))
	var text_size := _text_size(button)
	var gap := maxi(0, button.get_theme_constant("h_separation"))
	var texture := _icon(button)
	var icon_size := _icon_size(button, inner.size, text_size, gap)
	var natural_icon := _icon_size(button, Vector2(1000000.0, inner.size.y), text_size, gap)
	var icon_rect := Rect2()
	var text_rect := Rect2()
	var text_width := inner.size.x
	if texture != null:
		if icon_size.x > 0.0:
			var point := Vector2(button.size.x - margins.z - icon_size.x if button.is_layout_rtl() else margins.x, margins.y + (inner.size.y - icon_size.y) * 0.5)
			icon_rect = Rect2(point.floor(), icon_size)
		if not button.text.is_empty(): text_width -= icon_size.x + gap
	if not button.text.is_empty():
		var left := margins.x
		if button.is_layout_rtl(): left += ceilf(maxf(1.0, text_width)) - text_size.x
		elif texture != null: left += icon_size.x + gap
		text_rect = Rect2(Vector2(left, margins.y + (inner.size.y - text_size.y) * 0.5), text_size)
	var block := text_rect if not icon_rect.has_area() else icon_rect if not text_rect.has_area() else icon_rect.merge(text_rect)
	return {"icon": icon_rect, "text": text_rect, "block": block, "inner": inner, "gap": gap, "margin_left": margins.x, "margin_right": margins.z, "fits": icon_size == natural_icon and text_size.x <= ceilf(maxf(1.0, text_width)) and Rect2(Vector2.ZERO, button.size).encloses(block)}

static func _text_size(button: Button) -> Vector2:
	if button.text.is_empty(): return Vector2.ZERO
	return button.get_theme_font("font").get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size"))

static func _icon(button: Button) -> Texture2D:
	return button.icon if button.icon != null else button.get_theme_icon("icon") if button.has_theme_icon("icon") else null

static func _icon_size(button: Button, inner: Vector2, text_size: Vector2, gap: int) -> Vector2:
	var texture := _icon(button)
	if texture == null: return Vector2.ZERO
	var result := texture.get_size()
	if button.expand_icon:
		var available := inner
		var clipped := button.clip_text or button.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING or button.autowrap_mode != TextServer.AUTOWRAP_OFF
		if not clipped and text_size.x > 0.0: available.x -= text_size.x + gap
		result = Vector2(result.x * available.y / result.y, available.y)
		if result.x > available.x: result = Vector2(available.x, texture.get_height() * available.x / texture.get_width())
	var maximum := button.get_theme_constant("icon_max_width")
	if maximum > 0 and result.x > maximum: result = Vector2(maximum, result.y * maximum / result.x)
	return result.round()

static func _margins(button: Button) -> Vector4:
	var state := "normal"
	match button.get_draw_mode():
		BaseButton.DRAW_HOVER: state = "hover"
		BaseButton.DRAW_PRESSED: state = "pressed"
		BaseButton.DRAW_DISABLED: state = "disabled"
		BaseButton.DRAW_HOVER_PRESSED: state = "hover_pressed" if button.has_theme_stylebox("hover_pressed") else "pressed"
	var names: Array = STATES if button.get_theme_constant("align_to_largest_stylebox") != 0 else [state]
	var result := Vector4.ZERO
	for name in names:
		var actual: String = name + "_mirrored" if button.is_layout_rtl() and button.has_theme_stylebox(name + "_mirrored") else name
		if not button.has_theme_stylebox(actual): continue
		var style := button.get_theme_stylebox(actual)
		result = Vector4(maxf(result.x, style.get_margin(SIDE_LEFT)), maxf(result.y, style.get_margin(SIDE_TOP)), maxf(result.z, style.get_margin(SIDE_RIGHT)), maxf(result.w, style.get_margin(SIDE_BOTTOM)))
	return result
