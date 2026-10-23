extends Control

const State = preload("res://scripts/shop_state.gd")
const SaveStore = preload("res://scripts/save_store.gd")
const ShopArt = preload("res://scripts/shop_art.gd")
const RecentIncome = preload("res://scripts/recent_income.gd")
const HerbPlant = preload("res://scripts/herb_plant.gd")
const OperationCard = preload("res://scripts/operation_card.gd")
const ManagementPanel = preload("res://scripts/management_panel.gd")
const DesktopInput = preload("res://scripts/desktop_input.gd")
const WorkshopAssets = preload("res://scripts/workshop_assets.gd")
const MiniWorkshop = preload("res://scripts/mini_workshop.gd")
const WorkshopGauges = preload("res://scripts/workshop_gauges.gd")
var workshop_gauges: Control
const WindowLayout = preload("res://scripts/window_mode_layout.gd")
const CurrencyText = preload("res://scripts/currency_text.gd")
const Status = preload("res://scripts/management_status.gd")
const LoginResume = preload("res://scripts/login_resume.gd")
const SingleInstance = preload("res://scripts/single_instance.gd")
const SystemTray = preload("res://scripts/system_tray.gd")
var system_tray: Node
const ShopAudio = preload("res://scripts/shop_audio.gd")
var shop_audio: Node
var instance_guard: Node
var instance_bypassed := false
var login_resume: RefCounted
const SAVE_PATH := "user://potion_shop.json"
const INK := Color("f0dfc4")
const MUTED := Color("b4a4bd")
const GOLD := Color("efc77c")
const BG := Color("211b2d")
const NORMAL_SIZE := Vector2i(440, 704)
const MINI_SIZE := Vector2i(408, 296)
const MINIMAL_SIZE := Vector2i(320, 124)
const ART_POSITION := Vector2(16, 64)

var state := State.new()
var art: Control
var gold_label: RichTextLabel
var stock_label: Label
var brew_label: Label
var status_label: Label
var level_label: Label
var speed_label: RichTextLabel
var save_label: Label
var upgrade_button: Button
var minimize_button: Button
var brew_bar: ProgressBar
var save_elapsed := 0.0
var message_elapsed := 0.0
var save_failed := false
var test_mode := false
var body_font: Font = preload("res://assets/fonts/pretendard/Pretendard-Regular.otf")
var title_font: Font = preload("res://assets/fonts/pretendard/Pretendard-SemiBold.otf")
var normal_controls: Array[CanvasItem] = []
var scene_group: CanvasGroup
var mini_toolbar: Control
var mini_drag_surface: Control
var mini_button: Button
var business_status: Label
var mini_business_status: Label
var opacity_slider: HSlider
var opacity_label: Label
var opacity_save_delay := -1.0
var income := RecentIncome.new()
var small_hud: Control
var minimal_hud: Control
var small_gold: RichTextLabel
var small_stock: Label
var small_brew: Label
var small_bar: ProgressBar
var minimal_gold: RichTextLabel
var minimal_income: RichTextLabel
var minimal_brew: Label
var minimal_bar: ProgressBar
var toolbar_panel: Panel
var shrink_button: Button
var herb_label: RichTextLabel
var garden_label: Label
var harvest_label: RichTextLabel
var garden_button: Button
var garden_bar: ProgressBar
var herb_plant: Control
var supply_card: Control
var garden_card: Control
var cauldron_card: Control
var supply_button: Button
var stock_caption: Label
var workshop_toolbar: Control
var workshop_gold: Label
var workshop_environment: Label
var workshop_weather_icon: TextureRect
var workshop_time_icon: TextureRect
var workshop_weather_icons := {}
var workshop_minimize: Button
var management: Window
var management_raise_pending := false
var desktop_input: Node
var workshop_dragging := false
var workshop_drag_pointer := Vector2i.ZERO
var workshop_drag_position := Vector2i.ZERO
var desktop_suspended_for_minimize := false
var workshop_move: Button
var companion: Control


func _ready() -> void:
	test_mode = DisplayServer.get_name() == "headless" or "--smoke-test" in OS.get_cmdline_user_args() or get_tree().has_meta("isolated_preview")
	# Acquire before reading saves or touching login intent. Every playable entry uses it.
	instance_guard = _create_instance_guard()
	add_child(instance_guard)
	var claim: Dictionary = instance_guard.acquire()
	instance_bypassed = claim.bypassed
	if not claim.ok or (not claim.owner and not claim.bypassed):
		set_process(false)
		if not claim.ok: push_error(claim.error)
		get_tree().quit()
		return
	instance_guard.lost.connect(func():
		set_process(false)
		get_tree().quit())
	login_resume = LoginResume.new()
	# The hidden login launcher already checks this; recheck before building any UI.
	if not test_mode and "--autostart" in OS.get_cmdline_user_args():
		login_resume.initialize()
		if not LoginResume.should_resume(login_resume.snapshot()):
			set_process(false)
			get_tree().quit()
			return
	Engine.max_fps = 30
	get_tree().auto_accept_quit = false
	get_window().close_requested.connect(_close_shop)
	get_window().focus_exited.connect(func(): workshop_dragging = false)
	var shop_theme := Theme.new()
	shop_theme.default_font = body_font
	shop_theme.default_font_size = 16
	shop_theme.set_font("font", "Button", title_font)
	shop_theme.set_font("bold_font", "RichTextLabel", title_font)
	theme = shop_theme
	var load_result := "new" if test_mode else SaveStore.read_into(state, SAVE_PATH)
	# Older saves may contain the retired picture-plus-HUD stage.
	if state.window_mode == State.WindowMode.SMALL:
		state.window_mode = State.WindowMode.COMPANION
	# Always on top is fixed; there is no player toggle or periodic flag update.
	get_window().always_on_top = true
	get_viewport().transparent_bg = true
	get_viewport().gui_embed_subwindows = false
	get_window().transparent = true
	# --script entry points skip Godot's main-scene icon setup. Apply after
	# startup so the engine's fallback icon cannot overwrite our native ICO.
	_apply_application_icon.call_deferred()
	_build_interface()
	_build_compact_huds()
	_build_window_controls()
	_build_workshop_controls()
	companion = MiniWorkshop.new()
	companion.host = self
	add_child(companion)
	workshop_gauges = WorkshopGauges.new()
	workshop_gauges.host = self
	add_child(workshop_gauges)
	desktop_input = DesktopInput.new()
	add_child(desktop_input)
	desktop_input.unavailable.connect(func(): workshop_environment.tooltip_text = "클릭 통과를 시작하지 못했어요. 관리 버튼은 사용할 수 있어요.")
	_apply_window_mode()
	_apply_opacity()
	_update_interface()
	system_tray = SystemTray.new()
	system_tray.host = self
	add_child(system_tray)
	shop_audio = ShopAudio.new()
	shop_audio.name = "ShopAudio"
	shop_audio.apply_settings(state.audio_volume, state.audio_muted)
	add_child(shop_audio)
	if load_result == "recovered":
		show_message("이전 저장 기록을 복구했어요.")
	elif load_result == "invalid":
		show_message("저장 기록을 읽지 못했어요. 새 가게로 시작해요.", 10.0)
	if not test_mode and DisplayServer.get_name() != "headless":
		get_window().position = _initial_window_position()
	if "--smoke-test" in OS.get_cmdline_user_args():
		_run_smoke_test.call_deferred()
	elif "--workshop" in OS.get_cmdline_user_args():
		_set_window_mode(State.WindowMode.WORKSHOP)
	if not _owns_game_session():
		set_process(false)
		get_tree().quit()
		return
	login_resume.start_session()


func _apply_application_icon() -> void:
	if DisplayServer.get_name() == "headless" or Engine.is_editor_hint(): return
	var native_path := str(ProjectSettings.get_setting("application/config/windows_native_icon", "res://icon.ico"))
	if OS.get_name() == "Windows" and DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_ICON) and FileAccess.file_exists(native_path):
		DisplayServer.set_native_icon(native_path)
	elif DisplayServer.has_feature(DisplayServer.FEATURE_ICON):
		DisplayServer.set_icon(preload("res://icon.png").get_image())

func _create_instance_guard() -> Node:
	return SingleInstance.new()


func _owns_game_session() -> bool:
	return instance_bypassed or (instance_guard != null and instance_guard.is_owner())


func _build_interface() -> void:
	var background := ColorRect.new()
	background.color = BG
	background.size = Vector2(NORMAL_SIZE)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var title := _label("물약 상점", Rect2(20, 16, 280, 34), 28, INK)
	title.add_theme_font_override("font", title_font)
	minimize_button = _icon_button("minimize", Rect2(344, 16, 34, 34), "진행만 작게 보기 · 골드와 제작 게이지")
	minimize_button.pressed.connect(_show_companion_view)
	minimize_button.tooltip_text = "축소 · 최소모드로"
	art = ShopArt.new()
	art.position = ART_POSITION
	art.size = Vector2(408, 248)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	_label("보유 골드", Rect2(20, 330, 120, 20), 14, MUTED)
	gold_label = _currency_label(self, "0 G", Rect2(20, 350, 200, 38), 30, GOLD)
	stock_caption = _label("진열대", Rect2(250, 330, 170, 20), 14, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	stock_label = _label("", Rect2(230, 355, 190, 25), 14, INK, HORIZONTAL_ALIGNMENT_RIGHT)
	brew_label = _label("물약 제조 중", Rect2(20, 392, 260, 22), 14, INK)
	_currency_label(self, "체력 6 G · 마나 18 G", Rect2(288, 392, 132, 22), 12, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	brew_bar = ProgressBar.new()
	brew_bar.position = Vector2(20, 420)
	brew_bar.show_percentage = false
	brew_bar.add_theme_font_size_override("font_size", 1)
	brew_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brew_bar.add_theme_stylebox_override("background", _style(Color("3a3046"), Color.TRANSPARENT, 4))
	brew_bar.add_theme_stylebox_override("fill", _style(Color("b7cca0"), Color.TRANSPARENT, 4))
	add_child(brew_bar)
	brew_bar.size = Vector2(400, 7)
	_build_operation_cards()
	status_label = _label("", Rect2(20, 312, 400, 18), 12, Color("efaaa9"))
	save_label = _label("", Rect2(20, 684, 400, 18), 12, MUTED)
	mini_button = minimize_button # Compatibility alias; only one shrink action is shown.
	var workshop_button := _button("작업실", Rect2(268, 18, 68, 30), false)
	workshop_button.pressed.connect(func(): _set_window_mode(State.WindowMode.WORKSHOP))
	business_status = _label("자동 영업 중", Rect2(20, 643, 115, 36), 16, GOLD)
	opacity_label = _label("불투명도 100%", Rect2(163, 640, 257, 20), 14, INK)
	opacity_slider = HSlider.new()
	opacity_slider.position = Vector2(163, 661)
	opacity_slider.size = Vector2(257, 22)
	opacity_slider.min_value = 30
	opacity_slider.max_value = 100
	opacity_slider.step = 5
	opacity_slider.value = state.opacity * 100.0
	opacity_slider.tooltip_text = "낮출수록 뒤의 화면이 비쳐 보입니다. 30~100%"
	opacity_slider.value_changed.connect(_change_opacity)
	add_child(opacity_slider)
	# Composite the whole shop once so overlapping elements share one opacity.
	scene_group = CanvasGroup.new()
	scene_group.name = "ShopCanvas"
	var existing := get_children()
	add_child(scene_group)
	for child in existing:
		if child is CanvasItem:
			child.reparent(scene_group)
			if child is Control:
				child.theme = theme
			if child != art:
				normal_controls.append(child)


func _operation_card(y: float, accent: Color) -> Control:
	var card := OperationCard.new()
	card.position = Vector2(20, y)
	card.accent = accent
	add_child(card)
	return card


func _build_operation_cards() -> void:
	supply_card = _operation_card(434, Color("9ccbdc"))
	supply_card.set_icon(load("res://assets/mushroom_24.png"))
	supply_card.title_label.text = "달빛 버섯 · 자동 발주"
	supply_button = supply_card.action_button
	supply_button.hide()
	supply_card.tooltip_text = "12초마다 재료 보관함으로 버섯을 최대 2개 자동 구매합니다.\n버섯 1개당 4 G · 보관 한도 6개 · 구매 후 30 G 유지\n진열대와 별개입니다. 보관함·자금 부족 시 진행도를 유지하고 대기합니다."
	garden_card = _operation_card(504, Color("b7cca0"))
	herb_plant = HerbPlant.new()
	herb_plant.position = Vector2(4, 0)
	herb_plant.size = Vector2(32, 40)
	garden_card.icon_slot.add_child(herb_plant)
	garden_label = garden_card.title_label
	herb_label = garden_card.detail_label
	harvest_label = garden_card.status_label
	garden_bar = garden_card.progress
	garden_button = garden_card.action_button
	garden_card.action_pressed.connect(_upgrade_garden)
	cauldron_card = _operation_card(574, GOLD)
	cauldron_card.set_icon(load("res://assets/cauldron_48.png"))
	level_label = cauldron_card.title_label
	speed_label = cauldron_card.detail_label
	cauldron_card.status_label.text = "자동 제조 · 재료가 있으면 마나 우선"
	upgrade_button = cauldron_card.action_button
	cauldron_card.action_pressed.connect(_upgrade)


func _hud_label(parent: Control, value: String, rect: Rect2, font_size: int, color: Color, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := _label(value, rect, font_size, color, alignment)
	label.reparent(parent, false)
	return label


func _hud_panel(rect: Rect2) -> Control:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.theme = theme
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(_mini_input)
	panel.add_theme_stylebox_override("panel", _style(BG, Color("594764"), 5))
	scene_group.add_child(panel)
	return panel


func _hud_bar(parent: Control, rect: Rect2) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = rect.position
	bar.show_percentage = false
	bar.add_theme_font_size_override("font_size", 1)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", _style(Color("3a3046"), Color.TRANSPARENT, 2))
	bar.add_theme_stylebox_override("fill", _style(Color("b7cca0"), Color.TRANSPARENT, 2))
	parent.add_child(bar)
	bar.size = rect.size
	return bar


func _build_compact_huds() -> void:
	small_hud = _hud_panel(Rect2(0, 248, 408, 48))
	small_gold = _currency_label(small_hud, "", Rect2(12, 3, 140, 28), 18, GOLD)
	small_stock = _hud_label(small_hud, "", Rect2(156, 6, 88, 20), 13, INK)
	small_brew = _hud_label(small_hud, "", Rect2(244, 6, 152, 20), 13, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	small_bar = _hud_bar(small_hud, Rect2(12, 35, 384, 5))
	# One enclosing information panel also contains its bottom controls.
	minimal_hud = _hud_panel(Rect2(Vector2.ZERO,Vector2(MINIMAL_SIZE)))
	minimal_gold = _currency_label(minimal_hud, "", Rect2(12, 4, 140, 30), 22, GOLD)
	minimal_income = _currency_label(minimal_hud, "", Rect2(154, 8, 154, 24), 14, Color("b7cca0"), HORIZONTAL_ALIGNMENT_RIGHT)
	minimal_brew = _hud_label(minimal_hud, "", Rect2(12, 36, 296, 18), 14, MUTED)
	minimal_bar = _hud_bar(minimal_hud, Rect2(12, 58, 296, 5))


func _build_window_controls() -> void:
	mini_drag_surface = Control.new()
	mini_drag_surface.size = Vector2(MINI_SIZE)
	mini_drag_surface.mouse_default_cursor_shape = Control.CURSOR_MOVE
	mini_drag_surface.tooltip_text = "드래그해서 이동 · 더블 클릭하면 한 단계 확대"
	mini_drag_surface.gui_input.connect(_mini_input)
	add_child(mini_drag_surface)
	mini_toolbar = Control.new()
	mini_toolbar.size = Vector2(MINIMAL_SIZE.x, WorkshopAssets.BAR_HEIGHT)
	mini_toolbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mini_toolbar)
	toolbar_panel = Panel.new()
	toolbar_panel.size = mini_toolbar.size
	toolbar_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	toolbar_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mini_toolbar.add_child(toolbar_panel)
	_toolbar_move_button(mini_toolbar, Vector2(8, 9))
	mini_business_status = _label("자동 영업", Rect2(44, 6, 96, 28), 12, GOLD)
	mini_business_status.reparent(mini_toolbar)
	mini_business_status.hide()
	var actions := _toolbar_actions(mini_toolbar, false, true, _show_minimal_view, _restore_compact_view, "가장 작은 화면", "확대 · 최소모드로")
	shrink_button = actions.shrink


func _mini_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if event.double_click:
			_restore_compact_view()
		elif state.window_mode in [State.WindowMode.WORKSHOP, State.WindowMode.COMPANION]:
			# Native modal dragging does not move our layered transparent window.
			workshop_dragging = true
			workshop_drag_position = get_window().position
			var pixel_scale := Vector2(get_window().size) / Vector2(get_window().content_scale_size)
			workshop_drag_pointer = workshop_drag_position + Vector2i(event.global_position * pixel_scale)
		elif DisplayServer.has_feature(DisplayServer.FEATURE_WINDOW_DRAG):
			DisplayServer.window_start_drag()


func _input(event: InputEvent) -> void:
	if not workshop_dragging:
		return
	if event is InputEventMouseMotion or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed):
		_follow_workshop_drag()
		if event is InputEventMouseButton:
			_finish_workshop_drag()


func _follow_workshop_drag() -> void:
	get_window().position = drag_in_work_area(workshop_drag_position + DisplayServer.mouse_get_position() - workshop_drag_pointer, get_window().size)


## Stay inside the work area of the monitor under the pointer, never under the
## taskbar; crossing to another monitor still works. Shared with management.
func drag_in_work_area(position: Vector2i, size: Vector2i) -> Vector2i:
	var screen := _screen_at(DisplayServer.mouse_get_position())
	var usable := DisplayServer.screen_get_usable_rect(get_window().current_screen if screen < 0 else screen)
	return WindowLayout.keep_on_screen(position, size, usable)


func remember_management_position(position: Vector2i) -> void:
	state.management_position = position
	state.has_management_position = true
	_save()


## A saved position restored onto a monitor that still exists, inside its work
## area; Vector2i.MIN when that monitor is gone and the caller should use its default.
func _restored_position(position: Vector2i, size: Vector2i) -> Vector2i:
	var screen := _screen_at(position + size / 2)
	if screen < 0: return Vector2i.MIN
	return WindowLayout.keep_on_screen(position, size, DisplayServer.screen_get_usable_rect(screen))


func _finish_workshop_drag() -> void:
	workshop_dragging = false
	# Remember the dropped position right away instead of waiting for autosave.
	_save()


func _screen_at(point: Vector2i) -> int:
	for screen in DisplayServer.get_screen_count():
		if Rect2i(DisplayServer.screen_get_position(screen), DisplayServer.screen_get_size(screen)).has_point(point):
			return screen
	return -1


func _initial_window_position() -> Vector2i:
	var size := get_window().size
	if state.has_window_position:
		var restored := _restored_position(state.window_position, size)
		if restored != Vector2i.MIN: return restored
	var usable := DisplayServer.screen_get_usable_rect()
	return usable.position + Vector2i(maxi(0, usable.size.x - size.x - 24), maxi(32, usable.size.y - size.y - 48))


func _unhandled_key_input(event: InputEvent) -> void:
	if state.mini_mode and event.is_action_pressed("ui_cancel"):
		_restore_compact_view()
		get_viewport().set_input_as_handled()


func _set_mini_mode(enabled: bool) -> void:
	_show_companion_view() if enabled else _set_window_mode(state.main_window_mode)


func _set_window_mode(mode: int) -> void:
	if not _owns_game_session(): return
	var previous := Rect2i(get_window().position, get_window().size)
	var previous_toolbar_height := MiniWorkshop.SIZE.y - MiniWorkshop.ART_HEIGHT if state.window_mode == State.WindowMode.COMPANION else WorkshopAssets.BAR_HEIGHT
	if mode in [State.WindowMode.FULL, State.WindowMode.WORKSHOP]:
		state.main_window_mode = mode
	state.window_mode = clampi(mode, State.WindowMode.FULL, State.WindowMode.COMPANION)
	_apply_window_mode(previous, previous_toolbar_height)
	_apply_opacity()
	_save()


func _apply_window_mode(previous: Rect2i = Rect2i(), previous_toolbar_height: int = WorkshopAssets.BAR_HEIGHT) -> void:
	workshop_dragging = false
	var workshop := state.window_mode == State.WindowMode.WORKSHOP
	var companion_mode := state.window_mode == State.WindowMode.COMPANION
	companion.visible = companion_mode
	for control in normal_controls:
		control.visible = not state.mini_mode
	art.position = Vector2.ZERO if state.mini_mode else ART_POSITION
	art.workshop = workshop
	art.size = Vector2(WorkshopAssets.SIZE.x, WorkshopAssets.ART_HEIGHT) if workshop else Vector2(408, 248)
	art.visible = state.window_mode not in [State.WindowMode.MINIMAL, State.WindowMode.COMPANION]
	small_hud.visible = state.window_mode == State.WindowMode.SMALL
	small_hud.position.y = 286 if workshop else 248
	small_gold.visible = not workshop
	small_stock.position.x = 12 if workshop else 156
	minimal_hud.visible = state.window_mode == State.WindowMode.MINIMAL
	_refresh_notices()
	mini_drag_surface.visible = state.mini_mode and not workshop and not companion_mode
	var minimal := state.window_mode == State.WindowMode.MINIMAL
	mini_toolbar.visible = minimal
	var target := MINIMAL_SIZE if minimal else (MINI_SIZE if state.mini_mode else NORMAL_SIZE)
	if workshop: target = WorkshopAssets.SIZE
	if companion_mode: target = MiniWorkshop.SIZE
	if workshop_toolbar != null: workshop_toolbar.visible = workshop
	mini_drag_surface.size = Vector2(target.x, 44 if minimal else 248)
	mini_toolbar.position = Vector2(0, target.y - WorkshopAssets.BAR_HEIGHT)
	mini_toolbar.size.x = target.x
	toolbar_panel.size.x = target.x
	mini_business_status.hide()
	# Every stage retains the same actions, including disabled end-stage controls.
	get_window().borderless = state.mini_mode
	get_window().content_scale_size = target
	get_window().size = target
	get_window().mouse_passthrough = false
	if system_tray != null and system_tray.active:
		system_tray.register_window(get_window())
	if desktop_input != null:
		# Render-only verification must not change desktop input routing.
		var allow_desktop_input := not test_mode or get_tree().has_meta("desktop_input_verification")
		var input_regions: Array[Rect2i] = []
		if workshop: input_regions = WorkshopGauges.click_regions()
		var input_art_height: int = MiniWorkshop.ART_HEIGHT if companion_mode else mini(WorkshopAssets.ART_HEIGHT, target.y - WorkshopAssets.BAR_HEIGHT)
		desktop_input.configure(target, input_art_height, input_regions)
		desktop_input.set_enabled((workshop or companion_mode) and allow_desktop_input and get_window().mode != Window.MODE_MINIMIZED)
	if DisplayServer.get_name() != "headless":
		var usable := DisplayServer.screen_get_usable_rect(get_window().current_screen)
		var position := get_window().position
		if previous.size.x > 0 and previous.size.y > 0:
			var toolbar_height := MiniWorkshop.SIZE.y - MiniWorkshop.ART_HEIGHT if companion_mode else WorkshopAssets.BAR_HEIGHT
			position = WindowLayout.fixed_toolbar_position(previous, previous_toolbar_height, target, toolbar_height)
		get_window().position = WindowLayout.keep_on_screen(position, target, usable)


func _change_opacity(value: float) -> void:
	if not _owns_game_session(): return
	state.opacity = clampf(value / 100.0, 0.3, 1.0)
	_apply_opacity()
	opacity_save_delay = 0.35


func _apply_opacity() -> void:
	scene_group.visible = state.window_mode != State.WindowMode.COMPANION
	scene_group.self_modulate.a = 1.0 if state.window_mode == State.WindowMode.WORKSHOP else state.opacity
	opacity_label.text = "불투명도 %d%%" % roundi(state.opacity * 100)
	if companion != null: companion.scene.modulate.a = state.opacity


func _label(value: String, rect: Rect2, font_size: int, color: Color, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = value
	label.position = rect.position
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	# Size after font inheritance, so the temporary default font cannot enlarge it.
	label.size = rect.size
	return label

func _currency_label(parent: Node, value: String, rect: Rect2, font_size: int, color: Color, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> RichTextLabel:
	var label := CurrencyText.new()
	label.appearance(font_size, color)
	label.fit_content = false
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.money_alignment = alignment
	label.position = rect.position
	label.size = rect.size
	parent.add_child(label)
	label.set_value(value)
	return label


func _style(color: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	return style


func _button(value: String, rect: Rect2, primary: bool) -> Button:
	var button := Button.new()
	button.text = value
	button.position = rect.position
	button.size = rect.size
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 15 if primary else 13)
	button.add_theme_color_override("font_color", BG if primary else INK)
	button.add_theme_color_override("font_hover_color", BG if primary else Color.WHITE)
	button.add_theme_color_override("font_pressed_color", BG if primary else GOLD)
	button.add_theme_color_override("font_disabled_color", Color("a99aad"))
	button.add_theme_stylebox_override("normal", _style(GOLD if primary else Color("30273c"), Color("796449") if primary else Color("594764"), 6))
	button.add_theme_stylebox_override("hover", _style(Color("f8dba5") if primary else Color("44354e"), GOLD, 6))
	button.add_theme_stylebox_override("pressed", _style(Color("d4ac67") if primary else Color("463650"), GOLD, 6))
	button.add_theme_stylebox_override("disabled", _style(Color("3e3448"), Color("55455e"), 6))
	var focus := _style(Color.TRANSPARENT, GOLD, 6)
	focus.set_border_width_all(2)
	button.add_theme_stylebox_override("focus", focus)
	add_child(button)
	return button


func _icon_button(icon_name: String, rect: Rect2, description: String) -> Button:
	var button := _button("", rect, false)
	button.icon = load("res://assets/icons/" + icon_name + ".svg")
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 18)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_color_override("icon_normal_color", MUTED)
	button.add_theme_color_override("icon_hover_color", INK)
	button.add_theme_color_override("icon_pressed_color", GOLD)
	button.add_theme_color_override("icon_disabled_color", Color("66596e"))
	button.tooltip_text = description
	return button


func _toolbar_button(parent: Control, id: String, point: Vector2, description: String, callback: Callable = Callable()) -> Button:
	var node := _icon_button(id, Rect2(point, Vector2(28, 32)), description)
	_style_toolbar_button(node)
	node.add_theme_constant_override("h_separation",0)
	node.size = Vector2(28,32)
	node.reparent(parent, false)
	if callback.is_valid(): node.pressed.connect(callback)
	return node


func _style_toolbar_button(node: Button) -> void:
	# Keep each hit target, but draw only its icon/text inside the shared bar.
	for part in ["normal","hover","pressed","disabled"]:
		var empty := StyleBoxEmpty.new()
		empty.set_content_margin_all(2)
		node.add_theme_stylebox_override(part,empty)
	var focus := StyleBoxLine.new()
	focus.color = GOLD
	focus.thickness = 1
	focus.set_content_margin_all(2)
	node.add_theme_stylebox_override("focus",focus)


func _toolbar_backing(parent: Control, draggable: bool = false) -> NinePatchRect:
	var backing := NinePatchRect.new()
	backing.name = "ToolbarBackground"
	backing.texture = WorkshopAssets.toolbar_frame()
	# Keep the original corners at one fixed scale in every screen width.
	# Only the center stretches; the compact bar no longer squeezes its borders.
	backing.size = parent.size
	backing.patch_margin_left = 16
	backing.patch_margin_right = 16
	backing.patch_margin_top = 12
	backing.patch_margin_bottom = 12
	backing.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	backing.mouse_filter = Control.MOUSE_FILTER_STOP if draggable else Control.MOUSE_FILTER_IGNORE
	if draggable:
		backing.gui_input.connect(_mini_input)
		backing.mouse_default_cursor_shape = Control.CURSOR_MOVE
	parent.add_child(backing)
	return backing


func _toolbar_move_button(parent: Control, point: Vector2) -> Button:
	var node := _toolbar_button(parent, "move", point, "드래그해서 이동 · 더블 클릭하면 한 단계 확대")
	node.name = "MoveButton"
	node.mouse_default_cursor_shape = Control.CURSOR_MOVE
	node.gui_input.connect(_mini_input)
	return node


func _toolbar_manage_button(parent: Control, rect: Rect2) -> Button:
	var node := _button("관리", rect, true)
	node.add_theme_font_size_override("font_size", 13)
	node.size = rect.size
	node.reparent(parent, false)
	node.pressed.connect(open_management)
	return node


func _toolbar_actions(parent: Control, can_shrink: bool, can_expand: bool, shrink_callback: Callable, expand_callback: Callable, shrink_hint: String, expand_hint: String) -> Dictionary:
	# The four right-aligned slots stay in the same order at every window width.
	var x := parent.size.x - 146.0
	var y := floorf((parent.size.y - 32.0) / 2.0)
	var manage := _toolbar_manage_button(parent, Rect2(x, y, 42, 32))
	manage.name = "ManageButton"
	var shrink := _toolbar_button(parent, "minimize", Vector2(x + 46, y), shrink_hint, shrink_callback if can_shrink else Callable())
	shrink.name = "MinimizeButton"
	shrink.disabled = not can_shrink
	var expand := _toolbar_button(parent, "expand", Vector2(x + 78, y), expand_hint, expand_callback if can_expand else Callable())
	expand.name = "RestoreButton"
	expand.disabled = not can_expand
	var close := _toolbar_button(parent, "close", Vector2(x + 110, y), "저장하고 종료", _close_shop)
	close.name = "CloseButton"
	return {"manage": manage, "shrink": shrink, "expand": expand, "close": close}


func _process(delta: float) -> void:
	if not _owns_game_session():
		set_process(false)
		get_tree().quit()
		return
	_sync_minimized_state()
	if workshop_dragging:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_follow_workshop_drag()
		else:
			_finish_workshop_drag()
	if test_mode:
		return
	if state.window_mode in [State.WindowMode.SMALL, State.WindowMode.MINIMAL]:
		mini_toolbar.visible = state.window_mode == State.WindowMode.MINIMAL or Rect2(Vector2.ZERO, Vector2(MINI_SIZE)).has_point(get_local_mouse_position())
	if opacity_save_delay >= 0.0:
		opacity_save_delay -= delta
		if opacity_save_delay < 0.0:
			_save()
	_advance_game(delta)
	message_elapsed = maxf(0.0, message_elapsed - delta)
	_refresh_notices()
	save_elapsed += delta
	if save_elapsed >= 10.0:
		save_elapsed = 0.0
		_save()
	_update_interface()


func _advance_game(delta: float) -> void:
	if not _owns_game_session(): return
	var previous_returns: int = state.progression.totals["expeditions"]
	var previous_rare: int = state.progression.totals["rare"]
	var events := state.advance(delta)
	art.motion.trade_interval = state.customer_interval()
	if state.progression.totals["expeditions"] > previous_returns:
		art.on_expedition_return(state.progression.totals["expeditions"] - previous_returns)
		play_sound("expedition_return")
	if state.progression.totals["rare"] > previous_rare:
		art.on_rare_harvest(state.progression.totals["rare"] - previous_rare)
	income.advance(delta, events["earned"] + events.get("contract_earned", 0))
	art.apply_potion_events(events, state.stock, state.mana_stock, state.inventory_order())
	if events["sold"] > 0: play_sound("coin")
	if events["brewed"] > 0: play_sound("brew_done")
	# F22: a regular reaching a new stage is rare (16 stages in a whole game).
	if not events.get("regular_events", []).is_empty(): play_sound("unlock")
	if events["harvested"] > 0:
		herb_plant.on_harvest()
		art.on_harvest(events["harvested"])


func _update_interface() -> void:
	gold_label.set_value("%s G" % _number(state.gold))
	stock_caption.text = "물약 %d / %d" % [state.stock, state.capacity()]
	stock_label.text = "체력 %d · 마나 %d · 특수 %d" % [state.health_stock(), state.mana_stock, state.stock - state.health_stock() - state.mana_stock]
	var full := state.stock >= state.capacity()
	var waiting := state.waiting_for_herbs()
	var crafting := Status.crafting(state)
	brew_bar.value = crafting.progress * 100.0
	var remaining := state.brew_remaining_seconds()
	var harvest_remaining := maxf(0.0, state.harvest_duration() - state.harvest_elapsed)
	var contract_batch: bool = state.brew_active and state.contracts.batch.get("purpose", "ordinary") == "contract"
	brew_label.text = crafting.status if state.keeper.resting() else "%s 납품 제조 중 · %.1f초 남음" % [crafting.name, remaining] if contract_batch else "보관 가득 · 제작 대기" if full else ("재료 부족 · 약초 수확 %.1f초 후" % harvest_remaining if waiting else "%s 제조 중 · %.1f초 남음" % [crafting.name, remaining] if crafting.running else "제작 대기")
	brew_label.tooltip_text = "체력: 약초 2개 → 6 G\n마나: 약초 2개 + 달빛 버섯 1개 → 18 G\n다음 제조부터 재료가 있는 고급 물약을 우선합니다."
	brew_label.mouse_filter = Control.MOUSE_FILTER_PASS
	var brew_summary: String = crafting.status if not crafting.running else "%s %.1f초" % [crafting.name, remaining]
	var business_prefix := "" if state.shop_open else "휴업 · "
	small_gold.set_value("%s G" % _compact_number(state.gold))
	minimal_gold.set_value(small_gold.source_text)
	small_stock.text = "물약 %d/%d" % [state.stock, state.capacity()]
	small_brew.text = business_prefix + brew_summary
	# A short status leaves room for real counts at the larger information font.
	var compact_brew: String = crafting.status if not crafting.running else "제조 %.1f초" % remaining
	minimal_brew.text = business_prefix + compact_brew + " · 물약 %d/%d" % [state.stock, state.capacity()]
	if not waiting:
		minimal_brew.text += " · 약초 %d" % state.herbs
	small_brew.tooltip_text = "체력 %d · 마나 %d\n약초 %d/%d · 달빛 버섯 %d/%d\n%s" % [state.health_stock(), state.mana_stock, state.herbs, state.herb_capacity(), state.mushrooms, State.MUSHROOM_CAPACITY, state.purchase_status()]
	small_brew.mouse_filter = Control.MOUSE_FILTER_PASS
	minimal_brew.tooltip_text = small_brew.tooltip_text + "\n" + brew_summary
	minimal_brew.mouse_filter = Control.MOUSE_FILTER_PASS
	minimal_income.set_value("+%s G / 1분" % _compact_number(income.gold))
	for label in [small_gold, minimal_gold]:
		label.tooltip_text = "보유 골드: %s G" % _number(state.gold)
	minimal_income.tooltip_text = "최근 60초 수입: %s 골드\n일반 판매와 계약 대금의 합계예요. 재료 구매비와 강화 비용을 빼기 전 금액이며 다시 실행하면 0부터 집계합니다." % _number(income.gold)
	for label in [small_gold, minimal_gold, minimal_income]:
		label.mouse_filter = Control.MOUSE_FILTER_PASS
	for bar in [small_bar, minimal_bar]:
		# Every mode shows this actual batch, including its preserved paused value.
		bar.value = brew_bar.value
		bar.modulate = Color.WHITE if crafting.running else MUTED
	if save_failed:
		small_brew.text = "저장 실패 · 펼쳐서 확인"
		minimal_brew.text = "저장 실패 · 펼쳐서 확인"
	level_label.text = "솥 강화 · Lv.%d" % state.level
	var maxed := state.level >= State.MAX_LEVEL
	speed_label.text = "체력 %.1f초 · 마나 %.1f초" % [state.base_brew_duration(), state.base_brew_duration() * 1.25]
	cauldron_card.status_label.text = "최대 강화 · 고급 물약 우선" if maxed else "다음 단계 %.1f초 / %.1f초" % [maxf(0.8, state.base_brew_duration() * 0.88), maxf(0.8, state.base_brew_duration() * 0.88) * 1.25]
	cauldron_card.progress.value = brew_bar.value
	CurrencyText.button_value(upgrade_button, "최대 레벨" if maxed else "%s G · 강화" % _number(state.upgrade_cost()))
	upgrade_button.disabled = maxed or state.gold < state.upgrade_cost()
	upgrade_button.tooltip_text = "최대 레벨에 도달했어요." if maxed else "물약 제조 시간이 12%% 줄어듭니다.\n필요한 골드: %s G" % _number(state.upgrade_cost())
	var garden_maxed := state.garden_level >= State.MAX_GARDEN_LEVEL
	var herb_full := state.herbs >= state.herb_capacity()
	garden_label.text = "약초 화분 · Lv.%d" % state.garden_level
	herb_label.text = "약초 %d/%d · %d개 / %.1f초" % [state.herbs, state.herb_capacity(), State.HERBS_PER_HARVEST, state.harvest_duration()]
	harvest_label.text = "보관함 가득 · 성장 대기" if herb_full else "다음 수확 %.1f초" % harvest_remaining
	garden_bar.value = state.harvest_elapsed / state.harvest_duration() * 100.0
	CurrencyText.button_value(garden_button, "최대 레벨" if garden_maxed else "%s G · 강화" % _number(state.garden_upgrade_cost()))
	garden_button.disabled = garden_maxed or state.gold < state.garden_upgrade_cost()
	garden_button.tooltip_text = "최대 레벨에 도달했어요." if garden_maxed else "수확 %.1f초 → %.1f초\n약초 보관 %d → %d개" % [state.harvest_duration(), maxf(0.8, state.harvest_duration() * 0.86), state.herb_capacity(), state.herb_capacity() + 8]
	herb_plant.progress = state.harvest_elapsed / state.harvest_duration()
	herb_plant.storage_full = herb_full
	art.garden_progress = herb_plant.progress
	art.herb_storage_full = herb_full
	supply_card.detail_label.set_value("버섯 %d/%d · 2개에 %d G" % [state.mushrooms, State.MUSHROOM_CAPACITY, State.MUSHROOM_COST * State.DELIVERY_QUANTITY])
	supply_card.status_label.set_value(state.purchase_status())
	supply_card.progress.value = state.delivery_elapsed / State.DELIVERY_INTERVAL * 100.0
	supply_card.progress.modulate.a = 1.0 if state.auto_purchase and state.shop_open else 0.35
	art.shop_open = state.shop_open
	art.world = state.progression
	art.sync_inventory(state.stock, state.mana_stock, state.inventory_order())
	art.active_mana = state.active_mana
	art.set_potion_kind(crafting.kind)
	art.brewing = state.is_brewing()
	art.keeper_rest = state.keeper.state if state.keeper.resting() else ""
	art.aging_open = state.aging.opened()
	art.customer_phase = state.customer_elapsed / state.customer_interval()
	art.customer_interval = state.customer_interval()
	art.queue_redraw()
	if workshop_gauges != null: workshop_gauges.refresh()
	if workshop_gold != null:
		workshop_gold.text = _compact_number(state.gold)
		workshop_gold.tooltip_text = "보유 골드 %s G · 드래그해서 이동" % _number(state.gold)
		workshop_environment.text = ""
		workshop_time_icon.texture = workshop_weather_icons["time-night" if state.progression.is_night() else "time-day"]
		var weather_key: String = ["weather-sunny", "weather-cloudy", "weather-rainy"][state.progression.weather()]
		workshop_weather_icon.texture = workshop_weather_icons[weather_key]
		workshop_environment.tooltip_text = "클릭 통과를 시작하지 못했어요. 관리 버튼은 사용할 수 있어요." if desktop_input.failed else "%s · %s" % [state.recipe_name(), "선호 거래" if state.progression.is_preferred(state.progression.active_recipe) else "자동 제작"]


func _build_workshop_controls() -> void:
	workshop_toolbar = Control.new()
	workshop_toolbar.position = Vector2(0, WorkshopAssets.ART_HEIGHT)
	workshop_toolbar.size = Vector2(WorkshopAssets.SIZE.x, WorkshopAssets.BAR_HEIGHT)
	workshop_toolbar.clip_contents = true
	workshop_toolbar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(workshop_toolbar)
	_toolbar_backing(workshop_toolbar,true)
	var coin := TextureRect.new()
	# Disable the texture's intrinsic minimum size before assigning its image.
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.texture = WorkshopAssets.icon("gold-coin")
	coin.name = "GoldCoin"
	coin.position = WorkshopAssets.Layout.toolbar_rect("coin").position
	coin.size = WorkshopAssets.Layout.toolbar_rect("coin").size
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	workshop_toolbar.add_child(coin)
	workshop_gold = _label("", WorkshopAssets.Layout.toolbar_rect("gold"), 17, GOLD)
	workshop_gold.clip_text = true
	workshop_gold.add_theme_color_override("font_outline_color",Color("241c32"))
	workshop_gold.add_theme_constant_override("outline_size",3)
	workshop_gold.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	workshop_gold.mouse_filter = Control.MOUSE_FILTER_PASS
	workshop_gold.mouse_default_cursor_shape = Control.CURSOR_MOVE
	workshop_gold.gui_input.connect(_mini_input)
	workshop_gold.reparent(workshop_toolbar, false)
	for key in ["time-day", "time-night", "weather-sunny", "weather-cloudy", "weather-rainy"]:
		workshop_weather_icons[key] = WorkshopAssets.icon(key)
	workshop_time_icon = TextureRect.new()
	workshop_time_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	workshop_time_icon.position = WorkshopAssets.Layout.toolbar_rect("time").position
	workshop_time_icon.size = WorkshopAssets.Layout.toolbar_rect("time").size
	workshop_time_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	workshop_time_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	workshop_toolbar.add_child(workshop_time_icon)
	workshop_weather_icon = TextureRect.new()
	workshop_weather_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	workshop_weather_icon.position = WorkshopAssets.Layout.toolbar_rect("weather").position
	workshop_weather_icon.size = WorkshopAssets.Layout.toolbar_rect("weather").size
	workshop_weather_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	workshop_weather_icon.mouse_filter = Control.MOUSE_FILTER_STOP
	workshop_weather_icon.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	workshop_weather_icon.gui_input.connect(_sun_visitor_input)
	workshop_toolbar.add_child(workshop_weather_icon)
	workshop_environment = _label("", Rect2(188, 4, 56, 32), 11, INK)
	workshop_environment.reparent(workshop_toolbar, false)
	workshop_environment.hide()
	workshop_move = _toolbar_move_button(workshop_toolbar, WorkshopAssets.Layout.toolbar_rect("move").position)
	workshop_move.tooltip_text = "드래그해서 이동"
	var actions := _toolbar_actions(workshop_toolbar, true, false, _show_companion_view, _restore_compact_view, "축소 · 최소모드로", "가장 큰 화면")
	workshop_minimize = actions.shrink


func _sun_visitor_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if state.window_mode == State.WindowMode.WORKSHOP and state.progression.weather() == 0:
			art.window_visitor.tap()
		workshop_weather_icon.accept_event()



func open_management() -> void:
	if management == null:
		management = ManagementPanel.new()
		management.host = self
		management.visible = false
		add_child(management)
	# Recreate the native surface when restoring a minimized borderless window.
	# Godot's Windows mode/style update can otherwise drop WS_VISIBLE (#91588).
	if management.mode == Window.MODE_MINIMIZED:
		management.hide()
		management.mode = Window.MODE_WINDOWED
	var restored := _restored_position(state.management_position, management.size) if state.has_management_position and DisplayServer.get_name() != "headless" else Vector2i.MIN
	if restored != Vector2i.MIN:
		management.position = restored
	elif DisplayServer.get_name() != "headless":
		var usable := DisplayServer.screen_get_usable_rect()
		management.position = Vector2i(maxi(usable.position.x, get_window().position.x - management.size.x - 16), clampi(get_window().position.y - 326, usable.position.y + 32, maxi(usable.position.y + 32, usable.end.y - management.size.y - 30)))
	management.show()
	if system_tray != null and system_tray.active: system_tray.register_window(management)
	if not management_raise_pending:
		management_raise_pending = true
		_raise_management_after_click.call_deferred()


func _raise_management_after_click() -> void:
	# Finish both the toolbar input and native activation before raising the panel.
	await get_tree().process_frame
	management_raise_pending = false
	if not is_instance_valid(management) or not management.is_inside_tree() or not management.visible:
		return
	if DisplayServer.get_name() != "headless":
		# Topmost is set before creation in ManagementPanel._ready(). Reapplying
		# it to a visible borderless subwindow clears WS_VISIBLE on Windows.
		management.grab_focus()

func open_management_page(page: int) -> void:
	open_management()
	management.select_page(page)


func _number(value: int) -> String:
	var raw := str(value)
	var formatted := ""
	for index in range(raw.length()):
		if index > 0 and (raw.length() - index) % 3 == 0:
			formatted += ","
		formatted += raw[index]
	return formatted


func _compact_number(value: int) -> String:
	if value >= 100000000:
		return "%.1f억" % (value / 100000000.0)
	if value >= 100000:
		return "%.1f만" % (value / 10000.0)
	return _number(value)


func show_message(value: String, duration: float = 3.0) -> void:
	status_label.text = value
	message_elapsed = duration
	_refresh_notices()


func _refresh_notices() -> void:
	status_label.visible = not state.mini_mode and message_elapsed > 0.0
	save_label.visible = not state.mini_mode and save_failed


func _upgrade() -> void:
	if not _owns_game_session(): return
	if state.upgrade():
		_save()
		_update_interface()


func _upgrade_garden() -> void:
	if not _owns_game_session(): return
	if state.upgrade_garden():
		_save()
		_update_interface()


func _show_minimal_view() -> void:
	if management != null: management.hide()
	_set_window_mode(State.WindowMode.MINIMAL)
	_update_interface()


func _show_companion_view() -> void:
	if management != null: management.hide()
	_set_window_mode(State.WindowMode.COMPANION)
	companion.refresh()
	_update_interface()


func _restore_compact_view() -> void:
	# Expand one stage, regardless of the entry point or saved compact mode.
	if state.window_mode == State.WindowMode.MINIMAL:
		_show_companion_view()
	elif state.window_mode in [State.WindowMode.COMPANION, State.WindowMode.SMALL]:
		_set_window_mode(state.main_window_mode)
		_update_interface()


func _sync_minimized_state() -> void:
	if get_window().mode == Window.MODE_MINIMIZED:
		if not desktop_suspended_for_minimize:
			workshop_dragging = false
			if management != null: management.hide()
			desktop_input.set_enabled(false)
			desktop_suspended_for_minimize = true
	elif desktop_suspended_for_minimize:
		desktop_suspended_for_minimize = false
		var allow_desktop_input := not test_mode or get_tree().has_meta("desktop_input_verification")
		desktop_input.set_enabled(state.window_mode in [State.WindowMode.WORKSHOP, State.WindowMode.COMPANION] and allow_desktop_input)


## One quiet effect per call site; ShopAudio applies mute and per-sound spacing.
func play_sound(id: String) -> void:
	if shop_audio == null: return
	# Headless reports its dummy window as minimized; only a real hidden window rests.
	shop_audio.ambient_paused = DisplayServer.get_name() != "headless" and get_window().mode == Window.MODE_MINIMIZED
	shop_audio.play(id)


func set_audio_volume(value: float) -> void:
	if not _owns_game_session(): return
	state.audio_volume = clampf(value, 0.0, 1.0)
	if shop_audio != null: shop_audio.volume = state.audio_volume


func set_audio_muted(value: bool) -> void:
	if not _owns_game_session(): return
	state.audio_muted = value
	if shop_audio != null: shop_audio.muted = value
	_save()


func _save() -> bool:
	if not _owns_game_session(): return false
	if test_mode:
		return true
	# Minimized (tray-hidden) windows report an off-screen position; keep the last real one.
	if DisplayServer.get_name() != "headless" and get_window().mode == Window.MODE_WINDOWED:
		state.window_position = get_window().position
		state.has_window_position = true
	var result := SaveStore.write_from(state, SAVE_PATH)
	save_failed = result != OK
	save_label.text = "저장 실패 · 닫기 전 확인" if save_failed else ""
	save_label.add_theme_color_override("font_color", Color("efaaa9") if save_failed else MUTED)
	_refresh_notices()
	return not save_failed


func perform_contract_action(action: String, partner: String = "", choice: Dictionary = {}) -> Dictionary:
	if not _owns_game_session(): return {"ok": false, "error": "실행 보호가 종료되었어요"}
	var before: Dictionary = state.contracts.to_data().duplicate(true)
	var previous_gold: int = state.gold
	var previous_investment: int = state.progression.totals.manual_spent
	var result: Dictionary
	match action:
		"negotiate": result = state.contracts.negotiate(state, partner, choice)
		"accept": result = state.contracts.accept(state, partner, choice)
		"train":
			var next_level: Variant = choice.get("next_level", -1)
			if not choice.has("next_level") or not (next_level is int or next_level is float) or not is_finite(float(next_level)) or float(next_level) != int(next_level) or next_level < 1 or next_level > 3:
				return {"ok": false, "error": "오래된 훈련 화면이에요"}
			result = state.contracts.train(state, int(next_level))
		_: return {"ok": false, "error": "알 수 없는 계약 동작이에요"}
	if not result.get("ok", false): return result
	# A test can inject a failed workspace save without enabling player I/O.
	var saved := bool(get_meta("contract_save_fixture").call()) if test_mode and has_meta("contract_save_fixture") else _save()
	if not saved:
		state.gold = previous_gold
		state.progression.totals.manual_spent = previous_investment
		# Restore only this action's owned fields. Loading the entire save here
		# would apply migration defaults (including reopening a closed shop).
		var restored: bool = state.contracts.load_data(before, state.progression, state.brew_active, state.progression.active_recipe, state.contract_batch_context())
		assert(restored, "A failed contract action must restore its valid pre-action state")
		return {"ok": false, "error": "저장 실패 · 계약 변경을 반영하지 못했어요"}
	_update_interface()
	if management != null: management.refresh()
	return result


func perform_late_investment_action(track: String, expected_next_level: int) -> Dictionary:
	if not _owns_game_session(): return {"ok": false, "error": "실행 보호가 종료되었어요"}
	var before: Dictionary = state.late_investments.to_data().duplicate(true)
	var previous_gold: int = state.gold
	var previous_investment: int = state.progression.totals.manual_spent
	var result: Dictionary = state.late_investments.purchase(state, track, expected_next_level)
	if not result.get("ok", false): return result
	var saved := bool(get_meta("late_save_fixture").call()) if test_mode and has_meta("late_save_fixture") else _save()
	if not saved:
		state.gold = previous_gold
		state.progression.totals.manual_spent = previous_investment
		var restored: bool = state.late_investments.load_data(before, state)
		assert(restored, "A failed late investment must preserve its prior stage and reserved supply cycle")
		return {"ok": false, "error": "저장 실패 · 투자 변경을 반영하지 못했어요"}
	_update_interface()
	if management != null: management.refresh()
	return result


func perform_aging_action(track: String, expected_next_level: int) -> Dictionary:
	if not _owns_game_session(): return {"ok": false, "error": "실행 보호가 종료되었어요"}
	var before: Dictionary = state.aging.to_data()
	var previous_gold: int = state.gold
	var previous_investment: int = state.progression.totals.manual_spent
	var result: Dictionary = state.aging.purchase(state, track, expected_next_level)
	if not result.get("ok", false): return result
	var saved := bool(get_meta("aging_save_fixture").call()) if test_mode and has_meta("aging_save_fixture") else _save()
	if not saved:
		state.gold = previous_gold
		state.progression.totals.manual_spent = previous_investment
		var restored: bool = state.aging.load_data(before)
		assert(restored, "A failed aging purchase must preserve its prior stage, barrels and shelf")
		return {"ok": false, "error": "저장 실패 · 숙성 투자를 반영하지 못했어요"}
	_update_interface()
	if management != null: management.refresh()
	return result


func perform_keeper_action(track: String, expected_next_level: int) -> Dictionary:
	if not _owns_game_session(): return {"ok": false, "error": "실행 보호가 종료되었어요"}
	var upgrades: RefCounted = state.keeper.upgrades
	var before: Dictionary = upgrades.to_data()
	var previous_gold: int = state.gold
	var previous_investment: int = state.progression.totals.manual_spent
	var result: Dictionary = upgrades.purchase(state, track, expected_next_level)
	if not result.get("ok", false): return result
	var saved := bool(get_meta("keeper_save_fixture").call()) if test_mode and has_meta("keeper_save_fixture") else _save()
	if not saved:
		state.gold = previous_gold
		state.progression.totals.manual_spent = previous_investment
		var restored: bool = upgrades.load_data(before)
		assert(restored, "A failed keeper purchase must preserve its prior bed and tea levels")
		return {"ok": false, "error": "저장 실패 · 주인공 투자를 반영하지 못했어요"}
	_update_interface()
	if management != null: management.refresh()
	return result


func perform_workshop_action(expected_next_level: int) -> Dictionary:
	if not _owns_game_session(): return {"ok": false, "error": "실행 보호가 종료되었어요"}
	var before: Dictionary = state.workshop.to_data()
	var previous_gold: int = state.gold
	var previous_spent: int = state.progression.totals.manual_spent
	var result: Dictionary = state.workshop.purchase(state, expected_next_level)
	if not result.get("ok", false): return result
	var saved := bool(get_meta("workshop_save_fixture").call()) if test_mode and has_meta("workshop_save_fixture") else _save()
	if not saved:
		state.gold = previous_gold
		state.progression.totals.manual_spent = previous_spent
		state.workshop.restore(before)
		return {"ok": false, "error": "저장 실패 · 작업실 변경을 반영하지 못했어요"}
	_update_interface()
	if management != null: management.refresh()
	return result


func _close_shop() -> void:
	if not _owns_game_session():
		get_tree().quit()
		return
	if _save():
		_quit_manually()
	else:
		var dialog := ConfirmationDialog.new()
		dialog.dialog_text = "진행 상황을 저장하지 못했어요.\n저장하지 않고 종료할까요?"
		dialog.ok_button_text = "저장 없이 종료"
		dialog.cancel_button_text = "계속하기"
		dialog.confirmed.connect(_quit_manually)
		dialog.canceled.connect(dialog.queue_free)
		add_child(dialog)
		dialog.popup_centered()


func set_login_resume(value: bool) -> Dictionary:
	if not _owns_game_session(): return {"ok": false, "enabled": false, "status": "실행 보호가 종료되었어요", "error": "실행 보호가 종료되었어요"}
	return login_resume.set_enabled(value)


func _quit_manually() -> void:
	if not _owns_game_session():
		get_tree().quit()
		return
	login_resume.manual_closed()
	_request_manual_quit()


func _request_manual_quit() -> void:
	if test_mode:
		get_tree().set_meta("manual_quit_requested", true)
	else:
		get_tree().quit()


func _run_smoke_test() -> void:
	# Invoked explicitly; never reads or writes the player's save.
	state.gold = 30
	_update_interface()
	assert(not upgrade_button.disabled)
	upgrade_button.pressed.emit()
	assert(state.level == 2 and state.gold == 0)
	assert(not state.pinned) # Legacy preference is ignored.
	if DisplayServer.get_name() != "headless": assert(get_window().always_on_top)
	assert(not minimize_button.toggle_mode)
	state.advance(60.0)
	_update_interface()
	assert(state.total_sold > 0 and state.gold > 0)
	await get_tree().process_frame
	assert(brew_bar.size.y <= 8.0)
	assert(art.keeper_frames[0].get_size() == Vector2(96, 144))
	for frames in art.customer_sheets.values():
		assert(frames.size() == 4 and frames[0].get_size() == Vector2(96, 144))
	await _capture("shop-preview.png")
	opacity_slider.value = 55
	assert(is_equal_approx(state.opacity, 0.55))
	await _capture("shop-transparent.png")
	if DisplayServer.get_name() != "headless":
		var alpha := get_viewport().get_texture().get_image().get_pixel(22, 350).a
		print("Composited opacity: ", alpha)
		assert(absf(alpha - 0.55) < 0.03, "Window content must be composited with real alpha")
	minimize_button.pressed.emit()
	assert(state.window_mode == State.WindowMode.COMPANION and companion.visible and not art.visible)
	assert(not companion.minimize_button.toggle_mode)
	if DisplayServer.get_name() != "headless": assert(get_window().always_on_top)
	assert(get_window().size == MiniWorkshop.SIZE)
	await _capture("shop-mini.png")
	var sold_before := state.total_sold
	state.advance(60.0)
	_update_interface()
	assert(state.total_sold > sold_before)
	opacity_slider.value = 100
	companion.minimize_button.pressed.emit()
	assert(state.window_mode == State.WindowMode.MINIMAL and minimal_hud.visible)
	assert(mini_toolbar.visible and get_window().size == MINIMAL_SIZE)
	income.advance(1.0, 18)
	state.gold = 123456789
	_update_interface()
	assert(minimal_income.source_text == "+18 G / 1분" and minimal_gold.source_text == "1.2억 G")
	await _capture("shop-minimal.png")
	mini_toolbar.get_node("RestoreButton").pressed.emit()
	assert(state.window_mode == State.WindowMode.COMPANION and companion.visible)
	companion.restore_button.pressed.emit()
	assert(state.window_mode == State.WindowMode.FULL and upgrade_button.is_visible_in_tree())
	# Legacy picture/HUD rendering remains readable, but is no longer a mode button.
	_set_window_mode(State.WindowMode.SMALL)
	assert(small_hud.visible and art.visible)
	state.gold = 1248
	state.stock = 4
	state.brew_elapsed = state.brew_duration() * 0.65
	_update_interface()
	await _capture("shop-small-open.png")
	_set_window_mode(State.WindowMode.MINIMAL)
	await _capture("shop-minimal-open.png")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	_unhandled_key_input(escape)
	assert(state.window_mode == State.WindowMode.COMPANION)
	_unhandled_key_input(escape)
	assert(state.window_mode == State.WindowMode.FULL and upgrade_button.is_visible_in_tree())
	# Repeat transitions to catch position or scaling drift.
	for index in range(3):
		_set_mini_mode(true)
		_set_mini_mode(false)
	assert(art.position == ART_POSITION and get_window().content_scale_size == NORMAL_SIZE)
	# Exercise the real garden button and resource-starved HUD, not only model calls.
	state.gold = state.garden_upgrade_cost()
	var garden_before := state.garden_level
	state.harvest_elapsed = state.harvest_duration() * 0.5
	_update_interface()
	assert(not garden_button.disabled)
	garden_button.pressed.emit()
	assert(state.garden_level == garden_before + 1 and state.gold == 0)
	assert(is_equal_approx(state.harvest_elapsed / state.harvest_duration(), 0.5))
	state.stock = 0
	state.mana_stock = 0
	state.mushrooms = 0
	state.herbs = 0
	state.brew_active = false
	state.brew_elapsed = 0.0
	state.harvest_elapsed = state.harvest_duration() * 0.5
	_update_interface()
	assert(not art.brewing and brew_label.text.contains("재료 부족"))
	assert(garden_button.disabled and herb_plant.frames.size() == 4)
	await _capture("shop-herbs-waiting.png")
	_set_window_mode(State.WindowMode.SMALL)
	assert(not herb_plant.is_visible_in_tree() and not garden_button.is_visible_in_tree())
	await _capture("shop-small-herbs.png")
	_set_window_mode(State.WindowMode.MINIMAL)
	assert(is_zero_approx(minimal_bar.value), "Manufacturing gauge cannot display a harvest timer")
	await _capture("shop-minimal-herbs.png")
	var harvest_event: Dictionary = state.advance(state.harvest_duration() * 0.5)
	assert(harvest_event["harvested"] == State.HERBS_PER_HARVEST and state.is_brewing())
	herb_plant.on_harvest()
	art.on_harvest(harvest_event["harvested"])
	_update_interface()
	assert(art.brewing and not minimal_brew.text.contains("약초 대기"))
	_set_window_mode(State.WindowMode.FULL)
	assert(herb_plant.is_visible_in_tree() and garden_button.is_visible_in_tree())
	await _capture("shop-herbs-harvest.png")
	state.garden_level = State.MAX_GARDEN_LEVEL
	state.level = State.MAX_LEVEL
	state.herbs = state.herb_capacity()
	state.stock = State.CAPACITY
	state.brew_active = false
	state.set_shop_open(false)
	_update_interface()
	# Full storage pauses the current growth fraction; it does not fake100%.
	assert(garden_button.disabled and upgrade_button.disabled)
	assert(is_equal_approx(garden_bar.value, clampf(state.harvest_elapsed/state.harvest_duration()*100.0,0,100)))
	assert(harvest_label.text.contains("보관함 가득"))
	await _capture("shop-herbs-max.png")
	_set_window_mode(State.WindowMode.MINIMAL)
	await _capture("shop-minimal-herbs-max.png")
	assert(minimal_brew.get_minimum_size().x <= 296, "Even the longest compact status must fit")
	state = State.new()
	income = RecentIncome.new()
	state.gold = 100
	state.herbs = 24
	_set_window_mode(State.WindowMode.FULL)
	_advance_game(12.0)
	_update_interface()
	assert(state.mushrooms == 2 and state.gold == 98 and not state.active_mana)
	assert(not supply_button.visible and state.auto_purchase)
	_advance_game(3.0)
	_update_interface()
	assert(state.active_mana and state.mushrooms == 1 and brew_label.text.contains("마나"))
	_advance_game(6.25)
	_update_interface()
	assert(state.mana_stock == 1 and art.mana_stock == 1)
	await _capture("shop-auto-supply.png")
	var income_before := income.gold
	_advance_game(1.15)
	_update_interface()
	assert(income.gold - income_before == State.MANA_SALE_PRICE, "Recent income must count the actual mana sale price")
	supply_button.pressed.emit()
	assert(state.auto_purchase)
	_set_window_mode(State.WindowMode.MINIMAL)
	await _capture("shop-auto-minimal.png")
	_set_window_mode(State.WindowMode.FULL)
	for card in [supply_card, garden_card, cauldron_card]:
		assert(card.action_button.get_rect().end.x <= card.size.x)
		assert(not card.action_button.get_rect().intersects(card.status_label.get_rect()), "Action price must not overlap the full-width status row")
		assert(card.status_label.get_minimum_size().x <= card.status_label.size.x, "Operation-card status must fit its actual row")
	print("SMOKE PASS: three modes, shared operation cards, manual upgrades, automatic supply without switches, mana priority and actual income, herb recovery, opacity and storage caps")
	get_tree().quit()


func _capture(filename: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://.verification")
		get_viewport().get_texture().get_image().save_png("res://.verification/" + filename)
