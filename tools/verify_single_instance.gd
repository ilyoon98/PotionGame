extends SceneTree
## Own headless worker processes and isolated mutex namespaces only.
const Guard = preload("res://scripts/single_instance.gd")
const Binary = preload("res://native/windows/single_instance_binary.gd")
var folder := ""
var case_key := ""
var workers := {}
var checks_complete := 0
var worker_executable := ""
var guard_executable := ""

func _initialize() -> void:
	assert(DisplayServer.get_name() == "headless")
	Engine.max_fps = 60 # Timed process tests must not exhaust quit-after frames first.
	set_meta("isolated_preview", true)
	call_deferred("run")

func write_status(id: String, data: Dictionary) -> void:
	var path := folder.path_join(id + ".json")
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(data))
	file.close()
	assert(DirAccess.rename_absolute(temporary, path) == OK)

func read_status(id: String) -> Dictionary:
	var path := folder.path_join(id + ".json")
	if not FileAccess.file_exists(path): return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary: return {}
	return parser.data

func wait_until(check: Callable, timeout_ms: int = 6000) -> bool:
	var until := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < until:
		if check.call(): return true
		await create_timer(0.02).timeout
	return bool(check.call())

func native_unit() -> void:
	assert(Marshalls.base64_to_raw(Binary.BASE64) == FileAccess.get_file_as_bytes("res://native/windows/single_instance_guard.exe"))
	var first := Guard.new()
	root.add_child(first)
	assert(first.acquire().bypassed and first.process.is_empty(), "Ordinary headless tests do not start a helper")
	assert(not first.acquire_isolated("production-key").ok)
	var claimed: Dictionary = first.acquire_isolated(case_key + "-unit")
	assert(claimed.ok and claimed.owner and first.is_owner())
	var helper_pid: int = first.process.pid
	assert(first.acquire_isolated(case_key + "-unit").owner and first.process.pid == helper_pid, "An existing owner is idempotent")
	var second := Guard.new()
	root.add_child(second)
	var duplicate: Dictionary = second.acquire_isolated(case_key + "-unit")
	assert(duplicate.ok and not duplicate.owner and not duplicate.bypassed)
	assert(second.process.is_empty())
	var independent := Guard.new()
	root.add_child(independent)
	assert(independent.acquire_isolated(case_key + "-different").owner)
	var independent_pid: int = independent.process.pid
	independent.release()
	first.release()
	assert(await wait_until(func(): return not OS.is_process_running(helper_pid) and not OS.is_process_running(independent_pid)))
	assert(second.acquire_isolated(case_key + "-unit").owner, "A normal release permits a new owner")
	helper_pid = second.process.pid
	var observed := {"lost": false}
	second.lost.connect(func(): observed.lost = true)
	assert(OS.kill(helper_pid) == OK, "Only the known isolated helper PID is killed")
	assert(not second.is_owner(), "Liveness checks fail immediately before the next frame")
	assert(await wait_until(func(): return observed.lost and not second.is_owner()))
	var replacement := Guard.new()
	root.add_child(replacement)
	assert(replacement.acquire_isolated(case_key + "-unit").owner, "An abandoned mutex is reclaimable")
	helper_pid = replacement.process.pid
	replacement.release()
	assert(await wait_until(func(): return not OS.is_process_running(helper_pid)))
	# Recreate the first-launch extraction race rather than relying on cached bytes.
	assert(not OS.is_process_running(helper_pid))
	assert(DirAccess.remove_absolute(first.executable) == OK)
	assert(DirAccess.remove_absolute(first.executable.get_base_dir()) == OK)
	guard_executable = first.executable
	var publishers: Array[Node] = []
	var threads: Array[Thread] = []
	for i in 6:
		var publisher := Guard.new()
		publisher.executable = guard_executable
		var thread := Thread.new()
		publishers.append(publisher)
		threads.append(thread)
		assert(thread.start(publisher._publish_binary.bind(Marshalls.base64_to_raw(Binary.BASE64))) == OK)
	var all_published := true
	for thread in threads:
		if not thread.wait_to_finish(): all_published = false
	assert(all_published, "Six cold publishers produce one complete executable")
	assert(FileAccess.get_file_as_bytes(guard_executable) == Marshalls.base64_to_raw(Binary.BASE64))
	for publisher in publishers: publisher.free()
	for node in [first, second, independent, replacement]: node.free()
	checks_complete += 1

func spawn_worker(id: String) -> void:
	var args := PackedStringArray([guard_executable, Guard.mutex_name("verification|" + case_key), folder, id])
	var handle := OS.execute_with_pipe(worker_executable, args, false)
	assert(not handle.is_empty())
	workers[id] = handle

func mark(name: String) -> void:
	var file := FileAccess.open(folder.path_join(name), FileAccess.WRITE)
	assert(file != null)
	file.store_string("isolated test control")
	file.close()

func process_race() -> void:
	for i in 6: spawn_worker("race-" + str(i))
	assert(await wait_until(func():
		for id in workers:
			if read_status(id).get("phase", "") != "ready": return false
		return true
	, 30000))
	mark("gate")
	assert(await wait_until(func():
		for id in workers:
			if read_status(id).get("phase", "") != "claimed": return false
		return true
	, 10000))
	var owners: Array[String] = []
	var losers := 0
	for id in workers:
		var status := read_status(id)
		assert(status.ok and not status.bypassed)
		if status.owner:
			owners.append(id)
			assert(status.effects == ["isolated-save", "isolated-login", "isolated-rng"])
		else:
			losers += 1
			assert(status.effects.is_empty(), "Losers exit before any save/login/RNG surrogate")
	assert(owners.size() == 1 and losers == 5, "Six simultaneous claims have exactly one owner")
	var winning_id := owners[0]
	var winning := read_status(winning_id)
	var handle: Dictionary = workers[winning_id]
	assert(winning.pid == handle.pid)
	assert(OS.kill(handle.pid) == OK, "Only the headless worker created by this test is killed")
	assert(await wait_until(func(): return not OS.is_process_running(handle.pid) and not OS.is_process_running(winning.helper_pid)))
	spawn_worker("after-crash")
	assert(await wait_until(func(): return read_status("after-crash").get("phase", "") == "claimed"))
	var recovered := read_status("after-crash")
	assert(recovered.owner, "A forced owner exit cannot leave a permanent mutex")
	# Kill this fixture's guard; the owning test worker receives lost and exits.
	assert(OS.kill(recovered.helper_pid) == OK)
	assert(await wait_until(func(): return read_status("after-crash").get("phase", "") == "lost" and not OS.is_process_running(workers["after-crash"].pid)))
	spawn_worker("after-lost")
	assert(await wait_until(func(): return read_status("after-lost").get("phase", "") == "claimed"))
	var final_owner := read_status("after-lost")
	assert(final_owner.owner)
	mark("stop-after-lost")
	assert(await wait_until(func(): return not OS.is_process_running(workers["after-lost"].pid) and not OS.is_process_running(final_owner.helper_pid)))
	for id in workers:
		assert(await wait_until(func(): return not OS.is_process_running(workers[id].pid)))
		workers[id].stdio.close()
		workers[id].stderr.close()
	checks_complete += 1

func run() -> void:
	assert(OS.get_name() == "Windows")
	case_key = "verify-single-instance-" + str(OS.get_process_id()) + "-" + str(Time.get_ticks_usec())
	folder = ProjectSettings.globalize_path("res://.verification/" + case_key)
	assert(DirAccess.make_dir_recursive_absolute(folder) == OK)
	worker_executable = ProjectSettings.globalize_path("res://.verification/single-instance-fixture.exe")
	assert(FileAccess.file_exists(worker_executable), "Compile fixture with tools/build_single_instance.ps1 first")
	await native_unit()
	await process_race()
	assert(checks_complete == 2, "Both native unit and process race checks must complete")
	print("SINGLE INSTANCE PASS: atomic Windows mutex; six simultaneous first launches/executable publication yield one owner and five clean losers; normal release, forced owner exit and helper-loss/reclaim; live ownership check; all test workers/helpers gone; isolated headless only, no player save, registry or visible game")
	quit()
