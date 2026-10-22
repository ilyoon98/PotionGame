extends SceneTree
## Ordinary headless main-scene boot. No isolated-preview meta or injected guard.
## Refuse to create traps until both APPDATA and user:// are workspace fixtures.
const State = preload("res://scripts/shop_state.gd")
const Compare = preload("res://tests/state_compare.gd")
const LoginResume = preload("res://scripts/login_resume.gd")
var failures := 0
var traps := {}

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("HEADLESS BOOT CHECK FAILED: " + message)

func normalized(path: String) -> String:
	return path.replace("\\", "/").simplify_path().trim_suffix("/").to_lower()

func write_trap(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "Create isolated trap: " + path)
	if file != null:
		file.store_string(JSON.stringify(value, "\t"))
		file.close()
		traps[path] = FileAccess.get_sha256(path)

func traps_unchanged() -> void:
	for path in traps:
		check(FileAccess.get_sha256(path) == traps[path], "Trap byte-identical: " + path)
	for path in ["user://potion_shop.json.tmp", "user://login_resume.json.tmp", "user://resume-login.ps1", "user://native"]:
		check(not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path), "No unexpected headless files/helpers: " + path)

func run() -> void:
	check(DisplayServer.get_name() == "headless", "Headless driver is required")
	check(not has_meta("isolated_preview"), "The ordinary headless path has no opt-in isolation metadata")
	var fixture := normalized(ProjectSettings.globalize_path("res://../.verification")) + "/"
	var appdata := normalized(OS.get_environment("APPDATA"))
	var userdata := normalized(ProjectSettings.globalize_path("user://"))
	var safe := appdata.begins_with(fixture) and userdata.begins_with(appdata + "/")
	check(safe, "APPDATA and resolved user:// must be the workspace fixture before any trap write")
	if not safe:
		quit(1)
		return
	check(DirAccess.make_dir_recursive_absolute("user://") == OK, "Prepare only the isolated user fixture")
	var saved := State.new()
	saved.gold = 777777
	saved.stock = 5
	saved.mana_stock = 1
	saved.inventory = [false, true, false, false, false]
	var economic_trap := saved.to_data()
	var validator := State.new()
	check(validator.load_data(economic_trap), "Trap save would load successfully in a playable process")
	write_trap("user://potion_shop.json", economic_trap)
	write_trap("user://potion_shop.json.bak", economic_trap)
	write_trap("user://login_resume.json", {"owner": LoginResume.OWNER, "version": 1,
		"enabled": true, "was_running": true, "pid": 999999, "started_at": 123.0,
		"executable": "C:\\Fixture\\Moonshade.exe", "args": ["--", "--autostart"]})
	# Also launch the real project entry with no --script, no smoke flag and no
	# metadata. The verified fixture APPDATA is inherited; the child is headless.
	var child_log := "headless-autostart-main-process.log" if "--autostart" in OS.get_cmdline_user_args() else "headless-main-process.log"
	var child_arguments := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--quit-after", "3", "--log-file", ProjectSettings.globalize_path("res://../.verification/" + child_log)])
	if "--autostart" in OS.get_cmdline_user_args(): child_arguments.append_array(["--", "--autostart"])
	var child_output := []
	check(OS.execute(OS.get_executable_path(), child_arguments, child_output, true) == 0, "Ordinary headless project process exits cleanly")
	for line in child_output:
		check(not str(line).contains("SCRIPT ERROR:") and not str(line).contains("ERROR:"), "Ordinary headless project process has no engine/script errors")
	traps_unchanged()
	var scene: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	var shop: Control = scene.instantiate()
	var fresh: Dictionary = shop.state.to_data().duplicate(true)
	root.add_child(shop)
	current_scene = shop
	shop.set_process(false)
	check(shop.test_mode, "Every ordinary headless main boot is test mode")
	check(shop.instance_bypassed and shop.instance_guard.process.is_empty(), "Ordinary headless bypass never launches the native singleton helper")
	check(shop.art != null and shop.workshop_gauges != null, "The actual main UI boots")
	check(shop.state.gold == 0 and shop.state.stock == 0 and shop.state.herbs == State.STARTING_HERBS, "Valid economic trap is not loaded")
	check(Compare.equivalent(fresh, shop.state.to_data()), "Boot and UI do not read or advance the trap economy/RNG")
	check(shop.login_resume.blocked and not shop.login_resume.enabled, "Login recovery stays blocked without isolation metadata")
	var marker: Dictionary = shop.login_resume.snapshot()
	check(not marker.enabled and not marker.was_running and marker.pid == 0 and marker.started_at == 0, "Running trap/PID intent is not loaded or persisted")
	check(not shop.login_resume.startup._loaded, "Blocked login controller never queries native startup")
	traps_unchanged()
	for repeated in 4:
		shop._process(25.0)
		check(shop._save(), "Test-mode save succeeds without storage access")
		check(not shop.set_login_resume(true).ok, "Headless startup setting is blocked")
		check(not shop.set_login_resume(false).ok, "Headless unregister is blocked")
		shop._quit_manually()
		shop._close_shop()
		check(has_meta("manual_quit_requested"), "Explicit headless close records only test metadata")
		traps_unchanged()
	check(Compare.equivalent(fresh, shop.state.to_data()), "Headless process/save/close calls never advance model or RNG")
	print("HEADLESS BOOT RESULT: %d failures; ordinary main scene, no isolation meta, valid economy/login traps untouched, default model/UI, no native helper/registry/PID intent" % failures)
	shop.queue_free()
	quit(1 if failures else 0)
