extends SceneTree
## Generate production requests for an explicitly authorized desktop installation.
## This headless tool only writes project-local reviewable files; it never executes them.
const Startup = preload("res://scripts/windows_startup.gd")

func _initialize() -> void:
	var folder := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--state-folder="): folder = argument.trim_prefix("--state-folder=")
	assert(not folder.is_empty() and folder.is_absolute_path())
	var output := ProjectSettings.globalize_path("res://.verification/startup-always-20261015")
	assert(DirAccess.make_dir_recursive_absolute(output) == OK)
	var backend := Startup.new(Callable(), {
		"launcher_path": folder.path_join("resume-login.ps1"),
		"session_path": folder.path_join("login_resume.json"),
	})
	var registration := backend.registration_spec()
	var launch := backend.launch_spec()
	assert(registration.ok and launch.ok)
	var install: Dictionary = registration.duplicate(true)
	install["script"] = Startup.LOGIN_SCRIPT
	install["action"] = "install"
	for action in ["install", "query", "remove"]:
		var payload: Dictionary = install if action == "install" else {"action": action}
		var request := backend._prepare_request(payload, output)
		assert(request.ok)
		assert(Startup._native_command_length(registration.powershell, Startup._native_arguments(request.path)) <= Startup.MAX_PROCESS_COMMAND)
		var file := FileAccess.open(output.path_join(action + ".ps1"), FileAccess.WRITE)
		assert(file != null)
		file.store_string(Startup._native_script(request.path))
		file.close()
	var spec_file := FileAccess.open(output.path_join("expected.json"), FileAccess.WRITE)
	spec_file.store_string(JSON.stringify({"registration": registration, "launch": launch}))
	spec_file.close()
	print("PRODUCTION REQUESTS PREPARED: ", output)
	quit()
