extends Node
## OS tray controls are views of the existing game; never replace its state.
const Taskbar = preload("res://scripts/tray_taskbar.gd")
const ICON = preload("res://icon.png")
var host: Control
var indicator := -1
var menu := RID()
var taskbar: Node
var active := false
var hidden_to_tray := false
var elapsed := 0.0
var last_tooltip := ""

func _ready() -> void: start.call_deferred()

func start() -> bool:
	if active: return true
	if OS.get_name() != "Windows" or DisplayServer.get_name() == "headless": return false
	if host.test_mode and not get_tree().has_meta("tray_verification"): return false
	if not DisplayServer.has_feature(DisplayServer.FEATURE_STATUS_INDICATOR) or not NativeMenu.has_feature(NativeMenu.FEATURE_POPUP_MENU): return false
	menu = NativeMenu.create_menu()
	if not menu.is_valid(): return false
	NativeMenu.add_item(menu,"게임 숨기기",_menu_action,Callable(),"toggle")
	NativeMenu.add_item(menu,"관리 열기",_menu_action,Callable(),"manage")
	NativeMenu.add_item(menu,"통계 보기",_menu_action,Callable(),"statistics")
	NativeMenu.add_separator(menu)
	NativeMenu.add_item(menu,"저장 후 종료",_menu_action,Callable(),"quit")
	indicator = DisplayServer.create_status_indicator(ICON,"달그늘 물약상점",_pressed)
	if indicator < 0:
		NativeMenu.free_menu(menu)
		menu = RID()
		return false
	DisplayServer.status_indicator_set_menu(indicator,menu)
	active = true
	taskbar = Taskbar.new()
	add_child(taskbar)
	taskbar.unavailable.connect(_taskbar_failed)
	# Never remove the normal taskbar access route before the icon exists.
	var connected: bool = await taskbar.start_for(host.get_window(),indicator)
	if not connected: _taskbar_failed()
	elif host.management != null and host.management.visible: register_window(host.management)
	refresh()
	return true

func _pressed(button: int,_position: Vector2i) -> void:
	if button == MOUSE_BUTTON_LEFT: _menu_action("toggle")

func _menu_action(action: Variant) -> void: _dispatch.call_deferred(str(action))

func _dispatch(action: String) -> void:
	match action:
		"toggle":
			if hidden_to_tray or host.get_window().mode == Window.MODE_MINIMIZED: show_game()
			else: hide_game()
		"manage":
			show_game()
			host.open_management()
		"statistics":
			show_game()
			host.open_management_page(host.ManagementPanel.REPORT)
		"quit":
			show_game()
			host._close_shop()

func hide_game() -> void:
	if not active: return
	host.workshop_dragging = false
	if host.management != null: host.management.hide()
	host.desktop_input.set_enabled(false)
	# Godot forbids hiding its main Window. Minimize it while the helper keeps
	# its taskbar tab suppressed; the simulation and autosave keep processing.
	host.get_window().mode = Window.MODE_MINIMIZED
	hidden_to_tray = true
	refresh()

func show_game() -> void:
	var window := host.get_window()
	if window.mode == Window.MODE_MINIMIZED:
		window.mode = Window.MODE_WINDOWED
	hidden_to_tray = false
	host._apply_window_mode()
	if DisplayServer.get_name() != "headless": window.grab_focus()
	register_window(window)
	if taskbar != null: taskbar.restore_main()
	refresh()

func register_window(window: Window) -> void:
	if active and taskbar != null and taskbar.connected and not taskbar.stopping:
		if not taskbar.register_window(window): _taskbar_failed()

func _taskbar_failed() -> void:
	if taskbar != null: taskbar.stop()
	# The helper restores its original taskbar bits on EOF/failure. Make the game
	# visible too, so failure never strands a running, unsaved hidden game.
	if hidden_to_tray: show_game()
	push_warning("Taskbar hiding unavailable; restoring normal taskbar access. "+taskbar.last_error)

func refresh() -> void:
	if not active: return
	var tooltip := "달그늘 물약상점 · %s G · 재고 %d/%d" % [host._compact_number(host.state.gold),host.state.stock,host.state.capacity()]
	if tooltip != last_tooltip:
		DisplayServer.status_indicator_set_tooltip(indicator,tooltip)
		last_tooltip = tooltip
	NativeMenu.set_item_text(menu,0,"게임 보이기" if hidden_to_tray or host.get_window().mode == Window.MODE_MINIMIZED else "게임 숨기기")

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= 1.0:
		elapsed = 0
		refresh()

func _exit_tree() -> void:
	if taskbar != null: taskbar.stop()
	if indicator >= 0:
		DisplayServer.delete_status_indicator(indicator)
		indicator = -1
	if menu.is_valid():
		NativeMenu.free_menu(menu)
		menu = RID()
	active = false
