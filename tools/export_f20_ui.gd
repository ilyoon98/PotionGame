extends "res://tools/export_management_layout.gd"
const F20Fixture = preload("res://tests/late_investment_fixture.gd")
func _initialize() -> void:
	assert(DisplayServer.get_name() == "headless")
	set_meta("isolated_preview", true)
	server = TextServerManager.get_primary_interface()
	output = "res://.verification/f20-20261020/ui"
	strict_export_bounds = false; allow_text_clipping = true
	call_deferred("run")
func setup_fixture(amount: int) -> void:
	shop.state = F20Fixture.completed_store(73129, "final", "both3", "normal")
	shop.state.gold = 10000000
	if amount == 2:
		assert(shop.state.workshop.purchase(shop.state, 1).ok)
		shop.state.stock = 16; shop.state.mana_stock = 0; shop.state.inventory.clear()
		for i in 16: shop.state.inventory.append(false)
		shop.state.advance(0.35)
	else: shop.state.advance(0.25)
	shop.state.gold = 2700000 if amount == 1 else 3600000
func preview_cases() -> Array:
	return [{"id": "saving", "page": 0, "amount": 1, "label": "확장 저축 목표"}, {"id": "parallel", "page": 0, "amount": 2, "label": "실제 동시 제작"}, {"id": "expansion", "page": 5, "amount": 1, "focus_row": "workshop_1", "label": "정식 확장 구매 행"}, {"id": "upgrades", "page": 5, "amount": 2, "focus_row": "workshop_2", "label": "정식 개선 구매 행"}, {"id": "staff", "page": 5, "amount": 2, "bottom": true, "label": "직원·설정 분리"}, {"id": "settings", "page": 7, "amount": 1, "label": "설정 분리 유지"}]
