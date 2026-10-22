extends SceneTree
const Shop = preload("res://scripts/shop.gd")


func _initialize() -> void:
	set_meta("isolated_preview", true)
	call_deferred("_run")


func _run() -> void:
	# No OS mouse input, cursor movement, or native window drag is performed.
	var shop := Shop.new()
	root.add_child(shop)
	shop._set_window_mode(shop.State.WindowMode.WORKSHOP)
	shop.open_management()
	var panel: Window = shop.management
	panel.set_process(false)
	panel.refresh()
	var original_heading: String = panel.heading.text
	var original_gold: String = panel.gold_label.text
	var original_flow: String = panel.rows["gather_herb"]["detail"].text
	var original_gauge: float = panel.rows.gather_herb.work.bar.value
	var p: RefCounted = shop.state.progression
	p.expedition_unlocked = true
	p.expedition_active = true
	shop.state.gold = 1000
	shop.State.Progression.Expeditions.tick(shop.state, 0.0)
	p.expansion.cycles["forest_edge"]["elapsed"] = 66.0
	p.expedition_elapsed = 66.0
	var clock_before: float = p.clock
	shop.workshop_dragging = true
	for index in range(25):
		shop._advance_game(0.2)
		panel._process(0.2)
	assert(panel.heading.text == original_heading and panel.rows["gather_herb"]["detail"].text == original_flow,
		"Management content must stay untouched during a workshop drag")
	assert(panel.gold_label.text == original_gold and is_equal_approx(panel.rows.gather_herb.work.bar.value, original_gauge), "Defer both text and gauge sampling during drag")
	assert(is_equal_approx(p.clock - clock_before, 5.0), "Game time must continue during a drag")
	assert(p.expedition_count == 1 and p.rare_herbs == 2, "Expedition must return and deposit while refresh is deferred")
	shop.workshop_dragging = false
	panel._process(0.001)
	assert(panel.gold_label.text == shop._number(shop.state.gold), "Release must catch up immediately")
	assert(is_equal_approx(panel.rows.gather_herb.work.bar.value, panel.Status.material(shop.state, "herb").progress * 100.0))
	assert(panel.rows["gather_herb"]["detail"].text != original_flow)
	# Repeated refreshes must not restyle unchanged environment highlights.
	var style_changes := [0]
	for id in panel.rows:
		if panel.rows[id].has("style"):
			panel.rows[id]["style"].changed.connect(func(): style_changes[0] += 1)
	for index in range(100): panel.refresh()
	assert(style_changes[0] == 0, "Unchanged data must not invalidate highlight styles repeatedly")
	# Content refresh and reopening preserve the fixed topmost setting.
	panel.refresh()
	if DisplayServer.get_name() != "headless": assert(panel.always_on_top and root.always_on_top)
	panel.hide()
	var hidden_heading: String = panel.heading.text
	var hidden_gold: String = panel.gold_label.text
	shop.state.gold += 10
	panel._process(1.0)
	assert(panel.heading.text == hidden_heading)
	assert(panel.gold_label.text == hidden_gold)
	shop.open_management()
	panel._process(0.2)
	assert(panel.gold_label.text == shop._number(shop.state.gold))
	if DisplayServer.get_name() != "headless": assert(panel.always_on_top and root.always_on_top)
	print("MANAGEMENT DRAG PASS: refresh deferred, simulation and expedition continue, release catches up, stable styles, fixed topmost")
	quit()

