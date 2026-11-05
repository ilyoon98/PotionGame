extends RefCounted
## F23 decoration. Counter props are bought once and then equipped or removed for
## free. Decoration has no gameplay effect; buying never equips automatically and
## swapping never removes ownership. Approved 2026-10-23 (counter props, layout A);
## the souvenir slot (small workshop souvenirs on the window frame) 2026-11-05.
## Souvenirs are owned through the regulars record, never bought.
const VERSION := 2
const SLOTS := ["counter", "souvenir"]
## Prices from the 2026-10-07 proposal (cosmetic, one-time).
const ITEMS := {
	"decor_teacup": {"name": "작은 찻잔", "cost": 120, "slot": "counter"},
	"decor_dried_vase": {"name": "말린 꽃병", "cost": 240, "slot": "counter"},
}
const ORDER := ["decor_teacup", "decor_dried_vase"]
const Regulars = preload("res://scripts/shop_regulars.gd")

var owned: Array = []
var equipped := {"counter": "", "souvenir": ""}


func owns(id: String) -> bool:
	return owned.has(id)


func is_equipped(id: String) -> bool:
	return ITEMS.has(id) and equipped.get(ITEMS[id].slot, "") == id


func counter_prop() -> String:
	return str(equipped.counter)


func souvenir() -> String:
	return str(equipped.souvenir)


static func is_souvenir(id: String) -> bool:
	for customer in Regulars.STORIES:
		if Regulars.STORIES[customer].souvenir == id: return true
	return false


static func souvenir_ids() -> Array:
	var result: Array = []
	for customer in Regulars.ids(): result.append(Regulars.STORIES[customer].souvenir)
	return result


static func souvenir_name(id: String) -> String:
	for customer in Regulars.STORIES:
		if Regulars.STORIES[customer].souvenir == id: return Regulars.STORIES[customer].souvenir_name
	return id


## Souvenir slot: owned once the customer reaches the souvenir stage. Free toggle.
func souvenir_view(state: RefCounted, id: String) -> Dictionary:
	var received: bool = state.regulars.souvenirs().has(id)
	var on := souvenir() == id
	return {"id": id, "name": souvenir_name(id), "owned": received, "equipped": on, "action": "해제" if on else "장착" if received else "단골이 되면 받아요", "can_act": received}


func act_souvenir(state: RefCounted, id: String) -> Dictionary:
	if not is_souvenir(id): return {"ok": false, "error": "알 수 없는 기념품"}
	if not state.regulars.souvenirs().has(id): return {"ok": false, "error": "아직 받지 않은 기념품"}
	if souvenir() == id:
		equipped.souvenir = ""
		return {"ok": true, "action": "removed"}
	equipped.souvenir = id
	return {"ok": true, "action": "equipped"}


func view(state: RefCounted, id: String) -> Dictionary:
	if not ITEMS.has(id): return {"exists": false}
	var item: Dictionary = ITEMS[id]
	var reason := "" if owns(id) or state.gold >= int(item.cost) else "%d G 부족" % (int(item.cost) - state.gold)
	var action := "해제" if is_equipped(id) else "장착" if owns(id) else "구매"
	return {"exists": true, "id": id, "name": item.name, "cost": int(item.cost), "owned": owns(id), "equipped": is_equipped(id), "action": action, "reason": reason, "can_act": reason.is_empty()}


## Buy once (not equipped), or toggle an owned item in its slot.
func act(state: RefCounted, id: String) -> Dictionary:
	if not ITEMS.has(id): return {"ok": false, "error": "알 수 없는 장식"}
	var item: Dictionary = ITEMS[id]
	if not owns(id):
		if state.gold < int(item.cost): return {"ok": false, "error": "%d G 부족" % (int(item.cost) - state.gold)}
		state.gold -= int(item.cost)
		state.progression.totals.manual_spent += int(item.cost)
		owned.append(id)
		return {"ok": true, "action": "bought"}
	if is_equipped(id):
		equipped[item.slot] = ""
		return {"ok": true, "action": "removed"}
	equipped[item.slot] = id
	return {"ok": true, "action": "equipped"}


func to_data() -> Dictionary:
	return {"version": VERSION, "owned": owned.duplicate(), "equipped": equipped.duplicate()}


## Validate everything before assigning; a malformed record rejects the save.
## Version 1 had only the counter slot and gains an empty souvenir slot.
## Whether an equipped souvenir is owned is checked by the state against regulars.
func load_data(data: Variant) -> bool:
	if not data is Dictionary or not (data.get("version") == VERSION or data.get("version") == 1): return false
	var saved_owned: Variant = data.get("owned")
	var saved_equipped: Variant = data.get("equipped")
	if not saved_owned is Array or not saved_equipped is Dictionary: return false
	if data.version == 1:
		if saved_equipped.size() != 1: return false
		saved_equipped = saved_equipped.duplicate()
		saved_equipped["souvenir"] = ""
	if saved_equipped.size() != SLOTS.size(): return false
	var clean_owned: Array = []
	for id in saved_owned:
		if not id is String or not ITEMS.has(id) or clean_owned.has(id): return false
		clean_owned.append(id)
	var clean_equipped := {}
	for slot in SLOTS:
		var id: Variant = saved_equipped.get(slot)
		if not id is String: return false
		if slot == "souvenir":
			if not id.is_empty() and not is_souvenir(id): return false
		elif not id.is_empty() and (not clean_owned.has(id) or ITEMS[id].slot != slot): return false
		clean_equipped[slot] = id
	owned = clean_owned
	equipped = clean_equipped
	return true
