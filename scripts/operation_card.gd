extends Control
## One layout for supply and upgrades: item, current effect, next status, action.
signal action_pressed
const CurrencyText = preload("res://scripts/currency_text.gd")

var title_label: Label
var detail_label: RichTextLabel
var status_label: RichTextLabel
var action_button: Button
var progress: ProgressBar
var icon_slot: Control
var accent := Color("b7cca0")


func _ready() -> void:
	size = Vector2(400, 66)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := Panel.new()
	panel.size = size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _style(Color("30273c"), Color("594764")))
	add_child(panel)
	icon_slot = Control.new()
	icon_slot.position = Vector2(16, 11)
	icon_slot.size = Vector2(40, 44)
	icon_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icon_slot)
	title_label = _label(Rect2(70, 2, 200, 20), 16, Color("f0dfc4"))
	detail_label = _currency_label(Rect2(70, 24, 200, 18), 14, Color("b4a4bd"))
	# The action stays above the full-width status so larger type keeps the
	# original automatic-purchase explanation without overlapping its price.
	status_label = _currency_label(Rect2(70, 43, 316, 18), 14, accent)
	action_button = Button.new()
	action_button.position = Vector2(276, 6)
	action_button.size = Vector2(110, 32)
	action_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	action_button.add_theme_font_size_override("font_size", 13)
	action_button.add_theme_color_override("font_color", Color("f0dfc4"))
	action_button.add_theme_color_override("font_disabled_color", Color("a99aad"))
	action_button.add_theme_color_override("font_pressed_color", Color("efc77c"))
	action_button.add_theme_stylebox_override("normal", _style(Color("3a3046"), Color("796449")))
	action_button.add_theme_stylebox_override("hover", _style(Color("44354e"), Color("efc77c")))
	action_button.add_theme_stylebox_override("pressed", _style(Color("463650"), Color("efc77c")))
	action_button.add_theme_stylebox_override("disabled", _style(Color("302b37"), Color("504657")))
	action_button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, Color("efc77c")))
	action_button.pressed.connect(func(): action_pressed.emit())
	add_child(action_button)
	progress = ProgressBar.new()
	progress.position = Vector2(70, 62)
	progress.show_percentage = false
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress.add_theme_stylebox_override("background", _style(Color("3a3046"), Color.TRANSPARENT))
	progress.add_theme_stylebox_override("fill", _style(accent, Color.TRANSPARENT))
	add_child(progress)
	progress.size = Vector2(316, 3)


func set_icon(texture: Texture2D) -> void:
	var icon := TextureRect.new()
	icon.texture = texture
	icon.size = Vector2(40, 40)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_slot.add_child(icon)


func _label(rect: Rect2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = rect.position
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(label)
	# Apply the rectangle after inherited Pretendard replaces the default font's
	# minimum height; otherwise the old 23px minimum survives the larger type.
	label.size = rect.size
	return label

func _currency_label(rect: Rect2, font_size: int, color: Color) -> RichTextLabel:
	var label := CurrencyText.new()
	label.appearance(font_size, color)
	label.fit_content = false
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.position = rect.position
	label.size = rect.size
	add_child(label)
	return label


func _style(fill: Color, border: Color) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = fill
	result.border_color = border
	result.set_border_width_all(1)
	result.set_corner_radius_all(6)
	return result
