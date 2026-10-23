extends SceneTree
## Headless check for the first sound system (sfx_v1). Uses an isolated Shop
## (no player save, no Windows registration) and never starts audio playback.
const Shop = preload("res://scripts/shop.gd")
const State = preload("res://scripts/shop_state.gd")
const ShopAudio = preload("res://scripts/shop_audio.gd")
const Save = preload("res://scripts/save_store.gd")
const Compare = preload("res://tests/state_compare.gd")
const FOLDER := "res://.verification/sfx-v1/"
const DURATIONS := {"coin": 0.15, "brew_done": 0.30, "expedition_return": 0.50, "unlock": 0.60}

var checks := 0
var failures: Array[String] = []
var proof := {}


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("SFX V1 FAIL: " + message)


func _initialize() -> void:
	set_meta("isolated_preview", true)
	call_deferred("run")


func run() -> void:
	DirAccess.make_dir_recursive_absolute(FOLDER)
	check(DisplayServer.get_name() == "headless", "Run with --headless; this check must never play sound")
	_check_wav_files()
	await _check_rate_limit_and_mute_unit()
	await _check_shop_wiring()
	_check_save_settings()
	await _check_simulation_independent()
	proof["status"] = "passed" if failures.is_empty() else "failed"
	proof["failures"] = failures
	proof["checks"] = checks
	proof["player_save_accessed"] = false
	proof["speaker_listening"] = "not verified (headless)"
	var file := FileAccess.open(FOLDER + "proof.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(proof, "\t"))
	file.close()
	if not failures.is_empty():
		print("SFX V1 FAIL: %d of %d checks failed" % [failures.size(), checks])
		quit(1)
		return
	print("SFX V1 PASS: %d checks; 4 WAVs, event wiring, rate limits, mute, save fallback, simulation unchanged" % checks)
	quit()


## Raw RIFF data (independent of the importer) and the imported AudioStream.
func _check_wav_files() -> void:
	var files := {}
	for id in ShopAudio.SOUNDS:
		var path: String = ShopAudio.SOUNDS[id]
		var bytes := FileAccess.get_file_as_bytes(path)
		check(bytes.size() > 44 and bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WAVE", id + " is a RIFF/WAVE file")
		check(bytes.decode_u16(20) == 1 and bytes.decode_u16(22) == 1 and bytes.decode_u32(24) == 22050 and bytes.decode_u16(34) == 16, id + " is 16-bit PCM mono 22050 Hz")
		check(bytes.slice(36, 40).get_string_from_ascii() == "data", id + " has a plain data chunk")
		var frames := bytes.decode_u32(40) / 2
		var peak := 0
		for index in frames:
			peak = maxi(peak, absi(bytes.decode_s16(44 + index * 2)))
		var peak_dbfs := 20.0 * log(float(peak) / 32767.0) / log(10.0)
		var first := bytes.decode_s16(44)
		var last := bytes.decode_s16(44 + (frames - 1) * 2)
		check(peak > 0 and peak_dbfs <= -6.0, id + " peak is at or below -6 dBFS")
		check(absi(first) <= 1 and absi(last) <= 1, id + " starts and ends silent (fade, no click)")
		check(absf(float(frames) / 22050.0 - DURATIONS[id]) < 0.002, id + " has the planned short duration")
		var stream: AudioStream = load(path)
		check(stream is AudioStreamWAV, id + " loads as AudioStreamWAV")
		check(not stream.stereo and stream.mix_rate == 22050 and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, id + " imports mono, 22050 Hz, not looping")
		check(absf(stream.get_length() - DURATIONS[id]) < 0.01, id + " imported length matches")
		files[id] = {"frames": frames, "peak_dbfs": snappedf(peak_dbfs, 0.01), "length": snappedf(stream.get_length(), 0.001)}
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/sfx_v1/manifest.json"))
	check(manifest is Dictionary and manifest.sounds.size() == 4, "manifest.json records the four sounds")
	for id in files:
		check(int(manifest.sounds[id].frames) == files[id].frames, id + " manifest frame count matches the file")
	proof["wav"] = files


func _check_rate_limit_and_mute_unit() -> void:
	var audio := ShopAudio.new()
	root.add_child(audio)
	await process_frame
	check(not audio.playback_enabled, "Headless never plays")
	check(audio.volume == 0.5 and not audio.muted, "Defaults: volume 0.5, sound on")
	for id in ShopAudio.SOUNDS:
		var pool: Array = audio._pools[id]
		check(pool.size() == ShopAudio.POOL_SIZE and pool[0].stream != null, id + " has a loaded player pool")
		for player in pool: check(not player.playing, id + " pool stays silent in headless")
	audio.test_clock = 10.0
	check(audio.play("coin"), "First coin plays")
	check(not audio.play("coin") and not audio.play("coin"), "Same-frame coins collapse to one")
	var coin_gap: float = ShopAudio.MIN_INTERVAL.coin
	check(coin_gap >= 5.0 and ShopAudio.MIN_INTERVAL.brew_done >= 10.0, "Ambient sounds are spaced for a busy late shop")
	audio.test_clock = 10.0 + coin_gap - 0.05
	check(not audio.play("coin"), "Coin within the spacing is skipped")
	audio.test_clock = 10.0 + coin_gap
	check(audio.play("coin"), "Coin after the spacing plays again")
	check(audio.requests.coin == 5 and audio.plays.coin == 2, "Requests counted, two plays")
	check(audio.play("brew_done"), "Different sounds have separate spacing")
	check(not audio.play("nonexistent"), "Unknown ids are ignored")
	# Hidden in the tray: ambient sounds rest, the player's own unlock still plays.
	audio.ambient_paused = true
	audio.test_clock = 40.0
	check(not audio.play("coin") and not audio.play("brew_done") and not audio.play("expedition_return") and audio.play("unlock"), "Tray hide pauses ambient sounds only")
	audio.ambient_paused = false
	audio.reset_counts()
	audio.play("coin"); audio.play("coin"); audio.play("coin"); audio.play("coin"); audio.test_clock = 40.0 + coin_gap; audio.play("coin"); audio.play("brew_done")
	audio.muted = true
	audio.test_clock = 60.0
	for id in ShopAudio.SOUNDS: check(not audio.play(id), id + " is silent while muted")
	check(audio.plays.coin == 2 and audio.requests.coin == 6, "Muted requests are counted but never played")
	audio.muted = false
	audio.volume = 0.0
	audio.test_clock = 30.0
	check(not audio.play("coin"), "Volume 0 is silent")
	audio.volume = NAN
	check(audio.volume == 0.5, "Invalid volume falls back to default")
	audio.volume = 3.0
	check(audio.volume == 1.0, "Volume is clamped to 0..1")
	audio.volume = 0.25
	check(absf(audio._pools.coin[0].volume_db - linear_to_db(0.25)) < 0.001, "Master volume drives the player volume")
	audio.queue_free()
	await process_frame


func _new_shop() -> Node:
	var shop := Shop.new()
	root.add_child(shop)
	return shop


## The real Shop event points drive the requests.
func _check_shop_wiring() -> void:
	var shop := _new_shop()
	await process_frame
	check(shop.test_mode and shop.instance_bypassed, "Isolated shop, no player save")
	var audio: Node = shop.shop_audio
	check(audio != null and audio.get_parent() == shop and audio.name == "ShopAudio", "ShopAudio is a child of Shop")
	check(audio.volume == shop.state.audio_volume and audio.muted == shop.state.audio_muted, "ShopAudio starts from saved settings")
	# One big update with many sales and brews requests each sound once.
	shop._advance_game(60.0)
	check(shop.state.total_sold >= 5, "A minute sells several potions")
	check(audio.requests.coin == 1 and audio.requests.brew_done == 1, "Many sales/brews in one update request one coin and one brew sound")
	audio.reset_counts()
	# Step-wise play: each step with sales/brews/returns requests once.
	shop.state.gold += 100000
	shop.state.progression.reputation = maxi(shop.state.progression.reputation, 1000)
	shop.open_management()
	var panel: Window = shop.management
	panel.buy("expedition")
	check(shop.state.progression.expedition_unlocked, "Expedition unlocked from the management panel")
	check(audio.requests.unlock == 1, "Unlock purchase requests the unlock sound")
	panel.buy("expedition")
	check(audio.requests.unlock == 1, "A refused repeat purchase is silent")
	var upgrades_before: int = audio.requests.unlock
	panel.buy("upgrade:cauldron")
	check(audio.requests.unlock == upgrades_before, "Plain upgrades do not use the unlock sound")
	var expected := {"coin": 0, "brew_done": 0, "expedition_return": 0}
	var clock := 100.0
	var steps := 0
	while steps < 14400 and (expected.expedition_return < 2 or steps < 600):
		var sold: int = shop.state.total_sold
		var brewed: int = shop.state.progression.totals["brewed"]
		var returns: int = shop.state.progression.totals["expeditions"]
		clock += 0.5
		audio.test_clock = clock
		shop._advance_game(0.5)
		if shop.state.total_sold > sold: expected.coin += 1
		if shop.state.progression.totals["brewed"] > brewed: expected.brew_done += 1
		if shop.state.progression.totals["expeditions"] > returns: expected.expedition_return += 1
		steps += 1
	for id in expected:
		check(expected[id] > 0, id + " event happened during the run")
		check(audio.requests[id] == expected[id], "%s requests (%d) equal event steps (%d)" % [id, audio.requests[id], expected[id]])
		check(audio.plays[id] <= audio.requests[id] and audio.plays[id] > 0, id + " plays are a gated subset of requests")
	proof["stepped_run"] = {"steps": steps, "requests": audio.requests.duplicate(), "plays": audio.plays.duplicate()}
	# The settings toggle mutes the node and the state; nothing plays afterwards.
	var toggle: CheckButton = panel.sound_toggle
	check(toggle != null and toggle.button_pressed and panel.pages[panel.SETTINGS].get_node("GameSettings").is_ancestor_of(toggle), "Sound toggle sits in the settings area, on by default")
	toggle.button_pressed = false
	check(shop.state.audio_muted and audio.muted, "Turning the toggle off mutes state and audio")
	audio.reset_counts()
	var stages_before := 0
	for id in shop.state.regulars.ids(): stages_before += shop.state.regulars.stage(id)
	for i in 1200:
		clock += 0.5
		audio.test_clock = clock
		shop._advance_game(0.5)
	var muted_stage_ups := -stages_before
	for id in shop.state.regulars.ids(): muted_stage_ups += shop.state.regulars.stage(id)
	shop.state.gold += 100000
	check(shop.state.purchase_reason("staff:sales_assistant") == "", "A muted unlock purchase is available")
	panel.buy("staff:sales_assistant")
	check(audio.requests.unlock == 1 + muted_stage_ups, "Muted unlock and regular stage chimes are still requested")
	var muted_plays := 0
	for id in audio.plays: muted_plays += audio.plays[id]
	check(audio.requests.coin > 0 and muted_plays == 0, "Muted shop requests sounds but plays zero")
	toggle.button_pressed = true
	check(not shop.state.audio_muted and not audio.muted, "Turning it back on unmutes")
	# Volume slider right below the toggle drives the node and the saved state.
	var slider: HSlider = toggle.get_parent().get_child(toggle.get_index() + 2) as HSlider
	check(slider != null and absf(slider.value - shop.state.audio_volume) < 0.001, "Volume slider follows the saved volume")
	slider.value = 0.2
	check(absf(shop.state.audio_volume - 0.2) < 0.001 and absf(audio.volume - 0.2) < 0.001, "Volume slider changes state and audio")
	slider.value = 0.5
	proof["muted_run"] = {"requests": audio.requests.duplicate(), "plays": audio.plays.duplicate()}
	shop.queue_free()
	await process_frame


func _loaded_from(data: Dictionary) -> State:
	var loaded := State.new()
	check(loaded.load_data(data), "Save with any audio value still loads")
	return loaded


func _check_save_settings() -> void:
	# Audio is an optional key and never bumps the version; v16 = F22 regulars, v17 = F23 decor.
	check(State.SAVE_VERSION == 17, "SAVE_VERSION unchanged by audio")
	var state := State.new()
	check(state.audio_volume == 0.5 and not state.audio_muted, "New saves default to volume 0.5, sound on")
	state.audio_volume = 0.3
	state.audio_muted = true
	var data: Dictionary = state.to_data()
	check(data.audio is Dictionary and data.audio.volume == 0.3 and data.audio.muted == true, "to_data writes the optional audio key")
	var through_json: Variant = JSON.parse_string(JSON.stringify(data))
	var loaded := _loaded_from(through_json)
	check(absf(loaded.audio_volume - 0.3) < 0.0001 and loaded.audio_muted, "JSON roundtrip keeps the settings")
	check(Save.write_from(state, FOLDER + "roundtrip.json") == OK, "Workspace save write")
	var stored := State.new()
	check(Save.read_into(stored, FOLDER + "roundtrip.json") == "loaded", "Workspace save read")
	check(absf(stored.audio_volume - 0.3) < 0.0001 and stored.audio_muted and Compare.equivalent(stored.to_data(), state.to_data()), "SaveStore roundtrip keeps the whole state")
	var cases := {
		"missing": null, "string": "loud", "array": [1, 2], "empty": {},
		"volume_high": {"volume": 2.0, "muted": true}, "volume_negative": {"volume": -0.1, "muted": true},
		"volume_nan": {"volume": NAN, "muted": true}, "volume_inf": {"volume": INF, "muted": true},
		"volume_text": {"volume": "0.7", "muted": true}, "muted_number": {"volume": 0.8, "muted": 1},
		"muted_text": {"volume": 0.8, "muted": "true"},
	}
	var results := {}
	for name in cases:
		var broken: Dictionary = data.duplicate(true)
		if name == "missing": broken.erase("audio")
		else: broken.audio = cases[name]
		var restored := _loaded_from(broken)
		var expect_volume := 0.8 if name.begins_with("muted_") else 0.5
		var expect_muted: bool = name.begins_with("volume_")
		check(absf(restored.audio_volume - expect_volume) < 0.0001 and restored.audio_muted == expect_muted, "Malformed audio (%s) falls back field by field" % name)
		check(restored.gold == state.gold and restored.window_mode == state.window_mode, "Malformed audio (%s) does not reject the rest of the save" % name)
		results[name] = {"volume": restored.audio_volume, "muted": restored.audio_muted}
	var integer_volume: Dictionary = data.duplicate(true)
	integer_volume.audio = {"volume": 1, "muted": false}
	check(_loaded_from(integer_volume).audio_volume == 1.0, "Integer volume 1 is valid")
	proof["save_fallbacks"] = results


## Audio only listens: the same simulation with audio, without it, muted, and
## as a bare State gives identical results.
func _check_simulation_independent() -> void:
	var with_audio := _new_shop()
	var without_audio := _new_shop()
	var muted := _new_shop()
	await process_frame
	without_audio.shop_audio.queue_free()
	without_audio.shop_audio = null
	muted.shop_audio.muted = true
	var bare := State.new()
	for shop in [with_audio, without_audio, muted]: shop.state.gold += 5000
	bare.gold += 5000
	for i in 2400:
		with_audio._advance_game(0.25)
		without_audio._advance_game(0.25)
		muted._advance_game(0.25)
		bare.advance(0.25)
		if i == 400:
			for shop in [with_audio, without_audio, muted]: check(shop.state.upgrade(), "Mid-run upgrade")
			check(bare.upgrade(), "Mid-run upgrade (bare)")
	var reference := _comparable(without_audio.state.to_data())
	check(with_audio.shop_audio.requests.coin > 0 and with_audio.shop_audio.plays.coin > 0, "The audio shop really requested sounds")
	check(muted.shop_audio.requests.coin > 0 and muted.shop_audio.plays.coin == 0, "The muted shop requested but never played")
	var bare_data := _comparable(bare.to_data())
	# The headless Shop opens in its own window mode; that display choice is not simulation.
	for key in ["window_mode", "main_window_mode", "mini_mode"]:
		bare_data[key] = reference[key]
	for entry in [["Shop with audio == shop without audio", _comparable(with_audio.state.to_data())], ["Muted shop == shop without audio", _comparable(muted.state.to_data())], ["Bare State simulation == shop simulation", bare_data]]:
		var same := Compare.equivalent(entry[1], reference)
		if not same: _print_differences(entry[0], entry[1], reference)
		check(same, entry[0])
	proof["simulation"] = {"seconds": 600.0, "gold": with_audio.state.gold, "sold": with_audio.state.total_sold, "identical": true}
	for shop in [with_audio, without_audio, muted]: shop.queue_free()
	await process_frame


## report_started is the wall-clock time a State was created, not simulation.
func _comparable(data: Dictionary) -> Dictionary:
	var copy := data.duplicate(true)
	copy.progression.erase("report_started")
	return copy


func _print_differences(label: String, a: Dictionary, b: Dictionary, prefix: String = "") -> void:
	for key in a:
		if not b.has(key): print(label, " extra ", prefix, key)
		elif a[key] is Dictionary and b[key] is Dictionary: _print_differences(label, a[key], b[key], prefix + str(key) + ".")
		elif not Compare.equivalent(a[key], b[key]): print(label, " diff ", prefix, key, ": ", str(a[key]).left(200), " vs ", str(b[key]).left(200))
