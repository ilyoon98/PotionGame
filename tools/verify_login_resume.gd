extends SceneTree
## Fixture-only lifecycle checks. No native registration, player save or visible window.
const LoginResume = preload("res://scripts/login_resume.gd")
const Shop = preload("res://scripts/shop.gd")
const Compare = preload("res://tests/state_compare.gd")
var fixture_directory := ""
var failures := 0

class FakeStartup extends RefCounted:
	var registered := false
	var refresh_calls := 0
	var install_calls := 0
	var remove_calls := 0
	var fail_install := false
	var fail_remove := false
	var fail_spec := false
	var refresh_status: Variant = null
	func refresh() -> Dictionary:
		refresh_calls += 1
		var message := "켜짐 · 종료 여부와 관계없이 Windows 로그인마다 열어요." if registered else "꺼짐 · 로그인 때 게임을 다시 열지 않아요."
		return {"ok": true, "enabled": registered, "status": message if refresh_status == null else refresh_status, "error": ""}
	func launch_spec() -> Dictionary:
		if fail_spec: return {"ok": false, "error": "격리된 실행 파일 이동 오류"}
		return {"ok": true, "executable": "C:\\Fixture Only\\Moonshade.exe", "args": ["--", "--autostart"], "error": ""}
	func set_enabled(value: bool) -> Dictionary:
		if value: install_calls += 1
		else: remove_calls += 1
		if (value and fail_install) or (not value and fail_remove):
			return {"ok": false, "enabled": registered, "status": "격리된 등록 오류", "error": "격리된 등록 오류"}
		registered = value
		return {"ok": true, "enabled": registered, "status": "격리된 등록 완료", "error": ""}

class FailingResume extends LoginResume:
	var fail_write := false
	var write_calls := 0
	var fail_on_write_call := 0
	func _init(backend: RefCounted, path: String) -> void:
		super(backend, path, true)
	func _write(value: Dictionary) -> Error:
		write_calls += 1
		return ERR_FILE_CANT_WRITE if fail_write or write_calls == fail_on_write_call else super._write(value)

class FixtureShop extends Shop:
	var save_ok := true
	func _save() -> bool:
		return save_ok

func _initialize() -> void:
	set_meta("isolated_preview", true)
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("LOGIN RESUME CHECK FAILED: " + message)

func path_for(name: String) -> String:
	return fixture_directory.path_join(name + ".json")

func read_marker(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func create_session(name: String, backend: FakeStartup) -> RefCounted:
	var controller := LoginResume.new(backend, path_for(name), true)
	check(not controller.blocked, "An injected fixture may use only this project's verification directory")
	check(controller.initialize().ok, "Initialize the in-memory backend")
	check(controller.start_session().ok, "Begin the simulated game session")
	return controller

func enable_session(name: String, backend: FakeStartup) -> RefCounted:
	var controller := create_session(name, backend)
	check(controller.set_enabled(true).ok, "Explicit enable records the running session and registers once")
	check(controller.enabled and backend.registered and LoginResume.should_resume(read_marker(path_for(name))), "Enabled sessions can start at login")
	return controller

func verify_controller() -> void:
	var backend := FakeStartup.new()
	var fresh := create_session("initial-off", backend)
	check(not fresh.enabled and not LoginResume.should_resume(fresh.snapshot()), "Initial setting is off")
	check(fresh.status.begins_with("꺼짐"), "Fresh state remains off, without a registration warning")
	check(not FileAccess.file_exists(path_for("initial-off")), "Off sessions do not create a login marker")
	check(backend.install_calls == 0 and backend.remove_calls == 0, "Initialization never registers automatically")
	for i in 8: fresh.initialize()
	check(backend.refresh_calls == 1, "Repeated initialization reads registration only once")
	var valid: Dictionary = fresh.snapshot()
	valid.enabled = true
	valid.was_running = true
	check(LoginResume.should_resume(valid), "A valid previously running marker passes the bootstrap gate")
	var closed := valid.duplicate(true)
	closed.was_running = false
	check(LoginResume.should_resume(closed), "An enabled manually closed marker also passes the game bootstrap gate")
	for key in ["enabled", "was_running"]:
		for value in [false, 0, 1, "true", null]:
			if key == "was_running" and value is bool: continue
			var bad := valid.duplicate(true)
			bad[key] = value
			check(not LoginResume.should_resume(bad), "Bootstrap requires true booleans: " + key)
	for modification in [{"owner": "some-other-app"}, {"owner": 1}, {"owner": false}, {"owner": null}, {"version": 0}, {"version": 2}, {"version": "1"}, {"version": true}, {"version": null}, {"version": NAN}, {"version": INF}]:
		var bad := valid.duplicate(true)
		bad.merge(modification, true)
		check(not LoginResume.should_resume(bad), "Foreign/versioned markers are denied")
	for key in ["owner", "version", "enabled", "was_running"]:
		var incomplete := valid.duplicate(true)
		incomplete.erase(key)
		check(not LoginResume.should_resume(incomplete), "Missing bootstrap fields are denied: " + key)
	check(not LoginResume.should_resume(null) and not LoginResume.should_resume([]), "Non-object markers are denied")
	var denied_backend := FakeStartup.new()
	var denied := LoginResume.new(denied_backend, path_for("headless-blocked"))
	check(denied.blocked and not denied.initialize().ok, "Ordinary headless/isolated construction stays blocked")
	denied.start_session()
	denied.set_enabled(true)
	check(denied_backend.refresh_calls == 0 and denied_backend.install_calls == 0 and not FileAccess.file_exists(path_for("headless-blocked")), "Blocked code never touches registration or state files")
	var escaped := LoginResume.new(denied_backend, "user://login_resume.json", true)
	check(escaped.blocked, "Fixture injection cannot authorize real user storage")
	var sibling := LoginResume.new(denied_backend, "res://.verification-sibling/login_resume.json", true)
	check(sibling.blocked, "The fixture boundary requires a directory separator")
	var missing_backend := LoginResume.new(null, path_for("missing-backend"), true)
	check(missing_backend.blocked, "Fixtures require an injected backend")
	for modification in [{"owner": false}, {"version": "1"}, {"enabled": "true"}, {"was_running": 1}]:
		var invalid_path := path_for("invalid-json-%d" % failures) + "-%d" % Time.get_ticks_usec()
		var invalid_data := valid.duplicate(true)
		invalid_data.merge(modification, true)
		var file := FileAccess.open(invalid_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(invalid_data))
		file.close()
		var invalid_backend := FakeStartup.new()
		invalid_backend.registered = true
		var invalid := LoginResume.new(invalid_backend, invalid_path, true)
		invalid.initialize()
		check(not invalid.enabled and not LoginResume.should_resume(invalid.snapshot()), "Malformed owned fields are ignored without a type error")
	var failure_backend := FakeStartup.new()
	failure_backend.fail_install = true
	var failed := create_session("enable-failure", failure_backend)
	check(not failed.set_enabled(true).ok and not failed.enabled and not failure_backend.registered, "Failed registration leaves the setting off")
	check(not LoginResume.should_resume(read_marker(path_for("enable-failure"))), "Failed enable rolls back the previously off marker")
	check(failure_backend.install_calls == 1, "A failed enable is attempted once")
	# An existing startup entry makes a failed marker rollback consequential:
	# the launcher can still read the new enabled/running marker from disk.
	var rollback_backend := FakeStartup.new()
	rollback_backend.registered = true
	rollback_backend.fail_install = true
	var rollback := FailingResume.new(rollback_backend, path_for("enable-rollback-failure"))
	rollback.start_session()
	rollback.fail_on_write_call = 2
	check(not rollback.set_enabled(true).ok, "A failed enable plus rollback is reported as an error")
	check(rollback.write_calls == 2 and rollback_backend.remove_calls == 1, "A failed second write triggers one registration-removal fallback")
	check(not rollback.enabled and not rollback_backend.registered and not rollback.snapshot().enabled and not rollback.snapshot().was_running, "Successful fallback removes the launcher entry and presents the off state")
	check(LoginResume.should_resume(read_marker(path_for("enable-rollback-failure"))), "This fixture really retains the first write, so absence of the Run entry matters")
	var rollback_both_backend := FakeStartup.new()
	rollback_both_backend.registered = true
	rollback_both_backend.fail_install = true
	rollback_both_backend.fail_remove = true
	var rollback_both := FailingResume.new(rollback_both_backend, path_for("enable-rollback-and-removal-failure"))
	rollback_both.start_session()
	rollback_both.fail_on_write_call = 2
	check(not rollback_both.set_enabled(true).ok and rollback_both_backend.remove_calls == 1, "Both enable-recovery failures are reported, without retries")
	check(rollback_both.enabled and rollback_both_backend.registered and LoginResume.should_resume(rollback_both.snapshot()), "When the entry and eligible marker remain, the setting cannot falsely show off")
	check(Compare.equivalent(rollback_both.snapshot(), read_marker(path_for("enable-rollback-and-removal-failure"))), "Unrecovered state matches the actual marker left on disk")
	check(rollback_both.status.contains("다음 로그인") and rollback_both.status.contains("다시 켜질"), "Unrecovered state explains the possible next-login launch")
	var enabled_backend := FakeStartup.new()
	var enabled := enable_session("disable-failure", enabled_backend)
	var saved: Dictionary = enabled.snapshot()
	var text := FileAccess.get_file_as_string(path_for("disable-failure"))
	enabled_backend.fail_remove = true
	check(not enabled.set_enabled(false).ok and enabled.enabled and enabled_backend.registered, "Failed removal preserves the active setting")
	check(Compare.equivalent(saved, enabled.snapshot()) and FileAccess.get_file_as_string(path_for("disable-failure")) == text, "Failed disable preserves the resume marker")
	enabled_backend.fail_remove = false
	check(enabled.set_enabled(false).ok and not enabled.enabled and not enabled_backend.registered, "Successful disable removes only the simulated startup entry")
	check(not LoginResume.should_resume(read_marker(path_for("disable-failure"))), "A disabled marker cannot resume")
	var manual_backend := FakeStartup.new()
	var manual := enable_session("manual-close", manual_backend)
	check(manual.manual_closed().ok and not manual.active, "Explicit game exit ends the running session")
	check(manual.snapshot().enabled and not manual.snapshot().was_running and manual_backend.registered, "Manual exit keeps the preference and registration")
	check(LoginResume.should_resume(read_marker(path_for("manual-close"))), "Manual exit persists was_running=false without vetoing next login")
	var reopened := LoginResume.new(manual_backend, path_for("manual-close"), true)
	check(reopened.initialize().ok and reopened.enabled and reopened.start_session().ok, "A later manual launch re-arms an enabled preference")
	check(LoginResume.should_resume(read_marker(path_for("manual-close"))), "The later active game can resume after session end")
	var fallback_backend := FakeStartup.new()
	var fallback := FailingResume.new(fallback_backend, path_for("marker-failure"))
	fallback.start_session()
	check(fallback.set_enabled(true).ok, "Prepare an enabled fixture for close-write failures")
	fallback.fail_write = true
	check(fallback.manual_closed().ok and fallback.enabled and fallback_backend.registered and not fallback.active, "Failed close-marker write allows exit and preserves login startup")
	check(fallback_backend.remove_calls == 0 and fallback.snapshot().enabled, "Closing never removes startup registration")
	var both_backend := FakeStartup.new()
	var both := FailingResume.new(both_backend, path_for("both-close-failures"))
	both.start_session()
	check(both.set_enabled(true).ok, "Prepare simultaneous fixture failures")
	var old := both.snapshot()
	both.fail_write = true
	both_backend.fail_remove = true
	check(both.manual_closed().ok and not both.active and both.enabled and both_backend.remove_calls == 0, "A diagnostic write failure never attempts to remove registration or blocks exit")
	check(Compare.equivalent(old, both.snapshot()), "Both failures do not falsely record a manual exit")
	var moved_backend := FakeStartup.new()
	moved_backend.fail_spec = true
	var moved := create_session("moved-executable", moved_backend)
	check(not moved.set_enabled(true).ok and moved_backend.install_calls == 0, "Invalid executable specifications never register")
	# Check the actual enabled response contract: an entry can exist at a wrong
	# path, so its warning must survive controller initialization and UI display.
	for index in 4:
		var warning_backend := FakeStartup.new()
		var fixture_name := "registration-message-%d" % index
		enable_session(fixture_name, warning_backend)
		var warning: String = ["등록 경로가 현재 위치와 달라요. 다시 켜면 현재 위치로 갱신해요.", "자동 시작 경로가 너무 길어요(260자 초과).", "켜짐 · 종료 여부와 관계없이 Windows 로그인마다 열어요.", ""][index]
		warning_backend.refresh_status = warning
		var marker_before := FileAccess.get_file_as_string(path_for(fixture_name))
		var restored := LoginResume.new(warning_backend, path_for(fixture_name), true)
		var result := restored.initialize()
		check(result.ok and restored.enabled, "Read an enabled registration without changing the preference")
		check(restored.status == warning if not warning.is_empty() else restored.status.begins_with("켜짐"), "Keep a path/specification warning, normal enabled message or blank-message fallback")
		check(result.status == restored.status and FileAccess.get_file_as_string(path_for(fixture_name)) == marker_before, "The returned diagnostic matches the controller and does not rewrite the marker")
		for repeat in 4: restored.initialize()
		check(warning_backend.refresh_calls == 2 and warning_backend.install_calls == 1 and warning_backend.remove_calls == 0, "Diagnostic initialization remains cached and does not repair registration implicitly")
		var warning_shop: Control = new_shop(restored)
		var economy_before: Dictionary = warning_shop.state.to_data().duplicate(true)
		warning_shop.open_management()
		warning_shop.management.set_process(false)
		warning_shop.management.select_page(warning_shop.ManagementPanel.UPGRADES)
		warning_shop.management._refresh_startup_setting()
		check(warning_shop.management.startup_toggle.button_pressed and warning_shop.management.startup_status.text == restored.status, "Management shows the actual enabled registration diagnostic verbatim")
		check(warning_backend.refresh_calls == 2 and warning_backend.install_calls == 1 and FileAccess.get_file_as_string(path_for(fixture_name)) == marker_before, "Opening and refreshing management neither rewrites the marker nor changes registration")
		check(Compare.equivalent(economy_before, warning_shop.state.to_data()), "Registration diagnostic display does not change economy, progress, fees or RNG")
		warning_shop.queue_free()
	# A previously enabled preference without its entry is still an explicit
	# repair action; preserving diagnostics must not silently turn it back on.
	var missing_registration := FakeStartup.new()
	enable_session("missing-registration", missing_registration)
	missing_registration.registered = false
	missing_registration.refresh_status = "꺼짐 · 로그인 때 게임을 다시 열지 않아요."
	var absent := LoginResume.new(missing_registration, path_for("missing-registration"), true)
	absent.initialize()
	check(not absent.enabled and absent.status == "자동 시작 등록이 없어요 · 켜면 다시 등록해요", "The missing-registration branch keeps its actionable off diagnostic")
	check(missing_registration.install_calls == 1 and missing_registration.remove_calls == 0, "A missing entry never registers itself during initialization")

func new_shop(controller: RefCounted) -> Control:
	var shop := FixtureShop.new()
	root.add_child(shop)
	shop.set_process(false)
	check(shop.login_resume.blocked, "Ordinary isolated Shop cannot use real OS startup settings")
	shop.login_resume = controller
	return shop

func closing_dialog(shop: Control) -> ConfirmationDialog:
	for child in shop.get_children():
		if child is ConfirmationDialog and not child.is_queued_for_deletion(): return child
	return null

func verify_ui_and_close() -> void:
	var ordinary := FixtureShop.new()
	root.add_child(ordinary)
	ordinary.set_process(false)
	ordinary.open_management()
	ordinary.management.set_process(false)
	check(ordinary.login_resume.blocked and ordinary.management.startup_toggle.disabled and not ordinary.management.startup_toggle.button_pressed, "Ordinary isolated UI keeps OS startup changes disabled")
	ordinary.queue_free()
	await process_frame
	var backend := FakeStartup.new()
	var controller := create_session("ui-toggle", backend)
	var shop: Control = new_shop(controller)
	shop.open_management()
	var panel: Window = shop.management
	panel.set_process(false)
	panel.select_page(panel.UPGRADES)
	await process_frame
	await process_frame
	check(not panel.startup_toggle.disabled and not panel.startup_toggle.button_pressed, "The injected fixture displays its cached off setting")
	var economy: Dictionary = shop.state.to_data().duplicate(true)
	panel.startup_toggle.button_pressed = true
	check(controller.enabled and backend.install_calls == 1 and panel.startup_toggle.button_pressed, "The real toggle signal registers the explicit setting once")
	for i in 12:
		panel.refresh()
		panel._refresh_startup_setting()
	check(backend.refresh_calls == 1 and backend.install_calls == 1, "Periodic UI refresh performs no repeated registry queries or installations")
	check(Compare.equivalent(economy, shop.state.to_data()), "Setting and refresh preserve economy, ingredients, timers, fees and RNG")
	backend.fail_remove = true
	panel.startup_toggle.button_pressed = false
	check(controller.enabled and panel.startup_toggle.button_pressed and panel.startup_status.text == controller.status, "Failed removal visibly restores the actual enabled toggle")
	backend.fail_remove = false
	var running_marker: Dictionary = controller.snapshot()
	panel.close_requested.emit()
	check(not panel.visible and Compare.equivalent(running_marker, controller.snapshot()), "Closing management only hides it; the game is still running")
	# Save failure cancellation is neither a manual exit nor a successful save.
	shop.save_ok = false
	set_meta("manual_quit_requested", false)
	shop._close_shop()
	var dialog := closing_dialog(shop)
	check(dialog != null and controller.snapshot().was_running and not get_meta("manual_quit_requested"), "Save failure waits for the user's decision")
	if dialog != null: dialog.canceled.emit()
	await process_frame
	check(controller.snapshot().was_running and not get_meta("manual_quit_requested"), "Canceling failed-save closure retains the running marker")
	shop._close_shop()
	dialog = closing_dialog(shop)
	if dialog != null: dialog.confirmed.emit()
	check(get_meta("manual_quit_requested") and not read_marker(path_for("ui-toggle")).was_running, "Confirming exit without saving records a real manual close")
	check(Compare.equivalent(economy, shop.state.to_data()), "Closing cannot mutate the simulation or roll rewards")
	shop.queue_free()
	await process_frame
	# Actual main close signal uses the same successful-save commit path.
	var close_backend := FakeStartup.new()
	var close_controller := enable_session("main-close-signal", close_backend)
	shop = new_shop(close_controller)
	set_meta("manual_quit_requested", false)
	root.close_requested.emit()
	check(get_meta("manual_quit_requested") and not read_marker(path_for("main-close-signal")).was_running, "Main-window close commits manual exit after a successful save")
	shop.queue_free()
	await process_frame
	# A failed diagnostic write must neither remove startup nor block normal exit.
	var failure_backend := FakeStartup.new()
	var failure_session := FailingResume.new(failure_backend, path_for("failed-close-dialog"))
	failure_session.start_session()
	check(failure_session.set_enabled(true).ok, "Prepare a fixture for the failed-close confirmation")
	failure_session.fail_write = true
	failure_backend.fail_remove = true
	shop = new_shop(failure_session)
	set_meta("manual_quit_requested", false)
	shop._close_shop()
	dialog = closing_dialog(shop)
	check(dialog == null and get_meta("manual_quit_requested"), "Diagnostic close-write failure exits without an obsolete confirmation dialog")
	check(LoginResume.should_resume(read_marker(path_for("failed-close-dialog"))) and failure_backend.remove_calls == 0, "Failed close writing preserves login startup")
	shop.queue_free()
	await process_frame
	# Teardown without an explicit close models session/process ending. Do not
	# claim a real Windows logout, crash or power-off test.
	var session_backend := FakeStartup.new()
	var session := enable_session("session-end", session_backend)
	shop = new_shop(session)
	var before := FileAccess.get_file_as_string(path_for("session-end"))
	shop.queue_free()
	await process_frame
	check(FileAccess.get_file_as_string(path_for("session-end")) == before and LoginResume.should_resume(read_marker(path_for("session-end"))), "Generic teardown preserves the enabled running marker")
	check(session_backend.remove_calls == 0, "Generic teardown never removes startup registration")

func run() -> void:
	check(DisplayServer.get_name() == "headless", "This verification requires headless execution")
	if failures > 0:
		quit(1)
		return
	fixture_directory = "res://.verification/login-resume-tests/run-%d" % Time.get_ticks_usec()
	check(DirAccess.make_dir_recursive_absolute(fixture_directory) == OK, "Create a project-local fixture directory")
	verify_controller()
	await verify_ui_and_close()
	if failures == 0:
		print("LOGIN STARTUP PASS: enabled closed/running bootstrap, opt-out, strict schema, isolation, registration warnings/UI cache, enable/disable failures, manual exit retains startup including diagnostic-write failure, management toggle/save failure/main close signals, economy/RNG unchanged; real registration and login trigger require desktop validation")
	else:
		print("LOGIN RESUME FAILED: %d checks" % failures)
	quit(0 if failures == 0 else 1)
