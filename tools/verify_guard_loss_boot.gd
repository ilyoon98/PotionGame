extends SceneTree
## Inject only fake guard/login probes. Never start or kill a native process.
const Shop = preload("res://scripts/shop.gd")
const Compare = preload("res://tests/state_compare.gd")
var failures := 0

class FakeGuard extends Node:
	signal lost
	var permission_ok := true
	var owns_session := true
	var claims := 0
	var owner_checks := 0
	func acquire() -> Dictionary:
		claims += 1
		return {"ok": permission_ok, "owner": owns_session and permission_ok, "bypassed": false,
			"error": "EXPECTED GUARD FIXTURE: acquire denied" if not permission_ok else ""}
	func is_owner() -> bool:
		owner_checks += 1
		return owns_session and permission_ok

class SpyResume extends RefCounted:
	var blocked := false
	var enabled := true
	var status := "fixture"
	var start_calls := 0
	var manual_calls := 0
	var toggle_calls := 0
	var pid_intents := 0
	func start_session() -> Dictionary:
		start_calls += 1
		pid_intents += 1
		return {"ok": true, "enabled": enabled, "status": "fixture", "error": ""}
	func manual_closed() -> Dictionary:
		manual_calls += 1
		return {"ok": true, "enabled": enabled, "status": "fixture", "error": ""}
	func set_enabled(value: bool) -> Dictionary:
		toggle_calls += 1
		enabled = value
		return {"ok": true, "enabled": enabled, "status": "fixture", "error": ""}

class FixtureShop extends Shop:
	var fake_guard := FakeGuard.new()
	var spy := SpyResume.new()
	var lose_while_building := false
	var builds := 0
	func _create_instance_guard() -> Node:
		return fake_guard
	func _build_interface() -> void:
		builds += 1
		login_resume = spy
		super._build_interface()
		if lose_while_building: fake_guard.owns_session = false

func _initialize() -> void:
	set_meta("isolated_preview", true)
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("GUARD LOSS CHECK FAILED: " + message)

func attach_fixture(shop: FixtureShop) -> void:
	root.add_child(shop)

func reject_actions(shop: FixtureShop, before: Dictionary, start_calls: int) -> void:
	# Exercise the ownership branch ahead of both real and test-mode storage paths.
	shop.test_mode = false
	check(not shop._save(), "Guard loss denies storage even outside test mode")
	check(not shop.set_login_resume(true).ok and not shop.set_login_resume(false).ok, "Guard loss denies login toggles")
	shop._advance_game(600.0)
	shop._upgrade()
	shop._upgrade_garden()
	shop._set_window_mode(Shop.State.WindowMode.FULL)
	shop._change_opacity(30.0)
	if shop.builds > 0:
		shop.open_management()
		shop.management.buy("moon")
		shop.management._change_weather_effects(0.0)
		shop.management._change_brightness_floor(1.0)
		shop.management.result_button.pressed.emit()
		check(shop.management.statistics_values.size() == 12 and shop.management.pages[shop.management.REPORT].find_children("*", "Button", true, false).is_empty(), "Statistics offers no reset/ledger action after guard loss")
	shop._process(600.0)
	shop._close_shop()
	shop._quit_manually()
	check(not shop.is_processing(), "Guard loss stops model processing")
	check(shop.spy.manual_calls == 0 and shop.spy.toggle_calls == 0, "Guard loss never clears/changes login intent")
	check(shop.spy.start_calls == start_calls and shop.spy.pid_intents == start_calls, "No new start/PID intent after guard loss")
	check(Compare.equivalent(before, shop.state.to_data()), "Lost/rejected protection never advances economy/RNG")

func run() -> void:
	check(DisplayServer.get_name() == "headless", "No native/visible runtime")
	var denied := FixtureShop.new()
	denied.fake_guard.permission_ok = false
	var denied_before: Dictionary = denied.state.to_data().duplicate(true)
	print("EXPECTED GUARD FIXTURE: next acquire-denied error is the intentional production rejection branch")
	attach_fixture(denied)
	check(denied.fake_guard.claims == 1 and denied.builds == 0 and denied.art == null and denied.login_resume == null, "Permission failure rejects before UI/login/save-load")
	reject_actions(denied, denied_before, 0)
	var during_boot := FixtureShop.new()
	during_boot.lose_while_building = true
	var boot_before: Dictionary = during_boot.state.to_data().duplicate(true)
	attach_fixture(during_boot)
	check(during_boot.builds == 1 and during_boot.art != null, "Fixture loses ownership while building the actual UI")
	check(during_boot.fake_guard.owner_checks >= 1 and during_boot.spy.start_calls == 0 and during_boot.spy.pid_intents == 0, "Ready-end recheck precedes start_session/PID intent")
	reject_actions(during_boot, boot_before, 0)
	var runtime := FixtureShop.new()
	attach_fixture(runtime)
	check(runtime.spy.start_calls == 1 and runtime.spy.pid_intents == 1, "Only the successful owned boot starts a session once")
	runtime.state.gold = 1000000
	runtime.state.progression.reputation = 10000
	var runtime_before: Dictionary = runtime.state.to_data().duplicate(true)
	runtime.fake_guard.owns_session = false
	# No lost signal yet: guards must inspect helper ownership synchronously.
	reject_actions(runtime, runtime_before, 1)
	check(runtime.fake_guard.owner_checks >= 7, "Lifecycle entry points recheck ownership before mutations")
	var signaled := FixtureShop.new()
	attach_fixture(signaled)
	var signaled_before: Dictionary = signaled.state.to_data().duplicate(true)
	signaled.fake_guard.owns_session = false
	signaled.fake_guard.lost.emit()
	check(not signaled.is_processing(), "The guard-lost signal also stops processing immediately")
	reject_actions(signaled, signaled_before, 1)
	print("GUARD LOSS RESULT: %d failures; denied acquire, lost during UI boot, synchronous runtime loss and lost signal; no start/PID/close/toggle/storage/model/purchase/upgrade/settings mutations" % failures)
	for shop in [denied, during_boot, runtime, signaled]: shop.queue_free()
	quit(1 if failures else 0)
