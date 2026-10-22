extends SceneTree
## Period accounting through the real save adapter, using workspace files only.
const State = preload("res://scripts/shop_state.gd")
const Save = preload("res://scripts/save_store.gd")
const F = preload("res://tests/late_investment_fixture.gd")
const Compare = preload("res://tests/state_compare.gd")
const DIR := "res://.verification/f19-supplement-20261019/regression/save-store/"
var checks := 0
var failures: Array[String] = []


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func raw_write(path: String, data: Variant) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true


func _initialize() -> void:
	if DisplayServer.get_name() != "headless" or not OS.get_environment("APPDATA").replace("\\", "/").contains("/.verification/f19-supplement-20261019/"):
		push_error("Requires isolated workspace APPDATA and headless")
		quit(1)
		return
	call_deferred("run")


func run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var state: RefCounted = F.completed_store(73129, "final", "support1", "scarce_upper")
	state.start_report_period()
	var event: Dictionary = state.advance(60.0)
	check(event.supplied == 7, "Storage fixture uses an actual due seven-unit supply")
	check(state.report_text().contains("보급 +7"), "Actual supply appears in the period text before saving")
	var first: Dictionary = F.data(state)
	var first_text: String = state.report_text()
	var path := DIR + "current.json"
	check(Save.write_from(state, path) == OK, "Real save adapter writes a workspace primary file")
	check(Compare.equivalent(first, F.data(state)), "Saving never advances or mutates model/baseline/RNG")
	var restored := State.new()
	check(Save.read_into(restored, path) == "loaded", "Real save adapter restores the primary")
	check(Compare.equivalent(first, F.data(restored)) and restored.report_text() == first_text, "Primary roundtrip preserves every model field and period material text")

	state.advance(60.0)
	var second: Dictionary = F.data(state)
	check(Save.write_from(state, path) == OK, "Second normal save rotates a validated backup")
	check(FileAccess.file_exists(path + ".bak"), "Prior valid period state exists as the backup")
	var latest := State.new()
	check(Save.read_into(latest, path) == "loaded" and Compare.equivalent(second, F.data(latest)), "Latest normal primary preserves later real receipts")
	check(raw_write(path, {"version": 11}), "Corrupt-primary fixture is confined to the workspace")
	var recovered := State.new()
	check(Save.read_into(recovered, path) == "recovered", "An invalid primary falls back through the real adapter")
	check(Compare.equivalent(first, F.data(recovered)) and recovered.report_text() == first_text, "Backup recovery retains the original receipt baseline without another grant")

	var legacy: Dictionary = first.duplicate(true)
	legacy.erase("report_supply")
	var legacy_path := DIR + "previous-v11.json"
	check(raw_write(legacy_path, legacy), "Previous version11 fixture omits only the newly optional baseline")
	var migrated := State.new()
	check(Save.read_into(migrated, legacy_path) == "loaded", "Already-issued version11 loads through the save adapter")
	check(Compare.equivalent(migrated.late_investments.totals, first.late_investments.totals), "Migration preserves real cumulative supply totals across JSON numeric normalization")
	check(migrated.report_supply == migrated.late_investments.totals and not migrated.report_text().contains("보급 +"), "Unknown historical supply period starts from saved totals without relabeling old receipts")
	var migrated_before: Dictionary = F.data(migrated)
	for i in 5: migrated.report_text()
	check(Compare.equivalent(migrated_before, F.data(migrated)), "Repeated result reads cannot grant or reset supply")
	var next: Dictionary = migrated.advance(60.0)
	check(next.supplied == 7 and migrated.report_text().contains("보급 +7"), "The next actual receipt is counted after migration")
	var expected_migrated: Dictionary = F.data(migrated)
	check(Save.write_from(migrated, legacy_path) == OK, "The first post-migration save validates and rotates the old version11")
	var migrated_again := State.new()
	check(Save.read_into(migrated_again, legacy_path) == "loaded" and Compare.equivalent(expected_migrated, F.data(migrated_again)), "Post-migration save preserves exact supply baseline and economy")
	check(raw_write(legacy_path, null), "The migration recovery fixture damages only its workspace primary")
	var legacy_recovery := State.new()
	check(Save.read_into(legacy_recovery, legacy_path) == "recovered", "A previous-version11 backup is still recoverable")
	check(Compare.equivalent(legacy_recovery.late_investments.totals, first.late_investments.totals) and legacy_recovery.report_supply == legacy_recovery.late_investments.totals, "Old backup recovery preserves actual totals and performs the same conservative baseline migration")

	F.write_json(DIR + "proof.json", {"passed": failures.is_empty(), "checks": checks, "failures": failures, "save_version": State.SAVE_VERSION, "state_sha256": FileAccess.get_sha256("res://scripts/shop_state.gd"), "first_actual_supply_event": event.supply_events, "first_report": first_text, "all_files_workspace_only": true, "player_save_accessed": false})
	print("SUPPLY PERIOD STORAGE %s: %d checks; real adapter primary/backup/previous-v11 migration, no grants on result reads; workspace-only" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)
