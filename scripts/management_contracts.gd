extends Control
## The same management Window owns this screen. Every write uses Shop's gateway.
const Palette = preload("res://scripts/management_palette.gd")
const PixelArt = preload("res://scripts/pixel_art_catalog.gd")
const Currency = preload("res://scripts/currency_text.gd")
const Centered = preload("res://scripts/centered_button_content.gd")
const PARTNERS := [{"id": "caravan", "name": "여행자 상단", "customer": "traveler"}, {"id": "academy", "name": "마법 연구회", "customer": "mage"}, {"id": "grove", "name": "숲 조합", "customer": "elf"}]
const OPTION_NAMES := {"basic": "기본 제안", "payment": "대금 중심", "relationship": "거래 관계 중심"}
var panel: Window
var back_button: Button
var scroll: ScrollContainer
var list: VBoxContainer
var notice: Label
var error_label: Label
var rows := {}
var views := {}
var busy := false
var error_text := ""

func _ready() -> void:
	name = "ContractsScreen"
	back_button = panel._button(self, "돌아가기", Rect2(0, 0, 104, 40), panel.close_contracts)
	back_button.name = "ContractsBack"
	var heading: Label = panel._label(self, "수주 관리", Rect2(120, 0, 340, 40), 18)
	heading.add_theme_font_override("font", panel.host.title_font)
	scroll = ScrollContainer.new()
	scroll.name = "ContractsScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	notice = _label(list, "", Palette.MUTED)
	error_label = _label(list, "", Palette.ACTION)
	error_label.hide()
	for source in PARTNERS: _partner_row(source)
	resized.connect(_fit)
	_fit()

func _fit() -> void:
	position = Vector2(20, 90)
	size = Vector2(480, maxi(200, panel.size.y - 110))
	if scroll != null:
		scroll.position = Vector2(0, 54)
		scroll.size = Vector2(size.x, size.y - 54)

func _label(parent: Node, value: String, color: Color = Palette.TEXT, pixels: int = 16) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", pixels)
	label.add_theme_color_override("font_color", color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label

func _money(parent: Node) -> RichTextLabel:
	var label := Currency.new()
	label.appearance(16, Palette.TEXT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _button(parent: Node, value: String) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size.y = 40
	button.add_theme_font_size_override("font_size", 16)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel._purchase_style(button)
	parent.add_child(button)
	button.resized.connect(func(): panel._center_purchase_button(button))
	return button

func _partner_row(source: Dictionary) -> void:
	var card := PanelContainer.new()
	card.name = "Contract_" + source.id
	card.custom_minimum_size.y = 172
	var style: StyleBoxFlat = panel._divider_style(Palette.LINE)
	style.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", style)
	list.add_child(card)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	card.add_child(body)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	body.add_child(header)
	var icon := TextureRect.new()
	icon.texture = PixelArt.frame(source.customer, "idle", 0, false)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(32, 48)
	header.add_child(icon)
	var title := _label(header, source.name, Palette.TEXT, 18)
	title.add_theme_font_override("font", panel.host.title_font)
	var grade := _label(header, "1등급", Palette.ACCENT)
	grade.autowrap_mode = TextServer.AUTOWRAP_OFF
	grade.custom_minimum_size.x = 54
	grade.size_flags_horizontal = Control.SIZE_SHRINK_END
	var detail_toggle := Button.new()
	detail_toggle.text = "상세"
	detail_toggle.toggle_mode = true
	detail_toggle.custom_minimum_size = Vector2(52, 32)
	detail_toggle.add_theme_font_size_override("font_size", 16)
	panel._text_button_style(detail_toggle)
	header.add_child(detail_toggle)
	var status := _label(body, "첫 계약 대기", Palette.MUTED)
	status.custom_minimum_size.y = 24
	var gauge: Dictionary = panel._gauge(body, "납품", Palette.ACCENT)
	gauge.caption.add_theme_font_size_override("font_size", 16)
	gauge.count.add_theme_font_size_override("font_size", 16)
	gauge.count.custom_minimum_size.x = 106
	var counts := _label(body, "계약 전", Palette.TEXT)
	var action := _button(body, "첫 계약")
	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 6)
	details.hide()
	body.add_child(details)
	var detail_text := _money(details)
	var allowed := _money(details)
	var pending := _label(details, "", Palette.ACCENT)
	var negotiation := VBoxContainer.new()
	negotiation.name = "Negotiation_" + source.id
	negotiation.add_theme_constant_override("separation", 10)
	negotiation.hide()
	body.add_child(negotiation)
	var result := _label(negotiation, "", Palette.ACCENT)
	var options := {}
	for id in OPTION_NAMES:
		var box := VBoxContainer.new()
		box.name = "Option_" + id
		box.add_theme_constant_override("separation", 4)
		negotiation.add_child(box)
		_label(box, OPTION_NAMES[id], Palette.TEXT, 18)
		var preview := _money(box)
		var chance := _label(box, "", Palette.MUTED)
		var choose := _button(box, "기본 제안 수락" if id == "basic" else "이 조건으로 흥정")
		choose.name = source.id + "_" + id
		choose.button_down.connect(func(): choose.set_meta("held", {"action": choose.get_meta("action", ""), "token": choose.get_meta("token", {}).duplicate(true)}))
		choose.pressed.connect(func():
			var held: Dictionary = choose.get_meta("held", {})
			choose.set_meta("held", {})
			_perform(str(held.get("action", choose.get_meta("action", ""))), source.id, held.get("token", choose.get_meta("token", {}))))
		options[id] = {"box": box, "preview": preview, "chance": chance, "button": choose}
	action.pressed.connect(func(): negotiation.visible = not negotiation.visible)
	detail_toggle.toggled.connect(func(open): details.visible = open; panel._text_button_style(detail_toggle, open))
	rows[source.id] = {"panel": card, "body": body, "icon": icon, "title": title, "grade": grade, "status": status, "gauge": gauge, "counts": counts, "action": action, "toggle": detail_toggle, "details": details, "detail_text": detail_text, "allowed": allowed, "pending": pending, "negotiation": negotiation, "result": result, "options": options}

func _perform(action: String, id: String, token: Dictionary) -> void:
	if busy or action.is_empty(): return
	busy = true
	var result: Dictionary = panel.host.perform_contract_action(action, id, token.duplicate(true))
	error_text = "" if result.get("ok", false) else str(result.get("error", "계약 변경을 저장하지 못했어요."))
	busy = false
	panel.refresh()

func refresh() -> void:
	if panel == null or panel.host.state.get("contracts") == null: return
	_fit()
	error_label.text = error_text
	error_label.visible = not error_text.is_empty()
	var model: RefCounted = panel.host.state.contracts
	var unlocked: bool = model.unlocked(panel.host.state)
	notice.text = "" if unlocked else "별의 정원을 처음 열면 거래처와 계약할 수 있어요."
	notice.visible = not unlocked
	for source in PARTNERS:
		var view: Dictionary = model.partner_view(panel.host.state, source.id)
		views[source.id] = view
		_refresh_partner(rows[source.id], view, unlocked)

func _refresh_partner(row: Dictionary, view: Dictionary, unlocked: bool) -> void:
	# Populated from the module's pure public view, never by a UI-side roll.
	if not view.get("exists", false): return
	row.title.text = view.name
	row.grade.text = "%d등급" % int(view.grade)
	row.status.text = view.status
	var record: Dictionary = view.negotiation
	row.action.disabled = not unlocked or record.accepted
	row.action.visible = not record.accepted
	if record.accepted: row.negotiation.hide()
	row.action.text = "협의 완료" if record.accepted else "조건 협의" if view.active else "첫 계약"
	row.gauge.bar.value = clampf(float(view.progress), 0.0, 1.0) * 100.0
	row.gauge.count.text = "%d/%d병" % [view.shipped, view.required] if view.active else "계약 전"
	var counts := PackedStringArray()
	for count in view.counts:
		if view.active: counts.append("%s %d/%d병" % [count.name, count.shipped, count.required])
	row.counts.text = " · ".join(counts) if view.active else "첫 제안을 확인하고 수락하면 자동으로 시작해요."
	var progress_text := "거래 실적 %d점" % int(view.points)
	progress_text += " · 다음 등급 %d점" % int(view.next_points) if int(view.next_points) > 0 else " · 최고 등급"
	if view.active:
		progress_text += "\n현재 회차 %s · %s · 대금 +%.0f%%" % [str(view.round.id), OPTION_NAMES.get(view.round.terms.option, "기본 제안"), (float(view.multiplier) - 1.0) * 100.0]
		progress_text += "\n현재 누적 정산 예정 %s G · 회차 완료 때 한 번 지급" % panel.host._number(int(view.estimate))
	progress_text += "\n누적 대금 %s G · 출고 %s병 · 완료 %s회" % [panel.host._number(int(view.totals.paid)), panel.host._number(int(view.totals.shipped)), panel.host._number(int(view.totals.rounds))]
	progress_text += "\n일반 제조 4배치마다 납품 1배치 · 완료 대금 자동 정산\n기본 제안은 바로 수락할 수 있어요. 개선 요청은 협의마다 한 번만 판정해요."
	var late: Variant = panel.host.state.get("late_investments")
	var maximum: int = int(late.batch_max()) if late != null else 1
	progress_text += "\n한 번에 최대%d병 · 재료·남은 주문량에 따라 감소" % maximum
	var batch: Dictionary = panel.host.state.contracts.batch
	if panel.host.state.brew_active and batch.get("purpose", "ordinary") == "contract" and batch.get("partner", "") == view.id:
		progress_text += "\n진행 중 예약 %d병 · 이번 배치 수량 고정" % int(batch.get("quantity", 1))
	row.detail_text.set_value(progress_text)
	var unit_prices := _unit_text(view.allowed_items, "현재 회차 고정 단가" if view.active else "수락 전 현재 단가")
	if view.active and not view.get("proposal_items", []).is_empty(): unit_prices += "\n\n" + _unit_text(view.proposal_items, "다음 회차 예상 단가 · 시작할 때 고정")
	row.allowed.set_value(unit_prices)
	row.pending.text = "" if view.pending.is_empty() else "%d등급 · %s 적용 대기\n현재 회차를 보존하고 다음 회차부터 적용해요." % [view.pending.grade, OPTION_NAMES.get(view.pending.option, view.pending.option)]
	if record.tried:
		row.result.text = ("흥정 성공 · 수락할 조건을 확인하세요" if record.success else "흥정 실패 · 기본 제안 또는 기존 계약을 유지해요") + "\n판정 당시 %.0f%% · 흥정 훈련 %d단계" % [float(record.chance) * 100.0, int(record.training)]
	else: row.result.text = ""
	row.result.visible = record.tried
	var shown := []
	for option in view.options:
		var id: String = option.id
		if not row.options.has(id): continue
		shown.append(id)
		var controls: Dictionary = row.options[id]
		controls.box.show()
		var needs := PackedStringArray()
		for family in option.requirements:
			needs.append("%s %d병" % [panel.Content.lookup("families", family).get("name", family), int(option.requirements[family])])
		var preview: String = " + ".join(needs) + "\n대금 +%.0f%% · 완료 실적 +%d점" % [(float(option.multiplier) - 1.0) * 100.0, int(option.points)]
		controls.preview.set_value(preview)
		controls.chance.text = "기본 제안 · 성공 판정 없음" if id == "basic" else "흥정 성공률 %.0f%% · 실패 시 기본 제안/기존 납품 유지" % (float(option.chance) * 100.0)
		var action := "accept" if option.can_accept else "negotiate"
		var button: Button = controls.button
		button.set_meta("action", action)
		button.set_meta("token", option.token.duplicate(true))
		button.disabled = not unlocked or (not option.can_accept and not option.can_negotiate)
		button.text = "기본 제안 수락" if id == "basic" and option.can_accept else "개선 조건 수락" if option.can_accept else "이 조건으로 흥정" if option.can_negotiate else str(option.reason) if not str(option.reason).is_empty() else "협의 완료"
		button.tooltip_text = str(option.reason) if not str(option.reason).is_empty() else "기본 제안은 바로 수락 · 개선 흥정은 협의마다 한 번 판정\n종류별 단가는 거래처 상세에서 확인할 수 있어요."
		panel._center_purchase_button(button)
	for id in row.options: row.options[id].box.visible = id in shown

func _unit_text(items: Array, caption: String) -> String:
	var lines := PackedStringArray()
	for item in items:
		lines.append("%s · %s G" % [item.name, panel.host._number(int(item.price))])
	return caption + "\n" + ("\n".join(lines) if not lines.is_empty() else "구매한 해당 계열 레시피 필요")
