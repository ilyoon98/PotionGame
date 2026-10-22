extends SceneTree
const State = preload("res://scripts/shop_state.gd")
const F = preload("res://tests/late_investment_fixture.gd")
const M = preload("res://tests/contracts_fixture.gd")
const Compare = preload("res://tests/state_compare.gd")
const ROOT := "res://.verification/f20-recovery-20261020/checks/"
# F20-A spec (2026-10-21 fix): protection applies only from the first accepted
# contract. The frozen A source applied it from the start; mirror only that gate.
class SpecProtection extends "res://.verification/f20-20261020/A/source/scripts/shop_stock_protection.gd":
	static func in_use(state: RefCounted) -> bool:
		for id in state.contracts.partners:
			if not state.contracts.partners[id].agreement.is_empty(): return true
		return false
	func initialize(state: RefCounted) -> void:
		active = in_use(state) and state.stock <= int(thresholds(state.capacity()).low)
	func update(state: RefCounted) -> void:
		if not thresholds(state.capacity()).is_empty() and not in_use(state):
			if active: state.contracts.ordinary_batches = 0
			active = false
		else: super.update(state)
# Frozen free-protection implementation plus only the approved scheduling
# exception. Paid expansion must not change unowned timing, upgrades or RNG.
class Reference extends "res://.verification/f20-20261020/A/source/scripts/shop_state.gd":
	## F21 keeper postdates this reference: compare a keeper-disabled shop as a v12 save.
	static func legacy(shop: RefCounted) -> Dictionary:
		var data: Dictionary = JSON.parse_string(JSON.stringify(shop.to_data()))
		data.erase("keeper"); data.erase("aging"); data.erase("keeper_upgrades"); data.erase("report_f21"); data.version = 12
		return data
	func load_data(data: Variant) -> bool:
		if not super.load_data(data): return false
		var spec := SpecProtection.new()
		# v12+ saves keep the stored flag until the next scheduling boundary.
		spec.active = stock_protection.active and (int(data.version) >= 12 or SpecProtection.in_use(self))
		stock_protection = spec
		return true
	func production_candidates() -> Array[Dictionary]:
		if stock_protection.active and stock < capacity() and herbs >= HERBS_PER_POTION:
			return [_production_candidate("health")]
		return super.production_candidates()
	func _start_batch() -> void:
		stock_protection.update(self)
		if not brew_active and stock_protection.active and stock < capacity() and herbs >= HERBS_PER_POTION:
			herbs -= HERBS_PER_POTION
			progression.active_recipe = false; progression.batch_chance = 1.0; progression.batch_success = true
			brew_active = true; active_mana = false; brew_elapsed = 0.0
			contracts.clear_batch(); contracts.note_ordinary_start(); _record_batch_start()
		else: super._start_batch()
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func stock(s: RefCounted, n: int) -> void:
	s.stock = n; s.mana_stock = 0; s.inventory.clear()
	for i in n: s.inventory.append(false)
func scheduling(s: RefCounted) -> Dictionary:
	var p = s.progression; var ex = p.expansion
	return {"main_seed":p.seed_value,"rare_seed":ex.rare_seed,"contract_seed":s.contracts.seed,"recipe_cursor":p.recipe_cursor,"family_cursor":ex.family_cursor,"rare_cursor":ex.rare_cursor,"rare_turn":ex.rare_turn,"first_batches":ex.first_batches.duplicate()}
func _initialize() -> void: call_deferred("run")
func run() -> void:
	check(DisplayServer.get_name() == "headless", "Headless only")
	for seed_value in [73129,19337,9973]:
		var s := F.completed_store(seed_value,"final","both3","normal")
		s.stock_protection.update(s)
		var before: Dictionary = M.data(s)
		for i in 30:
			check(s.production_preview().selected is bool and s.production_preview().id == "health", "Recovery preview chooses basic, even with high and special recipes available")
			check(Compare.equivalent(s.stock_protection.reserve_materials(s), {"herb":2}), "Recovery allowance matches actual next ingredients")
		check(Compare.equivalent(before,M.data(s)), "Repeated preview does not spend materials, RNG or cursors")
		var materials: Dictionary = M.materials(s); var cursors := scheduling(s)
		s._start_batch()
		check(s.brew_active and s.progression.active_recipe is bool and not s.progression.active_recipe and s.contracts.batch.purpose == "ordinary", "Actual recovery batch is basic health")
		check(s.progression.batch_success and s.progression.batch_chance == 1.0, "Basic judgement preserved")
		for id in materials: check(s.material_count(id) == int(materials[id]) - (2 if id == "herb" else 0), "Only two herbs consumed: "+id)
		check(Compare.equivalent(cursors,scheduling(s)), "Recovery leaves recipe/special/contract RNG and original policy cursors intact")
		before = M.data(s); s._start_batch()
		check(Compare.equivalent(before,M.data(s)), "Existing basic batch is never restarted or charged twice")
		var loaded := State.new(); check(loaded.load_data(M.data(s)), "Basic reservation save restores")
		check(Compare.equivalent(M.data(s),M.data(loaded)), "Save preserves exact recovery and current paid batch")
		var released := false; var high_resumed := false; var partners := {}
		for i in 600:
			var event: Dictionary = s.advance(1.0)
			if not s.stock_protection.active: released = true
			for batch in event.batch_events:
				if batch.purpose == "ordinary" and not batch.kind is bool: high_resumed = true
				if batch.purpose == "contract": partners[batch.partner] = true
		check(released and high_resumed, "Open shop reaches recovery threshold and resumes original high recipes")
		check(partners.size() == 3, "Actual resumed shipments rotate through all three partners")
		# No invented herbs or fake retail allowance when the basic blend cannot start.
		s = F.completed_store(seed_value,"final","both3","normal"); s.herbs = 0
		s.stock_protection.update(s); before = M.data(s)
		var next: Dictionary = s.production_preview()
		check(next.selected != null and next.id != "health", "Unavailable basic does not suppress craftable alternate recipes")
		check(Compare.equivalent(before,M.data(s)), "No-herb preview remains pure")
		s._start_batch(); check(s.brew_active and s.herbs == 0, "Recovery uses a craftable alternative without fabricating or overdrawing herbs")
		# An auxiliary reservation is paid already: protection only stops new ones.
		s = F.completed_store(seed_value,"final","both3","inventory_full")
		s.gold = 10000000; check(s.workshop.purchase(s,1).ok,"Buy actual expansion")
		stock(s,16)
		s._start_batch(); var aux: Dictionary = s.workshop.aux.duplicate(true)
		check(not aux.is_empty(),"Reserve actual auxiliary shipment")
		stock(s,0); materials = M.materials(s); var main_elapsed: float = s.brew_elapsed
		s._start_batch()
		check(s.stock_protection.active and Compare.equivalent(aux,s.workshop.aux),"Protection never rerolls existing auxiliary judgement/timing/materials")
		check(Compare.equivalent(materials,M.materials(s)) and s.brew_elapsed == main_elapsed,"Protection does not interrupt existing main batch")
		loaded = State.new(); check(loaded.load_data(M.data(s)),"Both reservations remain valid through recovery save")
		# Full differential regression for unpaid expansion, including mid-batch upgrades.
		s = State.new(); s.gold = 100000; s.keeper.enabled = false
		s.progression.seed_value = seed_value; s.progression.expansion.rare_seed = seed_value; s.contracts.seed = seed_value
		var reference := Reference.new(); check(reference.load_data(Reference.legacy(s)),"Load independent approved free-policy reference")
		for i in 400:
			s.advance(0.25); reference.advance(0.25)
			if i in [1,3,7,15,29,61,127]:
				check(s.upgrade() == reference.upgrade(),"Unowned cauldron upgrade unchanged")
				check(s.upgrade_garden() == reference.upgrade_garden(),"Unowned garden upgrade unchanged")
			var current: Dictionary = M.data(s); current.erase("workshop")
			# Desktop placement prefs (2026-10-21) postdate the frozen reference.
			current.erase("window_position"); current.erase("management_position"); current.erase("audio")
			current.erase("keeper"); current.erase("aging"); current.erase("keeper_upgrades"); current.erase("report_f21"); current.version = 12
			check(Compare.equivalent(current,M.data(reference)),"Unowned whole state matches approved free policy")
		# A mid-batch paid purchase freezes the existing duration without rewinding.
		s = F.completed_store(seed_value,"final","both3","normal"); s.advance(0.25); s.gold = 10000000
		var duration: float = s.brew_duration(); var elapsed: float = s.brew_elapsed
		check(s.workshop.purchase(s,1).ok,"Purchase while recovery basic is already in progress")
		check(s.workshop.main_duration == duration and s.brew_elapsed == elapsed,"Expansion freezes exact running recovery duration and elapsed")
		loaded = State.new(); check(loaded.load_data(M.data(s)),"Paid recovery timer roundtrip valid")
	M.write_json(ROOT+"recovery.json",{"passed":failures.is_empty(),"checks":checks,"failures":failures,"policy":"user-approved basic health first during recovery; original choice resumes after H"})
	print("F20 RECOVERY %s %d checks" % ["PASS" if failures.is_empty() else "FAIL",checks])
	quit(0 if failures.is_empty() else 1)
