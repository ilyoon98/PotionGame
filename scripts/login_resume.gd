extends RefCounted
## Login startup is separate from game progress. Manual exits keep the preference.
const WindowsStartup = preload("res://scripts/windows_startup.gd")
const OWNER := "moonshade-potion-shop"
const PATH := "user://login_resume.json"
var startup: RefCounted
var marker_path: String
var blocked := false
var enabled := false
var active := false
var status := "꺼짐 · 로그인 때 게임을 자동으로 열지 않아요"
var data := {"owner": OWNER, "version": 1, "enabled": false, "was_running": false, "executable": "", "args": [], "pid": 0, "started_at": 0.0}
var initialized := false
var started_at := 0.0

func _init(backend: RefCounted = null, path: String = PATH, fixture: bool = false) -> void:
	marker_path = path
	blocked = OS.get_name() != "Windows" or DisplayServer.get_name() == "headless" or "--smoke-test" in OS.get_cmdline_user_args()
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.has_meta("isolated_preview"): blocked = true
	if fixture:
		var folder := ProjectSettings.globalize_path("res://.verification/").simplify_path().trim_suffix("/")
		var target := ProjectSettings.globalize_path(path).simplify_path()
		# Tests may only use a supplied backend and files within this project fixture area.
		blocked = backend == null or not target.begins_with(folder + "/")
	startup = backend if backend != null else WindowsStartup.new()

static func should_resume(value: Variant) -> bool:
	return is_owned_state(value) and value.enabled

static func is_owned_state(value: Variant) -> bool:
	if not value is Dictionary or not value.get("owner") is String or value.owner != OWNER: return false
	var version: Variant = value.get("version")
	if not (version is int or version is float) or not is_finite(float(version)) or float(version) != 1.0: return false
	return value.get("enabled") is bool and value.get("was_running") is bool

func snapshot() -> Dictionary:
	return data.duplicate(true)

func _result(ok: bool, error: String = "") -> Dictionary:
	return {"ok": ok, "enabled": enabled, "status": status, "error": error}

func initialize() -> Dictionary:
	if initialized: return _result(true)
	initialized = true
	if blocked:
		status = "자동 시작은 Windows 게임 실행에서 설정할 수 있어요"
		return _result(false, status)
	if FileAccess.file_exists(marker_path):
		var file := FileAccess.open(marker_path, FileAccess.READ)
		if file != null and file.get_length() <= 16384:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if is_owned_state(parsed):
				data = parsed.duplicate(true)
	var registered: Dictionary = startup.refresh()
	enabled = data.enabled and registered.get("ok", false) and registered.get("enabled", false)
	if not registered.get("ok", false):
		status = str(registered.get("error", "자동 시작 등록 상태를 확인하지 못했어요"))
	elif enabled:
		# An existing registration can point at a moved path. Keep the backend's
		# diagnostic instead of presenting every existing Run value as healthy.
		var registration_status := str(registered.get("status", "")).strip_edges()
		status = registration_status if not registration_status.is_empty() else "켜짐 · 종료 여부와 관계없이 Windows 로그인마다 열어요"
	elif data.enabled:
		status = "자동 시작 등록이 없어요 · 켜면 다시 등록해요"
	return _result(registered.get("ok", false), str(registered.get("error", "")))

func _write(value: Dictionary) -> Error:
	if blocked: return ERR_UNAVAILABLE
	var temporary := marker_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(value))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK: return error
	return DirAccess.rename_absolute(temporary, marker_path)

func _running_data(value: Dictionary, spec: Dictionary) -> Dictionary:
	var updated := value.duplicate(true)
	updated.owner = OWNER
	updated.version = 1
	updated.executable = spec.executable
	updated.args = Array(spec.args)
	updated.pid = OS.get_process_id()
	updated.started_at = started_at
	# Current process identity differs from the next-login launch arguments.
	updated.running_executable = OS.get_executable_path()
	updated.was_running = active
	return updated

func start_session() -> Dictionary:
	active = true
	started_at = Time.get_unix_time_from_system()
	initialize()
	if blocked or not enabled: return _result(not blocked)
	var spec: Dictionary = startup.launch_spec()
	if not spec.get("ok", false):
		status = str(spec.get("error", "게임 실행 파일을 확인하지 못했어요"))
		return _result(false, status)
	var updated := _running_data(data, spec)
	if _write(updated) != OK:
		status = "실행 상태를 기록하지 못했어요 · 자동 시작을 다시 켜 주세요"
		return _result(false, status)
	data = updated
	return _result(true)

func set_enabled(value: bool) -> Dictionary:
	initialize()
	if blocked: return _result(false, status)
	if value:
		var spec: Dictionary = startup.launch_spec()
		if not spec.get("ok", false):
			status = str(spec.get("error", "실행 파일을 확인하지 못했어요"))
			return _result(false, status)
		var previous := data.duplicate(true)
		var updated := _running_data(data, spec)
		updated.enabled = true
		if _write(updated) != OK:
			status = "자동 시작 설정을 저장하지 못했어요"
			return _result(false, status)
		var registration: Dictionary = startup.set_enabled(true)
		if not registration.get("ok", false):
			if _write(previous) != OK:
				var removal: Dictionary = startup.set_enabled(false)
				if removal.get("ok", false):
					enabled = false
					data = previous
					data.enabled = false
					data.was_running = false
					status = "등록에 실패해 자동 시작을 해제했어요 · 설정 파일 복구도 실패했어요"
				else:
					# Disk may still authorize the retained Run value; show the uncertain
					# enabled state so the user can retry disabling it explicitly.
					data = updated
					enabled = true
					status = "설정 복구에 실패했어요 · 다음 로그인 때 게임이 다시 켜질 수 있어요"
				return _result(false, status)
			status = str(registration.get("error", "자동 시작을 등록하지 못했어요"))
			return _result(false, status)
		data = updated
		enabled = true
		status = "켜짐 · 종료 여부와 관계없이 Windows 로그인마다 열어요"
	else:
		var registration: Dictionary = startup.set_enabled(false)
		if not registration.get("ok", false):
			status = str(registration.get("error", "자동 시작을 해제하지 못했어요"))
			return _result(false, status)
		var updated := data.duplicate(true)
		updated.enabled = false
		updated.was_running = false
		enabled = false
		data = updated
		status = "꺼짐 · 로그인 때 게임을 자동으로 열지 않아요"
		if _write(updated) != OK:
			status = "자동 시작은 해제했지만 설정 파일을 저장하지 못했어요"
			return _result(false, status)
	return _result(true)

func manual_closed() -> Dictionary:
	# was_running is diagnostic identity only; closing never disables login startup.
	active = false
	if blocked: return _result(true)
	if not data.enabled: return _result(true)
	var updated := data.duplicate(true)
	updated.was_running = false
	if _write(updated) != OK:
		status = "종료 상태를 기록하지 못했어요 · 로그인 자동 실행 설정은 유지돼요"
		return _result(true)
	data = updated
	return _result(true)
