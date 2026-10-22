extends SceneTree
const Shop = preload("res://scripts/shop.gd")


func _initialize() -> void:
	set_meta("isolated_preview", true)
	set_meta("desktop_input_verification", true)
	call_deferred("_run")


func _run() -> void:
	var shop := Shop.new()
	root.add_child(shop)
	root.title = "작업실 검증 · 저장하지 않음"
	shop._set_window_mode(shop.State.WindowMode.WORKSHOP)
	root.position = Vector2i(200, 160)
	root.always_on_top = true
	shop.state.gold = 2500
	shop.state.progression.reputation = 40
	shop.state.stock = 7
	shop.state.mana_stock = 2
	shop._update_interface()
	shop.art.motion.visit = shop.art.Motion.Visit.WAITING
	shop.art.motion.customer_x = 350
	print("NATIVE PREVIEW READY")
