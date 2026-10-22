extends SceneTree
const Shop = preload("res://scripts/shop.gd")
const Compare = preload("res://tests/state_compare.gd")
class DuplicateGuard extends Node:
	signal lost
	func acquire() -> Dictionary: return {"ok": true, "owner": false, "bypassed": false, "error": ""}
	func is_owner() -> bool: return false
class DuplicateShop extends Shop:
	func _create_instance_guard() -> Node: return DuplicateGuard.new()

func _initialize() -> void:
	assert(DisplayServer.get_name() == "headless")
	set_meta("isolated_preview", true)
	call_deferred("run")
func run() -> void:
	var shop := DuplicateShop.new()
	var before: Dictionary = shop.state.to_data().duplicate(true)
	root.add_child(shop)
	assert(shop.art == null and shop.login_resume == null and shop.management == null)
	assert(not shop.is_processing() and not shop._save())
	assert(Compare.equivalent(before, shop.state.to_data()))
	assert(not shop.set_login_resume(true).ok)
	print("DUPLICATE BOOT PASS: rejected before save load/login controller/UI/ticks; state and RNG unchanged; no save or login intent writes; actual atomic race covered by verify_single_instance")
	quit()
