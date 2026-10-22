extends RefCounted
## Free hysteresis, independent of the paid workshop expansion.
const Content = preload("res://scripts/shop_content.gd")
var active := false

static func thresholds(capacity: int) -> Dictionary:
	if capacity <= 0: return {}
	if capacity == 1: return {"low": 0, "high": 1}
	var low := mini(capacity, maxi(1, mini(6, int(ceil(capacity * 0.2)))))
	return {"low": low, "high": mini(capacity, maxi(low + 1, mini(12, int(ceil(capacity * 0.4)))))}

## F20-A applies from the first accepted contract. Before that, retail has no
## competing contract demand and purchased recipes join production directly.
func initialize(state: RefCounted) -> void:
	active = state.contracts.in_use() and state.stock <= int(thresholds(state.capacity()).low)

func update(state: RefCounted) -> void:
	var limits := thresholds(state.capacity())
	if limits.is_empty(): return
	var previous := active
	if not state.contracts.in_use(): active = false
	elif state.stock <= int(limits.low): active = true
	elif state.stock >= int(limits.high): active = false
	if previous != active: state.contracts.ordinary_batches = 0

func reserve_materials(state: RefCounted) -> Dictionary:
	var preview: Dictionary = state.production_preview()
	if preview.selected == null: return {}
	return Content.lookup("potions", preview.id).ingredients.duplicate()

func valid_mode(value: Variant, state: RefCounted) -> bool:
	if not value is bool: return false
	# A stock event can occur at the end of a saved frame. The next scheduling
	# boundary applies hysteresis; an existing batch is never reconstructed.
	return not thresholds(state.capacity()).is_empty()
