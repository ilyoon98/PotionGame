extends SceneTree
## Production statistics navigation must never replace or reset game state.
const Shop = preload("res://scripts/shop.gd")
const State = preload("res://scripts/shop_state.gd")
const Save = preload("res://scripts/save_store.gd")
const Compare = preload("res://tests/state_compare.gd")
const FOLDER := "res://.verification/statistics-persistence/"

func _initialize() -> void:
	set_meta("isolated_preview",true)
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(FOLDER)
	var shop := Shop.new()
	root.add_child(shop)
	assert(shop.test_mode and shop.instance_bypassed)
	shop._advance_game(123.25)
	shop.state.gold += 1000
	assert(shop.state.upgrade())
	shop._update_interface()
	var identity: RefCounted = shop.state
	var before: Dictionary = shop.state.to_data().duplicate(true)
	var before_clock: float = shop.state.progression.clock
	for i in 20:
		shop.open_management_page(shop.ManagementPanel.REPORT)
		assert(shop.management.statistics_values.play_time.source_text == shop.Status.lifetime_summary(shop.state).time)
		shop.management.close_requested.emit()
		assert(not shop.management.visible)
		shop.open_management_page(shop.ManagementPanel.REPORT)
		shop.management.select_page(shop.ManagementPanel.POTIONS)
		shop.management.hide()
		assert(shop.state == identity and Compare.equivalent(before,shop.state.to_data()),"Opening/hiding/changing statistics pages must not reset any model field")
	shop._advance_game(15.5)
	assert(shop.state == identity and shop.state.progression.clock > before_clock+15.0)
	shop.open_management_page(shop.ManagementPanel.REPORT)
	var after := shop.Status.lifetime_summary(shop.state)
	assert(shop.management.statistics_values.play_time.source_text == after.time)
	assert(Save.write_from(shop.state,FOLDER+"roundtrip.json") == OK)
	var loaded := State.new()
	assert(Save.read_into(loaded,FOLDER+"roundtrip.json") == "loaded")
	assert(Compare.equivalent(shop.state.to_data(),loaded.to_data()))
	assert(shop.Status.lifetime_summary(loaded).seconds == after.seconds)
	var proof := {"status":"passed","navigation_cycles":20,"same_state_instance":true,"all_model_fields_preserved":true,"clock_before":before_clock,"clock_after":shop.state.progression.clock,"displayed_time":after.time,"save_roundtrip_preserved":true,"player_save_accessed":false}
	var file := FileAccess.open(FOLDER+"ui-proof.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(proof,"\t"))
	print("STATISTICS PERSISTENCE PASS:20 open/close/page cycles; same state; clock continues; save roundtrip")
	shop.queue_free()
	await process_frame
	quit()
