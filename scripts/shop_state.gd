extends RefCounted
## The economy is independent of the scene, so save data and timing can be tested.

const CAPACITY := 12
const SALE_PRICE := 6
const CUSTOMER_INTERVAL := 3.2
const MAX_LEVEL := 15
const SAVE_VERSION := 15
const StockProtection = preload("res://scripts/shop_stock_protection.gd")
const WorkshopOperations = preload("res://scripts/shop_workshop_operations.gd")
const Keeper = preload("res://scripts/shop_keeper.gd")
const Aging = preload("res://scripts/shop_aging.gd")
const Content = preload("res://scripts/shop_content.gd")
const Rare = preload("res://scripts/rare_recipes.gd")
const Contracts = preload("res://scripts/shop_contracts.gd")
const LateInvestments = preload("res://scripts/shop_late_investments.gd")
const Progression = preload("res://scripts/shop_progression.gd")
const MANA_SALE_PRICE := 18
const MUSHROOM_COST := 4
const MUSHROOM_CAPACITY := 6
const DELIVERY_QUANTITY := 2
const DELIVERY_INTERVAL := 12.0
const GOLD_RESERVE := 30
const HERBS_PER_POTION := 2
const HERBS_PER_HARVEST := 2
const STARTING_HERBS := 6
const MAX_GARDEN_LEVEL := 12
enum WindowMode { FULL, SMALL, MINIMAL, WORKSHOP, COMPANION }

var gold: int = 0
var stock: int = 0
var level: int = 1
var total_sold: int = 0
var brew_elapsed: float = 0.0
var customer_elapsed: float = 0.0
var sales_counter_level: int = 0
var customer_waiting: bool = false
var herbs: int = STARTING_HERBS
var garden_level: int = 1
var harvest_elapsed: float = 0.0
var brew_active: bool = false
var mana_stock: int = 0
var inventory: Array = [] # false/true = legacy health/mana; strings = purchased recipes.
var progression := Progression.new()
var contracts := Contracts.new()
var late_investments := LateInvestments.new()
var stock_protection := StockProtection.new()
var workshop := WorkshopOperations.new()
var keeper := Keeper.new()
var aging := Aging.new()
var report_supply := {}
## Period baseline for the F21 return-report lines (keeper counters, aged sales).
var report_f21 := {}
var _pending_batch_events: Array[Dictionary] = []
var mushrooms: int = 0
var active_mana: bool = false
var auto_purchase: bool = true
var delivery_elapsed: float = 0.0
var total_spent_materials: int = 0
var total_spent_expeditions: int = 0
var total_sales_gold: int = 0
var pinned: bool = false # Legacy save key, ignored; windows are always on top.
var shop_open: bool = true
var window_mode: int = WindowMode.FULL
var main_window_mode: int = WindowMode.FULL # Main scene to return to from the two compact stages.
var mini_mode: bool:
	get:
		return window_mode != WindowMode.FULL
	set(value):
		window_mode = WindowMode.SMALL if value else WindowMode.FULL
var opacity: float = 1.0
var has_window_position: bool = false # False keeps the default bottom-right corner.
var window_position: Vector2i = Vector2i.ZERO # Last windowed top-left on the desktop.
var has_management_position: bool = false # False opens management beside the game window.
var management_position: Vector2i = Vector2i.ZERO


func set_shop_open(enabled: bool) -> void:
	if shop_open != enabled:
		shop_open = enabled
		# A fresh visitor arrives after reopening, never an instant queued sale.
		customer_elapsed = 0.0
		progression.customer_selected = false
		customer_waiting = false


func customer_interval() -> float:
	return Content.SALES_COUNTER_SECONDS[sales_counter_level]


func sales_counter_cost() -> int:
	return 0 if sales_counter_level >= Content.SALES_COUNTER_COSTS.size() else Content.SALES_COUNTER_COSTS[sales_counter_level]


func sales_counter_reason() -> String:
	if sales_counter_level >= Content.SALES_COUNTER_COSTS.size(): return "최대 단계"
	var required: int = Content.SALES_COUNTER_REGIONS[sales_counter_level]
	if progression.completed_regions() < required: return "지역 %d곳 조사 필요" % required
	if gold < sales_counter_cost(): return "%d G 부족" % (sales_counter_cost() - gold)
	return ""


func upgrade_sales_counter() -> bool:
	if not sales_counter_reason().is_empty(): return false
	var progress := customer_elapsed / customer_interval()
	var cost := sales_counter_cost()
	gold -= cost
	progression.totals["manual_spent"] += cost
	sales_counter_level += 1
	# Keep the same visitor and transaction phase; never roll or sell on upgrade.
	customer_elapsed = progress * customer_interval()
	return true


func bottleneck_hint() -> Dictionary:
	if stock >= capacity():
		if sales_counter_level >= Content.SALES_COUNTER_COSTS.size():
			return {"text": "재고 가득 · 최대 판매 속도로 판매를 기다려요", "target": ""}
		var reason := sales_counter_reason()
		return {"text": "재고 가득 · 판매대 강화로 거래를 빠르게" + ("\n" + reason if not reason.is_empty() else ""), "target": "sales_counter"}
	if waiting_for_herbs():
		return {"text": "기본 약초 부족 · 수확을 기다려요", "target": "garden" if garden_level < MAX_GARDEN_LEVEL else ""}
	if customer_waiting:
		return {"text": "손님이 완성품을 기다려요 · 제조 속도를 살펴봐요", "target": "cauldron" if level < MAX_LEVEL else ""}
	if not progression.owned.is_empty() and progression.rare_herbs == 0 and not progression.active_recipe is String:
		return {"text": "별잎 부족 · 기본 물약을 만들며 재배를 기다려요", "target": "rare"}
	return {"text": "자동 제작과 거래가 이어지고 있어요", "target": ""}


func brew_duration() -> float:
	if brew_active and contracts.batch.get("purpose", "ordinary") == "contract" and contracts.batch.has("duration"):
		return float(contracts.batch.duration)
	if brew_active and workshop.main_duration > 0.0: return workshop.main_duration
	if brew_active and progression.active_recipe is String:
		return brew_duration_for(progression.active_recipe)
	return base_brew_duration() * (1.25 if active_mana else 1.0)


func brew_duration_for(kind: Variant) -> float:
	if kind is String:
		var factor := 1.0 if Content.LEGACY_RECIPES.has(kind) else progression.expansion.effect("brewing_assistant", "new_recipe_time_multiplier", 1.0)
		return maxf(0.8, base_brew_duration() * Content.RECIPES[kind]["duration"] * factor)
	return base_brew_duration() * (1.25 if kind is bool and kind else 1.0)


func base_brew_duration() -> float:
	return maxf(0.8, 5.0 * pow(0.88, level - 1))


func health_stock() -> int:
	return inventory_order().count(false)


func inventory_order() -> Array:
	# Also supports legacy saves and development fixtures with count-only stock.
	if inventory.size() != stock or inventory.count(true) != mana_stock:
		inventory.clear()
		for index in range(stock):
			inventory.append(index < mana_stock)
	return inventory.duplicate()


func recipe_name() -> String:
	if brew_active and progression.active_recipe is String:
		return Content.potion_name(progression.active_recipe)
	return "마나" if active_mana else "체력"


func set_auto_purchase(enabled: bool) -> void:
	auto_purchase = enabled


func purchase_status() -> String:
	if not auto_purchase:
		return "자동 구매 꺼짐"
	if not shop_open:
		return "휴업 · 발주 대기"
	if mushrooms >= MUSHROOM_CAPACITY:
		return "재료 보관함 가득 · 대기"
	var quantity := mini(DELIVERY_QUANTITY, MUSHROOM_CAPACITY - mushrooms)
	if gold < GOLD_RESERVE + quantity * MUSHROOM_COST:
		return "자금 대기 · %d G 남기기" % GOLD_RESERVE
	return "다음 구매 %.1f초 · %d G 남기기" % [maxf(0.0, DELIVERY_INTERVAL - delivery_elapsed), GOLD_RESERVE]


func _buy_delivery() -> int:
	if not auto_purchase or not shop_open:
		return 0
	var quantity := mini(DELIVERY_QUANTITY, MUSHROOM_CAPACITY - mushrooms)
	var cost := quantity * MUSHROOM_COST
	if quantity <= 0 or gold < GOLD_RESERVE + cost:
		return 0
	gold -= cost
	total_spent_materials += cost
	mushrooms += quantity
	return quantity


func _fulfill_ready_delivery() -> int:
	if delivery_elapsed < DELIVERY_INTERVAL - 0.000001:
		return 0
	var quantity := _buy_delivery()
	# A ready order stays ready until storage and money allow a real purchase.
	if quantity > 0:
		delivery_elapsed = 0.0
	return quantity


func upgrade_cost() -> int:
	return int(round(30.0 * pow(1.55, level - 1)))


func herb_capacity() -> int:
	return int(progression.expansion.effect("herb_pot", "herb_capacity", 24 + (garden_level - 1) * 8))


func harvest_duration() -> float:
	return progression.expansion.effect("herb_pot", "harvest_seconds", maxf(0.8, 4.0 * pow(0.86, garden_level - 1)))


func capacity() -> int:
	return progression.expansion.potion_capacity()


func material_count(id: String) -> int:
	return {"herb": herbs, "moon_mushroom": mushrooms, "starleaf": progression.rare_herbs}.get(id, int(progression.expansion.materials.get(id, 0)))


func can_make(id: String) -> bool:
	for material in Content.lookup("potions", id)["ingredients"]:
		if material_count(material) < int(Content.lookup("potions", id)["ingredients"][material]): return false
	return true


func _production_candidate(id: String, first: bool = false, family_index: int = -1, rare_index: int = -1) -> Dictionary:
	var row := Content.lookup("potions", id)
	return {"id": id, "kind": false if id == "health" else true if id == "mana" else id, "first_batch": first, "is_rare": Rare.is_special(id), "family": row.family, "order": int(row.order), "family_index": family_index, "rare_index": rare_index}

func _recovery_basic_available() -> bool:
	return stock_protection.active and stock < capacity() and herbs >= HERBS_PER_POTION

func production_candidates() -> Array[Dictionary]:
	# Recovery must outpace retail demand before expensive recipes can resume.
	# The preview and actual reservation share this pure predicate.
	if _recovery_basic_available(): return [_production_candidate("health")]
	var ex = progression.expansion
	var first: Array[Dictionary] = []
	for id in ex.first_batches:
		if progression.owned.has(id) and not Content.LEGACY_RECIPES.has(id) and (not Rare.is_special(id) or Rare.is_owned(id, progression)) and can_make(id):
			first.append(_production_candidate(id, true, -1, _rare_index(id)))
	var ordinary: Array[Dictionary] = []
	var families: Array = Content.DATA["rules"]["family_order"]
	for offset in families.size():
		var index: int = (int(ex.family_cursor) + offset) % families.size()
		var chosen := ""
		var order := -1
		for id in progression.owned:
			if Content.LEGACY_RECIPES.has(id) or Rare.is_special(id): continue
			var row := Content.lookup("potions", id)
			if row["family"] == families[index] and int(row["order"]) > order and can_make(id):
				chosen = id
				order = int(row["order"])
		if not chosen.is_empty():
			ordinary.append(_production_candidate(chosen, false, index))
	if ordinary.is_empty() and herbs >= HERBS_PER_POTION:
		var legacy: Array = progression.owned.filter(func(id): return Content.LEGACY_RECIPES.has(id))
		var id: String = str(legacy[progression.recipe_cursor % legacy.size()]) if progression.rare_herbs > 0 and not legacy.is_empty() else "mana" if mushrooms > 0 else "health"
		ordinary.append(_production_candidate(id))
	var special: Array[Dictionary] = []
	for offset in Rare.ROWS.size():
		var index: int = (int(ex.rare_cursor) + offset) % Rare.ROWS.size()
		var id: String = Rare.ROWS[index].id
		if Rare.is_owned(id, progression) and can_make(id): special.append(_production_candidate(id, false, -1, index))
	var result: Array[Dictionary] = []
	for group in [first, special if ex.rare_turn else ordinary, ordinary if ex.rare_turn else special]:
		for item in group:
			var duplicate := false
			for previous in result:
				if previous.id == item.id: duplicate = true
			if not duplicate: result.append(item)
	return result

func _rare_index(id: String) -> int:
	for index in Rare.ROWS.size():
		if Rare.ROWS[index].id == id: return index
	return -1

func production_preview() -> Dictionary:
	var candidates := production_candidates()
	var result: Dictionary = candidates[0].duplicate() if not candidates.is_empty() else {"id": "", "kind": null, "first_batch": false, "is_rare": false, "family": "", "order": -1, "family_index": -1, "rare_index": -1}
	result["selected"] = result.kind
	result["candidates"] = candidates
	return result

func choose_new_recipe() -> String:
	var choice := production_preview()
	if choice.selected == null or choice.selected is bool or Content.LEGACY_RECIPES.has(choice.selected): return ""
	var ex = progression.expansion
	var id: String = choice.selected
	ex.rare_turn = not choice.is_rare
	if choice.is_rare: ex.rare_cursor = (int(choice.rare_index) + 1) % Rare.ROWS.size()
	elif not choice.first_batch: ex.family_cursor = (int(choice.family_index) + 1) % Content.DATA["rules"]["family_order"].size()
	return id


func garden_upgrade_cost() -> int:
	return int(round(24.0 * pow(1.55, garden_level - 1)))


func upgrade_garden() -> bool:
	if garden_level >= MAX_GARDEN_LEVEL or gold < garden_upgrade_cost():
		return false
	var progress := harvest_elapsed / harvest_duration()
	gold -= garden_upgrade_cost()
	progression.totals["manual_spent"] += garden_upgrade_cost()
	garden_level += 1
	harvest_elapsed = progress * harvest_duration()
	return true


## Real seconds left in the current main batch at the keeper's current speed.
func brew_remaining_seconds() -> float:
	return maxf(0.0, brew_duration() - brew_elapsed) / keeper.brew_speed()


## Regular is always available; busier policies unlock with reputation.
func keeper_policy_reason(value: String) -> String:
	if not Keeper.POLICIES.has(value): return "알 수 없는 근무 방식"
	if value != "regular" and not keeper.policy_unlocked(progression.reputation): return "명성 %d 필요" % Keeper.POLICY_REPUTATION
	return ""


func set_keeper_policy(value: String) -> bool:
	if not keeper_policy_reason(value).is_empty(): return false
	return keeper.set_policy(value, progression.clock)


func is_brewing() -> bool:
	# A sleeping keeper pauses the main cauldron; elapsed time is kept.
	return brew_active and not keeper.resting() and (contracts.batch.get("purpose", "ordinary") == "contract" or stock < capacity())


func waiting_for_herbs() -> bool:
	return not brew_active and stock < capacity() and herbs < HERBS_PER_POTION and production_preview().selected == null


func _start_batch() -> void:
	stock_protection.update(self)
	# A full shelf hands four bottles to an empty barrel before the cauldron decides.
	aging.settle(self)
	if workshop.level > 0 and brew_active and contracts.batch.get("purpose") != "contract" and workshop.main_duration == 0.0:
		workshop.main_duration = brew_duration_for(progression.active_recipe)
	_start_main_batch()
	workshop.start(self)


func _consume_materials(ingredients: Dictionary) -> void:
	for material in ingredients: assert(material_count(material) >= int(ingredients[material]))
	for material in ingredients:
		var quantity := int(ingredients[material])
		if material == "herb": herbs -= quantity
		elif material == "moon_mushroom": mushrooms -= quantity
		elif material == "starleaf": progression.rare_herbs -= quantity
		else: progression.expansion.materials[material] -= quantity


func _start_main_batch() -> void:
	if brew_active or keeper.resting(): return
	if _recovery_basic_available():
		herbs -= HERBS_PER_POTION
		progression.active_recipe = false
		keeper.judge(progression, 1.0, true)
		brew_active = true
		active_mana = false
		brew_elapsed = 0.0
		contracts.clear_batch()
		contracts.note_ordinary_start()
		_record_batch_start()
		return
	# A due contract slot uses its own pure candidate/cursors. A blocked retail
	# warehouse may still manufacture a directly dispatched contract bottle.
	if workshop.level == 0 and not stock_protection.active and (contracts.ordinary_batches >= 4 or stock >= capacity()):
		var shipment: Dictionary = contracts.candidate(self, stock_protection.reserve_materials(self))
		if not shipment.is_empty():
			var ingredients: Dictionary = shipment.ingredients
			for material in ingredients:
				var quantity := int(ingredients[material])
				if material == "herb": herbs -= quantity
				elif material == "moon_mushroom": mushrooms -= quantity
				elif material == "starleaf": progression.rare_herbs -= quantity
				else: progression.expansion.materials[material] -= quantity
			progression.active_recipe = shipment.kind
			keeper.judge(progression, float(shipment.chance), shipment.kind is bool, int(shipment.get("quantity", 1)))
			contracts.reserve(shipment, {"chance": progression.batch_chance, "success": progression.batch_success})
			active_mana = shipment.kind is bool and shipment.kind
			brew_active = true
			brew_elapsed = 0.0
			_record_batch_start()
			return
	if not brew_active and stock < capacity():
		var new_recipe := choose_new_recipe()
		if not new_recipe.is_empty():
			var ingredients: Dictionary = Content.lookup("potions", new_recipe)["ingredients"]
			for material in ingredients:
				var quantity: int = int(ingredients[material])
				if material == "herb": herbs -= quantity
				elif material == "moon_mushroom": mushrooms -= quantity
				elif material == "starleaf": progression.rare_herbs -= quantity
				else: progression.expansion.materials[material] -= quantity
			progression.active_recipe = new_recipe
			keeper.judge(progression, progression.success_chance(new_recipe), false)
			brew_active = true
			active_mana = false
			brew_elapsed = 0.0
			contracts.clear_batch()
			contracts.note_ordinary_start()
			_record_batch_start()
			return
		if herbs < HERBS_PER_POTION: return
		herbs -= HERBS_PER_POTION
		progression.reserve_batch(mushrooms > 0, keeper)
		active_mana = progression.active_recipe is bool and progression.active_recipe
		if active_mana:
			mushrooms -= 1
		brew_active = true
		brew_elapsed = 0.0
		progression.expansion.rare_turn = true
		contracts.clear_batch()
		contracts.note_ordinary_start()
		_record_batch_start()


func _record_batch_start() -> void:
	var kind: Variant = progression.active_recipe
	if workshop.level > 0 and contracts.batch.get("purpose") != "contract": workshop.main_duration = brew_duration_for(kind)
	var id: String = ("mana" if kind else "health") if kind is bool else str(kind)
	_pending_batch_events.append({"line": "main", "purpose": contracts.batch.get("purpose", "ordinary"), "kind": kind, "quantity": int(contracts.batch.get("quantity", 1)), "ingredients": contracts.batch.get("ingredients", Content.lookup("potions", id).ingredients).duplicate(), "duration": brew_duration(), "chance": progression.batch_chance, "success": progression.batch_success, "partner": contracts.batch.get("partner", ""), "round_id": contracts.batch.get("round_id", 0)})


func contract_batch_context() -> Dictionary:
	return {"chance": progression.batch_chance, "success": progression.batch_success, "max_quantity": late_investments.batch_max(), "duration": brew_duration_for(progression.active_recipe)}


func upgrade() -> bool:
	if level >= MAX_LEVEL or gold < upgrade_cost():
		return false
	var progress := brew_elapsed / brew_duration()
	gold -= upgrade_cost()
	progression.totals["manual_spent"] += upgrade_cost()
	level += 1
	brew_elapsed = progress * brew_duration()
	return true


func purchase_reason(kind: String) -> String:
	if kind.begins_with("region:"):
		var region_reason := progression.expansion.region_reason(kind.trim_prefix("region:"), progression)
		if not region_reason.is_empty(): return region_reason
		return "%d G 부족" % (purchase_cost(kind) - gold) if gold < purchase_cost(kind) else ""
	if kind.begins_with("staff:") or kind.begins_with("upgrade:"): return expansion_purchase_reason(kind)
	var cost := purchase_cost(kind)
	var fame := 0
	var owned := false
	if Content.RECIPES.has(kind):
		owned = progression.owned.has(kind)
		fame = Content.RECIPES[kind]["reputation"]
		if not owned and not Content.LEGACY_RECIPES.has(kind):
			var recipe_reason := progression.expansion.recipe_reason(kind, progression)
			if not recipe_reason.is_empty(): return recipe_reason
	elif kind == "filter": owned = progression.filter_owned
	elif kind == "employee":
		owned = progression.employee or progression.expansion.staff.has("sales_assistant")
		fame = Content.EMPLOYEE_REPUTATION
	elif kind == "expedition":
		owned = progression.expedition_unlocked
		fame = Content.EXPEDITION_REPUTATION
	else: return "알 수 없는 상품"
	if owned: return "구매 완료"
	if progression.reputation < fame: return "명성 %d 필요" % fame
	if gold < cost: return "%d G 부족" % (cost - gold)
	return ""


func purchase_cost(kind: String) -> int:
	if kind.begins_with("region:"): return int(Content.lookup("regions", kind.trim_prefix("region:"))["cost"])
	if kind.begins_with("staff:"): return int(Content.lookup("employees", kind.trim_prefix("staff:"))["cost"])
	if kind.begins_with("upgrade:"): return int(next_investment(kind.trim_prefix("upgrade:")).get("cost", 0))
	if Content.RECIPES.has(kind): return Content.RECIPES[kind]["cost"]
	return {"filter": Content.FILTER_COST, "employee": Content.EMPLOYEE_COST, "expedition": Content.EXPEDITION_COST}.get(kind, 0)


func purchase(kind: String) -> bool:
	if purchase_reason(kind) != "": return false
	if kind.begins_with("upgrade:"): return buy_investment(kind.trim_prefix("upgrade:"))
	var brew_progress := brew_elapsed / brew_duration()
	gold -= purchase_cost(kind)
	progression.totals["manual_spent"] += purchase_cost(kind)
	progression.totals["unlocks"] += 1
	if kind.begins_with("region:"):
		var id := kind.trim_prefix("region:")
		progression.expansion.regions.append(id)
		progression.expansion.destination = id
		Progression.Expeditions.ensure(progression)
		progression.expedition_unlocked = true
		progression.expedition_active = true
	elif kind.begins_with("staff:"):
		progression.expansion.staff.append(kind.trim_prefix("staff:"))
		if kind == "staff:sales_assistant": progression.employee = true
		brew_elapsed = brew_progress * brew_duration()
	elif Content.RECIPES.has(kind):
		progression.owned.append(kind)
		if not Content.LEGACY_RECIPES.has(kind): progression.expansion.grant_recipe(kind)
	elif kind == "filter": progression.filter_owned = true
	elif kind == "employee": progression.employee = true
	elif kind == "expedition":
		progression.expedition_unlocked = true
		progression.expedition_active = true
	if kind == "expedition" or kind.begins_with("region:"): Progression.Expeditions.tick(self, 0.0)
	return true


func track_level(track: String) -> int:
	var baseline: int = {"cauldron": level - 1, "herb_pot": garden_level - 1, "sales_counter": sales_counter_level, "precision_filter": int(progression.filter_owned)}.get(track, 0)
	return maxi(baseline, int(progression.expansion.stages.get(track, 0)))


func next_investment(track: String) -> Dictionary:
	for row in Content.track_rows(track):
		if int(row["stage"]) == track_level(track) + 1: return row
	return {}


func expansion_purchase_reason(kind: String) -> String:
	var track := kind.get_slice(":", 1)
	var row := Content.lookup("employees", track) if kind.begins_with("staff:") else next_investment(track)
	if row.is_empty(): return "최대 단계" if kind.begins_with("upgrade:") else "알 수 없는 직원"
	if kind.begins_with("staff:") and (progression.expansion.staff.has(track) or (track == "sales_assistant" and progression.employee)): return "고용 완료"
	if row.get("kind", "") == "training" and not progression.expansion.staff.has(track) and not (track == "sales_assistant" and progression.employee): return "직원 고용 필요"
	if progression.completed_regions() < int(row["completed_regions"]): return "지역 %d곳 조사 필요" % int(row["completed_regions"])
	if progression.reputation < int(row["reputation"]): return "명성 %d 필요" % int(row["reputation"])
	if gold < int(row["cost"]): return "%d G 부족" % (int(row["cost"]) - gold)
	return ""


func buy_investment(track: String) -> bool:
	if expansion_purchase_reason("upgrade:" + track) != "": return false
	if track == "cauldron" and level < MAX_LEVEL: return upgrade()
	if track == "herb_pot" and garden_level < MAX_GARDEN_LEVEL: return upgrade_garden()
	if track == "sales_counter": return upgrade_sales_counter()
	if track == "precision_filter" and not progression.filter_owned: return purchase("filter")
	var row := next_investment(track)
	var brew_progress := brew_elapsed / brew_duration()
	var harvest_progress := harvest_elapsed / harvest_duration()
	gold -= int(row["cost"])
	progression.totals["manual_spent"] += int(row["cost"])
	progression.expansion.stages[track] = int(row["stage"])
	brew_elapsed = brew_progress * brew_duration()
	harvest_elapsed = harvest_progress * harvest_duration()
	return true


func report_text() -> String:
	var p := progression
	var elapsed := p.clock - p.last_report_clock
	var sales := total_sales_gold - p.report_sales
	var contract_pay := int(contracts.totals.paid) - contracts.report_paid
	var materials := total_spent_materials - p.report_materials
	var fees := total_spent_expeditions - p.report_expeditions
	var lines := PackedStringArray(["기록 시작 %s" % p.report_started.replace("T", " "), "앱 실행 중 %d분 %d초 · 종료 중 시간 제외" % [int(elapsed) / 60, int(elapsed) % 60], "", "매출 +%d G  /  재료비 −%d G" % [sales, materials], "계약 대금 +%d G" % contract_pay, "원정 출발비 −%d G" % fees, "순영업수입 %+d G" % (sales + contract_pay - materials - fees)])
	var names := {"harvested": "기본 약초 수확", "rare": "별잎 입고", "brewed": "제조 성공", "failed": "제조 실패", "sold": "판매", "visits": "손님 방문", "preferred": "선호 거래", "reputation": "획득 명성", "expeditions": "원정 귀환", "unlocks": "구매·고용", "manual_spent": "직접 투자한 골드"}
	for key in names:
		lines.append("%s  %d" % [names[key], p.totals[key] - p.report_baseline[key]])
	for region in Content.DATA["regions"]:
		var count: int = p.expansion.region_returns(region["id"], p) - int(p.expansion.report_returns.get(region["id"], 0))
		if count > 0: lines.append("%s 귀환 %d회 · 조사 %d/%d" % [region["name"], count, p.expansion.region_returns(region["id"], p), int(region["complete_returns"])])
	for potion in Content.DATA["potions"]:
		var condition: Dictionary = potion["unlock"].get("discovery", {})
		if condition.is_empty(): continue
		var id: String = condition["region"]
		var threshold: int = int(condition["returns"])
		if p.expansion.region_returns(id, p) >= threshold and int(p.expansion.report_returns.get(id, 0)) < threshold: lines.append("발견 · %s 레시피 구매 가능" % potion["name"])
	for material in p.expansion.reward_totals:
		var count: int = int(p.expansion.reward_totals[material]) - int(p.expansion.report_rewards.get(material, 0))
		if count > 0: lines.append("%s 원정 보상 +%d" % [Content.lookup("materials", material)["name"], count])
	for material in Content.DATA.materials:
		var count: int = int(late_investments.totals.get(material.id, 0)) - int(report_supply.get(material.id, 0))
		if count > 0: lines.append("%s 보급 +%d" % [material.name, count])
	var f21 := report_f21_counts()
	lines.append("주인공 수면 %d회 · 기절 %d회" % [f21.sleeps, f21.faints])
	lines.append("피로로 인한 제조 실패  %d" % f21.fatigue_failed)
	if aging.opened() or f21.aged_sold > 0: lines.append("숙성품 판매 %d병 · +%d G" % [f21.aged_sold, f21.aged_revenue])
	lines.append("\n모든 수익·재료는 이미 반영됐어요.")
	return "\n".join(lines)


func _f21_totals() -> Dictionary:
	return {"sleeps": int(keeper.totals.sleeps), "faints": int(keeper.totals.faints), "fatigue_failed": int(keeper.totals.fatigue_failed), "aged_sold": int(aging.totals.sold), "aged_revenue": int(aging.totals.revenue)}


## F21 counts since the report period started (sleeps, faints, fatigue failures, aged sales).
func report_f21_counts() -> Dictionary:
	var counts := _f21_totals()
	for key in counts: counts[key] -= int(report_f21.get(key, 0))
	return counts


func start_report_period() -> void:
	contracts.report_paid = int(contracts.totals.paid)
	report_supply = late_investments.totals.duplicate()
	report_f21 = _f21_totals()
	progression.last_report_clock = progression.clock
	progression.report_started = Time.get_datetime_string_from_system()
	progression.report_baseline = progression.totals.duplicate()
	progression.report_sales = total_sales_gold
	progression.report_materials = total_spent_materials
	progression.report_expeditions = total_spent_expeditions
	for row in Content.DATA["regions"]: progression.expansion.report_returns[row["id"]] = progression.expansion.region_returns(row["id"], progression)
	progression.expansion.report_rewards = progression.expansion.reward_totals.duplicate()


func advance(seconds: float) -> Dictionary:
	inventory_order()
	var potion_events: Array[Dictionary] = []
	var contract_events: Array[Dictionary] = []
	var supply_events: Array[Dictionary] = []
	var supplied := 0
	var contract_earned := 0
	var brewed := 0
	var sold := 0
	var harvested := 0
	var earned := 0
	var bought := 0
	var last_sold_mana := false
	var last_brewed_mana := false
	var full_seconds := 0.0
	var customer_wait_seconds := 0.0
	var material_wait_seconds := 0.0
	var inventory_seconds := 0.0
	var inventory_ratio_seconds := 0.0
	var empty_sale_attempts := 0
	var zero_stock_seconds := 0.0
	var main_activity_seconds := 0.0
	var aux_activity_seconds := 0.0
	var aux_material_wait_seconds := 0.0
	var protection_seconds := 0.0
	if not is_finite(seconds) or seconds <= 0.0:
		return {"brewed": brewed, "sold": sold, "harvested": harvested, "earned": earned, "contract_earned": 0, "contract_events": [], "supply_events": [], "supplied": 0, "bought": bought, "last_sold_mana": false, "last_brewed_mana": false}
	var remaining := minf(seconds, 86400.0)
	# Process events in time order, independent of frame rate. Brewing pauses
	# at capacity and resumes after the next purchase without losing progress.
	while remaining > 0.000001:
		bought += _fulfill_ready_delivery()
		supplied += _fulfill_supply(supply_events)
		_start_batch()
		bought += _fulfill_ready_delivery()
		var can_brew := is_brewing()
		var can_grow := herbs < herb_capacity()
		var can_order := auto_purchase and shop_open
		# Speed is fixed for this step; crossing the rested band is itself a step boundary.
		var brew_speed := keeper.brew_speed()
		var to_brew := maxf(0.0, brew_duration() - brew_elapsed) / brew_speed if can_brew else INF
		var to_harvest := maxf(0.0, harvest_duration() - harvest_elapsed) if can_grow else INF
		var interval := customer_interval()
		var to_customer := maxf(0.0, interval - customer_elapsed) if shop_open else INF
		var to_delivery := maxf(0.0, DELIVERY_INTERVAL - delivery_elapsed) if can_order and delivery_elapsed < DELIVERY_INTERVAL - 0.000001 else INF
		var to_visitor := maxf(0.0, interval * 0.34 - customer_elapsed) if shop_open and not progression.customer_selected else INF
		var supply: Dictionary = late_investments.supply
		var to_supply := maxf(0.0, float(supply.duration) - float(supply.elapsed)) if not supply.is_empty() else INF
		var step := minf(workshop.remaining(), minf(remaining, minf(to_supply, minf(1.0 - progression.tick_elapsed, minf(to_visitor, minf(to_delivery, minf(to_harvest, minf(to_brew, to_customer))))))))
		step = minf(step, minf(keeper.remaining(progression.clock, can_brew), aging.remaining()))
		full_seconds += step if stock >= capacity() else 0.0
		zero_stock_seconds += step if stock == 0 else 0.0
		main_activity_seconds += step if can_brew else 0.0
		aux_activity_seconds += step if not workshop.aux.is_empty() else 0.0
		protection_seconds += step if stock_protection.active else 0.0
		aux_material_wait_seconds += step if workshop.level > 0 and workshop.aux.is_empty() and not stock_protection.active and contracts.batch.get("purpose") != "contract" else 0.0
		customer_wait_seconds += step if shop_open and customer_waiting else 0.0
		material_wait_seconds += step if waiting_for_herbs() else 0.0
		inventory_seconds += stock * step
		inventory_ratio_seconds += float(stock) / capacity() * step
		remaining -= step
		progression.clock += step
		keeper.advance(step, progression.clock, can_brew)
		progression.tick_elapsed += step
		late_investments.supply_tick(step)
		workshop.tick(step)
		aging.tick(step)
		if progression.tick_elapsed >= 1.0 - 0.000001:
			progression.tick_elapsed = 0.0
			progression.tick_second()
			Progression.Expeditions.tick(self)
		if shop_open:
			customer_elapsed += step
			if not progression.customer_selected and customer_elapsed >= interval * 0.34 - 0.000001:
				progression.select_customer()
		if can_brew:
			brew_elapsed = minf(brew_duration(), brew_elapsed + step * brew_speed)
		if can_grow:
			harvest_elapsed += step
		if can_order:
			delivery_elapsed = minf(DELIVERY_INTERVAL, delivery_elapsed + step)
		if can_grow and harvest_elapsed >= harvest_duration() - 0.000001:
			harvest_elapsed = 0.0
			var gathered := mini(int(progression.expansion.effect("herb_pot", "harvest_quantity", HERBS_PER_HARVEST)), herb_capacity() - herbs)
			herbs += gathered
			harvested += gathered
			progression.totals["harvested"] += gathered
		if can_brew and brew_elapsed >= brew_duration() - 0.000001:
			var batch_quantity := int(contracts.batch.get("quantity", 1)) if contracts.batch.get("purpose", "ordinary") == "contract" else 1
			brew_elapsed = 0.0
			brew_active = false
			workshop.main_duration = 0.0
			last_brewed_mana = active_mana
			if progression.batch_success:
				brewed += batch_quantity
				progression.totals["brewed"] += batch_quantity
				progression.expansion.first_batches.erase(progression.active_recipe)
				if progression.active_recipe is String and not progression.expansion.first_brewed.has(progression.active_recipe): progression.expansion.first_brewed.append(progression.active_recipe)
				if contracts.batch.get("purpose", "ordinary") == "contract":
					var previous_paid := int(contracts.totals.paid)
					var dispatch: Dictionary = contracts.complete(self, progression.active_recipe)
					contract_earned += int(contracts.totals.paid) - previous_paid
					if not dispatch.is_empty(): contract_events.append(dispatch)
				else:
					stock += 1
					inventory.append(progression.active_recipe)
					if active_mana: mana_stock += 1
					potion_events.append({"kind": "brew", "mana": progression.active_recipe})
			else:
				progression.totals["failed"] += batch_quantity
			contracts.clear_batch()
			active_mana = false
		if shop_open and customer_elapsed >= interval - 0.000001:
			customer_elapsed = 0.0
			if aging.has_aged():
				# Aged bottles sell first, at the retail price times their stage multiplier.
				var aged: Dictionary = aging.take_aged()
				var aged_kind: Variant = aged.kind
				var aged_preferred := progression.is_preferred(aged_kind)
				var aged_price := int(round(_retail_price(aged_kind, aged_preferred) * Aging.multiplier(int(aged.stage))))
				last_sold_mana = aged_kind is bool and aged_kind
				gold += aged_price
				earned += aged_price
				total_sales_gold += aged_price
				total_sold += 1
				sold += 1
				aging.totals.sold += 1
				aging.totals.revenue += aged_price
				progression.record_sale(aged_kind)
				potion_events.append({"kind": "aged_sale", "mana": aged_kind, "gold": aged_price, "stage": int(aged.stage), "customer": progression.customer, "preferred": aged_preferred})
				progression.customer_selected = false
				customer_waiting = false
			elif stock > 0:
				stock -= 1
				var index := progression.sale_index(inventory)
				var kind: Variant = inventory[index]
				inventory.remove_at(index)
				last_sold_mana = kind is bool and kind
				var preferred := progression.is_preferred(kind)
				var price := _retail_price(kind, preferred)
				if last_sold_mana:
					mana_stock -= 1
				gold += price
				earned += price
				total_sales_gold += price
				total_sold += 1
				sold += 1
				progression.record_sale(kind)
				if kind is String and not progression.expansion.first_sold.has(kind): progression.expansion.first_sold.append(kind)
				potion_events.append({"kind": "sale", "mana": kind, "gold": price, "index": index, "customer": progression.customer, "preferred": preferred})
				progression.customer_selected = false
				customer_waiting = false
			else:
				customer_waiting = true
				empty_sale_attempts += 1
		# A sale on the same tick may fund a delivery. The current batch never changes.
		bought += _fulfill_ready_delivery()
		supplied += _fulfill_supply(supply_events)
		var auxiliary: Dictionary = workshop.finish(self)
		if not auxiliary.is_empty():
			brewed += int(auxiliary.get("shipped", 0))
			contract_earned += int(auxiliary.get("paid", 0))
			if auxiliary.get("ok", false): contract_events.append(auxiliary)
			# A new payment can fund the ready order at this same boundary.
			# Resolve it before either a loop continuation or frame-end reservation.
			bought += _fulfill_ready_delivery()
	_start_batch()
	bought += _fulfill_ready_delivery()
	var batch_events: Array = _pending_batch_events.duplicate(true)
	_pending_batch_events.clear()
	return {"brewed": brewed, "sold": sold, "harvested": harvested, "earned": earned, "contract_earned": contract_earned, "contract_events": contract_events, "supply_events": supply_events, "supplied": supplied, "batch_events": batch_events, "bought": bought, "last_sold_mana": last_sold_mana, "last_brewed_mana": last_brewed_mana, "potion_events": potion_events, "full_seconds": full_seconds, "customer_wait_seconds": customer_wait_seconds, "material_wait_seconds": material_wait_seconds, "inventory_seconds": inventory_seconds, "inventory_ratio_seconds": inventory_ratio_seconds, "empty_sale_attempts": empty_sale_attempts, "zero_stock_seconds": zero_stock_seconds, "main_activity_seconds": main_activity_seconds, "aux_activity_seconds": aux_activity_seconds, "aux_material_wait_seconds": aux_material_wait_seconds, "protection_seconds": protection_seconds}


func _retail_price(kind: Variant, preferred: bool) -> int:
	var price: int = Content.RECIPES[kind]["price"] if kind is String else (MANA_SALE_PRICE if kind else SALE_PRICE)
	var potion_id: String = kind if kind is String else ("mana" if kind else "health")
	var row := Content.lookup("potions", potion_id)
	var quality := progression.expansion.effect("cauldron", "quality_sale_bonus") + (progression.expansion.effect("brewing_assistant", "new_recipe_quality_bonus") if not row["existing"] else 0.0)
	var family_bonus := progression.expansion.effect("family_" + str(row["family"]), "preferred_sale_bonus") if preferred else 0.0
	price = int(round(price * (1.0 + quality) * (1.0 + family_bonus)))
	if preferred: price += int(progression.expansion.effect("sales_assistant", "preferred_sale_flat", 2 if progression.employee else 0))
	return price


func _fulfill_supply(events: Array[Dictionary]) -> int:
	var shipment: Dictionary = late_investments.supply_boundary(self)
	var quantity := int(shipment.get("quantity", 0))
	if quantity > 0: events.append(shipment)
	return quantity


func to_data() -> Dictionary:
	var saved_inventory := inventory_order()
	return {
		"version": SAVE_VERSION, "gold": gold, "stock": stock,
		"stock_protection": stock_protection.active,
		"workshop": workshop.to_data(),
		"keeper": keeper.to_data(),
		"aging": aging.to_data(),
		"keeper_upgrades": keeper.upgrades.to_data(),
		"report_f21": report_f21.duplicate(),
		"level": level, "total_sold": total_sold,
		"brew_elapsed": brew_elapsed, "customer_elapsed": customer_elapsed,
		"sales_counter_level": sales_counter_level, "customer_waiting": customer_waiting,
		"herbs": herbs, "garden_level": garden_level, "harvest_elapsed": harvest_elapsed, "brew_active": brew_active,
		"mana_stock": mana_stock, "mushrooms": mushrooms, "active_mana": active_mana,
		"inventory": saved_inventory,
		"progression": progression.to_data(),
		"contracts": contracts.to_data(),
		"late_investments": late_investments.to_data(),
		"report_supply": report_supply.duplicate(),
		"auto_purchase": auto_purchase, "delivery_elapsed": delivery_elapsed,
		"total_spent_materials": total_spent_materials, "total_sales_gold": total_sales_gold,
		"total_spent_expeditions": total_spent_expeditions,
		"pinned": pinned,
		"shop_open": shop_open, "mini_mode": mini_mode, "window_mode": window_mode, "main_window_mode": main_window_mode, "opacity": opacity,
		"window_position": [window_position.x, window_position.y] if has_window_position else null,
		"management_position": [management_position.x, management_position.y] if has_management_position else null,
	}


func load_data(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	for key in ["version", "gold", "stock", "level", "total_sold", "brew_elapsed", "customer_elapsed"]:
		if not data.has(key) or not (data[key] is int or data[key] is float):
			return false
		if not is_finite(float(data[key])):
			return false
	if float(data["version"]) != int(data["version"]) or int(data["version"]) not in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, SAVE_VERSION]:
		return false
	var saved_fees: Variant = data.get("total_spent_expeditions", 0)
	if not (saved_fees is int or saved_fees is float) or not is_finite(float(saved_fees)) or saved_fees < 0 or saved_fees > 1000000000000 or float(saved_fees) != int(saved_fees): return false
	if data["version"] >= 8 and (not data.has("total_spent_expeditions") or not data.get("progression", {}).get("expansion", {}).has("parallel_version")): return false
	var saved_counter: Variant = data.get("sales_counter_level", 0)
	if not (saved_counter is int or saved_counter is float) or not is_finite(float(saved_counter)):
		return false
	if float(saved_counter) != int(saved_counter) or saved_counter < 0 or saved_counter > Content.SALES_COUNTER_COSTS.size():
		return false
	if not data.get("customer_waiting", false) is bool: return false
	if data["version"] >= 6 and (not data.has("sales_counter_level") or not data.has("customer_waiting")): return false
	for key in ["pinned", "shop_open", "mini_mode"]:
		if not data.get(key, false) is bool:
			return false
	var saved_opacity: Variant = data.get("opacity", 1.0)
	if not (saved_opacity is float or saved_opacity is int) or not is_finite(float(saved_opacity)):
		return false
	var saved_mode: Variant = data.get("window_mode", WindowMode.SMALL if data.get("mini_mode", false) else WindowMode.FULL)
	if not (saved_mode is int or saved_mode is float) or not is_finite(float(saved_mode)):
		return false
	if float(saved_mode) != int(saved_mode) or int(saved_mode) < WindowMode.FULL or int(saved_mode) > WindowMode.COMPANION:
		return false
	var saved_main: Variant = data.get("main_window_mode", int(saved_mode) if int(saved_mode) in [WindowMode.FULL, WindowMode.WORKSHOP] else WindowMode.WORKSHOP)
	if not (saved_main is int or saved_main is float) or not is_finite(float(saved_main)):
		return false
	if float(saved_main) != int(saved_main) or int(saved_main) not in [WindowMode.FULL, WindowMode.WORKSHOP]:
		return false
	# Validate the whole new payload before mutating progress; v1 gets a starter garden.
	var legacy: bool = data["version"] == 1
	if not legacy:
		for key in ["herbs", "garden_level", "harvest_elapsed"]:
			if not data.has(key) or not (data[key] is int or data[key] is float) or not is_finite(float(data[key])):
				return false
		if not data.has("brew_active") or not data["brew_active"] is bool:
			return false
	var legacy_recipes: bool = data["version"] < 3
	if not legacy_recipes:
		for key in ["mana_stock", "mushrooms", "delivery_elapsed", "total_spent_materials", "total_sales_gold"]:
			if not data.has(key) or not (data[key] is int or data[key] is float) or not is_finite(float(data[key])):
				return false
		for key in ["active_mana", "auto_purchase"]:
			if not data.has(key) or not data[key] is bool:
				return false
	var saved_inventory: Array = []
	var saved_progression := Progression.new()
	if data["version"] >= 5 and not saved_progression.load_data(data.get("progression")): return false
	if data["version"] >= 9 and not data.get("progression", {}).get("expansion", {}).has("rare_version"): return false
	for id in saved_progression.owned:
		if Rare.is_special(id) and not Rare.is_discovered(id, saved_progression): return false
	if saved_progression.active_recipe is String and Rare.is_special(saved_progression.active_recipe) and not Rare.is_owned(saved_progression.active_recipe, saved_progression): return false
	if data["version"] >= 8 and saved_progression.expansion.parallel_version != 1: return false
	if data["version"] >= 7 and not data["progression"].has("expansion"): return false
	var saved_capacity := saved_progression.expansion.potion_capacity()
	if data["version"] >= 4:
		if not data.get("inventory") is Array:
			return false
		for bottle in data["inventory"]:
			if not Content.valid_kind(bottle) or (data["version"] < 5 and not bottle is bool):
				return false
			if bottle is String and Rare.is_special(bottle) and not Rare.is_owned(bottle, saved_progression): return false
			saved_inventory.append(bottle)
		if saved_inventory.size() != int(clampf(float(data["stock"]), 0, saved_capacity)) or saved_inventory.count(true) != int(clampf(float(data["mana_stock"]), 0, saved_inventory.size())):
			return false
	if data["version"] >= 5:
		if not saved_progression.load_data(data.get("progression")):
			return false
	else:
		saved_progression.active_recipe = data.get("active_mana", false)
		saved_progression.report_sales = int(data.get("total_sales_gold", 0))
		saved_progression.report_materials = int(data.get("total_spent_materials", 0))
	var saved_contracts := Contracts.new()
	var saved_late := LateInvestments.new()
	var saved_brewing: bool = float(data["brew_elapsed"]) > 0.0 if legacy else data["brew_active"]
	# Parse independent stages before validating the batch quantity, then validate
	# ownership and grade against the completely parsed temporary economy.
	if data["version"] >= 11 and not saved_late.load_data(data.get("late_investments")): return false
	var validation_state: RefCounted = get_script().new()
	validation_state.progression = saved_progression
	validation_state.late_investments = saved_late
	validation_state.level = int(clampf(float(data.level), 1, MAX_LEVEL))
	validation_state.garden_level = 1 if legacy else int(clampf(float(data.garden_level), 1, MAX_GARDEN_LEVEL))
	validation_state.sales_counter_level = int(saved_counter)
	validation_state.gold = int(clampf(float(data.gold), 0, 1000000000))
	if data["version"] >= 10 and not saved_contracts.load_data(data.get("contracts"), saved_progression, saved_brewing, saved_progression.active_recipe, validation_state.contract_batch_context(), data["version"] <= 10): return false
	validation_state.contracts = saved_contracts
	if data["version"] >= 11:
		if not saved_late.load_data(data.get("late_investments"), validation_state): return false
		if saved_brewing and saved_contracts.batch.get("purpose", "ordinary") == "contract" and (float(data.brew_elapsed) < 0.0 or float(data.brew_elapsed) > float(saved_contracts.batch.duration) + 0.000001): return false
	var saved_report_supply := {}
	if data["version"] >= 11:
		if data.has("report_supply"):
			if not data.report_supply is Dictionary: return false
			for material in data.report_supply:
				if not material is String or not saved_late.totals.has(material): return false
				var count: Variant = data.report_supply[material]
				if not (count is int or count is float) or not is_finite(float(count)) or float(count) != int(count) or count < 1 or count > int(saved_late.totals[material]): return false
				saved_report_supply[material] = int(count)
		else:
			# Earlier v11 saves did not record this comparison baseline. Their
			# historical period is unknowable; begin at the saved actual receipts.
			saved_report_supply = saved_late.totals.duplicate()
	# All contract and legacy fields have been validated before any live field
	var saved_protection := StockProtection.new()
	validation_state.stock = int(clampf(float(data.stock), 0, saved_capacity))
	if data.version >= 12:
		if not saved_protection.valid_mode(data.get("stock_protection"), validation_state): return false
		saved_protection.active = data.stock_protection
	else: saved_protection.initialize(validation_state)
	validation_state.brew_active = saved_brewing
	validation_state.brew_elapsed = float(data.brew_elapsed)
	var saved_workshop := WorkshopOperations.new()
	if data.version >= 12:
		if not saved_workshop.load_data(data.get("workshop"), validation_state): return false
	else:
		saved_workshop.seed = WorkshopOperations.derived_seed(validation_state)
	# v12 and older start rested and awake; the first bedtime follows the saved clock.
	var saved_keeper := Keeper.new()
	if data.version >= 13 and not saved_keeper.load_data(data.get("keeper"), saved_progression.clock, data.version <= 14): return false
	# v14 and older have no bed/herb-tea levels.
	if data.version >= 15 and not saved_keeper.upgrades.load_data(data.get("keeper_upgrades")): return false
	# v13 and older have no aging; special bottles in barrels must still be owned.
	var saved_aging := Aging.new()
	if data.version >= 14:
		if not saved_aging.load_data(data.get("aging")): return false
		var aged_kinds: Array = saved_aging.shelf.map(func(item): return item.kind)
		for barrel in saved_aging.barrels: aged_kinds.append_array(barrel.bottles)
		for kind in aged_kinds:
			if kind is String and Rare.is_special(kind) and not Rare.is_owned(kind, saved_progression): return false
	var actual_f21 := {"sleeps": int(saved_keeper.totals.sleeps), "faints": int(saved_keeper.totals.faints), "fatigue_failed": int(saved_keeper.totals.fatigue_failed), "aged_sold": int(saved_aging.totals.sold), "aged_revenue": int(saved_aging.totals.revenue)}
	# Older saves did not record this baseline; begin the period at the saved totals.
	var saved_report_f21 := actual_f21.duplicate()
	if data.version >= 15:
		if not data.get("report_f21") is Dictionary: return false
		# A new game has no period baseline yet ({}); otherwise all five counters.
		if not data.report_f21.is_empty() and data.report_f21.size() != actual_f21.size(): return false
		for key in actual_f21:
			if not data.report_f21.is_empty() and not data.report_f21.has(key): return false
			var count: Variant = data.report_f21.get(key, 0)
			if not (count is int or count is float) or not is_finite(float(count)) or float(count) != int(count) or count < 0 or count > actual_f21[key]: return false
		saved_report_f21 = {} if data.report_f21.is_empty() else data.report_f21.duplicate()
		for key in saved_report_f21: saved_report_f21[key] = int(saved_report_f21[key])
	# is assigned. Versions1..9 keep their existing paid batch as retail.
	contracts = saved_contracts
	stock_protection = saved_protection
	workshop = saved_workshop
	keeper = saved_keeper
	aging = saved_aging
	late_investments = saved_late
	report_supply = saved_report_supply
	report_f21 = saved_report_f21
	_pending_batch_events.clear()
	progression = saved_progression
	Progression.Expeditions.migrate(progression)
	total_spent_expeditions = int(saved_fees)
	sales_counter_level = int(saved_counter)
	customer_waiting = data.get("customer_waiting", false) and progression.customer_selected
	gold = int(clampf(float(data["gold"]), 0, 1000000000))
	stock = int(clampf(float(data["stock"]), 0, saved_capacity))
	level = int(clampf(float(data["level"]), 1, MAX_LEVEL))
	total_sold = int(clampf(float(data["total_sold"]), 0, 1000000000))
	mana_stock = 0 if legacy_recipes else int(clampf(float(data["mana_stock"]), 0, stock))
	inventory = saved_inventory
	inventory_order()
	mushrooms = 0 if legacy_recipes else int(clampf(float(data["mushrooms"]), 0, MUSHROOM_CAPACITY))
	active_mana = false if legacy_recipes else data["active_mana"]
	# Removed player switches migrate to automatic operation without resetting timers.
	auto_purchase = true
	delivery_elapsed = 0.0 if legacy_recipes else clampf(float(data["delivery_elapsed"]), 0, DELIVERY_INTERVAL)
	total_spent_materials = 0 if legacy_recipes else int(clampf(float(data["total_spent_materials"]), 0, 1000000000000))
	total_sales_gold = total_sold * SALE_PRICE if legacy_recipes else int(clampf(float(data["total_sales_gold"]), 0, 1000000000000))
	brew_active = float(data["brew_elapsed"]) > 0.0 if legacy else data["brew_active"]
	brew_elapsed = clampf(float(data["brew_elapsed"]), 0.0, brew_duration())
	garden_level = 1 if legacy else int(clampf(float(data["garden_level"]), 1, MAX_GARDEN_LEVEL))
	herbs = STARTING_HERBS if legacy else int(clampf(float(data["herbs"]), 0, herb_capacity()))
	harvest_elapsed = 0.0 if legacy else clampf(float(data["harvest_elapsed"]), 0.0, harvest_duration())
	# An in-progress old potion is already paid for; migration never resets its timer.
	if not brew_active:
		brew_elapsed = 0.0
		active_mana = false
	customer_elapsed = clampf(float(data["customer_elapsed"]), 0.0, customer_interval())
	pinned = false
	shop_open = true
	window_mode = int(saved_mode)
	main_window_mode = int(saved_main)
	opacity = clampf(float(saved_opacity), 0.3, 1.0)
	# Optional and non-critical: a malformed position only falls back to the default placement.
	var saved_window: Variant = _saved_position(data.get("window_position", null))
	has_window_position = saved_window != null
	window_position = saved_window if has_window_position else Vector2i.ZERO
	var saved_management: Variant = _saved_position(data.get("management_position", null))
	has_management_position = saved_management != null
	management_position = saved_management if has_management_position else Vector2i.ZERO
	return true


static func _saved_position(value: Variant) -> Variant:
	if not value is Array or value.size() != 2: return null
	for item in value:
		if not (item is int or item is float) or not is_finite(float(item)) or absf(float(item)) > 100000.0: return null
	return Vector2i(int(value[0]), int(value[1]))
