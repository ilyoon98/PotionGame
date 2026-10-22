extends RichTextLabel
## Display only. Keep original strings available without changing purchase reasons.
const COIN = preload("res://assets/workshop_v1/gold_coin.tres")
const COIN_PATH := "res://assets/workshop_v1/gold_coin.tres"
static var gold_pattern: RegEx
var source_text := ""
var coin_count := 0
var initialized := false
var currency_size := 14
var money_alignment := HORIZONTAL_ALIGNMENT_LEFT

func _init() -> void:
	bbcode_enabled = true
	fit_content = true
	scroll_active = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE

static func pattern() -> RegEx:
	if gold_pattern == null:
		gold_pattern = RegEx.new()
		gold_pattern.compile("([+−-]?[0-9][0-9,]*(?:\\.[0-9]+)?(?:만|억)?)\\s*G\\b")
	return gold_pattern

static func escape(value: String) -> String:
	return value.replace("[", "\u0001").replace("]", "[rb]").replace("\u0001", "[lb]")

func appearance(font_size: int, color: Color) -> void:
	currency_size = maxi(12, font_size + 2)
	add_theme_font_size_override("normal_font_size", font_size)
	add_theme_color_override("default_color", color)

func set_value(value: String) -> void:
	if initialized and source_text == value: return
	initialized = true
	source_text = value
	coin_count = 0
	var parts := PackedStringArray()
	var offset := 0
	for item in pattern().search_all(value):
		parts.append(escape(value.substr(offset, item.get_start() - offset)))
		parts.append("[img=%dx%d]%s[/img] %s" % [currency_size, currency_size, COIN_PATH, item.get_string(1)])
		offset = item.get_end()
		coin_count += 1
	parts.append(escape(value.substr(offset)))
	var formatted := "".join(parts)
	text = "[right]" + formatted + "[/right]" if money_alignment == HORIZONTAL_ALIGNMENT_RIGHT else formatted

static func button_value(button: Button, value: String) -> void:
	button.set_meta("currency_source", value)
	var item := pattern().search(value)
	button.expand_icon = true
	if button.get_theme_constant("icon_max_width") != 16: button.add_theme_constant_override("icon_max_width", 16)
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if item == null:
		button.icon = null
		button.text = value
		return
	# Keep the single price immediately after the coin, then the action/condition.
	var prefix := value.substr(0, item.get_start()).strip_edges().trim_suffix("·").strip_edges()
	var suffix := value.substr(item.get_end()).strip_edges()
	button.text = item.get_string(1) + (" " + suffix if not suffix.is_empty() else "") + (" · " + prefix if not prefix.is_empty() else "")
	button.icon = COIN
