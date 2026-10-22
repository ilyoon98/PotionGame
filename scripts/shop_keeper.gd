extends RefCounted
## F21 keeper fatigue and sleep. ShopState schedules the boundaries returned by
## remaining(); every transition happens exactly at a stored absolute clock, so
## coarse and fine advances agree. Only the main cauldron needs the keeper.
const Content = preload("res://scripts/shop_content.gd")
const Upgrades = preload("res://scripts/shop_keeper_upgrades.gd")
const HOUR := Content.DAY_SECONDS / 24.0
const POLICY_ORDER := ["regular", "busy", "allnighter"]
const POLICIES := {
	"regular": {"name": "규칙적", "bed": 22.0, "wake": 6.0},
	"busy": {"name": "바쁘게", "bed": 0.0, "wake": 6.0},
	"allnighter": {"name": "철야", "bed": 2.0, "wake": 6.0},
}
## Per game hour. Regular peaks at 16 x 2.4 = 38.4 and fully recovers in 8h.
## These are the unupgraded rates; the bed and herb-tea shelf scale them.
const BREW_RATE := 2.4 / HOUR
const IDLE_RATE := 1.2 / HOUR
const SLEEP_RATE := 5.0 / HOUR
const VERSION := 2
const FAINT_SECONDS := 10.0 * HOUR
const PENALTIES := [[80.0, 0.20], [60.0, 0.10], [40.0, 0.03]]
const CONDITIONS := [[80.0, "한계"], [60.0, "피곤"], [40.0, "보통"], [0.0, "상쾌"]]
const MIN_CHANCE := 0.30
## Rested bonus: below the first penalty band the keeper brews faster, so a
## regular sleeper recovers most of the night's lost cauldron time.
const FRESH_BELOW := 40.0
const FRESH_SPEED := 1.3
## Threshold comparisons tolerate float drift so a batch reserved exactly when a
## band boundary is reached gets the same chance for any frame size.
const BAND_TOLERANCE := 0.000001
const POLICY_REPUTATION := 1000
const EPSILON := 0.000001

var fatigue := 0.0
var state := "awake" # awake / asleep / fainted
var policy := "regular"
var next_at := -1.0 # Absolute clock of the next scheduled transition; -1 until first scheduled.
var sleep_started := 0.0
var last_sleep_hours := 0.0
## Lifetime counters for the return report. Fatigue failures are counted when a
## batch is reserved, because that is when its outcome is drawn.
var totals := {"sleeps": 0, "faints": 0, "fatigue_failed": 0}
## Bed/herb-tea levels, saved under their own key by ShopState.
var upgrades: RefCounted = Upgrades.new()
## Verification hook only (never saved): isolates non-keeper systems when they
## are compared against frozen pre-F21 reference implementations.
var enabled := true

static func hour_of(clock: float) -> float:
	return fposmod(0.45 + clock / Content.DAY_SECONDS, 1.0) * 24.0

static func until_hour(clock: float, target: float) -> float:
	var wait := fposmod(target - hour_of(clock), 24.0) * HOUR
	return Content.DAY_SECONDS if wait <= EPSILON else wait

func resting() -> bool:
	return enabled and state != "awake"

func awake_rate(brewing: bool) -> float:
	return (BREW_RATE if brewing else IDLE_RATE) * upgrades.awake_factor()

func sleep_rate() -> float:
	return upgrades.sleep_per_hour() / HOUR

static func sleep_hours(id: String) -> float:
	return fposmod(float(POLICIES[id].wake) - float(POLICIES[id].bed), 24.0)

## Worst-case day (brewing the whole time awake) for a policy at the current upgrades.
func daily(id: String) -> Dictionary:
	var hours := sleep_hours(id)
	var gain := (24.0 - hours) * HOUR * awake_rate(true)
	var recovery := hours * HOUR * sleep_rate()
	return {"gain": gain, "recovery": recovery, "sustainable": gain <= recovery + EPSILON, "fresh": gain <= recovery + EPSILON and gain < FRESH_BELOW - BAND_TOLERANCE}

func _schedule(clock: float) -> void:
	if state == "awake": next_at = clock + until_hour(clock, float(POLICIES[policy].bed))
	elif state == "asleep": next_at = clock + until_hour(clock, float(POLICIES[policy].wake))

func ensure(clock: float) -> void:
	if next_at < 0.0: _schedule(clock)

## Seconds to the next fatigue or sleep transition given the current cauldron use.
func remaining(clock: float, brewing: bool) -> float:
	if not enabled: return INF
	ensure(clock)
	var wait := maxf(0.0, next_at - clock)
	if state == "awake":
		var rate := awake_rate(brewing)
		wait = minf(wait, maxf(0.0, (100.0 - fatigue) / rate))
		# Crossing out of the rested band changes brewing speed mid-batch.
		if is_fresh(): wait = minf(wait, (FRESH_BELOW - fatigue) / rate)
	return wait

## Multiplier on main-cauldron progress for the step that starts now.
func brew_speed() -> float:
	return FRESH_SPEED if enabled and state == "awake" and is_fresh() else 1.0

func is_fresh() -> bool:
	return fatigue < FRESH_BELOW - BAND_TOLERANCE

## Accumulate fatigue for a step already taken, then apply any transition at the new clock.
func advance(step: float, clock: float, brewing: bool) -> void:
	if not enabled: return
	ensure(clock - step)
	if state == "awake": fatigue = minf(100.0, fatigue + awake_rate(brewing) * step)
	else: fatigue = maxf(0.0, fatigue - sleep_rate() * step)
	if state == "awake" and fatigue >= 100.0 - EPSILON:
		fatigue = 100.0
		_fall_asleep(clock, "fainted")
	elif clock >= next_at - EPSILON:
		if state == "awake": _fall_asleep(clock, "asleep")
		else: _wake(clock)

func _fall_asleep(clock: float, kind: String) -> void:
	state = kind
	sleep_started = clock
	totals["faints" if kind == "fainted" else "sleeps"] += 1
	next_at = clock + FAINT_SECONDS if kind == "fainted" else clock + until_hour(clock, float(POLICIES[policy].wake))

func _wake(clock: float) -> void:
	last_sleep_hours = (clock - sleep_started) / HOUR
	state = "awake"
	_schedule(clock)

func in_window(clock: float) -> bool:
	var hour := hour_of(clock)
	var bed := float(POLICIES[policy].bed)
	var wake := float(POLICIES[policy].wake)
	if bed > wake: return hour >= bed or hour < wake
	return hour >= bed and hour < wake

func policy_unlocked(reputation: int) -> bool:
	return reputation >= POLICY_REPUTATION

## A policy change applies at once: inside the new window the keeper goes to bed,
## outside it a scheduled sleep ends. Fainting always runs its full recovery.
func set_policy(value: String, clock: float) -> bool:
	if not POLICIES.has(value) or value == policy: return false
	policy = value
	if state == "fainted": return true
	if state == "awake" and in_window(clock): _fall_asleep(clock, "asleep")
	elif state == "asleep" and not in_window(clock): _wake(clock)
	else: _schedule(clock)
	return true

func penalty() -> float:
	if not enabled: return 0.0
	for row in PENALTIES:
		if fatigue >= float(row[0]) - BAND_TOLERANCE: return float(row[1])
	return 0.0

func condition() -> String:
	for row in CONDITIONS:
		if fatigue >= float(row[0]) - BAND_TOLERANCE: return str(row[1])
	return "상쾌"

## Basic health/mana potions (bool kinds) take half the penalty so recovery never stalls.
func adjusted(chance: float, basic: bool) -> float:
	var cut := penalty() * (0.5 if basic else 1.0)
	if cut <= 0.0: return chance
	return maxf(minf(chance, MIN_CHANCE), chance - cut)

## Reserve-time judgement for every main-cauldron path. Draws exactly as before
## (no roll when the chance is certain) and records a fatigue failure when the
## same roll would have succeeded without the penalty.
func judge(progression: RefCounted, base: float, basic: bool, quantity: int = 1) -> void:
	var chance := adjusted(base, basic)
	var roll := 0.0 if chance >= 1.0 else float(progression.random_value())
	progression.batch_chance = chance
	progression.batch_success = chance >= 1.0 or roll < chance
	if not progression.batch_success and (base >= 1.0 or roll < base): totals.fatigue_failed += quantity

func to_data() -> Dictionary:
	return {"version": VERSION, "fatigue": fatigue, "state": state, "policy": policy, "next_at": next_at, "sleep_started": sleep_started, "last_sleep_hours": last_sleep_hours, "totals": totals.duplicate()}

static func _count(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == int(value) and value >= 0 and value <= 1000000000

## Saves up to v14 carry keeper version 1, which has no counters; they start at zero.
func load_data(data: Variant, clock: float, legacy: bool = false) -> bool:
	if not data is Dictionary or data.size() != (7 if legacy else 8): return false
	for key in ["version", "fatigue", "next_at", "sleep_started", "last_sleep_hours"]:
		if not (data.get(key) is int or data.get(key) is float) or not is_finite(float(data[key])): return false
	if float(data.version) != (1.0 if legacy else float(VERSION)): return false
	var saved_totals := {"sleeps": 0, "faints": 0, "fatigue_failed": 0}
	if not legacy:
		if not data.get("totals") is Dictionary or data.totals.size() != saved_totals.size(): return false
		for key in saved_totals:
			if not _count(data.totals.get(key)): return false
			saved_totals[key] = int(data.totals[key])
	if data.fatigue < 0.0 or data.fatigue > 100.0 or data.last_sleep_hours < 0.0 or data.last_sleep_hours > 24.0: return false
	if not data.get("state") is String or data.state not in ["awake", "asleep", "fainted"]: return false
	if not data.get("policy") is String or not POLICIES.has(data.policy): return false
	# A scheduled transition is never further than one day (or one faint) ahead.
	if data.next_at >= 0.0 and (data.next_at < clock - EPSILON or data.next_at > clock + maxf(Content.DAY_SECONDS, FAINT_SECONDS) + EPSILON): return false
	if data.next_at < 0.0 and data.state != "awake": return false
	if data.sleep_started > clock + EPSILON: return false
	fatigue = float(data.fatigue); state = data.state; policy = data.policy
	next_at = float(data.next_at); sleep_started = float(data.sleep_started); last_sleep_hours = float(data.last_sleep_hours)
	totals = saved_totals
	return true
