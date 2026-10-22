extends RefCounted
## A private management theme. Game art and the host theme remain untouched.
const BG := Color("1d242b")
const SURFACE := Color("263139")
const LINE := Color("40545a")
const TEXT := Color("f3ede0")
const MUTED := Color("abb9be")
const ACCENT := Color("aacbb0")
const ACTION := Color("e5ba73")
const ACTION_TEXT := Color("272b2d")
const TRIP := Color("a7b9d6")
const HOVER := Color("333d45")
const PRESSED := Color("242e36")
const TYPES := ["Button", "CheckButton", "CheckBox", "HSlider", "VSlider", "HScrollBar", "VScrollBar", "Label", "RichTextLabel", "TooltipPanel", "TooltipLabel", "Panel", "PanelContainer", "ProgressBar", "ScrollContainer", "HSeparator", "VSeparator", "OptionButton", "MenuButton", "MenuBar", "LinkButton", "LineEdit", "TextEdit", "SpinBox", "PopupMenu", "PopupPanel", "PopupDialog", "AcceptDialog", "Window", "TabBar", "TabContainer"]

static func build_theme(host_theme: Theme) -> Theme:
	var result := host_theme.duplicate() as Theme if host_theme != null else Theme.new()
	var defaults := ThemeDB.get_default_theme()
	# Import only paint items from the fallback theme. Existing fonts, font
	# sizes, constants and control metrics continue to use their original data.
	for type in TYPES:
		var names := _item_names(defaults.get_stylebox_list(type), result.get_stylebox_list(type))
		for name in names:
			var source := result.get_stylebox(name, type) if result.has_stylebox(name, type) else defaults.get_stylebox(name, type)
			result.set_stylebox(name, type, _style(source, type, name))
		for name in _item_names(defaults.get_color_list(type), result.get_color_list(type)):
			var source := result.get_color(name, type) if result.has_color(name, type) else defaults.get_color(name, type)
			result.set_color(name, type, _color(name, source, type))
		for name in defaults.get_icon_list(type):
			# Explicit host icons can be game art. Recolor only built-in UI tools.
			if host_theme != null and host_theme.has_icon(name, type): continue
			result.set_icon(name, type, _ui_icon(defaults.get_icon(name, type), _icon_color(type, name)))
	_button_states(result)
	# The abstract types have no default items; provide consistent fallbacks.
	for type in ["ScrollBar", "Slider"]:
		var concrete := "HScrollBar" if type == "ScrollBar" else "HSlider"
		for name in result.get_stylebox_list(concrete): result.set_stylebox(name, type, result.get_stylebox(name, concrete))
		for name in result.get_icon_list(concrete): result.set_icon(name, type, result.get_icon(name, concrete))
	result.set_color("default_color", "RichTextLabel", TEXT)
	result.set_color("font_selected_color", "RichTextLabel", BG)
	result.set_color("selection_color", "RichTextLabel", ACCENT)
	return result

static func _item_names(first: PackedStringArray, second: PackedStringArray) -> PackedStringArray:
	var result := first.duplicate()
	for name in second:
		if not result.has(name): result.append(name)
	return result

static func _color(name: String, original: Color, type: String) -> Color:
	if name.contains("icon") or name.ends_with("checked_color"): return Color.WHITE
	if name.contains("shadow") or name.contains("outline"): return Color(BG, original.a)
	if name == "font_selected_color": return BG if type in ["RichTextLabel", "LineEdit", "TextEdit"] else TEXT
	if name == "selection_color": return ACCENT
	if name.contains("font") or name == "default_color":
		return MUTED if name.contains("disabled") or name.contains("placeholder") or name.contains("readonly") or name.contains("uneditable") else TEXT
	if name.contains("caret") or name.contains("cursor") or name.contains("highlight"): return ACCENT
	if name.contains("border") or name.contains("separator") or name.contains("line"): return Color(LINE, original.a)
	return Color(SURFACE, original.a)

static func _style(source: StyleBox, type: String, name: String) -> StyleBox:
	var result := source.duplicate() as StyleBox
	var fill := SURFACE
	var edge := LINE
	if name.contains("focus"):
		edge = ACCENT
	elif name.contains("pressed"):
		fill = PRESSED
		edge = ACCENT
	elif name.contains("hover") or name.contains("highlight"):
		fill = HOVER
		edge = ACCENT
	if type in ["Panel", "PanelContainer", "Window"]: fill = BG
	if type in ["HSlider", "VSlider"]:
		if name.begins_with("grabber_area"): fill = ACCENT.lightened(0.05) if name.contains("highlight") else ACCENT
	if type in ["HScrollBar", "VScrollBar"]:
		if name.begins_with("grabber"): fill = ACCENT if name.contains("highlight") else ACCENT.darkened(0.06) if name.contains("pressed") else LINE.lerp(MUTED, 0.5)
	if type == "ProgressBar" and name == "fill": fill = ACTION
	if name in ["selected", "selected_focus", "tab_selected", "hover"] and type in ["PopupMenu", "TabBar", "TabContainer", "ItemList", "Tree"]: fill = SURFACE
	if result is StyleBoxFlat:
		result.bg_color = Color(fill, result.bg_color.a)
		result.border_color = Color(edge, result.border_color.a)
		result.shadow_color = Color(BG, result.shadow_color.a)
	elif result is StyleBoxLine:
		result.color = Color(edge, result.color.a)
	elif result is StyleBoxTexture:
		result.modulate_color = Color(fill, result.modulate_color.a)
	return result

static func _button_states(theme: Theme) -> void:
	for type in ["Button", "CheckButton", "CheckBox", "OptionButton", "MenuButton", "MenuBar"]:
		if not theme.has_stylebox("hover_pressed", type): theme.set_stylebox("hover_pressed", type, theme.get_stylebox("pressed", type).duplicate())
		for name in ["normal", "hover", "pressed", "disabled", "hover_pressed", "focus"]:
			if not theme.has_stylebox(name, type): theme.set_stylebox(name, type, theme.get_stylebox(name, "Button").duplicate())
			var mirrored: String = name + "_mirrored"
			if not theme.has_stylebox(mirrored, type): theme.set_stylebox(mirrored, type, theme.get_stylebox(name, type).duplicate())
		for name in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]: theme.set_color(name, type, TEXT)
		theme.set_color("font_disabled_color", type, MUTED)
		for name in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color", "icon_disabled_color"]: theme.set_color(name, type, Color.WHITE)

static func _icon_color(type: String, name: String) -> Color:
	if name.contains("disabled"): return MUTED
	if name == "tick" or name == "horizontal_rule": return LINE
	if name.contains("unchecked"): return MUTED
	if type in ["CheckButton", "CheckBox", "HSlider", "VSlider"]: return ACCENT.lightened(0.05) if name.contains("highlight") else ACCENT
	return TEXT

static func _ui_icon(texture: Texture2D, color: Color) -> Texture2D:
	if texture == null or texture.get_width() <= 0 or texture.get_height() <= 0: return texture
	var image := texture.get_image()
	if image == null or image.is_empty(): return texture
	image = image.duplicate()
	image.convert(Image.FORMAT_RGBA8)
	var maximum := 0.0
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a > 0.0: maximum = maxf(maximum, pixel.get_luminance())
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			var shade := pixel.get_luminance() / maximum if maximum > 0.0 else 1.0
			image.set_pixel(x, y, Color(color.r * shade, color.g * shade, color.b * shade, pixel.a))
	return ImageTexture.create_from_image(image)
