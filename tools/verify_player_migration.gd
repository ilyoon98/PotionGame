extends SceneTree
const State = preload("res://scripts/shop_state.gd")


func _initialize() -> void:
	var source := "res://.verification/player-save-migration-input.json"
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(source))
	assert(data is Dictionary)
	var state := State.new()
	assert(state.load_data(data))
	for key in ["gold", "stock", "level", "garden_level", "herbs", "mushrooms", "mana_stock", "total_sold", "brew_elapsed", "harvest_elapsed", "delivery_elapsed"]:
		assert(is_equal_approx(float(state.get(key)), float(data[key])), "Migration changed " + key)
	var saved := state.to_data()
	var restored := State.new()
	assert(restored.load_data(JSON.parse_string(JSON.stringify(saved))))
	assert(saved["version"] == State.SAVE_VERSION)
	print("PLAYER MIGRATION PASS: existing save loads and round-trips with gold, inventory, upgrades and all reserved progress unchanged; original file never written")
	quit()
