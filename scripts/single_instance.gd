extends Node
## Claim before saves/login/model ticks. An OS mutex survives no crashed owner.
const Binary = preload("res://native/windows/single_instance_binary.gd")
const APP_ID := "moonshade-potion-shop"
var process := {}
var executable := ""
var _owned := false
var _namespace := ""
var _last := {"ok": true, "owner": false, "bypassed": true, "error": ""}
signal lost

func _ready() -> void: set_process(false)

func acquire() -> Dictionary:
	if _owned: return _last.duplicate()
	if OS.get_name() != "Windows" or DisplayServer.get_name() == "headless" or "--smoke-test" in OS.get_cmdline_user_args() or get_tree().has_meta("isolated_preview"):
		_last = {"ok": true, "owner": false, "bypassed": true, "error": ""}
		return _last.duplicate()
	var identity := ProjectSettings.globalize_path("user://").replace("/", "\\").to_lower().trim_suffix("\\")
	return _claim(APP_ID + "|" + identity, false)

func acquire_isolated(verification_namespace: String) -> Dictionary:
	# Only a deliberate headless fixture can start a test-only helper.
	if OS.get_name() != "Windows" or DisplayServer.get_name() != "headless" or not get_tree().has_meta("isolated_preview") or not verification_namespace.begins_with("verify-"):
		return {"ok": false, "owner": false, "bypassed": false, "error": "격리된 검증 네임스페이스가 필요해요."}
	if _owned:
		if _namespace == "verification|" + verification_namespace: return _last.duplicate()
		return {"ok": false, "owner": true, "bypassed": false, "error": "이미 다른 검증 잠금을 보유하고 있어요."}
	return _claim("verification|" + verification_namespace, true)

func is_owner() -> bool:
	return _owned and not process.is_empty() and OS.is_process_running(process.pid)

static func mutex_name(identity: String) -> String:
	return "Local\\MoonshadePotionShop.Instance." + identity.sha256_text().left(32)

func _claim(identity: String, isolated: bool) -> Dictionary:
	if not process.is_empty(): release()
	var bytes := Marshalls.base64_to_raw(Binary.BASE64)
	var folder := "res://.verification/single-instance-native" if isolated else "user://native"
	if DirAccess.make_dir_recursive_absolute(folder) != OK: return _fail("단일 실행 보호 파일을 준비하지 못했어요.")
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	executable = ProjectSettings.globalize_path(folder.path_join("single-instance-" + hash.finish().hex_encode().left(16)).path_join("guard.exe"))
	if not _publish_binary(bytes): return _fail("단일 실행 보호 파일을 준비하지 못했어요.")
	process = OS.execute_with_pipe(executable, PackedStringArray([str(OS.get_process_id()), mutex_name(identity)]), false)
	if process.is_empty(): return _fail("단일 실행 보호를 시작하지 못했어요.")
	var deadline := Time.get_ticks_msec() + 5000
	var reply := ""
	while Time.get_ticks_msec() < deadline:
		var available: int = process.stdio.get_length()
		if available > 0: reply += process.stdio.get_buffer(available).get_string_from_utf8()
		if reply.contains("\n"): break
		if not OS.is_process_running(process.pid): break
		OS.delay_msec(5)
	var decision := reply.strip_edges()
	if decision == "DUPLICATE":
		release()
		_last = {"ok": true, "owner": false, "bypassed": false, "error": ""}
		return _last.duplicate()
	if decision != "OWNER":
		release()
		return _fail("같은 게임의 실행 여부를 확인하지 못했어요.")
	_owned = true
	_namespace = identity
	_last = {"ok": true, "owner": true, "bypassed": false, "error": ""}
	set_process(true)
	return _last.duplicate()

func _publish_binary(bytes: PackedByteArray) -> bool:
	if FileAccess.file_exists(executable) and FileAccess.get_file_as_bytes(executable) == bytes: return true
	# Windows Godot file rename deletes an existing target first. Publish a whole
	# completed directory instead: MoveFileW cannot replace the winner's directory.
	var destination := executable.get_base_dir()
	var temporary := destination + ".tmp-" + str(OS.get_process_id()) + "-" + str(get_instance_id()) + "-" + str(Time.get_ticks_usec())
	if DirAccess.make_dir_absolute(temporary) != OK: return false
	var temporary_executable := temporary.path_join(executable.get_file())
	var file := FileAccess.open(temporary_executable, FileAccess.WRITE)
	if file == null:
		DirAccess.remove_absolute(temporary)
		return false
	file.store_buffer(bytes)
	file.close()
	if FileAccess.get_file_as_bytes(temporary_executable) != bytes:
		DirAccess.remove_absolute(temporary_executable)
		DirAccess.remove_absolute(temporary)
		return false
	var published := DirAccess.rename_absolute(temporary, destination)
	var ready := FileAccess.file_exists(executable) and FileAccess.get_file_as_bytes(executable) == bytes
	if published != OK or DirAccess.dir_exists_absolute(temporary):
		DirAccess.remove_absolute(temporary_executable)
		DirAccess.remove_absolute(temporary)
	return ready

func _process(_delta: float) -> void:
	if not _owned or process.is_empty() or OS.is_process_running(process.pid): return
	_owned = false
	_close_pipes()
	_last = {"ok": false, "owner": false, "bypassed": false, "error": "단일 실행 보호가 종료되었어요."}
	set_process(false)
	lost.emit()

func release() -> void:
	_owned = false
	_namespace = ""
	_close_pipes()
	set_process(false)

func _close_pipes() -> void:
	if process.is_empty(): return
	# EOF is enough; never kill or enumerate unrelated player processes.
	process.stdio.close()
	process.stderr.close()
	process.clear()

func _fail(message: String) -> Dictionary:
	_last = {"ok": false, "owner": false, "bypassed": false, "error": message}
	return _last.duplicate()

func _exit_tree() -> void: release()
