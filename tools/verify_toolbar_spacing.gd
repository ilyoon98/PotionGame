extends SceneTree
## Headless layout only; does not touch native windows or player saves.
const Shop = preload("res://scripts/shop.gd")

func _initialize() -> void:
	set_meta("isolated_preview", true)
	call_deferred("run")

func run() -> void:
	assert(DisplayServer.get_name() == "headless")
	var shop := Shop.new()
	root.add_child(shop)
	shop.set_process(false)
	shop._set_window_mode(shop.State.WindowMode.WORKSHOP)
	assert(root.size == Vector2i(540, 300))
	assert(shop.workshop_toolbar.get_rect() == Rect2(0, 248, 540, 52))
	assert(shop.find_child("ExpeditionMapButton", true, false) == null)
	var nodes := [shop.workshop_move, shop.workshop_toolbar.get_node("GoldCoin"), shop.workshop_gold, shop.workshop_time_icon, shop.workshop_weather_icon, shop.workshop_toolbar.get_node("ManageButton")]
	var expected := [Rect2(4, 10, 28, 32), Rect2(40, 17, 16, 18), Rect2(64, 10, 100, 32), Rect2(184, 14, 20, 24), Rect2(220, 14, 22, 24), Rect2(398, 10, 42, 32)]
	for amount in [0, 12345, 99999, 100000, 148634, 999999, 1000000, 123456789, 999999999999]:
		shop.state.gold = amount
		shop._update_interface()
		# Covers all weather/time icon variants, without faking a journey or paying for it.
		for clock in [0.0, 100.0, 190.0, 240.0]:
			shop.state.progression.clock = clock
			shop._update_interface()
			await process_frame
			await process_frame
			var previous_end := 0.0
			for i in nodes.size():
				var node: Control = nodes[i]
				if i > 0 and node.position.x - previous_end < 8.0:
					print("SPACING FAILURE gold=", amount, " node=", i, " gap=", node.position.x - previous_end)
					quit(1)
					return
				assert(Rect2(Vector2.ZERO, shop.workshop_toolbar.size).encloses(node.get_rect()))
				assert(node.get_rect() == expected[i], "Actual nodes use the wider reserved slots and centered vertical layout")
				assert(node.position.y >= 10 and shop.workshop_toolbar.size.y - node.get_rect().end.y >= 10, "Visible controls and gold retain at least ten pixels above and below")
				previous_end = node.get_rect().end.x
			var font := shop.workshop_gold.get_theme_font("font")
			var pixels: int = shop.workshop_gold.get_theme_font_size("font_size")
			assert(pixels == 17 and font.get_height(pixels) <= shop.workshop_gold.size.y)
			assert(font.get_string_size(shop.workshop_gold.text, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x <= shop.workshop_gold.size.x, "Displayed gold fits its reserved slot without covering time")
		assert(shop.workshop_gold.tooltip_text.contains(shop._number(amount)))
	assert(not shop.workshop_environment.visible)
	shop.state.gold = 148634
	shop._update_interface()
	assert(shop.workshop_gold.text == "14.9만")
	assert(shop.workshop_gold.gui_input.is_connected(shop._mini_input), "Gold tooltip area remains draggable")
	for entry in [["MinimizeButton", 444], ["RestoreButton", 476], ["CloseButton", 508]]:
		assert(shop.workshop_toolbar.get_node(entry[0]).get_rect() == Rect2(entry[1], 10, 28, 32))
	print("TOOLBAR SPACING PASS: 540x52 bar without map; >=8px left gaps and >=10px vertical padding; actual 17px gold fits and exact tooltip; all time/weather variants; reserved action slots; headless only")
	quit()
