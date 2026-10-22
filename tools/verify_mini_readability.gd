extends SceneTree
## Instantiate MiniWorkshop with shared button helpers and a disabled host lifecycle.
const Shop = preload("res://scripts/shop.gd")
const Mini = preload("res://scripts/mini_workshop.gd")
const Compare = preload("res://tests/state_compare.gd")
var host: Control
var mini: Control

class ToolbarHost extends Shop:
	func _ready() -> void: set_process(false)
	func _process(_delta: float) -> void: pass

func _initialize() -> void:
	assert(DisplayServer.get_name() == "headless")
	set_meta("isolated_preview", true)
	call_deferred("run")

func rect_data(rect: Rect2) -> Array: return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]

func fits(label: Label) -> Vector2:
	var extent := label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size"))
	assert(extent.x <= label.size.x and extent.y <= label.size.y, "Every displayed glyph must fit without ellipsis: " + label.text)
	return extent

func run() -> void:
	host = ToolbarHost.new()
	var mini_theme := Theme.new()
	mini_theme.default_font = host.body_font
	mini_theme.default_font_size = 18
	mini_theme.set_font("font", "Button", host.title_font)
	host.theme = mini_theme
	root.add_child(host)
	mini = Mini.new()
	mini.host = host
	mini.theme = mini_theme
	host.add_child(mini)
	mini.set_process(false)
	await process_frame
	await process_frame
	assert(host.instance_guard == null and host.login_resume == null, "This fixture does not execute the game's lifecycle")
	assert(mini.size == Vector2(256, 172) and mini.toolbar.get_rect() == Rect2(0, 128, 256, 44))
	assert(mini.drag.size == Vector2(114, 44) and mini.scene.size == Vector2(128, 64) and mini.scene.scale == Vector2(2, 2), "Only toolbar height grows; the 128px artwork and horizontal layout stay fixed")
	assert(mini.gold.get_theme_font_size("font_size") == 15 and mini.gold.get_theme_font("font") == host.body_font)
	var coin: TextureRect = mini.drag.get_node("GoldCoin")
	assert(coin.get_rect() == Rect2(36, 14, 16, 16))
	var previous_end := 0.0
	for control: Control in [mini.move_button, coin, mini.gold, mini.manage_button, mini.minimize_button, mini.restore_button, mini.close_button]:
		assert(control.position.x >= previous_end and Rect2(0, 0, 256, 44).encloses(control.get_rect()), "Toolbar nodes stay separate and inside 256×44: %s %s previous end %s" % [control.name, control.get_rect(), previous_end])
		assert(is_equal_approx(control.get_rect().get_center().y, 22), "All footer controls align to the same vertical center")
		previous_end = control.get_rect().end.x
	assert(mini.manage_button.position == Vector2(114, 6) and mini.manage_button.size == Vector2(42, 32))
	for button in [mini.move_button, mini.minimize_button, mini.restore_button, mini.close_button]:
		assert(button.size == Vector2(28, 32) and button.position.y == 6, "Shared icon buttons retain width and gain 32px height with 6px vertical padding")
	assert(mini.manage_button.get_theme_font_size("font_size") == 13, "The shared toolbar manage label uses the enlarged 13px size")
	assert(mini.minimize_button.position.x == 160 and mini.restore_button.position.x == 192 and mini.close_button.position.x == 224, "The mode buttons keep their right-aligned slots")
	var manage_extent: Vector2 = mini.manage_button.get_theme_font("font").get_string_size(mini.manage_button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, mini.manage_button.get_theme_font_size("font_size"))
	for part in ["normal", "hover", "pressed", "disabled"]:
		var style: StyleBox = mini.manage_button.get_theme_stylebox(part)
		assert(manage_extent.x + style.get_content_margin(SIDE_LEFT) + style.get_content_margin(SIDE_RIGHT) <= mini.manage_button.size.x)
		assert(manage_extent.y + style.get_content_margin(SIDE_TOP) + style.get_content_margin(SIDE_BOTTOM) <= mini.manage_button.size.y)
	var measurements := []
	for amount in [0, 9, 999, 9999, 10000, 12345, 99999, 100000, 148634, 999999, 1000000, 9999999, 10000000, 99999999, 100000000, 123456789, 999999999, 999999999999, 1000000000000, 9999999999999999, 9223372036854775807]:
		host.state.gold = amount
		var before: Dictionary = host.state.to_data().duplicate(true)
		mini.refresh()
		await process_frame
		var extent := fits(mini.gold)
		assert(mini.gold.size == Vector2(58, 32) and mini.gold.get_theme_font_size("font_size") == 15)
		assert(mini.drag.tooltip_text.contains(host._number(amount)), "The exact gold amount remains in the tooltip")
		assert(Compare.equivalent(before, host.state.to_data()), "A readability refresh must not alter economy, saved progress or RNG")
		measurements.append({"amount": str(amount), "text": mini.gold.text, "extent": [extent.x, extent.y]})
	var path := ProjectSettings.globalize_path("res://../.verification/mini-readability-measurements.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"size": [256, 172], "bar": rect_data(mini.toolbar.get_rect()), "coin": rect_data(coin.get_rect()), "gold": rect_data(mini.gold.get_rect()), "font": 15, "manageFont": mini.manage_button.get_theme_font_size("font_size"), "measurements": measurements}, "\t"))
	mini.free()
	host.free()
	print("MINI READABILITY PASS: 15px Pretendard/16px coin; 256×172 with 128px artwork and 44px toolbar; controls 32px high with 6px vertical padding; all nodes and gold glyphs through int64 max fit; exact tooltip; unchanged right offsets; shared manage style fits; economy/save/RNG unchanged; independent Mini-only headless fixture")
	quit()
