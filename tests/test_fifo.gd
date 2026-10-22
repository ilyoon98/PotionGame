extends SceneTree
const State = preload("res://scripts/shop_state.gd")
const Display = preload("res://scripts/potion_display.gd")
## F21: a rested keeper brews FRESH_SPEED work-seconds per real second.
const SPEED: float = preload("res://scripts/shop_keeper.gd").FRESH_SPEED


func _initialize() -> void:
	var state := State.new()
	state.auto_purchase = false
	state.set_shop_open(false)
	state.advance(4.9 / SPEED)
	state.mushrooms = 1
	state.advance(0.1 / SPEED)
	state.advance(6.25 / SPEED)
	assert(state.inventory_order() == [false, true])
	var restored := State.new()
	assert(restored.load_data(JSON.parse_string(JSON.stringify(state.to_data()))))
	assert(restored.inventory_order() == [false, true])
	var bottles := Display.new()
	bottles.restore(restored.stock, restored.mana_stock, restored.inventory_order())
	assert(bottles.inventory_order() == [false, true])
	restored.set_shop_open(true)
	restored.progression.customer = 3
	restored.progression.customer_selected = true
	var events: Dictionary = restored.advance(3.2)
	assert(events["earned"] == 6 and not events["last_sold_mana"])
	assert(bottles.take() == bottles.slot_center(0))
	restored.progression.customer = 3
	restored.progression.customer_selected = true
	events = restored.advance(3.2)
	assert(events["earned"] == 18 and events["last_sold_mana"])
	print("PASS: actual health then mana production sells FIFO with correct prices after save/load")
	var snapshot := state.to_data()
	var invalid := snapshot.duplicate(true)
	invalid["inventory"] = [true, true]
	assert(not state.load_data(invalid) and state.to_data() == snapshot)
	invalid["inventory"] = [false, "mana"]
	assert(not state.load_data(invalid) and state.to_data() == snapshot)
	invalid.erase("inventory")
	assert(not state.load_data(invalid))
	print("PASS: corrupt or missing FIFO queue is rejected without changing progress")
	var legacy := snapshot.duplicate(true)
	legacy["version"] = 3
	legacy.erase("inventory")
	assert(restored.load_data(legacy))
	assert(restored.stock == state.stock and restored.mana_stock == state.mana_stock and restored.gold == state.gold)
	assert(restored.inventory_order() == [true, false])
	assert(restored.to_data()["version"] == State.SAVE_VERSION)
	print("FIFO PASS: old saves retain inventory and migrate once to a persistent queue")
	quit()
