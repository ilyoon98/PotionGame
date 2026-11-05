extends Window
const Expeditions = preload("res://scripts/parallel_expeditions.gd")
const Content = preload("res://scripts/shop_content.gd")
const ItemArt = preload("res://scripts/item_art.gd")
const PixelIcon = preload("res://scripts/pixel_icon.gd")
const ManagementArt = preload("res://scripts/management_art.gd")
const WorkshopAssets = preload("res://scripts/workshop_assets.gd")
const HerbPlant = preload("res://scripts/herb_plant.gd")
const Status = preload("res://scripts/management_status.gd")
const RewardIcons = preload("res://scripts/reward_icons.gd")
const CurrencyText = preload("res://scripts/currency_text.gd")
const CenteredButtonContent = preload("res://scripts/centered_button_content.gd")
const IngredientIcons = preload("res://scripts/ingredient_icons.gd")
const Rare = preload("res://scripts/rare_recipes.gd")
const Palette = preload("res://scripts/management_palette.gd")
const ContractsScreen = preload("res://scripts/management_contracts.gd")
const Regulars = preload("res://scripts/shop_regulars.gd")
const INK := Palette.TEXT
const MUTED := Palette.MUTED
const OPERATION := 0
const HERBS := 1
const POTIONS := 2
const RECIPES := 3
const EXPEDITIONS := 4
const UPGRADES := 5
const REPORT := 6
const SETTINGS := 7
const TAB_PAGES := [OPERATION, HERBS, POTIONS, RECIPES, EXPEDITIONS, UPGRADES, SETTINGS]
const PANEL_WIDTH := 520
const CONTENT_WIDTH := 480
const CONTENT_TOP := 144
const LIST_ICON_SIZE := 48
const BODY_SIZE := 16
const TITLE_SIZE := 18
const AUX_SIZE := 14
const ROW_LIMIT := 110
var host: Control
var heading: Label
var gold_label: Label
var gold_icon: TextureRect
var gold_caption: Label
var reputation_label: Label
var reputation_icon: TextureRect
var reputation_caption: Label
var header_stats: HBoxContainer
var gold_group: HBoxContainer
var reputation_group: HBoxContainer
var potion_heading: Label
var tabs: Array[Button] = []
var pages: Array[VBoxContainer] = []
var rows := {}
var selected := 0
var statistics_values := {}
var regular_cards := {} # F22 customer id -> card controls on the statistics page
var regular_viewed := {} # customer id -> stage last shown on the statistics page (this window only)
var regular_dot: ColorRect
var collection_values := {} # completion record key -> value label (separate from statistics_values)
var collection_done: Label
var result_button: Button
var close_button: Button
var title_drag_handle: Control
var title_dragging := false
var title_drag_position := Vector2i.ZERO
var title_drag_pointer := Vector2i.ZERO
var scroll: ScrollContainer
var refresh_elapsed := 0.0
var scroll_refresh_pending := false
var page_scroll := {}
var recommend_panel: Panel
var recommend_title: Label
var recommend_effect: RichTextLabel
var recommend_why: Label
var recommend_button: Button
var workshop_goal: Control
var workshop_goal_title: Label
var workshop_goal_gold: RichTextLabel
var workshop_goal_condition: Label
var workshop_goal_bar: ProgressBar
var workshop_goal_button: Button
var workshop_feedback := ""
var recommend_pressed_action := ""
var recommend_pressed_next_level := 0
var recommend_feedback := ""
var feedback_elapsed := 0.0
var operation_materials: Array[String] = []
var operation_regions: Array[String] = []
var recommendation := {}
var snap_gauges := false
var startup_toggle: CheckButton
var startup_status: Label
var sound_toggle: CheckButton
var contracts_view: Control
var contracts_origin := 0
var contracts_origin_scroll := 0
var contract_feedback := ""
var late_feedback := {}
var aging_feedback := ""
var decor_feedback := ""
var keeper_feedback := ""

func _ready() -> void:
	title = "달그늘 물약상점 · 관리"
	# Keep readable controls on smaller monitors too; the list handles the overflow.
	var height := 800
	if DisplayServer.get_name() != "headless":
		height = clampi(DisplayServer.screen_get_usable_rect().size.y - 64, 600, 800)
	size = Vector2i(PANEL_WIDTH, height)
	unresizable = true
	borderless = true
	always_on_top = true
	close_requested.connect(hide)
	visibility_changed.connect(func():
		if not visible: title_dragging = false)
	theme = Palette.build_theme(host.theme)
	theme.default_font_size = BODY_SIZE
	var root := Panel.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = theme
	root.add_theme_stylebox_override("panel", host._style(Palette.BG, Palette.LINE, 8))
	add_child(root)
	title_drag_handle = Control.new()
	title_drag_handle.name = "TitleDragHandle"
	title_drag_handle.size = Vector2(PANEL_WIDTH, 54)
	title_drag_handle.mouse_default_cursor_shape = Control.CURSOR_MOVE
	title_drag_handle.gui_input.connect(_title_drag_input)
	root.add_child(title_drag_handle)
	heading = _label(root, "달그늘 물약상점", Rect2(20, 12, 300, 34), 24)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_theme_font_override("font", host.title_font)
	result_button = _button(root, "통계", Rect2(328, 16, 80, 34), func(): select_page(REPORT))
	result_button.name = "StatisticsButton"
	result_button.tooltip_text = "플레이 시간 · 누적 수입과 운영 기록"
	_header_button_icon(result_button, preload("res://assets/icons/statistics.svg"))
	regular_dot = ColorRect.new()
	regular_dot.name = "RegularNewDot"
	regular_dot.color = Palette.ACTION
	regular_dot.size = Vector2(8, 8)
	regular_dot.position = Vector2(68, 4)
	regular_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	regular_dot.hide()
	result_button.add_child(regular_dot)
	header_stats = HBoxContainer.new()
	header_stats.name = "HeaderStats"
	header_stats.position = Vector2(20, 54)
	header_stats.size = Vector2(CONTENT_WIDTH, 28)
	header_stats.add_theme_constant_override("separation", 24)
	root.add_child(header_stats)
	var coin := ManagementArt.small_icon("coin")
	var gold := _header_metric("GoldGroup", "골드", coin if coin != null else WorkshopAssets.icon("gold-coin"))
	gold_group = gold.group
	gold_icon = gold.icon
	gold_caption = gold.caption
	gold_label = gold.value
	var reputation := _header_metric("ReputationGroup", "명성", ManagementArt.small_icon("reputation"))
	reputation_group = reputation.group
	reputation_icon = reputation.icon
	reputation_caption = reputation.caption
	reputation_label = reputation.value
	gold_label.resized.connect(_update_header_values)
	reputation_label.resized.connect(_update_header_values)
	close_button = _button(root, "닫기", Rect2(420, 16, 80, 34), hide)
	close_button.name = "CloseManagementButton"
	_header_button_icon(close_button, preload("res://assets/icons/management_close.svg"))
	var tab_x := 20.0
	var tab_widths := [84, 52, 52, 64, 52, 96, 56]
	for index in TAB_PAGES.size():
		var page_index: int = TAB_PAGES[index]
		var tab := _button(root, ["가게 운영", "약초", "포션", "레시피", "원정", "가구·직원", "설정"][index], Rect2(tab_x, 90, tab_widths[index], 40), func(): select_page(page_index))
		tab.toggle_mode = true
		tabs.append(tab)
		tab_x += tab_widths[index] + 4
	recommend_panel = Panel.new()
	recommend_panel.position = Vector2(20, CONTENT_TOP - 2)
	recommend_panel.size = Vector2(CONTENT_WIDTH, 180)
	recommend_panel.add_theme_stylebox_override("panel", _divider_style(Palette.LINE))
	root.add_child(recommend_panel)
	recommend_title = _label(recommend_panel, "", Rect2(12, 7, 234, 26), TITLE_SIZE)
	recommend_title.add_theme_font_override("font", host.title_font)
	recommend_title.clip_text = true
	recommend_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	recommend_why = _label(recommend_panel, "", Rect2(10, 32, 220, 22), AUX_SIZE)
	recommend_why.hide()
	recommend_why.add_theme_color_override("font_color", MUTED)
	recommend_effect = _currency_label(recommend_panel, BODY_SIZE, INK)
	recommend_effect.position = Vector2(12, 40)
	recommend_effect.size = Vector2(234, 26)
	recommend_effect.fit_content = false
	recommend_effect.autowrap_mode = TextServer.AUTOWRAP_OFF
	recommend_effect.clip_contents = true
	recommend_effect.mouse_filter = Control.MOUSE_FILTER_PASS
	recommend_button = _button(recommend_panel, "", Rect2(258, 18, 210, 40), _recommendation_selected)
	_purchase_style(recommend_button)
	recommend_button.add_theme_font_size_override("font_size", BODY_SIZE)
	recommend_button.resized.connect(_center_recommendation_button)
	recommend_button.button_down.connect(func():
		recommend_pressed_action = str(recommend_button.get_meta("purchase_key", ""))
		recommend_pressed_next_level = int(recommend_button.get_meta("next_level", 0)))
	workshop_goal = Control.new()
	workshop_goal.position = Vector2(0, 76); workshop_goal.size = Vector2(CONTENT_WIDTH, 104)
	workshop_goal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	recommend_panel.add_child(workshop_goal)
	var goal_divider := ColorRect.new()
	goal_divider.position = Vector2(12, 0); goal_divider.size = Vector2(456, 1)
	goal_divider.color = Palette.LINE; goal_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	workshop_goal.add_child(goal_divider)
	workshop_goal_title = _label(workshop_goal, "", Rect2(12, 6, 300, 26), BODY_SIZE)
	workshop_goal_title.clip_text = true
	workshop_goal_gold = _currency_label(workshop_goal, BODY_SIZE, INK)
	workshop_goal_gold.position = Vector2(12, 36); workshop_goal_gold.size = Vector2(456, 24)
	workshop_goal_gold.fit_content = false
	workshop_goal_condition = _label(workshop_goal, "", Rect2(12, 74, 456, 24), AUX_SIZE)
	workshop_goal_condition.clip_text = true
	workshop_goal_bar = _bar(workshop_goal, Palette.ACTION)
	workshop_goal_bar.position = Vector2(12, 64); workshop_goal_bar.size = Vector2(456, 6)
	workshop_goal_button = _button(workshop_goal, "항목 보기", Rect2(328, 8, 140, 32), _workshop_goal_selected)
	workshop_goal_button.button_down.connect(func(): workshop_goal_button.set_meta("held_level", int(workshop_goal_button.get_meta("next_level", 0))))
	scroll = ScrollContainer.new()
	scroll.position = Vector2(20, CONTENT_TOP)
	scroll.size = Vector2(CONTENT_WIDTH, size.y - 20 - CONTENT_TOP)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	scroll.get_v_scroll_bar().value_changed.connect(func(_value): scroll_refresh_pending = true)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(stack)
	for index in SETTINGS + 1:
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 4 if index == OPERATION else 8)
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stack.add_child(page)
		pages.append(page)
	_section(OPERATION, "포션")
	_row(OPERATION, "craft", "현재 제조", "health")
	# Approved keeper frames; the icon follows awake/asleep/fainted (see _refresh_keeper).
	_row(OPERATION, "keeper", "주인공", "keeper", "근무 방식", _cycle_keeper_policy)
	# Fit the longest label ("명성 1000 필요" with the fame icon); the centered
	# content otherwise keeps the first, shorter label's width and overflows.
	rows.keeper.button.custom_minimum_size.x = 156
	_row(OPERATION, "sale", "판매", "sales_counter")
	_section(OPERATION, "자동 납품")
	_row(OPERATION, "aux_craft", "보조 조제대", "cauldron")
	_row(OPERATION, "contract_summary", "거래처 납품", "sales_assistant", "수주 관리", open_contracts)
	# Approved wall cask art (F21 rest/aging A안).
	_row(OPERATION, "aging", "숙성", "aging_cask")
	_section(OPERATION, "채집")
	for material in Content.DATA["materials"]:
		var id: String = material["id"]
		_row(OPERATION, "gather_" + id, material["name"], id)
	_row(OPERATION, "gather_supply_support", "보급 지원", "growth:herb_storage")
	_section(OPERATION, "원정")
	for region in Content.DATA["regions"]:
		_row(OPERATION, "trip_" + str(region["id"]), region["name"], region["id"])
	potion_heading = _section(POTIONS, "포션 · 보유 / 제작 상태")
	for kind in [false, true] + Content.RECIPES.keys():
		var id := Status.kind_id(kind)
		_row(POTIONS, "potion_" + id, "특별 레시피 · 미발견" if Rare.is_special(id) else Content.lookup("potions", id)["name"], "unknown_recipe" if Rare.is_special(id) else id)
	_section(HERBS, "재료 · 품종별 보유 / 공급")
	_row(HERBS, "supply_support", "보급 지원", "growth:herb_storage")
	for material in Content.DATA["materials"]:
		var id: String = material["id"]
		_row(HERBS, material_row(id), material["name"], id)
	_section(RECIPES, "레시피 · 한 번 구매")
	_row(RECIPES, "basic", "체력", "health")
	_row(RECIPES, "basic_mana", "마나", "mana")
	for id in Content.RECIPES:
		if Rare.is_special(id): continue
		_row(RECIPES, id, Content.RECIPES[id]["name"], id, "배우기", func(): buy(id))
	_section(RECIPES, "특별 레시피 · 원정 발견")
	for id in Content.RECIPES:
		if Rare.is_special(id): _row(RECIPES, id, "특별 레시피 · 미발견", "unknown_recipe", "미발견", func(): buy(id))
	_section(EXPEDITIONS, "지역 · 원정 열기 / 진행")
	for region in Content.DATA["regions"]:
		var id: String = region["id"]
		_row(EXPEDITIONS, id, region["name"], id, "원정 열기", func(): region_action(id))
	_section(UPGRADES, "설비 · 계열 · 훈련")
	var tracks := []
	for entry in Content.DATA["upgrades"]:
		var track: String = entry["track"]
		if tracks.has(track): continue
		tracks.append(track)
		var info := Status.investment(host.state, track)
		_row(UPGRADES, info.target, info.name, "growth:" + track, "강화", func(): buy("upgrade:" + track))
	_row(UPGRADES, "contract_training", "흥정 훈련", "sales_assistant", "훈련", _train_contracts)
	rows.contract_training.button.button_down.connect(func(): _capture_next_level(rows.contract_training.button))
	_section(UPGRADES, "숙성")
	for track in host.state.Aging.TRACKS:
		var aging_id := "aging_" + str(track)
		_row(UPGRADES, aging_id, host.state.Aging.NAMES[track], "aging_cask", "투자", func(): _buy_aging(track))
		var aging_button: Button = rows[aging_id].button
		aging_button.button_down.connect(func(): _capture_next_level(aging_button))
	_section(UPGRADES, "주인공")
	# Placeholder icons until bed/tea-shelf art is approved.
	for track in host.state.keeper.upgrades.TRACKS:
		var keeper_id := "keeper_" + str(track)
		_row(UPGRADES, keeper_id, host.state.keeper.upgrades.NAMES[track], "keeper_sleep" if track == "bed" else "herb", "투자", func(): _buy_keeper(track))
		var keeper_button: Button = rows[keeper_id].button
		keeper_button.button_down.connect(func(): _capture_next_level(keeper_button))
	_section(UPGRADES, "후반 투자")
	for track in Status.LATE_TRACKS:
		var id: String = Status.LATE_INVESTMENT_PREFIX + track
		_row(UPGRADES, id, "보급 지원" if track == "supply_support" else "납품 일괄 조제", "growth:herb_storage" if track == "supply_support" else "cauldron", "투자", func(): _buy_late_investment(track))
		var button: Button = rows[id].button
		button.button_down.connect(func(): _capture_next_level(button))
	for target_level in range(1, 4):
		var id := "workshop_%d" % target_level
		_row(UPGRADES, id, "작업실 운영 확장" if target_level == 1 else "보조 조제대 개선%d" % (target_level - 1), "cauldron", "확장" if target_level == 1 else "개선", func(): _buy_workshop(target_level))
	_section(UPGRADES, "꾸미기")
	for id in host.state.Decor.ORDER:
		_row(UPGRADES, id, host.state.Decor.ITEMS[id].name, id, "구매", func(): _act_decor(id))
	# Souvenirs come from the regulars record; the 12x12 workshop art is an exact 4x in the 48px icon.
	for id in host.state.Decor.souvenir_ids():
		_row(UPGRADES, "decor_" + id, host.state.Decor.souvenir_name(id), id + "_mini", "장착", func(): _act_decor(id))
	_section(UPGRADES, "직원")
	for employee in Content.DATA["employees"]:
		var id: String = employee["id"]
		_row(UPGRADES, "employee" if id == "sales_assistant" else id, employee["name"], id, "고용", func(): buy("staff:" + id))
	_section(SETTINGS, "화면 설정")
	var settings := VBoxContainer.new()
	settings.name = "GameSettings"
	pages[SETTINGS].add_child(settings)
	var companion_entry := _button(settings, "최소모드 · 캐릭터 보기", Rect2(0, 0, 398, 32), host._show_companion_view)
	companion_entry.custom_minimum_size.y = 32
	var information_entry := _button(settings, "정보모드 · 진행 정보만 보기", Rect2(0, 0, 398, 32), host._show_minimal_view)
	information_entry.name = "InformationOnlyButton"
	information_entry.custom_minimum_size.y = 32
	startup_toggle = CheckButton.new()
	startup_toggle.name = "LoginResumeToggle"
	startup_toggle.text = "Windows 로그인마다 게임 자동 실행"
	startup_toggle.custom_minimum_size.y = 42
	startup_toggle.add_theme_font_size_override("font_size", BODY_SIZE)
	startup_toggle.add_theme_color_override("font_color", INK)
	startup_toggle.tooltip_text = "켜 두면 게임을 직접 종료했어도 다음 Windows 로그인 때 자동으로 열어요. 자동 실행을 멈추려면 이 설정을 꺼 주세요."
	settings.add_child(startup_toggle)
	startup_status = Label.new()
	startup_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	startup_status.add_theme_color_override("font_color", MUTED)
	startup_status.add_theme_font_size_override("font_size", BODY_SIZE)
	settings.add_child(startup_status)
	startup_toggle.toggled.connect(_change_startup_setting)
	_refresh_startup_setting()
	_slider(settings, "날씨 효과 강도", 0.0, 1.0, host.state.progression.effects, _change_weather_effects)
	_slider(settings, "밤의 밝기 하한", 0.5, 1.0, host.state.progression.brightness_floor, _change_brightness_floor)
	sound_toggle = CheckButton.new()
	sound_toggle.name = "SoundToggle"
	sound_toggle.text = "효과음"
	sound_toggle.custom_minimum_size.y = 42
	sound_toggle.add_theme_font_size_override("font_size", BODY_SIZE)
	sound_toggle.add_theme_color_override("font_color", INK)
	sound_toggle.tooltip_text = "판매·제조 완료·원정 귀환·해금 때 작은 효과음을 들려줘요. 끄면 소리가 나지 않아요."
	sound_toggle.set_pressed_no_signal(not host.state.audio_muted)
	# Re-sync from the model: a refused change (lost session guard) must not leave the toggle flipped.
	sound_toggle.toggled.connect(func(enabled: bool):
		host.set_audio_muted(not enabled)
		sound_toggle.set_pressed_no_signal(not host.state.audio_muted))
	settings.add_child(sound_toggle)
	_slider(settings, "효과음 크기", 0.0, 1.0, host.state.audio_volume, _change_audio_volume)
	_section(REPORT, "플레이 통계")
	_statistic("play_time", "플레이 시간", TITLE_SIZE, INK, "게임을 켜 둔 누적 시간이에요. 게임을 종료한 시간은 제외해요.")
	_statistic("net", "순영업수입", 22, Palette.ACCENT, "일반 매출과 계약 대금에서 재료비와 원정 출발비를 뺀 금액이에요. 강화·레시피·직원 비용은 포함하지 않아요.")
	_section(REPORT, "수입 · 지출")
	_statistic("sales", "매출")
	_statistic("materials_cost", "재료비")
	_statistic("fees", "원정 출발비")
	_section(REPORT, "누적 운영")
	_statistic("brewed", "물약 제조")
	_statistic("sold", "물약 판매")
	_statistic("expeditions", "완료한 원정")
	_statistic("reputation_gain", "획득 명성")
	_section(REPORT, "자동 납품")
	_statistic("contract_paid", "계약 대금")
	_statistic("contract_shipped", "계약 출고")
	_statistic("contract_rounds", "완료한 납품 회차")
	_section(REPORT, "주인공 · 숙성")
	_statistic("keeper_sleeps", "수면", TITLE_SIZE, INK, "주인공이 잠든 횟수예요. 기절은 따로 세요.")
	_statistic("keeper_faints", "기절", TITLE_SIZE, INK, "피로 100으로 쓰러진 횟수예요.")
	_statistic("fatigue_failed", "피로로 인한 실패", TITLE_SIZE, INK, "피로 페널티가 없었다면 성공했을 실패 물약 수예요.")
	_statistic("aged_sold", "숙성품 판매")
	_statistic("aged_revenue", "숙성 수입")
	_section(REPORT, "수집 기록")
	for row in Status.collection(host.state): _collection_row(row.key, row.caption)
	collection_done = Label.new()
	collection_done.name = "CollectionComplete"
	collection_done.text = "준비된 레시피와 소장품을 모두 모았어요. 가게가 완성됐어요."
	collection_done.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	collection_done.add_theme_font_size_override("font_size", BODY_SIZE)
	collection_done.add_theme_color_override("font_color", Palette.ACTION)
	collection_done.hide()
	pages[REPORT].add_child(collection_done)
	_section(REPORT, "단골 손님")
	for id in Regulars.ids(): _regular_card(id)
	contracts_view = ContractsScreen.new()
	contracts_view.panel = self
	contracts_view.hide()
	root.add_child(contracts_view)
	select_page(OPERATION)


func _refresh_startup_setting() -> void:
	# Read the cached setting only; never query Windows during periodic UI refresh.
	startup_toggle.disabled = host.login_resume.blocked
	startup_toggle.set_pressed_no_signal(host.login_resume.enabled)
	startup_status.text = host.login_resume.status

func _title_drag_hit(point: Vector2) -> bool:
	if not Rect2(Vector2.ZERO, title_drag_handle.size).has_point(point): return false
	for button in [result_button, close_button]:
		if button != null and button.get_rect().has_point(point): return false
	return true

func _title_drag_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT: return
	if not event.pressed:
		_finish_title_drag()
		return
	if not _title_drag_hit(event.position): return
	title_dragging = true
	title_drag_position = position
	if DisplayServer.get_name() != "headless": title_drag_pointer = DisplayServer.mouse_get_position()
	title_drag_handle.accept_event()

func _finish_title_drag() -> void:
	if not title_dragging: return
	title_dragging = false
	# Headless drags never move the native window; only remember real moves.
	if DisplayServer.get_name() != "headless": host.remember_management_position(position)


func _change_startup_setting(value: bool) -> void:
	host.set_login_resume(value)
	_refresh_startup_setting()

func _label(parent: Node, text: String, rect: Rect2, font_size: int) -> Label:
	var node := Label.new()
	node.text = text
	node.position = rect.position
	node.size = rect.size
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", INK)
	parent.add_child(node)
	return node

func _header_metric(id: String, text: String, texture: Texture2D) -> Dictionary:
	var group := HBoxContainer.new()
	group.name = id
	group.custom_minimum_size = Vector2(216, 28)
	group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.add_theme_constant_override("separation", 8)
	header_stats.add_child(group)
	var icon := PixelIcon.new()
	icon.texture = texture
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.custom_minimum_size = Vector2(24, 24)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	group.add_child(icon)
	var caption := Label.new()
	caption.text = text
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", AUX_SIZE)
	caption.add_theme_color_override("font_color", MUTED)
	group.add_child(caption)
	var value := Label.new()
	value.clip_text = true
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.add_theme_font_size_override("font_size", TITLE_SIZE)
	value.add_theme_color_override("font_color", INK)
	group.add_child(value)
	return {"group": group, "icon": icon, "caption": caption, "value": value}

func _update_header_values() -> void:
	if gold_label == null or reputation_label == null: return
	_header_value(gold_label, host.state.gold, "골드")
	_header_value(reputation_label, host.state.progression.reputation, "명성")

func _header_value(label: Label, value: int, caption: String) -> void:
	var full: String = host._number(value)
	var available: float = label.size.x if label.size.x > 0 else 190.0
	var extent := label.get_theme_font("font").get_string_size(full, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE)
	_text(label, full if extent.x <= available else host._compact_number(value))
	label.tooltip_text = caption + " " + full


func _statistic(key: String, caption: String, font_size: int = TITLE_SIZE, color: Color = INK, tooltip: String = "") -> void:
	var panel := PanelContainer.new()
	panel.name = "Statistic_" + key
	panel.custom_minimum_size.y = 42 if key in ["play_time", "net"] else 32
	panel.add_theme_stylebox_override("panel", _divider_style(Palette.LINE))
	panel.tooltip_text = tooltip
	pages[REPORT].add_child(panel)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 16)
	panel.add_child(line)
	var title := Label.new()
	title.text = caption
	title.custom_minimum_size.x = 120
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", BODY_SIZE)
	title.add_theme_color_override("font_color", MUTED)
	line.add_child(title)
	var value := CurrencyText.new()
	value.name = "Value_" + key
	value.money_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.autowrap_mode = TextServer.AUTOWRAP_OFF
	value.fit_content = false
	value.custom_minimum_size.y = 34 if key in ["play_time", "net"] else 28
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	value.appearance(font_size, color)
	line.add_child(value)
	statistics_values[key] = value


func _signed_number(value: int) -> String:
	return ("+" if value > 0 else "−" if value < 0 else "") + host._number(absi(value))

func _center_recommendation_button() -> void:
	if recommend_button != null: CenteredButtonContent.apply(recommend_button)

func _center_purchase_button(button: Button) -> void:
	# Container rows can change width when the scrollbar appears. Re-measure
	# their allocated width, keeping the coin beside the single price.
	if button.autowrap_mode != TextServer.AUTOWRAP_OFF or button.size.x <= 0: return
	var parent := button.get_parent() as Control
	if parent == null or parent.size.x <= 0: return
	var allocated := Vector2(parent.size.x, button.size.y) if button.size_flags_horizontal == Control.SIZE_EXPAND_FILL else button.size
	button.set_meta(CenteredButtonContent.SIZE_META, allocated)
	CenteredButtonContent.apply(button, 12.0, 6)


func _header_button_icon(button: Button, texture: Texture2D) -> void:
	button.icon = texture
	button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	for role in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
		button.add_theme_color_override(role, INK)
	button.add_theme_color_override("icon_disabled_color", MUTED)
	CenteredButtonContent.apply(button, 12.0, 6)

func _currency_label(parent: Node, font_size: int, color: Color) -> RichTextLabel:
	var node := CurrencyText.new()
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.appearance(font_size, color)
	parent.add_child(node)
	return node

func _button(parent: Node, text: String, rect: Rect2, callback: Callable) -> Button:
	var node := Button.new()
	node.text = text
	node.position = rect.position
	node.size = rect.size
	node.add_theme_font_size_override("font_size", BODY_SIZE)
	node.add_theme_color_override("font_color", INK)
	for part in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var fill: Color = Palette.HOVER if part == "hover" else Palette.PRESSED if part in ["pressed", "hover_pressed"] else Palette.SURFACE
		node.add_theme_stylebox_override(part, host._style(fill, Palette.LINE, 5))
	if callback.is_valid(): node.pressed.connect(callback)
	parent.add_child(node)
	return node

func _purchase_style(button: Button) -> void:
	for part in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var fill: Color = {"normal": Palette.ACTION, "hover": Palette.ACTION.lightened(0.08), "pressed": Palette.ACTION.darkened(0.08), "hover_pressed": Palette.ACTION.darkened(0.08), "disabled": Palette.SURFACE}[part]
		button.add_theme_stylebox_override(part, host._style(fill, Palette.LINE if part == "disabled" else Palette.ACTION.darkened(0.25), 5))
	for part in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(part, Palette.ACTION_TEXT)
	button.add_theme_color_override("font_hover_pressed_color", Palette.ACTION_TEXT)
	button.add_theme_color_override("font_disabled_color", MUTED)

func _divider_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = color
	style.border_width_bottom = 1
	return style

func _text_button_style(button: Button, selected: bool = false) -> void:
	for part in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var style := _divider_style(Palette.ACCENT if selected else Palette.LINE)
		style.border_width_bottom = 2 if selected else 1 if part == "hover" else 0
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.content_margin_top = 6
		style.content_margin_bottom = 6
		button.add_theme_stylebox_override(part, style)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = MUTED
	focus.set_border_width_all(1)
	button.add_theme_stylebox_override("focus", focus)
	for part in ["font_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(part, Palette.ACCENT if selected else INK)
	button.add_theme_color_override("font_hover_color", Palette.ACCENT if selected else INK)
	button.set_meta("selected_underline", selected)

## F22: one record card per customer. Points come from completed sales only.
func _collection_row(key: String, caption: String) -> void:
	var panel := PanelContainer.new()
	panel.name = "Collection_" + key
	panel.custom_minimum_size.y = 32
	panel.add_theme_stylebox_override("panel", _divider_style(Palette.LINE))
	pages[REPORT].add_child(panel)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 16)
	panel.add_child(line)
	var title := Label.new()
	title.text = caption
	title.custom_minimum_size.x = 120
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", BODY_SIZE)
	title.add_theme_color_override("font_color", MUTED)
	line.add_child(title)
	var value := Label.new()
	value.name = "Value_" + key
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.add_theme_font_size_override("font_size", TITLE_SIZE)
	value.add_theme_color_override("font_color", INK)
	line.add_child(value)
	collection_values[key] = value


func _regular_card(id: String) -> void:
	var panel := PanelContainer.new()
	panel.name = "Regular_" + id
	panel.add_theme_stylebox_override("panel", _divider_style(Palette.LINE))
	panel.tooltip_text = "실제로 물약을 산 거래만 기록돼요. 일반 거래 1점, 선호 거래 3점이며 기록은 줄지 않아요."
	pages[REPORT].add_child(panel)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	panel.add_child(line)
	var portrait := PixelIcon.new()
	portrait.texture = ManagementArt.icon("regular_" + id)
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(32, 48)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Left column: customer portrait, then the souvenir once the stage gives it.
	var side := VBoxContainer.new()
	side.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	side.add_theme_constant_override("separation", 8)
	line.add_child(side)
	side.add_child(portrait)
	var souvenir := PixelIcon.new()
	souvenir.name = "Souvenir"
	souvenir.texture = ManagementArt.icon(Regulars.STORIES[id].souvenir)
	souvenir.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	souvenir.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	souvenir.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	souvenir.custom_minimum_size = Vector2(32, 32) # Approved display: native 1x.
	souvenir.tooltip_text = "단골 기념품 · " + Regulars.STORIES[id].souvenir_name
	side.add_child(souvenir)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 4)
	line.add_child(body)
	var top := HBoxContainer.new()
	body.add_child(top)
	var title := Label.new()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", BODY_SIZE)
	title.add_theme_color_override("font_color", INK)
	top.add_child(title)
	var badge := Label.new()
	badge.text = "새 이야기"
	badge.add_theme_font_size_override("font_size", AUX_SIZE)
	badge.add_theme_color_override("font_color", Palette.ACTION)
	top.add_child(badge)
	var bar := _bar(body, Palette.ACCENT)
	var progress := Label.new()
	progress.add_theme_font_size_override("font_size", AUX_SIZE)
	progress.add_theme_color_override("font_color", MUTED)
	body.add_child(progress)
	var habits := Label.new()
	habits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	habits.custom_minimum_size.x = CONTENT_WIDTH - 64
	habits.add_theme_font_size_override("font_size", AUX_SIZE)
	habits.add_theme_color_override("font_color", MUTED)
	body.add_child(habits)
	var story := Label.new()
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story.custom_minimum_size.x = CONTENT_WIDTH - 64
	story.add_theme_font_size_override("font_size", AUX_SIZE)
	story.add_theme_color_override("font_color", INK)
	body.add_child(story)
	regular_cards[id] = {"panel": panel, "portrait": portrait, "souvenir": souvenir, "title": title, "badge": badge, "bar": bar, "progress": progress, "habits": habits, "story": story}


func _refresh_regulars(state: RefCounted) -> void:
	for id in regular_cards:
		var card: Dictionary = regular_cards[id]
		var data: Dictionary = state.regulars.view(id)
		# The last stage carries the proposal's record mark.
		_text(card.title, "%s · %s%s" % [data.name, data.stage_name, " ★" if data.next == 0 else ""])
		card.badge.visible = data.new
		card.souvenir.visible = not data.souvenir.is_empty()
		card.bar.value = data.fraction * card.bar.max_value
		_text(card.progress, data.progress)
		_text(card.habits, Regulars.habits(id, state.progression))
		var lines: PackedStringArray = data.lines
		_text(card.story, "아직 거래 기록이 없어요." if lines.is_empty() else "
".join(lines))


func _section(page: int, text: String) -> Label:
	if page == OPERATION:
		var gap := Control.new()
		gap.name = "SectionGap"
		# Include the strip-to-scroll gap for the first section, VBox gaps thereafter.
		gap.custom_minimum_size.y = 8 if pages[page].get_children().is_empty() else 12
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gap.set_meta("section_gap", true)
		pages[page].add_child(gap)
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", BODY_SIZE)
	node.add_theme_font_override("font", host.title_font)
	node.add_theme_color_override("font_color", MUTED)
	pages[page].add_child(node)
	return node

func _bar(parent: Node, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.step = 0.0
	bar.add_theme_font_size_override("font_size", 1)
	bar.custom_minimum_size = Vector2(0, 7)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for part in ["background", "fill"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Palette.SURFACE if part == "background" else color
		style.set_corner_radius_all(2)
		bar.add_theme_stylebox_override(part, style)
	parent.add_child(bar)
	return bar

func _gauge(parent: Node, text: String, color: Color) -> Dictionary:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	parent.add_child(box)
	var caption := Label.new()
	caption.text = text
	caption.custom_minimum_size.x = 32
	caption.add_theme_font_size_override("font_size", AUX_SIZE)
	caption.add_theme_color_override("font_color", MUTED)
	box.add_child(caption)
	var bar := _bar(box, color)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var count := Label.new()
	count.custom_minimum_size.x = 82
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.add_theme_font_size_override("font_size", AUX_SIZE)
	count.add_theme_color_override("font_color", MUTED)
	box.add_child(count)
	return {"box": box, "caption": caption, "bar": bar, "count": count}


func _readable_rewards(list: HFlowContainer) -> void:
	# Reward chips are shared elsewhere; enlarge only this management instance.
	for chip in list.get_children():
		for child in chip.get_children():
			if child is Label and child.get_theme_font_size("font_size") != BODY_SIZE:
				child.add_theme_font_size_override("font_size", BODY_SIZE)

func _row(page: int, id: String, title_text: String, icon_id: String, action: String = "", callback: Callable = Callable()) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = CONTENT_WIDTH - 22
	var style := _divider_style(Palette.LINE)
	for side in ["left", "right", "top", "bottom"]: style.set("content_margin_" + side, 8.0)
	panel.add_theme_stylebox_override("panel", style)
	pages[page].add_child(panel)
	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	panel.add_child(layout)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 4)
	layout.add_child(body)
	var line := HBoxContainer.new()
	body.add_child(line)
	var icon := PixelIcon.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.texture = ItemArt.unknown_recipe_icon() if icon_id == "unknown_recipe" else ManagementArt.readable_icon(ManagementArt.icon(icon_id) if ManagementArt.has_icon(icon_id) else ItemArt.icon(icon_id))
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(LIST_ICON_SIZE, LIST_ICON_SIZE)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layout.add_child(icon)
	layout.move_child(icon, 0)
	var title := Label.new()
	title.text = title_text
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.custom_minimum_size.x = 120
	title.add_theme_font_size_override("font_size", TITLE_SIZE)
	title.add_theme_font_override("font", host.title_font)
	title.add_theme_color_override("font_color", INK)
	line.add_child(title)
	var reputation_marker := PixelIcon.new()
	reputation_marker.texture = ManagementArt.small_icon("reputation")
	reputation_marker.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	reputation_marker.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	reputation_marker.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	reputation_marker.custom_minimum_size = Vector2(20, 20)
	reputation_marker.visible = false
	line.add_child(reputation_marker)
	var badge := Label.new()
	badge.add_theme_font_size_override("font_size", AUX_SIZE)
	badge.add_theme_color_override("font_color", Palette.ACCENT)
	line.add_child(badge)
	var toggle := Button.new()
	toggle.text = "상세"
	toggle.toggle_mode = true
	toggle.add_theme_font_size_override("font_size", BODY_SIZE)
	toggle.custom_minimum_size = Vector2(52, 32)
	_text_button_style(toggle)
	toggle.toggled.connect(func(open): _text_button_style(toggle, open))
	line.add_child(toggle)
	var detail: Control = Label.new() if page == OPERATION else CurrencyText.new()
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if detail is RichTextLabel: detail.appearance(BODY_SIZE, MUTED)
	else:
		detail.add_theme_font_size_override("font_size", BODY_SIZE)
		detail.add_theme_color_override("font_color", MUTED)
	if id in ["craft", "sale"] or page == POTIONS:
		detail.autowrap_mode = TextServer.AUTOWRAP_OFF
		if detail is Label: detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		else: detail.clip_contents = true
		detail.custom_minimum_size.y = 24
	body.add_child(detail)
	var work := _gauge(body, "작업", Palette.TRIP if id.begins_with("trip_") or page == EXPEDITIONS else Palette.ACTION if id == "craft" or page == POTIONS else Palette.ACCENT)
	var stock := _gauge(body, "보유", Palette.ACCENT.darkened(0.15))
	stock["animate"] = true
	var summary := _currency_label(body, BODY_SIZE, INK)
	var button := Button.new()
	button.text = action
	button.visible = not action.is_empty()
	button.add_theme_font_size_override("font_size", BODY_SIZE)
	_purchase_style(button)
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	button.custom_minimum_size = Vector2(120, 32)
	if page in [RECIPES, EXPEDITIONS, UPGRADES]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 40
	if callback.is_valid(): button.pressed.connect(callback)
	body.add_child(button)
	button.resized.connect(func(): _center_purchase_button(button))
	var extra := _currency_label(body, BODY_SIZE, MUTED)
	extra.visible = false
	toggle.toggled.connect(func(open): extra.visible = open)
	panel.set_meta("row_id", id)
	rows[id] = {"panel": panel, "body": body, "page": page, "order": rows.size(), "completed": false, "title": title, "detail": detail, "extra": extra, "toggle": toggle, "icon": icon, "reputation_marker": reputation_marker, "badge": badge, "button": button, "summary": summary, "work": work, "stock": stock, "bar": work.bar, "style": style, "highlighted": false}
	if page in [RECIPES, POTIONS]:
		if Rare.is_special(id.trim_prefix("potion_")):
			panel.custom_minimum_size.y = 210 if page == RECIPES else 190
		if page == RECIPES: summary.custom_minimum_size.y = 24
		var blend_box := VBoxContainer.new()
		blend_box.name = "RecipeBlend"
		blend_box.custom_minimum_size.y = 56
		blend_box.add_theme_constant_override("separation", 2)
		body.add_child(blend_box)
		body.move_child(blend_box, detail.get_index() + 1)
		var blend_title := Label.new()
		blend_title.text = "1병 배합"
		blend_title.add_theme_font_size_override("font_size", BODY_SIZE)
		blend_title.add_theme_color_override("font_color", MUTED)
		blend_box.add_child(blend_title)
		var blend := IngredientIcons.new()
		blend_box.add_child(blend)
		rows[id]["blend_box"] = blend_box
		rows[id]["blend_title"] = blend_title
		rows[id]["blend"] = blend
	if page == EXPEDITIONS:
		panel.custom_minimum_size.y = 148
		detail.hide()
		badge.hide()
		work.caption.add_theme_font_size_override("font_size", BODY_SIZE)
		work.count.add_theme_font_size_override("font_size", BODY_SIZE)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		var primary := HBoxContainer.new()
		primary.add_theme_constant_override("separation", 6)
		body.add_child(primary)
		body.move_child(primary, summary.get_index())
		var primary_icon := PixelIcon.new()
		primary_icon.custom_minimum_size = Vector2(32, 32)
		primary_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		primary_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		primary_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		primary_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		primary.add_child(primary_icon)
		summary.reparent(primary)
		summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var detail_box := VBoxContainer.new()
		detail_box.add_theme_constant_override("separation", 6)
		detail_box.visible = false
		body.add_child(detail_box)
		extra.reparent(detail_box)
		extra.show()
		toggle.toggled.connect(func(open): detail_box.visible = open)
		var result_title := Label.new()
		result_title.add_theme_font_size_override("font_size", BODY_SIZE)
		result_title.custom_minimum_size.y = 24
		detail_box.add_child(result_title)
		var guaranteed_list := RewardIcons.new()
		detail_box.add_child(guaranteed_list)
		var draw_title := Label.new()
		draw_title.text = "추첨 · 아래 후보 중 1~2종"
		draw_title.add_theme_font_size_override("font_size", BODY_SIZE)
		detail_box.add_child(draw_title)
		var reward_list := RewardIcons.new()
		reward_list.custom_minimum_size.y = 24
		detail_box.add_child(reward_list)
		var recipe_title := Label.new()
		recipe_title.text = "조사로 해금할 레시피 · 해금 후 1회 구매"
		recipe_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		recipe_title.add_theme_font_size_override("font_size", BODY_SIZE)
		detail_box.add_child(recipe_title)
		var recipe_list := RewardIcons.new()
		detail_box.add_child(recipe_list)
		detail_box.move_child(extra, detail_box.get_child_count() - 1)
		rows[id]["primary_icon"] = primary_icon
		rows[id]["detail_box"] = detail_box
		rows[id]["result_title"] = result_title
		rows[id]["guaranteed_list"] = guaranteed_list
		rows[id]["reward_list"] = reward_list
		rows[id]["draw_title"] = draw_title
		rows[id]["recipe_title"] = recipe_title
		rows[id]["recipe_list"] = recipe_list
		if not Rare.by_region(id).is_empty():
			panel.custom_minimum_size.y = 188
			var rare_line := HBoxContainer.new()
			rare_line.name = "SpecialRecipeDiscovery"
			rare_line.add_theme_constant_override("separation", 6)
			body.add_child(rare_line)
			body.move_child(rare_line, primary.get_index() + 1)
			var rare_icon := PixelIcon.new()
			rare_icon.texture = ItemArt.unknown_recipe_icon()
			rare_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rare_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			rare_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			rare_icon.custom_minimum_size = Vector2(32, 40)
			rare_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rare_line.add_child(rare_icon)
			var rare_link := Button.new()
			rare_link.text = "특별 레시피 · 미발견"
			rare_link.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rare_link.alignment = HORIZONTAL_ALIGNMENT_LEFT
			rare_link.add_theme_font_size_override("font_size", BODY_SIZE)
			rare_link.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			_text_button_style(rare_link)
			rare_link.pressed.connect(func(): _show_rare_recipe(id))
			rare_line.add_child(rare_link)
			var rare_state := Label.new()
			rare_state.add_theme_font_size_override("font_size", AUX_SIZE)
			rare_state.add_theme_color_override("font_color", MUTED)
			rare_state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			rare_line.add_child(rare_state)
			rows[id]["rare_line"] = rare_line
			rows[id]["rare_icon"] = rare_icon
			rows[id]["rare_link"] = rare_link
			rows[id]["rare_state"] = rare_state

	if page in [OPERATION, HERBS, POTIONS]:
		style.content_margin_top = 6
		style.content_margin_bottom = 6
		body.add_theme_constant_override("separation", 2)
		detail.autowrap_mode = TextServer.AUTOWRAP_OFF
		if detail is Label:
			detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			detail.clip_text = true
		else:
			detail.fit_content = false
			detail.custom_minimum_size.y = 24
			detail.clip_contents = true
		detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		badge.hide()
		if page in [HERBS, POTIONS]:
			# One readable full-width condition, fixed even when work is waiting.
			detail.reparent(body)
			body.move_child(detail, 1)
			if page == HERBS and not ItemArt.growth_path(icon_id).is_empty():
				var growth := PixelIcon.new()
				growth.custom_minimum_size = Vector2(32, 40)
				growth.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				growth.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				growth.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				growth.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				growth.mouse_filter = Control.MOUSE_FILTER_IGNORE
				growth.visible = false
				body.add_child(growth)
				rows[id]["growth_preview"] = growth
				toggle.toggled.connect(func(open): growth.visible = open)

func material_row(id: String) -> String:
	return {"herb": "herb_inventory", "starleaf": "rare_inventory"}.get(id, "material_" + id)

func _text(node: Control, value: String) -> void:
	if node is CurrencyText: node.set_value(value)
	elif node.text != value: node.text = value

func _reputation_condition(row: Dictionary, condition: String) -> void:
	row.reputation_marker.visible = not condition.is_empty()
	row.reputation_marker.tooltip_text = condition

func _purchase_button(row: Dictionary, key: String, action: String, completed: String = "") -> void:
	var reason := Status.purchase_condition(host.state, key)
	CurrencyText.button_value(row.button, completed if not completed.is_empty() else reason if not reason.is_empty() else "%s · %d G" % [action, host.state.purchase_cost(key)])
	row.button.disabled = not completed.is_empty() or not reason.is_empty()
	if reason.contains("명성") and completed.is_empty():
		row.button.icon = ManagementArt.small_icon("reputation")
		row.button.add_theme_constant_override("icon_max_width", 16)
	_center_purchase_button(row.button)

func _gauge_value(gauge: Dictionary, visible: bool, fraction: float, caption: String, count: String = "") -> void:
	gauge.box.visible = visible
	if not visible: return
	_fraction(gauge, fraction)
	_text(gauge.caption, caption)
	_text(gauge.count, count)

func _fraction(gauge: Dictionary, fraction: float, delta: float = 0.0) -> void:
	var value := fraction * 100.0
	var previous: float = gauge.bar.value
	var initialized: bool = gauge.has("target")
	gauge["target"] = value
	if gauge.get("animate", false) and initialized and not snap_gauges and visible and gauge.box.is_visible_in_tree():
		if delta <= 0.0: return
		value = lerpf(previous, value, 1.0 - exp(-delta / 0.10))
		if absf(value - float(gauge.target)) < 0.01: value = gauge.target
	if not is_equal_approx(gauge.bar.value, value): gauge.bar.value = value

func refresh_gauges(delta: float = 0.0) -> void:
	# Read the simulation every frame; never advance clocks or award work in the UI.
	if contracts_view != null and contracts_view.visible: return
	var state: RefCounted = host.state
	var p: RefCounted = state.progression
	if selected in [OPERATION, HERBS]: _refresh_supply_support(state)
	if selected == OPERATION:
		_refresh_workshop_progress(state, true)
		_refresh_keeper(state, true)
		_refresh_aging(state, true)
		var production := Status.production_current(state)
		var remaining := "%.1f초" % production.remaining
		_fraction(rows.craft.work, production.progress)
		_text(rows.craft.work.count, remaining if production.running else "대기")
		_text(rows.craft.detail, production.status + (" · " + remaining + " 남음" if production.running else ""))
		var trading: bool = state.shop_open and p.customer_selected and state.stock > 0 and not state.customer_waiting
		_fraction(rows.sale.work, Status.ratio(state.customer_elapsed, state.customer_interval()) if trading else 0.0)
		var sale_remaining := "%.1f초" % maxf(0.0, state.customer_interval() - state.customer_elapsed)
		_text(rows.sale.work.count, sale_remaining if trading else "대기")
		_text(rows.sale.detail, "영업 휴식" if not state.shop_open else "손님 기다리는 중" if not p.customer_selected else "완성품 기다리는 중" if not trading else sale_remaining + " 남음")
	for source in Content.DATA.materials:
		var id: String = source.id
		if selected != HERBS and not (selected == OPERATION and operation_materials.has(id)): continue
		var data := Status.material(state, id)
		var row: Dictionary = rows[material_row(id) if selected == HERBS else "gather_" + id]
		_fraction(row.work, data.get("display_progress", data.progress) if data.available else 0.0)
		_fraction(row.stock, data.inventory, delta)
		row.work.box.show()
		var remaining: float = maxf(0.0, data.duration - data.get("display_elapsed", data.elapsed)) / maxf(0.0001, data.rate)
		_text(row.work.count, "%.1f초" % remaining if data.running else "대기")
		if data.running and data.pending == 0:
			_text(row.detail, "%s · %.1f초 남음" % [data.action, remaining])
	if selected == POTIONS:
		var progress := Status.ratio(state.brew_elapsed, state.brew_duration())
		var capacity: int = state.capacity()
		for kind in [false, true] + Content.RECIPES.keys():
			var row: Dictionary = rows["potion_" + Status.kind_id(kind)]
			if not _row_on_screen(row): continue
			var known := Status.known_potion(state, kind)
			var active: bool = known and state.brew_active and typeof(kind) == typeof(p.active_recipe) and kind == p.active_recipe
			# Match Status.potion's read-only legacy count without computing
			# purchase conditions, ingredients and production priorities per frame.
			var count: int = state.inventory.count(kind) if state.inventory.size() == state.stock else (state.mana_stock if kind is bool and kind else state.stock - state.mana_stock if kind is bool else 0)
			row.work.box.show()
			_fraction(row.work, progress if active else 0.0)
			_fraction(row.stock, Status.ratio(count, capacity) if known else 0.0, delta)
			var running: bool = active and state.is_brewing()
			var remaining := "%.1f초" % state.brew_remaining_seconds()
			_text(row.work.count, remaining if running else "대기")
			if running:
				_text(row.detail, ("납품 제조 중" if Status.is_contract_batch(state) else "제작 중") + " · " + remaining + " 남음")
	for source in Content.DATA.regions:
		var id: String = source.id
		if selected != EXPEDITIONS and not (selected == OPERATION and operation_regions.has(id)): continue
		var data := Status.region(state, id)
		_fraction(rows[id if selected == EXPEDITIONS else "trip_" + id].work, data.display_progress if data.running or selected == OPERATION else 0.0)

func _highlight(id: String, active: bool, text: String = "") -> void:
	var row: Dictionary = rows[id]
	row.highlighted = active
	_text(row.badge, text if active else "")
	# Favorable weather retains its own accent; the ordinary bottom divider stays.
	var border: Color = Palette.ACCENT if active else Palette.LINE
	var width := 2 if active else 0
	if row.style.border_color != border: row.style.border_color = border
	if row.style.border_width_left != width: row.style.border_width_left = width
	row.panel.tooltip_text = text if active else ""

func _slider(parent: Node, text: String, minimum: float, maximum: float, value: float, callback: Callable) -> void:
	var caption := Label.new()
	caption.text = text
	caption.add_theme_font_size_override("font_size", BODY_SIZE)
	parent.add_child(caption)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 0.05
	slider.value = value
	slider.value_changed.connect(callback)
	parent.add_child(slider)

func select_page(index: int) -> void:
	if index < 0 or index >= pages.size(): return
	if contracts_view != null and contracts_view.visible:
		contracts_view.hide()
		for tab in tabs: tab.show()
		scroll.show()
		_restore_scroll.call_deferred(index, int(page_scroll.get(index, 0)))
	if index != selected:
		page_scroll[selected] = scroll.scroll_vertical
		selected = index
		_restore_scroll.call_deferred(index, int(page_scroll.get(index, 0)))
	for i in pages.size(): pages[i].visible = i == index
	for i in tabs.size():
		tabs[i].set_pressed_no_signal(TAB_PAGES[i] == index)
		_text_button_style(tabs[i], TAB_PAGES[i] == index)
	if index == SETTINGS: _refresh_startup_setting()
	snap_gauges = true
	refresh()
	snap_gauges = false

func open_contracts() -> void:
	if contracts_view == null: return
	if not contracts_view.visible:
		contracts_origin = selected
		contracts_origin_scroll = scroll.scroll_vertical
		page_scroll[selected] = contracts_origin_scroll
	for tab in tabs: tab.hide()
	scroll.hide()
	recommend_panel.hide()
	contracts_view.show()
	contracts_view.refresh()

func close_contracts() -> void:
	if contracts_view == null or not contracts_view.visible: return
	contracts_view.hide()
	for tab in tabs: tab.show()
	scroll.show()
	select_page(contracts_origin)
	_restore_scroll.call_deferred(contracts_origin, contracts_origin_scroll)

func _train_contracts() -> void:
	_perform_contract_training(_next_level_from_button(rows.contract_training.button))
	refresh()

func _capture_next_level(button: Button) -> void:
	button.set_meta("held_next_level", int(button.get_meta("next_level", 0)))

func _next_level_from_button(button: Button) -> int:
	var next_level: int = int(button.get_meta("held_next_level", button.get_meta("next_level", 0)))
	button.remove_meta("held_next_level")
	return next_level

func _perform_contract_training(next_level: int) -> void:
	var result: Dictionary = host.perform_contract_action("train", "", {"next_level": next_level})
	contract_feedback = "" if result.get("ok", false) else str(result.get("error", "훈련 변경을 저장하지 못했어요."))
	if not contract_feedback.is_empty(): rows.contract_training.toggle.set_pressed(true)

func _buy_late_investment(track: String) -> void:
	var row: Dictionary = rows[Status.LATE_INVESTMENT_PREFIX + track]
	_perform_late_investment(track, _next_level_from_button(row.button))
	refresh()

func _buy_workshop(next_level: int) -> void:
	var result: Dictionary = host.perform_workshop_action(next_level)
	workshop_feedback = "" if result.get("ok", false) else str(result.get("error", "작업실 변경 실패"))
	refresh()

func _workshop_goal_selected() -> void:
	var next_level: int = int(workshop_goal_button.get_meta("held_level", workshop_goal_button.get_meta("next_level", 0)))
	workshop_goal_button.remove_meta("held_level")
	if next_level <= 0: return
	if bool(workshop_goal_button.get_meta("can_buy", false)):
		_buy_workshop(next_level)
		return
	select_page(UPGRADES)
	await get_tree().process_frame
	await get_tree().process_frame
	# Override the page's deferred old scroll only after layout has settled.
	if selected == UPGRADES:
		scroll.scroll_vertical = int(rows["workshop_%d" % next_level].panel.position.y)

func _buy_aging(track: String) -> void:
	var result: Dictionary = host.perform_aging_action(track, _next_level_from_button(rows["aging_" + track].button))
	aging_feedback = "" if result.get("ok", false) else str(result.get("error", "숙성 투자를 저장하지 못했어요."))
	refresh()

func _act_decor(id: String) -> void:
	var result: Dictionary = host.perform_decor_action(id)
	decor_feedback = "" if result.get("ok", false) else str(result.get("error", "장식을 바꾸지 못했어요."))
	refresh()


## F23: buy once, then equip or remove for free. No gameplay effect.
func _refresh_decor(state: RefCounted) -> void:
	for id in state.Decor.ORDER:
		var item: Dictionary = state.decor.view(state, id)
		var row: Dictionary = rows[id]
		row.completed = false
		row.work.box.hide(); row.stock.box.hide()
		_text(row.title, str(item.name))
		_text(row.detail, "판매대에 놓여 있어요" if item.equipped else "소장 · 판매대 비어 있음" if item.owned and state.decor.counter_prop().is_empty() else "소장" if item.owned else "판매대 소품")
		_text(row.summary, "작업실 판매대 위에 놓는 장식 · 기능 효과 없음")
		_text(row.extra, "판매대 소품 칸은 1개예요. 다른 소품을 장착하면 바뀌고, 산 소품은 계속 소장해요." + ("
" + decor_feedback if not decor_feedback.is_empty() else ""))
		CurrencyText.button_value(row.button, str(item.reason) if not item.reason.is_empty() else "구매 · %s G" % host._number(int(item.cost)) if not item.owned else str(item.action))
		row.button.disabled = not bool(item.can_act)
		_center_purchase_button(row.button)
	for id in state.Decor.souvenir_ids():
		var item: Dictionary = state.decor.souvenir_view(state, id)
		var row: Dictionary = rows["decor_" + id]
		row.completed = false
		row.work.box.hide(); row.stock.box.hide()
		_text(row.title, "%s · 기념품" % item.name)
		_text(row.detail, "창틀 위에 놓여 있어요" if item.equipped else "소장" if item.owned else "단골 손님에게 받는 기념품")
		_text(row.summary, "작업실 창틀 위에 놓는 장식 · 기능 효과 없음")
		_text(row.extra, "기념품 칸은 1개예요. 해당 손님이 단골(기록 %d) 단계가 되면 받아요." % Regulars.THRESHOLDS[Regulars.SOUVENIR_STAGE - 1] + ("
" + decor_feedback if not decor_feedback.is_empty() else ""))
		CurrencyText.button_value(row.button, str(item.action))
		row.button.disabled = not bool(item.can_act)
		_center_purchase_button(row.button)


func _buy_keeper(track: String) -> void:
	var result: Dictionary = host.perform_keeper_action(track, _next_level_from_button(rows["keeper_" + track].button))
	keeper_feedback = "" if result.get("ok", false) else str(result.get("error", "주인공 투자를 저장하지 못했어요."))
	refresh()

func _refresh_keeper_upgrades(state: RefCounted) -> void:
	var keeper: RefCounted = state.keeper
	for track in keeper.upgrades.TRACKS:
		var item: Dictionary = keeper.upgrades.view(state, track)
		var upgrade: Dictionary = rows["keeper_" + track]
		upgrade.completed = item.complete
		upgrade.work.box.hide(); upgrade.stock.box.hide()
		var reason: String = str(item.reason)
		_text(upgrade.title, "%s · %d/%d단계" % [item.name, item.level, item.max_level])
		_text(upgrade.detail, "구매 완료" if item.complete else "조건 필요" if not reason.is_empty() else "구매 가능")
		_text(upgrade.summary, "현재 %s" % item.current_effect + (" · 다음: " + str(item.next_effect) if not item.complete else ""))
		_text(upgrade.extra, _keeper_days(state) + ("
" + keeper_feedback if not keeper_feedback.is_empty() else ""))
		CurrencyText.button_value(upgrade.button, "최대 단계" if item.complete else reason if not reason.is_empty() else "투자 · %s G" % host._number(int(item.cost)))
		upgrade.button.disabled = not bool(item.can_buy)
		upgrade.button.icon = ManagementArt.small_icon("reputation") if reason.contains("명성") else upgrade.button.icon
		upgrade.button.set_meta("next_level", int(item.next_level))
		_center_purchase_button(upgrade.button)

## Worst-case daily fatigue per policy at the current bed/tea levels.
func _keeper_days(state: RefCounted) -> String:
	var parts := PackedStringArray()
	for id in state.Keeper.POLICY_ORDER:
		var day: Dictionary = state.keeper.daily(id)
		parts.append("%s +%.0f/−%.0f%s" % [state.Keeper.POLICIES[id].name, day.gain, day.recovery, " 상쾌 유지" if day.fresh else " 유지" if day.sustainable else " 누적"])
	return "하루 피로(계속 조제 시) · " + " · ".join(parts)

static func _minutes(seconds: float) -> String:
	var total := int(ceil(maxf(0.0, seconds)))
	return "%d분 %02d초" % [total / 60, total % 60] if total >= 60 else "%d초" % total

func _refresh_aging(state: RefCounted, progress_only: bool = false) -> void:
	var aging: RefCounted = state.aging
	var row: Dictionary = rows.aging
	row.panel.visible = aging.opened()
	if row.panel.visible:
		var target: float = aging.target_seconds()
		var best := 0.0
		var waiting: float = aging.remaining()
		for barrel in aging.barrels: best = maxf(best, float(barrel.elapsed) / target)
		_gauge_value(row.work, true, best, "숙성", "대기" if aging.barrels.is_empty() else "진열 대기" if waiting == INF else _minutes(waiting))
		_text(row.detail, "숙성통 %d/%d · 진열 %d/%d병" % [aging.barrels.size(), aging.barrel_count(), aging.shelf.size(), aging.shelf_capacity()])
		if not progress_only:
			row.stock.box.hide()
			_text(row.summary, "목표 %s · 판매가 ×%.0f · 누적 %s병 %s G" % [aging.STAGE_NAMES[aging.max_stage() - 1], state.Aging.multiplier(aging.max_stage()), host._number(int(aging.totals.sold)), host._number(int(aging.totals.revenue))])
			var lines: Array[String] = []
			for barrel in aging.barrels:
				lines.append("%s 외 %d병 · %s" % [state.Aging.aged_name(barrel.bottles[0], aging.max_stage()), barrel.bottles.size() - 1, "완성 · 진열 대기" if float(barrel.elapsed) >= target - 0.000001 else _minutes(target - float(barrel.elapsed)) + " 남음"])
			_text(row.extra, ("\n".join(lines) if not lines.is_empty() else "판매 재고가 %d병 이상이면 가장 비싼 %d병을 빈 숙성통에 넣어요." % [aging.BATCH, aging.BATCH]) + "\n숙성은 게임이 켜져 있을 때만 진행되고 실패하지 않아요. 손님은 숙성품을 먼저 사요.")
	if progress_only: return
	for track in aging.TRACKS:
		var item: Dictionary = aging.view(state, track)
		var upgrade: Dictionary = rows["aging_" + track]
		upgrade.completed = item.complete
		upgrade.work.box.hide(); upgrade.stock.box.hide()
		var reason: String = str(item.reason)
		_text(upgrade.title, "%s · %d/%d단계" % [item.name, item.level, item.max_level] if item.max_level > 1 else str(item.name))
		_text(upgrade.detail, "구매 완료" if item.complete else "조건 필요" if not reason.is_empty() else "구매 가능")
		_text(upgrade.summary, "다음: " + str(item.next_effect) if not item.complete else "최대 단계")
		_text(upgrade.extra, "오래 걸리지만 비싼 숙성 물약 · 넘치는 판매 재고를 활용해요." + ("\n" + aging_feedback if not aging_feedback.is_empty() else ""))
		CurrencyText.button_value(upgrade.button, "최대 단계" if item.complete else reason if not reason.is_empty() else "투자 · %s G" % host._number(int(item.cost)))
		upgrade.button.disabled = not bool(item.can_buy)
		upgrade.button.icon = ManagementArt.small_icon("reputation") if reason.contains("명성") else upgrade.button.icon
		upgrade.button.set_meta("next_level", int(item.next_level))
		_center_purchase_button(upgrade.button)

func _next_keeper_policy(state: RefCounted) -> String:
	var order: Array = state.Keeper.POLICY_ORDER
	return order[(order.find(state.keeper.policy) + 1) % order.size()]

func _cycle_keeper_policy() -> void:
	if not host._owns_game_session(): return
	if host.state.set_keeper_policy(_next_keeper_policy(host.state)): changed()

func _refresh_keeper(state: RefCounted, gauges_only: bool = false) -> void:
	var row: Dictionary = rows.keeper
	var keeper: RefCounted = state.keeper
	var portrait: Texture2D = ManagementArt.icon("keeper_faint" if keeper.state == "fainted" else "keeper_sleep" if keeper.state == "asleep" else "keeper")
	if row.icon.texture != portrait: row.icon.texture = portrait
	var policies: Dictionary = state.Keeper.POLICIES
	var policy: Dictionary = policies[keeper.policy]
	var left := maxf(0.0, keeper.next_at - state.progression.clock)
	_text(row.title, "주인공 · %s" % policy.name)
	_text(row.detail, "기절 · 회복까지 %.0f초" % left if keeper.state == "fainted" else "수면 중 · %d시 기상 · %.0f초" % [int(policy.wake), left] if keeper.state == "asleep" else "깨어 있음 · %d시 취침" % int(policy.bed))
	_gauge_value(row.work, true, keeper.fatigue / 100.0, "피로", "%d / 100" % int(floor(keeper.fatigue)))
	row.stock.box.hide()
	var cut: float = keeper.penalty() * 100.0
	var effect := "성공률 −%.0f%%p · 기본 물약 −%.1f%%p" % [cut, cut * 0.5] if cut > 0.0 else "제조 속도 +%.0f%%" % ((keeper.FRESH_SPEED - 1.0) * 100.0) if keeper.is_fresh() else "성공률 변화 없음"
	_text(row.summary, "컨디션 %s · %s" % [keeper.condition(), effect])
	if gauges_only: return
	var next := _next_keeper_policy(state)
	var reason: String = state.keeper_policy_reason(next)
	CurrencyText.button_value(row.button, reason if not reason.is_empty() else "다음: %s" % policies[next].name)
	row.button.disabled = not reason.is_empty()
	row.button.icon = ManagementArt.small_icon("reputation") if reason.contains("명성") else null
	if reason.contains("명성"): row.button.add_theme_constant_override("icon_max_width", 16)
	_center_purchase_button(row.button)
	_text(row.extra, "솥은 주인공이 깨어 있을 때만 돌아가요. 판매·채집·원정·보조 조제대는 자는 동안에도 계속돼요.\n규칙적 22~6시 · 바쁘게 0~6시 · 철야 2~6시\n피로 40 미만(상쾌): 깨어 있는 동안 제조 속도 +30%\n피로 40/60/80 이상: 성공률 −3/−10/−20%p (기본 물약은 절반)\n피로 100이면 쓰러져 10시간 동안 회복해요.
" + _keeper_days(state))

func _refresh_workshop_progress(state: RefCounted, progress_only: bool = false) -> void:
	var row: Dictionary = rows.aux_craft
	var status: Dictionary = state.workshop.status(state)
	row.panel.visible = state.workshop.level > 0
	if not row.panel.visible: return
	var remaining := "%.1f초" % maxf(0.0, float(status.duration) - float(status.elapsed))
	if progress_only:
		_fraction(row.work, float(status.progress))
		_text(row.work.count, remaining if status.running else "대기")
		return
	_text(row.title, "보조 조제대 · 납품")
	_text(row.detail, "%s · %d병 · %s 남음" % [status.status, status.quantity, remaining] if status.running else status.status)
	_gauge_value(row.work, true, float(status.progress), "납품 제작", remaining if status.running else "대기")
	row.stock.box.hide(); row.summary.hide()
	_text(row.extra, "%s · 예약 %d병 · %.1f초\n일반 판매 재고에는 들어가지 않아요." % [Content.potion_name(status.kind), status.quantity, status.duration] if status.running else status.status)

func _refresh_workshop(state: RefCounted) -> void:
	var item: Dictionary = state.workshop.view(state)
	# An affordable workshop recommendation already owns the purchase action.
	# Keep the saving goal only when it adds a different next step.
	workshop_goal.visible = not item.complete and recommendation.get("purchase_key", "") != "workshop"
	recommend_panel.size.y = 180 if workshop_goal.visible else 76
	_text(workshop_goal_title, "다음 목표 · " + item.name if not item.complete else "작업실 운영 개선 완료")
	_text(workshop_goal_gold, "%s G / %s G" % [host._number(state.gold), host._number(item.cost)] if not item.complete else "판매·납품 동시 제작")
	workshop_goal_bar.value = Status.ratio(state.gold, item.cost) * 100.0 if not item.complete else 100.0
	_text(workshop_goal_condition, workshop_feedback if not workshop_feedback.is_empty() else str(item.missing[0]) if not item.missing.is_empty() else "저축 중 · 구매하면 바로 자동 운영해요" if not item.can_buy and not item.complete else item.next_effect)
	CurrencyText.button_value(workshop_goal_button, "완료" if item.complete else "확장하기" if item.can_buy and item.level == 0 else "개선하기" if item.can_buy else "항목 보기")
	workshop_goal_button.disabled = item.complete
	workshop_goal_button.set_meta("can_buy", item.can_buy)
	workshop_goal_button.set_meta("next_level", item.next_level)
	_purchase_style(workshop_goal_button) if item.can_buy else _text_button_style(workshop_goal_button)
	for target_level in range(1, 4):
		var row: Dictionary = rows["workshop_%d" % target_level]
		row.completed = state.workshop.level >= target_level
		row.work.box.hide(); row.stock.box.hide()
		var cost: int = state.workshop.COSTS[target_level - 1]
		var reason := "구매 완료" if row.completed else "이전 단계 필요" if target_level != state.workshop.level + 1 else str(item.reason)
		if reason.ends_with("G 부족"): reason = "%s G 부족" % host._number(maxi(0, cost - state.gold))
		_text(row.detail, "구매 완료" if row.completed else "조건 필요" if not reason.is_empty() else "구매 가능")
		_text(row.summary, "%s · 최대 %d병" % [state.workshop.speed_text(target_level), state.workshop.aux_max(state)])
		_text(row.extra, "판매와 납품을 동시에 제작해요.\n" + (" · ".join(PackedStringArray(item.missing)) if not item.missing.is_empty() else "진행 중 배치의 시간과 성공 판정은 유지돼요.") + ("\n" + workshop_feedback if not workshop_feedback.is_empty() else ""))
		CurrencyText.button_value(row.button, reason if not reason.is_empty() else "%s · %s G" % ["확장" if target_level == 1 else "개선", host._number(cost)])
		row.button.disabled = row.completed or target_level != int(item.next_level) or not item.can_buy
		_center_purchase_button(row.button)

func _perform_late_investment(track: String, next_level: int) -> void:
	var result: Dictionary = host.perform_late_investment_action(track, next_level)
	late_feedback[track] = "" if result.get("ok", false) else str(result.get("error", "투자 변경을 저장하지 못했어요."))
	if not str(late_feedback[track]).is_empty() and rows.has(Status.LATE_INVESTMENT_PREFIX + track): rows[Status.LATE_INVESTMENT_PREFIX + track].toggle.set_pressed(true)

func _refresh_late_investments(state: RefCounted) -> void:
	for track in Status.LATE_TRACKS:
		var row: Dictionary = rows[Status.LATE_INVESTMENT_PREFIX + track]
		var data := Status.late_investment(state, track)
		if data.is_empty():
			row.panel.hide()
			continue
		row.panel.show()
		row.completed = int(data.level) >= int(data.max_level)
		_text(row.title, data.name)
		_text(row.detail, "%d/%d단계" % [data.level, data.max_level])
		row.work.box.hide()
		row.stock.box.hide()
		_text(row.summary, data.effect_text)
		var details: String = "부족 조건 · " + " · ".join(PackedStringArray(data.missing)) if not data.missing.is_empty() else "구매 조건 충족" if not row.completed else "최대 단계"
		if track == "supply_support":
			var supply := Status.supply_support(state)
			details += "\n실행 중 주기마다 부족한 특수 재료 한 종류를 보급해요.\n실제 누적 입고 %s개 · 진행 중 예약 수량 %d개\n중간 강화는 다음 주기부터 적용돼요." % [host._number(int(supply.get("total_received", 0))), int(supply.get("reserved_quantity", 0))]
		else: details += "\n재료·남은 주문량에 따라 감소 · 일반 제조는 1병을 유지해요.\n진행 중 납품 배치의 예약 병수는 바뀌지 않아요."
		var feedback: String = str(late_feedback.get(track, ""))
		_text(row.extra, details + ("\n" + feedback if not feedback.is_empty() else ""))
		var reason: String = str(data.reason)
		CurrencyText.button_value(row.button, "최대 단계" if row.completed else reason if not reason.is_empty() else "투자 · %s G" % host._number(int(data.cost)))
		row.button.disabled = not bool(data.can_buy)
		row.button.set_meta("next_level", int(data.next_level))
		row.button.tooltip_text = "최대 %d단계 · %s\n%s" % [data.max_level, data.current_effect, details] if row.completed else "다음 단계 %d · %s G\n%s" % [data.next_level, host._number(int(data.cost)), details]
		_center_purchase_button(row.button)

func _refresh_supply_support(state: RefCounted) -> void:
	var data := Status.supply_support(state)
	for id in ["gather_supply_support", "supply_support"]:
		var row: Dictionary = rows[id]
		row.panel.visible = bool(data.purchased)
		if not data.purchased: continue
		_text(row.title, "보급 지원 · %d단계" % int(data.get("level", 0)))
		var remaining: float = maxf(0.0, float(data.duration) - float(data.elapsed))
		_text(row.detail, "보급 중 · %.1f초" % remaining if str(data.status).begins_with("보급 중") else str(data.status))
		_gauge_value(row.work, true, float(data.progress), "보급", "%.1f초" % remaining)
		row.stock.box.hide()
		row.summary.hide()
		_text(row.extra, "진행 주기 예약 최대 %d개 · 실제 누적 입고 %s개\n빈 보관 공간만 채우며 초과분은 적립하지 않아요." % [data.reserved_quantity, host._number(int(data.total_received))])

func _refresh_contracts(state: RefCounted, visible_only: bool = false) -> void:
	var model: RefCounted = state.contracts
	if not visible_only or selected == OPERATION:
		var unlocked: bool = model.unlocked(state)
		var summary: Dictionary = rows.contract_summary
		var shipped := 0
		var required := 0
		var active := 0
		var statuses := PackedStringArray()
		for partner in model.PARTNERS:
			var view: Dictionary = model.partner_view(state, partner.id)
			shipped += int(view.shipped)
			required += int(view.required)
			active += int(view.active)
			statuses.append(view.name + " · " + view.status)
		_text(summary.detail, "%d곳 자동 납품 · %d/%d병" % [active, shipped, required] if unlocked else "별의 정원 개방 필요")
		var delivery_running: bool = (state.brew_active and model.batch.get("purpose") == "contract") or not state.workshop.aux.is_empty()
		if unlocked and active > 0 and not delivery_running:
			if state.stock_protection.active: _text(summary.detail, "판매 재고 확보 중 · %d/%d병" % [shipped, required])
			elif model.candidate(state, state.stock_protection.reserve_materials(state), true).is_empty(): _text(summary.detail, "판매 재료 확보 중 · %d/%d병" % [shipped, required])
		_gauge_value(summary.work, true, Status.ratio(shipped, required), "납품", "%d/%d병" % [shipped, required])
		# Delivery reflects completed bottles only, without the manufacturing interpolation.
		summary.work.bar.value = Status.ratio(shipped, required) * 100.0
		summary.stock.box.hide()
		summary.summary.hide()
		summary.detail.show()
		summary.button.disabled = false
		_text(summary.extra, "\n".join(statuses) + ("\n판매·납품 동시 제작 · 완료 대금 자동 정산" if state.workshop.level > 0 else "\n판매 재고·재료를 확보한 뒤 자동 납품 · 완료 대금 자동 정산"))
	if not visible_only or selected == UPGRADES:
		var training: Dictionary = model.training_view(state)
		var row: Dictionary = rows.contract_training
		row.completed = training.level >= training.max_level
		_text(row.detail, "%d/%d단계" % [training.level, training.max_level])
		_gauge_value(row.work, true, Status.ratio(training.level, training.max_level), "단계", "%d/%d" % [training.level, training.max_level])
		row.stock.box.hide()
		_text(row.summary, "일반 흥정 %.0f%%" % (float(training.chance) * 100.0) + (" → %.0f%%" % (float(training.next_chance) * 100.0) if not row.completed else " · 최대 훈련") + "\n최종 등급 %.0f%% 확정" % (float(training.final_chance) * 100.0))
		_text(row.extra, "앞으로 적용 가능한 흥정 %d회\n일반 흥정 %.0f%% → %.0f%%\n등급을 건너뛰면 적용 횟수가 줄 수 있어요." % [int(training.get("remaining_opportunities", 0)), float(training.chance) * 100.0, float(training.next_chance) * 100.0] + ("\n" + contract_feedback if not contract_feedback.is_empty() else ""))
		var reason: String = str(training.reason)
		CurrencyText.button_value(row.button, "최대 단계" if row.completed else reason if not reason.is_empty() else "훈련 · %s G" % host._number(int(training.cost)))
		row.button.disabled = not bool(training.can_buy)
		row.button.set_meta("next_level", int(training.get("next_level", int(training.level) + 1)))
		row.button.tooltip_text = str(training.reason)
		_center_purchase_button(row.button)
	if contracts_view.visible: contracts_view.refresh()

func _restore_scroll(page: int, value: int) -> void:
	# A short results page can still own the scrollbar range during tab layout.
	await get_tree().process_frame
	_apply_page_scroll.call_deferred(page, value)

func _apply_page_scroll(page: int, value: int) -> void:
	if selected == page: scroll.scroll_vertical = value

func _recommendation_selected() -> void:
	var key := recommend_pressed_action if not recommend_pressed_action.is_empty() else str(recommend_button.get_meta("purchase_key", ""))
	var next_level: int = recommend_pressed_next_level if not recommend_pressed_action.is_empty() else int(recommend_button.get_meta("next_level", 0))
	recommend_pressed_action = ""
	recommend_pressed_next_level = 0
	if key.is_empty(): return
	if key == "workshop":
		_buy_workshop(next_level)
		return
	if key == Status.CONTRACT_TRAINING_KEY:
		_perform_contract_training(next_level)
		recommend_feedback = contract_feedback
		feedback_elapsed = 2.0 if not recommend_feedback.is_empty() else 0.0
		refresh()
		return
	if key.begins_with(Status.AGING_PREFIX) or key.begins_with(Status.KEEPER_PREFIX):
		var aging := key.begins_with(Status.AGING_PREFIX)
		var result: Dictionary = host.perform_aging_action(key.trim_prefix(Status.AGING_PREFIX), next_level) if aging else host.perform_keeper_action(key.trim_prefix(Status.KEEPER_PREFIX), next_level)
		recommend_feedback = "" if result.get("ok", false) else str(result.get("error", "투자를 저장하지 못했어요."))
		feedback_elapsed = 2.0 if not recommend_feedback.is_empty() else 0.0
		refresh()
		return
	if key.begins_with(Status.LATE_INVESTMENT_PREFIX):
		var track := key.trim_prefix(Status.LATE_INVESTMENT_PREFIX)
		_perform_late_investment(track, next_level)
		recommend_feedback = str(late_feedback.get(track, ""))
		feedback_elapsed = 2.0 if not recommend_feedback.is_empty() else 0.0
		refresh()
		return
	if key.begins_with("upgrade:") and int(host.state.track_level(key.trim_prefix("upgrade:"))) + 1 != next_level:
		recommend_feedback = "강화 단계가 변경되었어요"
		feedback_elapsed = 2.0
		refresh()
		return
	recommend_feedback = Status.condition_text(host.state.purchase_reason(key))
	if (key == "expedition" and host.state.progression.expedition_unlocked) or (key.begins_with("region:") and Expeditions.opened(key.trim_prefix("region:"), host.state.progression)): recommend_feedback = "열림"
	feedback_elapsed = 2.0 if not recommend_feedback.is_empty() else 0.0
	buy(key)

func changed() -> void:
	host._update_interface()
	host._save()
	refresh()

func _change_weather_effects(value: float) -> void:
	if not host._owns_game_session(): return
	host.state.progression.effects = value
	changed()

## Live volume; the regular autosave and the exit save keep it.
func _change_audio_volume(value: float) -> void:
	host.set_audio_volume(value)


func _change_brightness_floor(value: float) -> void:
	if not host._owns_game_session(): return
	host.state.progression.brightness_floor = value
	changed()

func buy(kind: String) -> void:
	if not host._owns_game_session(): return
	var unlocks: int = host.state.progression.totals["unlocks"]
	host.state.purchase(kind)
	if host.state.progression.totals["unlocks"] > unlocks: host.play_sound("unlock")
	changed()

func region_action(id: String) -> void:
	if Expeditions.opened(id, host.state.progression): return
	buy("expedition" if id == "forest_edge" else "region:" + id)

func _process(delta: float) -> void:
	if not visible: return
	if title_dragging:
		if DisplayServer.get_name() != "headless":
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): position = host.drag_in_work_area(title_drag_position + DisplayServer.mouse_get_position() - title_drag_pointer, size)
			else: _finish_title_drag()
		return
	refresh_elapsed = minf(refresh_elapsed + delta, 0.2)
	if host.workshop_dragging: return
	feedback_elapsed = maxf(0.0, feedback_elapsed - delta)
	if feedback_elapsed == 0.0: recommend_feedback = ""
	refresh_gauges(delta)
	if refresh_elapsed >= 0.2 or scroll_refresh_pending:
		refresh_elapsed = 0.0
		scroll_refresh_pending = false
		refresh(true)

func _row_on_screen(row: Dictionary) -> bool:
	# Scrolled-out recipe lists can contain dozens of expensive projections.
	# Full refreshes initialize them; scrolling refreshes newly exposed rows.
	return row.panel.get_global_rect().intersects(scroll.get_global_rect())

func _display_material(id: String, data: Dictionary, operation: bool) -> void:
	var row: Dictionary = rows[id]
	row.panel.visible = data.available and operation_materials.has(data.icon) if operation else true
	var remaining: float = maxf(0.0, data.duration - data.get("display_elapsed", data.elapsed)) / maxf(0.0001, data.rate)
	_text(row.detail, ("%s · %.1f초 남음" % [data.action, remaining] if data.running and data.pending == 0 else data.status if data.pending == 0 else "재료 보관 대기 %d" % data.pending) if operation else Status.material_primary(host.state, data.icon, data))
	_gauge_value(row.work, true, data.get("display_progress", data.progress) if data.available else 0.0, data.action, "%.1f초" % remaining if data.running else "대기")
	_gauge_value(row.stock, true, data.inventory, "보유", "%d/%d" % [data.count, data.capacity])
	if operation: row.stock.box.hide()
	row.detail.show()
	row.summary.hide()
	row.stock.box.tooltip_text = "이 약초 품종의 보관량과 한도예요. 다른 품종의 보관과는 별개예요."
	if row.has("growth_preview"):
		row.growth_preview.texture = ItemArt.growth_frame(data.icon, data.get("display_progress", data.progress) if data.supplied else 0.0)
		row.growth_preview.tooltip_text = data.name + (" · 재배 중" if data.running else " · " + data.status)
	_text(row.extra, data.condition + "\n공급 %.1f/%.1f · 성장 ×%.2f
재료 보관 대기 %d · 보관 한도 %d" % [data.elapsed, data.duration, data.rate, data.pending, data.capacity])
	var source := Content.lookup("materials", data.icon)
	if source.has("region"):
		var key: String = "expedition" if source.region == "forest_edge" else "region:" + str(source.region)
		var reason := Status.purchase_condition(host.state, key)
		_text(row.extra, row.extra.source_text + "\n원정 조달 · " + str(Content.lookup("regions", source.region).name) + " · " + ("자동 원정" if Expeditions.opened(source.region, host.state.progression) else reason if not reason.is_empty() else "원정 탭에서 열기 가능"))
	_highlight(id, data.favored, "환경 성장 ↑")

func _display_expedition(id: String, data: Dictionary) -> void:
	var row: Dictionary = rows[id]
	var state: RefCounted = host.state
	var conditions := Status.region_card_conditions(state, id)
	var status := Status.region_status(state, id)
	if status == "출발비 부족" and conditions.contains("다음 출발 대기"): status = "다음 출발 대기"
	row.completed = data.available
	row.detail.hide()
	row.stock.box.hide()
	row.reputation_marker.hide()
	_gauge_value(row.work, data.available, data.display_progress if data.running else 0.0, status, "%.0f초 남음" % maxf(0.0, data.duration - data.display_elapsed) if data.running else "")
	row.button.visible = not data.available
	if not data.available:
		_purchase_button(row, "expedition" if id == "forest_edge" else "region:" + id, "원정 열기")
	var guaranteed := []
	var optional := []
	var recipes := []
	for entry in Status.region_preview(state, id):
		if entry.kind == "material":
			var item: Dictionary = entry.duplicate(true)
			item["range_only"] = true
			if entry.guaranteed: guaranteed.append(item)
			else: optional.append(item)
		elif not entry.id.begins_with("rare_") and not state.progression.owned.has(entry.id):
			var item: Dictionary = entry.duplicate(true)
			var discovery: Dictionary = Content.lookup("potions", entry.id).unlock.discovery
			item.status = "%d/%d회" % [mini(data.returns, int(discovery.returns)), int(discovery.returns)]
			recipes.append(item)
	var main: Dictionary = guaranteed[0]
	row.primary_icon.texture = ItemArt.icon(main.id)
	_text(row.summary, "주재료 %s %d~%d개 · 매회 %d G" % [Content.lookup("materials", main.id).name, main.min, main.max, data.fee])
	_text(row.result_title, "획득 재료 · 보장")
	row.guaranteed_list.show_entries(guaranteed)
	row.reward_list.show_entries(optional)
	row.recipe_list.show_entries(recipes)
	row.recipe_title.visible = not recipes.is_empty()
	row.recipe_list.visible = not recipes.is_empty()
	for list in [row.guaranteed_list, row.reward_list, row.recipe_list]: _readable_rewards(list)
	_text(row.extra, conditions)
	if data.has("timing"): _text(row.extra, row.extra.source_text + "\n" + str(data.timing.text))
	if row.has("rare_line"):
		var discovery: Dictionary = Rare.preview(id, state.progression)
		row.rare_icon.texture = ItemArt.recipe_icon(discovery.id) if discovery.known else ItemArt.unknown_recipe_icon()
		_text(row.rare_link, discovery.name)
		row.rare_link.disabled = not discovery.known
		row.rare_link.tooltip_text = "레시피 탭에서 확인" if discovery.known else "이 지역 원정에서 특별 레시피를 찾아요."
		_text(row.rare_state, "구매 완료" if discovery.owned else "발견 · 미구매" if discovery.known else "")
		var discovery_detail := "특별 레시피 · " + ("구매 완료" if discovery.owned else "발견 · 레시피 탭에서 구매" if discovery.known else "미발견")
		if not discovery.known:
			discovery_detail += "\n발견 확률 %.0f%% · 유효 완료 %d/%d회 보장" % [float(discovery.chance) * 100.0, int(discovery.failures), int(discovery.guarantee)]
		_text(row.extra, row.extra.source_text + "\n" + discovery_detail)
	var special: bool = data.get("mode", "normal") == "special" or (not data.running and data.get("next_mode", "") == "special")
	if special:
		row.primary_icon.texture = ItemArt.unknown_recipe_icon()
		_text(row.summary, "특별 탐색 · 매회 %d G" % data.fee)
		_text(row.result_title, "특별 탐색 회차 · 재료 보상 없음")
	row.guaranteed_list.visible = not special
	row.reward_list.visible = not special
	row.draw_title.visible = not special
	if special: _text(row.extra, row.extra.source_text + "\n이 회차는 특별 발견만 진행하며 일반 재료를 지급하지 않아요.")


func _known_recipe(id: String) -> bool:
	return not Rare.is_special(id) or Rare.is_discovered(id, host.state.progression)


func _show_rare_recipe(region: String) -> void:
	var info := Rare.preview(region, host.state.progression)
	if not info.known: return
	select_page(RECIPES)
	_reveal_recipe_row.call_deferred(str(info.id))


func _reveal_recipe_row(id: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if selected == RECIPES and visible and rows.has(id): scroll.ensure_control_visible(rows[id].panel)


func _recipe_blend(row: Dictionary, kind: Variant, known: bool = true) -> void:
	row.blend_title.visible = known
	row.blend.show_ingredients(host.state, kind, known)
	row.blend_box.tooltip_text = IngredientIcons.detail_text(row.blend.entries) if known else "특별 레시피를 발견하면 배합을 확인할 수 있어요."


func _masked_recipe_row(row: Dictionary, id: String) -> void:
	var info := Rare.recipe_info(id, host.state.progression)
	row.completed = false
	_text(row.title, info.name)
	row.icon.texture = ItemArt.unknown_recipe_icon()
	var hidden_text := str(Content.lookup("regions", info.region).name) + " · 원정 발견 필요"
	row.panel.tooltip_text = hidden_text
	row.title.tooltip_text = hidden_text
	row.icon.tooltip_text = hidden_text
	_text(row.detail, hidden_text)
	if row.page == RECIPES: row.summary.show()
	else: row.summary.hide()
	_text(row.summary, "")
	_text(row.extra, "특별 레시피를 발견하면 이름과 배합을 확인할 수 있어요.")
	row.extra.tooltip_text = row.extra.source_text
	row.reputation_marker.hide()
	_recipe_blend(row, id, false)
	if row.page == RECIPES:
		row.work.box.hide()
		row.stock.box.hide()
		CurrencyText.button_value(row.button, "원정 발견 필요")
		row.button.disabled = true
		row.button.tooltip_text = hidden_text
		_center_purchase_button(row.button)
	else:
		_gauge_value(row.work, true, 0.0, "제조", "대기")
		_gauge_value(row.stock, true, 0.0, "보유", "0개")
	_highlight(str(row.panel.get_meta("row_id")), false)

func refresh(visible_only: bool = false) -> void:
	# Periodic updates touch the open page and skip scrolled-out recipe rows.
	# Explicit refreshes still initialize the complete presentation.
	if heading == null: return
	var state: RefCounted = host.state
	var p: RefCounted = state.progression
	_update_header_values()
	if visible_only and contracts_view != null and contracts_view.visible:
		contracts_view.refresh()
		return
	_text(potion_heading, "포션 · 공용 창고 %d/%d" % [state.stock, state.capacity()])
	var contracts_open: bool = contracts_view != null and contracts_view.visible
	recommend_panel.visible = selected == OPERATION and not contracts_open
	scroll.position.y = recommend_panel.position.y + recommend_panel.size.y + 8 if recommend_panel.visible else CONTENT_TOP
	scroll.size.x = CONTENT_WIDTH
	scroll.size.y = size.y - 20 - scroll.position.y
	if not visible_only or selected == OPERATION:
		recommendation = Status.recommendation(state)
		_refresh_workshop(state)
		_refresh_workshop_progress(state)
		_refresh_keeper(state)
		_refresh_aging(state)
		scroll.position.y = recommend_panel.position.y + recommend_panel.size.y + 8 if recommend_panel.visible else CONTENT_TOP
		scroll.size.y = size.y - 20 - scroll.position.y
		if not recommendation.is_empty():
			_text(recommend_title, "성장 추천 · " + recommendation.name)
			_text(recommend_effect, recommend_feedback if not recommend_feedback.is_empty() else Status.recommendation_purpose(recommendation, state))
			recommend_effect.tooltip_text = recommend_feedback if not recommend_feedback.is_empty() else recommendation.effect + "\n" + recommendation.why
			CurrencyText.button_value(recommend_button, "%s · %s G" % [recommendation.action, host._number(recommendation.cost)])
			recommend_button.disabled = false
			recommend_button.set_meta("purchase_key", recommendation.purchase_key)
			recommend_button.set_meta("target", recommendation.target)
			recommend_button.set_meta("next_level", int(recommendation.get("next_level", 0)))
		else:
			_text(recommend_title, "성장 추천")
			_text(recommend_effect, recommend_feedback if not recommend_feedback.is_empty() else "지금 구매할 수 있는 항목이 없어요")
			CurrencyText.button_value(recommend_button, "구매 대기")
			recommend_button.disabled = true
			recommend_button.set_meta("purchase_key", "")
			recommend_button.set_meta("target", "")
			recommend_button.set_meta("next_level", 0)
		_center_recommendation_button()
		# Two stable representatives from each source; full lists stay in their tabs.
		operation_materials.clear()
		operation_regions.clear()
		for source in Content.DATA.materials:
			if Status.material(state, source.id).available and operation_materials.size() < 2: operation_materials.append(source.id)
		for source in Content.DATA.regions:
			if Expeditions.opened(source.id, p) and operation_regions.size() < 2: operation_regions.append(source.id)
		var active: String = Status.kind_id(p.active_recipe)
		var craft: Dictionary = rows.craft
		_text(craft.title, (state.recipe_name() if _known_recipe(active) else "특별 레시피 · 미발견") + " · 제조")
		craft.icon.texture = ManagementArt.readable_icon(ItemArt.icon(active)) if _known_recipe(active) else ItemArt.unknown_recipe_icon()
		var production := Status.production_current(state)
		_text(craft.detail, production.status + (" · %.1f초 남음" % production.remaining if production.running else ""))
		_gauge_value(craft.work, true, production.progress, "납품 제조" if production.purpose == "contract" else "제조", "대기" if not production.running else "%.1f초" % production.remaining)
		_gauge_value(craft.stock, true, Status.ratio(state.stock, state.capacity()), "재고", "%d/%d" % [state.stock, state.capacity()])
		craft.detail.visible = true
		craft.stock.box.hide()
		craft.summary.hide()
		_text(craft.extra, "재고 %d/%d · 현재 배치 %.1f/%.1f초 · 예약 성공률 %.0f%%" % [state.stock, state.capacity(), state.brew_elapsed, state.brew_duration(), p.batch_chance * 100])
		var sale: Dictionary = rows.sale
		var trading: bool = state.shop_open and p.customer_selected and state.stock > 0 and not state.customer_waiting
		sale.panel.visible = true
		_text(sale.detail, "영업 휴식" if not state.shop_open else "손님 기다리는 중" if not p.customer_selected else "완성품 기다리는 중" if not trading else "%.1f초 남음" % maxf(0.0, state.customer_interval() - state.customer_elapsed))
		_gauge_value(sale.work, true, Status.ratio(state.customer_elapsed, state.customer_interval()) if trading else 0.0, "판매", "%.1f초" % maxf(0.0, state.customer_interval() - state.customer_elapsed) if trading else "대기")
		sale.detail.visible = true
		_text(sale.title, "판매 · " + str(Content.CUSTOMERS[p.customer]["name"]) if p.customer_selected else "판매")
		sale.stock.box.hide()
		sale.summary.hide()
		_text(sale.extra, "실제 거래 주기 %.2f초 · 거래 예약이나 결제는 이 화면에서 하지 않아요" % state.customer_interval())
	for kind in [false, true] + Content.RECIPES.keys():
		if visible_only and selected != POTIONS: continue
		var id: String = "potion_" + Status.kind_id(kind)
		var row: Dictionary = rows[id]
		if visible_only and not _row_on_screen(row): continue
		if not _known_recipe(Status.kind_id(kind)):
			_masked_recipe_row(row, Status.kind_id(kind))
			continue
		var data := Status.potion(state, kind)
		_text(row.title, Content.potion_name(kind))
		row.icon.texture = ManagementArt.readable_icon(ItemArt.icon(Status.kind_id(kind)))
		row.panel.tooltip_text = Content.potion_name(kind)
		row.title.tooltip_text = Content.potion_name(kind)
		row.icon.tooltip_text = Content.potion_name(kind)
		_recipe_blend(row, kind)
		row.panel.visible = true
		row.detail.visible = true
		_text(row.detail, Status.potion_primary(state, kind, data))
		_gauge_value(row.work, true, data.work.get("progress", 0.0), "제조", "대기" if not data.active or not state.is_brewing() else "%.1f초" % state.brew_remaining_seconds())
		_gauge_value(row.stock, true, data.inventory, "보유", "%d개" % data.count)
		row.stock.box.tooltip_text = "공용 물약 창고 한도 %d개 중 이 품목의 보유량이에요. 품목별 목표량이 아니에요." % data.capacity
		row.summary.hide()
		_text(row.extra, data.condition + "\n" + IngredientIcons.detail_text(row.blend.entries) + "\n현재 환경 성공률 %.0f%% · %s" % [data.chance * 100, "현재 제조 배치의 예약 판정" if data.active else "다음 배치 기준"])
		row.extra.tooltip_text = row.extra.source_text
		_highlight(id, data.favored, "환경 성공 ↑")
	for material in Content.DATA["materials"]:
		if visible_only and selected not in [OPERATION, HERBS]: continue
		var id: String = material["id"]
		var data := Status.material(state, id)
		if not visible_only or selected == OPERATION: _display_material("gather_" + id, data, true)
		if not visible_only or selected == HERBS: _display_material(material_row(id), data, false)
	for id in Content.RECIPES:
		if visible_only and selected != RECIPES: continue
		var row: Dictionary = rows[id]
		if visible_only and not _row_on_screen(row): continue
		if not _known_recipe(id):
			_masked_recipe_row(row, id)
			continue
		_text(row.title, Content.potion_name(id))
		# Special recipes and F26/F27 rows have approved 32x40 recipe icons; older rows reuse the potion icon.
		row.icon.texture = ItemArt.recipe_icon(id) if Rare.is_special(id) or Content.lookup("potions", id).has("recipe_candidate") else ManagementArt.readable_icon(ItemArt.icon(id))
		row.panel.tooltip_text = Content.potion_name(id)
		row.title.tooltip_text = Content.potion_name(id)
		row.icon.tooltip_text = Content.potion_name(id)
		row.button.tooltip_text = Content.potion_name(id) + " · 레시피 구매"
		_recipe_blend(row, id)
		var reason: String = Status.purchase_condition(state, id)
		var source := Content.lookup("potions", id)
		row.completed = p.owned.has(id)
		_reputation_condition(row, "명성 %d 필요" % int(Content.RECIPES[id].reputation) if int(Content.RECIPES[id].reputation) > 0 else "")
		_text(row.detail, "구매 완료" if p.owned.has(id) else reason)
		row.work.box.hide()
		row.stock.box.hide()
		_text(row.summary, "%d G · 판매 %d G · 명성 %d" % [state.purchase_cost(id), Content.RECIPES[id]["price"], Content.RECIPES[id]["reputation"]])
		_text(row.extra, IngredientIcons.detail_text(row.blend.entries) + "\n성공률 %.0f%% · 구매 후 자동 제작 합류" % (p.success_chance(id) * 100))
		row.extra.tooltip_text = row.extra.source_text
		_purchase_button(row, id, "구매하기", "구매 완료" if p.owned.has(id) else "")
		_highlight(id, p.environment_bonus(id) > 0.0001, "환경 성공 ↑")
	for basic in [{"id": "basic", "kind": false}, {"id": "basic_mana", "kind": true}]:
		if visible_only and selected != RECIPES: continue
		var row: Dictionary = rows[basic.id]
		if visible_only and not _row_on_screen(row): continue
		row.work.box.hide()
		row.stock.box.hide()
		row.summary.hide()
		row.completed = true
		_text(row.detail, "기본 레시피 · 구매 완료")
		_recipe_blend(row, basic.kind)
		_text(row.extra, IngredientIcons.detail_text(row.blend.entries))
	var tracks := []
	for entry in Content.DATA["upgrades"]:
		if visible_only and selected != UPGRADES: continue
		var track: String = entry["track"]
		if tracks.has(track): continue
		tracks.append(track)
		var data := Status.investment(state, track)
		var row: Dictionary = rows[data.target]
		row.completed = data.maxed
		_reputation_condition(row, Status.condition_text(data.reason) if data.reason.contains("명성") else "")
		_text(row.detail, "%d/%d단계" % [data.level, data.maximum])
		_gauge_value(row.work, true, data.progress, "단계", "%d/%d" % [data.level, data.maximum])
		row.stock.box.hide()
		_text(row.summary, data.effect + ("\n%d G" % data.cost if not data.maxed else ""))
		_text(row.extra, "최대 %d단계 · 효과는 강화 후 자동 운영에 반영돼요" % data.maximum)
		_purchase_button(row, "upgrade:" + track, "훈련" if entry.get("kind", "") == "training" else "강화", "최대 단계" if data.maxed else "")
		if Content.lookup("employees", track).is_empty() and not track.begins_with("family_"): row.icon.texture = ManagementArt.readable_icon(ItemArt.equipment_icon(track, data.level))
		_highlight(data.target, false)
	for employee in Content.DATA["employees"]:
		if visible_only and selected != UPGRADES: continue
		var id: String = employee["id"]
		var row: Dictionary = rows["employee" if id == "sales_assistant" else id]
		var owned: bool = p.expansion.staff.has(id) or (id == "sales_assistant" and p.employee)
		row.completed = owned
		var reason: String = Status.purchase_condition(state, "staff:" + id)
		_reputation_condition(row, "명성 %d 필요" % int(employee.reputation) if int(employee.reputation) > 0 else "")
		_text(row.detail, "고용 완료" if owned else Status.condition_text(reason))
		_gauge_value(row.work, true, 1.0 if owned else 0.0, "고용", "%d/1" % int(owned))
		row.stock.box.hide()
		_text(row.summary, "%s · %d G · 명성 %d · 조사 %d곳" % [Status.effects_text(employee.effect), employee.cost, employee.reputation, employee.completed_regions])
		_text(row.extra, "고용 후 훈련 항목에서 단계별로 성장할 수 있어요")
		_purchase_button(row, "staff:" + id, "고용", "고용 완료" if owned else "")
		_highlight("employee" if id == "sales_assistant" else id, false)
	for region in Content.DATA["regions"]:
		if visible_only and selected not in [OPERATION, EXPEDITIONS]: continue
		var id: String = region["id"]
		var data := Status.region(state, id)
		for row_id in [id, "trip_" + id]:
			if visible_only and ((row_id == id and selected != EXPEDITIONS) or (row_id != id and selected != OPERATION)): continue
			var row: Dictionary = rows[row_id]
			row.panel.visible = data.available and operation_regions.has(id) if row_id.begins_with("trip_") else true
			if row_id == id:
				_display_expedition(id, data)
				continue
			var reason: String = Status.condition_text(state.purchase_reason("expedition" if id == "forest_edge" else "region:" + id))
			_text(row.detail, Status.region_status(state, id) if data.available else reason if not reason.is_empty() else "원정 열기 가능")
			row.detail.custom_minimum_size.y = 24
			_gauge_value(row.work, true, data.display_progress, "원정", "%.0f초" % maxf(0.0, data.duration - data.display_elapsed) if data.running else "대기")
			row.work.box.modulate.a = 1.0 if data.available else 0.0
			row.detail.visible = true
			row.stock.box.hide()
			row.summary.visible = not row_id.begins_with("trip_")
			var investigation: String = "조사 완료" if data.returns >= data.max_returns else "조사 진행 %d/%d회" % [data.returns, data.max_returns]
			_text(row.summary, "원정 열기 %d G · 매회 %d G · %s" % [data.cost, data.fee, investigation])
			_text(row.extra, Status.region_card_conditions(state, id))
	_refresh_contracts(state, visible_only)
	if not visible_only or selected == UPGRADES: _refresh_late_investments(state)
	if not visible_only or selected == UPGRADES: _refresh_workshop(state)
	if not visible_only or selected == UPGRADES: _refresh_aging(state)
	if not visible_only or selected == UPGRADES: _refresh_keeper_upgrades(state)
	if not visible_only or selected == UPGRADES: _refresh_decor(state)
	if not visible_only or selected in [OPERATION, HERBS]: _refresh_supply_support(state)
	if selected == REPORT:
		var lifetime := Status.lifetime_summary(state)
		_text(statistics_values.play_time, lifetime.time)
		_text(statistics_values.net, _signed_number(lifetime.net) + " G")
		_text(statistics_values.sales, host._number(lifetime.sales) + " G")
		_text(statistics_values.materials_cost, _signed_number(-lifetime.materials_cost) + " G")
		_text(statistics_values.fees, _signed_number(-lifetime.fees) + " G")
		_text(statistics_values.contract_paid, host._number(lifetime.contract_paid) + " G")
		_text(statistics_values.contract_shipped, host._number(lifetime.contract_shipped) + "병")
		_text(statistics_values.contract_rounds, host._number(lifetime.contract_rounds) + "회")
		_text(statistics_values.keeper_sleeps, host._number(lifetime.keeper_sleeps) + "회")
		_text(statistics_values.keeper_faints, host._number(lifetime.keeper_faints) + "회")
		_text(statistics_values.fatigue_failed, host._number(lifetime.fatigue_failed) + "병")
		_text(statistics_values.aged_sold, host._number(lifetime.aged_sold) + "병")
		_text(statistics_values.aged_revenue, host._number(lifetime.aged_revenue) + " G")
		for key in ["brewed", "sold", "expeditions", "reputation_gain"]:
			_text(statistics_values[key], host._number(lifetime[key]) + ("회" if key == "expeditions" else "개" if key in ["brewed", "sold"] else ""))
		for row in Status.collection(state):
			var done: bool = int(row.have) >= int(row.total)
			_text(collection_values[row.key], "%d / %d%s" % [row.have, row.total, " · 완료" if done else ""])
			collection_values[row.key].add_theme_color_override("font_color", Palette.ACCENT if done else INK)
		collection_done.visible = Status.collection_complete(state)
		_refresh_regulars(state)
		# Viewing is remembered by the window, never by the model.
		for id in Regulars.ids(): regular_viewed[id] = state.regulars.stage(id)
	regular_dot.visible = Regulars.ids().any(func(id): return state.regulars.is_new(id) and state.regulars.stage(id) > int(regular_viewed.get(id, 0)))
	_sort_completed(visible_only)

func _sort_completed(visible_only: bool = false) -> void:
	# Sort purchase lists within their sections; never reshuffle active job lists.
	for page in [RECIPES, EXPEDITIONS, UPGRADES]:
		if visible_only and page != selected: continue
		var group: Array[Control] = []
		for child in pages[page].get_children():
			if child.has_meta("row_id"):
				group.append(child)
			else:
				_sort_group(pages[page], group)
				group.clear()
		_sort_group(pages[page], group)

func _sort_group(parent: Node, group: Array[Control]) -> void:
	if group.is_empty(): return
	var start: int = group[0].get_index()
	group.sort_custom(func(a, b):
		var first: Dictionary = rows[a.get_meta("row_id")]
		var second: Dictionary = rows[b.get_meta("row_id")]
		return not first.completed if first.completed != second.completed else first.order < second.order)
	for i in group.size():
		if group[i].get_index() != start + i: parent.move_child(group[i], start + i)

func ingredients_text(id: String) -> String:
	var parts := PackedStringArray()
	var source := Content.lookup("potions", id)
	for material in source.ingredients: parts.append("%s %d" % [Content.lookup("materials", material)["name"], int(source.ingredients[material])])
	return " + ".join(parts)
