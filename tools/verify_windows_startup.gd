extends SceneTree
## In-memory registry and explicit PowerShell -DryRun only; never installs startup.
const Startup = preload("res://scripts/windows_startup.gd")
const FIXTURE := "res://.verification/windows-startup-dryrun"
var fixture_path := ""
var source_path := ""
var powershell := ""
var dry_calls := 0
var transport_calls := 0
var transport_complete := false

class RegistryFixture extends RefCounted:
	var values := {"UnrelatedApplication": "keep this value"}
	var calls: Array[String] = []
	var scripts := {}
	var fail := false
	func request(action: String, payload: Dictionary) -> Dictionary:
		calls.append(action)
		if fail: return {"ok": false, "error": "fixture registry failure"}
		if action == "query": return {"ok": true, "exists": values.has(Startup.VALUE_NAME), "command": values.get(Startup.VALUE_NAME, "")}
		if action == "install":
			values[Startup.VALUE_NAME] = payload.command
			scripts[payload.launcher_path] = payload.script
			return {"ok": true}
		if action == "remove":
			values.erase(Startup.VALUE_NAME)
			return {"ok": true}
		return {"ok": false, "error": "unknown fixture request"}

func _initialize() -> void:
	assert(DisplayServer.get_name() == "headless")
	set_meta("isolated_preview", true)
	call_deferred("run")

func context() -> Dictionary:
	return {"os": "Windows", "exported": false, "executable": "C:\\개발 폴더\\Godot_console.exe", "project": "C:\\작업실 &$() ; ' [한글]", "powershell": "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe", "launcher_path": "C:\\Users\\tester\\AppData\\Roaming\\Godot\\app_userdata\\달그늘 물약상점\\resume-login.ps1", "session_path": "C:\\Users\\tester\\AppData\\Roaming\\Godot\\app_userdata\\달그늘 물약상점\\login_resume.json", "file_exists": func(_path: String) -> bool: return true}

func verify_helper() -> void:
	var registry := RegistryFixture.new()
	var helper := Startup.new(registry.request, context())
	assert(registry.calls.is_empty() and not helper.enabled(), "Construction must never opt in or query")
	assert(helper.refresh().ok and not helper.enabled())
	helper.refresh()
	for i in 20:
		helper.enabled()
		helper.status()
	assert(registry.calls == ["query"], "Registry reads are cached, not polled by UI")
	var launch: Dictionary = helper.launch_spec()
	assert(launch.ok and launch.executable == "C:\\개발 폴더\\Godot.exe")
	assert(launch.args == ["--path", "C:\\작업실 &$() ; ' [한글]", "--", "--autostart"])
	assert(not launch.command.contains("--editor") and not launch.command.contains("_console.exe"))
	assert(helper.registration_spec().ok)
	assert(helper.registration_spec().command.length() <= 260)
	assert(helper.registration_spec().command.contains("-WindowStyle \"Hidden\""))
	assert(helper.set_enabled(true).ok and helper.enabled())
	assert(registry.values.UnrelatedApplication == "keep this value")
	assert(registry.scripts.values()[0] == Startup.LOGIN_SCRIPT)
	assert(helper.set_enabled(false).ok and not helper.enabled())
	assert(registry.values == {"UnrelatedApplication": "keep this value"})
	registry.fail = true
	assert(not helper.set_enabled(true).ok and not helper.enabled())
	registry.fail = false
	assert(helper.set_enabled(true).ok)
	registry.fail = true
	assert(not helper.set_enabled(false).ok and helper.enabled(), "A failed removal retains registered state")
	registry.fail = false
	assert(helper.set_enabled(false).ok)
	var moved := context()
	moved.file_exists = func(path: String) -> bool: return not path.ends_with("project.godot")
	var moved_helper := Startup.new(registry.request, moved)
	assert(not moved_helper.launch_spec().ok and not moved_helper.set_enabled(true).ok)
	assert(moved_helper.set_enabled(false).ok, "Removing our own value does not require moved game paths")
	var missing_window := context()
	missing_window.file_exists = func(path: String) -> bool: return not path.ends_with("Godot.exe")
	assert(not Startup.new(registry.request, missing_window).launch_spec().ok)
	var exported := context()
	exported.exported = true
	exported.executable = "C:\\Games\\달그늘 물약상점\\Moonshade.exe"
	var export_spec: Dictionary = Startup.new(registry.request, exported).launch_spec()
	assert(export_spec.ok and export_spec.args == ["--", "--autostart"])
	var too_long := context()
	too_long.launcher_path = "C:\\" + "긴 경로".repeat(100) + "\\resume-login.ps1"
	assert(not Startup.new(registry.request, too_long).registration_spec().ok)
	var unsupported := context()
	unsupported.os = "Linux"
	var before := registry.calls.size()
	assert(not Startup.new(registry.request, unsupported).refresh().ok)
	assert(registry.calls.size() == before)
	var real := Startup.new(Callable(), context())
	assert(not real._native_allowed())
	assert(not real.refresh().ok and not real.set_enabled(true).ok and not real.set_enabled(false).ok)
	assert(not real._native_request("remove", {}).ok, "Headless guard is also enforced at the native implementation")
	assert(Startup.quote_windows("") == "\"\"")
	assert(Startup.quote_windows("a\"b") == "\"a\\\"b\"")
	assert(Startup.quote_windows("C:\\경로\\") == "\"C:\\경로\\\\\"")
	assert(Startup.parse_response(["provider diagnostic\n{\"ok\":true,\"exists\":false}\n"]).ok)
	assert(Startup.LOGIN_SCRIPT.to_utf8_buffer() == FileAccess.get_file_as_bytes(Startup.LAUNCHER_SOURCE), "Runtime embedded login script is byte-identical to source")

func write_json(name: String, data: Dictionary) -> String:
	var path := fixture_path.path_join(name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(data))
	file.close()
	return path

func dry(state: Dictionary, expected: String, process: Dictionary = {}) -> void:
	var session := write_json("login_resume.json", state)
	var args := PackedStringArray(["-NoLogo", "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", source_path, "-DryRun", "-StatePath", session])
	if not process.is_empty():
		args.append_array(["-ProcessFixture", write_json("process.json", process)])
	var bytes := FileAccess.get_file_as_bytes(session)
	var output: Array = []
	# Explicit read-only script mode; registration backend is never invoked here.
	var code := OS.execute(powershell, args, output, false, false)
	assert(not output.is_empty())
	var result: Dictionary = Startup.parse_response(output)
	assert(result is Dictionary, "PowerShell dry-run must return structured JSON: " + str(output))
	assert(code == (0 if result.ok else 1), "Task Scheduler must receive a nonzero exit code for launch errors")
	if result.reason != expected:
		print("DRY-RUN FAILURE expected=", expected, " got=", result)
		quit(1)
		return
	assert(result.dry_run and result.would_launch == (expected == "ready"))
	assert(FileAccess.get_file_as_bytes(session) == bytes, "Dry-run never edits the session marker")
	dry_calls += 1

func verify_launcher() -> void:
	fixture_path = ProjectSettings.globalize_path(FIXTURE)
	assert(DirAccess.make_dir_recursive_absolute(fixture_path) == OK)
	source_path = ProjectSettings.globalize_path(Startup.LAUNCHER_SOURCE)
	powershell = OS.get_environment("SystemRoot").path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
	var executable := fixture_path.path_join("한글 게임 & ; [검사].exe").replace("/", "\\")
	var file := FileAccess.open(executable, FileAccess.WRITE)
	file.store_string("Dry-run fixture only; this is not an executable program.")
	file.close()
	var project := fixture_path.path_join("작업실 $() ' [검사]").replace("/", "\\")
	assert(DirAccess.make_dir_recursive_absolute(project) == OK)
	file = FileAccess.open(project.path_join("project.godot"), FileAccess.WRITE)
	file.store_string("; isolated launch-path fixture, never opened by Godot\n")
	file.close()
	var state := {"owner": "moonshade-potion-shop", "version": 1, "enabled": true, "was_running": true, "executable": executable, "args": ["--", "--autostart"], "pid": 19337, "started_at": 1050.5}
	dry(state, "ready")
	var changed := state.duplicate(true)
	changed.was_running = false
	dry(changed, "ready")
	changed.enabled = false
	dry(changed, "disabled")
	changed = state.duplicate(true)
	changed.enabled = "true"
	dry(changed, "invalid_flags")
	changed = state.duplicate(true)
	changed.owner = "another-application"
	dry(changed, "invalid_owner")
	for version in [true, "1", 2]:
		changed = state.duplicate(true)
		changed.version = version
		dry(changed, "invalid_owner")
	changed = state.duplicate(true)
	changed.executable = executable + ".missing.exe"
	dry(changed, "missing_executable")
	changed = state.duplicate(true)
	changed.args = ["--editor"]
	dry(changed, "invalid_args")
	var dev := state.duplicate(true)
	dev.args = ["--path", project, "--", "--autostart"]
	dry(dev, "ready")
	changed = dev.duplicate(true)
	changed.args[1] = project + "-moved"
	dry(changed, "missing_project")
	var expected_args: Array[String] = []
	expected_args.assign(dev.args)
	var process := {"pid": 19337, "executable": executable, "start_time": 1000.5, "command_line": Startup.windows_command(executable, expected_args)}
	dry(dev, "already_running", process)
	var other := process.duplicate(true)
	other.pid = 19338
	dry(dev, "ready", other)
	other = process.duplicate(true)
	other.start_time = 1051.0
	dry(dev, "ready", other)
	other = process.duplicate(true)
	other.start_time = 980.0
	dry(dev, "ready", other)
	other = process.duplicate(true)
	other.executable += ".different.exe"
	dry(dev, "ready", other)
	other = process.duplicate(true)
	other.command_line = Startup.windows_command(executable, ["--path", project + "-different", "--", "--autostart"])
	dry(dev, "ready", other)
	other = process.duplicate(true)
	other.command_line = ""
	dry(dev, "already_running_unverified", other)
	other = process.duplicate(true)
	other.command_line = Startup.windows_command(executable, ["--path", project, "--", "--workshop"])
	dry(dev, "already_running", other)
	other = process.duplicate(true)
	other.command_line = Startup.windows_command(executable, ["--path", project, "--editor"])
	dry(dev, "ready", other)
	other = process.duplicate(true)
	other.command_line = Startup.windows_command(executable, ["--path", project, "--headless"])
	dry(dev, "ready", other)
	other = process.duplicate(true)
	other.command_line = Startup.windows_command(executable, ["--path", project, "--script", "res://tools/test.gd"])
	dry(dev, "ready", other)
	var manual := dev.duplicate(true)
	manual.running_executable = executable.trim_suffix(".exe") + "_console.exe"
	other = process.duplicate(true)
	other.executable = manual.running_executable
	other.command_line = Startup.windows_command(manual.running_executable, ["--path", project, "--", "--workshop"])
	dry(manual, "already_running", other)
	other.command_line = Startup.windows_command(manual.running_executable, ["--path", "relative/path"])
	dry(manual, "already_running_unverified", other)
	other.command_line = Startup.windows_command(manual.running_executable, ["--path", project + "\\", "--", "--workshop"])
	dry(manual, "already_running", other)
	assert(not FileAccess.file_exists(fixture_path.path_join("login_resume.pending.json")), "Dry-run never creates pending child state")
	var pending := {"owner": "moonshade-potion-shop", "version": 1, "pid": 19337, "started_at": 1000.5, "executable": executable, "args": dev.args}
	var primary := dev.duplicate(true)
	primary.pid = 7
	var pending_path := write_json("login_resume.pending.json", pending)
	var pending_before := FileAccess.get_file_as_bytes(pending_path)
	dry(primary, "already_running_pending", process)
	assert(FileAccess.get_file_as_bytes(pending_path) == pending_before)
	other = process.duplicate(true)
	other.pid = 19338
	dry(primary, "ready", other)
	other = process.duplicate(true)
	other.command_line = Startup.windows_command(executable, ["--path", project, "--", "--workshop"])
	dry(primary, "ready", other)
	other = process.duplicate(true)
	other.start_time = 1001.0
	dry(primary, "ready", other)
	DirAccess.remove_absolute(pending_path)

func probe_transport(request_path: String) -> Dictionary:
	# A fixed producer flag short-circuits every registry/game branch. Execute the
	# same command/UTF8 file parser as production, with a project fixture file only.
	var arguments := Startup._native_arguments(request_path, true)
	assert(arguments[-2] == "-EncodedCommand")
	assert(Marshalls.base64_to_raw(arguments[-1]) == Startup._native_script(request_path, true).to_utf16_buffer())
	assert(Startup._native_command_length(powershell, arguments) < Startup.MAX_PROCESS_COMMAND)
	var output: Array = []
	var code := OS.execute(powershell, arguments, output, false, false)
	assert(code == 0 and not output.is_empty(), "Probe PowerShell must start with the production arguments")
	assert(not FileAccess.file_exists(request_path), "Bootstrap finally deletes only its private request file")
	transport_calls += 1
	return Startup.parse_response(output)

func verify_transport() -> void:
	var directory := fixture_path.path_join("한글 전달 &$() ; ' [검사]")
	var helper := Startup.new(RegistryFixture.new().request, context())
	var payload: Dictionary = helper.registration_spec().duplicate(true)
	payload["action"] = "install"
	payload["script"] = Startup.LOGIN_SCRIPT
	payload["launch_spec"] = helper.launch_spec()
	var prepared := helper._prepare_request(payload, directory)
	assert(prepared.ok, str(prepared.get("error", "")))
	assert(FileAccess.get_file_as_bytes(prepared.path) == JSON.stringify(payload).to_utf8_buffer())
	assert(not FileAccess.file_exists(str(prepared.path) + ".tmp"), "Only complete unique requests are published")
	var other := helper._prepare_request(payload, directory)
	assert(other.ok and other.path != prepared.path, "Requests never share or replace one file")
	var arguments := Startup._native_arguments(prepared.path)
	var size := Startup._native_command_length(powershell, arguments)
	assert(size < Startup.MAX_PROCESS_COMMAND, "The full installer must fit CreateProcessW")
	var decoded := Startup._native_script(prepared.path)
	assert(not decoded.contains(Startup.LOGIN_SCRIPT), "No large source body in the process command")
	# This is the previous nesting even without the rest of its registration body.
	var old_body := "[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('%s')) | ConvertFrom-Json" % Marshalls.utf8_to_base64(JSON.stringify(payload))
	var old_arguments := PackedStringArray(["-EncodedCommand", Marshalls.raw_to_base64(old_body.to_utf16_buffer())])
	assert(Startup._native_command_length(powershell, old_arguments) > Startup.MAX_PROCESS_COMMAND, "Fixture reproduces the previous oversized installer")
	var echoed := probe_transport(prepared.path)
	if echoed.get("ok", false) and echoed.get("payload") is Dictionary:
		for key in payload:
			if echoed.payload.get(key) != payload[key]:
				var before: Variant = payload[key]
				var after: Variant = echoed.payload.get(key)
				print("TRANSPORT DIFFERENCE key=", key, " types=", type_string(typeof(before)), "/", type_string(typeof(after)))
				if before is String and after is String: print("STRING lengths=", before.length(), "/", after.length(), " hashes=", before.sha256_text(), "/", after.sha256_text())
				elif before is Dictionary and after is Dictionary:
					for nested in before:
						if before[nested] != after.get(nested): print("NESTED DIFFERENCE ", nested, " before=", before[nested], " after=", after.get(nested))
	else: print("TRANSPORT PROBE FAILURE ", echoed)
	assert(echoed.ok and echoed.payload == payload, "Actual PowerShell round-trips full source, project, Unicode, metacharacters and quoting")
	assert(FileAccess.file_exists(other.path), "Another pending request is never removed")
	assert(probe_transport(other.path).payload.script == Startup.LOGIN_SCRIPT)
	for action in ["query", "remove"]:
		var request := helper._prepare_request({"action": action}, directory)
		assert(request.ok)
		assert(probe_transport(request.path).payload.action == action, "The same small transport handles each action without accessing HKCU in the probe")
	var malformed := directory.path_join("invalid-request.json")
	var file := FileAccess.open(malformed, FileAccess.WRITE)
	assert(file != null)
	file.store_string("{not valid JSON")
	file.close()
	var rejected := probe_transport(malformed)
	assert(not rejected.ok and not str(rejected.error).is_empty(), "File parser failures return their actual cause and still clean up")
	var blocked_folder := directory.path_join("folder-is-a-file")
	file = FileAccess.open(blocked_folder, FileAccess.WRITE)
	assert(file != null)
	file.store_string("fixture blocks directory creation")
	file.close()
	var failed := helper._prepare_request({}, blocked_folder)
	assert(not failed.ok and str(failed.error).contains("요청 폴더"), "A file preparation failure identifies the failing operation")
	assert(FileAccess.get_file_as_string(blocked_folder) == "fixture blocks directory creation")
	var excessive := Startup._native_arguments("C:\\" + "a".repeat(16000))
	assert(Startup._native_command_length(powershell, excessive) > Startup.MAX_PROCESS_COMMAND, "Length guard measures the real generated argument list")
	print("STARTUP TRANSPORT MEASURE: production installer command ", size, " chars including conservative quotes/prefix/null; previous payload nesting ", Startup._native_command_length(powershell, old_arguments), " chars; external JSON ", JSON.stringify(payload).to_utf8_buffer().size(), " bytes")
	transport_complete = true

func run() -> void:
	verify_helper()
	if "--transport-only" in OS.get_cmdline_user_args():
		fixture_path = ProjectSettings.globalize_path(FIXTURE)
		assert(DirAccess.make_dir_recursive_absolute(fixture_path) == OK)
		powershell = OS.get_environment("SystemRoot").path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
		verify_transport()
		assert(transport_calls == 5 and transport_complete, "All probe and late cleanup/error/length assertions must finish")
		print("WINDOWS STARTUP TRANSPORT PASS: five actual PowerShell echo/parser probes, no registry/game operations")
		quit()
		return
	verify_launcher()
	verify_transport()
	assert(dry_calls >= 30, "Every launcher fixture must complete before success is reported")
	assert(transport_calls == 5 and transport_complete, "Every production-transport probe and late error/length check must finish before success")
	print("WINDOWS STARTUP PASS: opt-in only, cached query, own HKCU value via fake backend; window/export launch specs, Unicode/metacharacter/quote handling, moved paths, 260-char Run bound and 32767-char installer bound, live headless isolation; ", dry_calls, " launcher dry-run cases plus ", transport_calls, " actual PowerShell file-transport echo/parser probes; unique complete requests and finally cleanup; no real registration, player save, game launch or desktop input")
	quit()
