extends Node
## Small, soft and rare sound effects for the always-on-top desktop shop (sfx_v1).
## A child of Shop. It only listens to events the game already produced and never
## changes ShopState. Headless runs never start playback but still count requests
## so tests can verify the wiring, rate limits and mute.

const SOUNDS := {
	"coin": "res://assets/audio/sfx_v1/coin.wav",
	"brew_done": "res://assets/audio/sfx_v1/brew_done.wav",
	"expedition_return": "res://assets/audio/sfx_v1/expedition_return.wav",
	"unlock": "res://assets/audio/sfx_v1/unlock.wav",
}
## Minimum seconds between two plays of the same sound. Several events in the
## same frame therefore play once.
const MIN_INTERVAL := {"coin": 0.25, "brew_done": 0.6, "expedition_return": 1.0, "unlock": 0.4}
## Players per sound, so a new play does not cut off a ringing tail.
const POOL_SIZE := 2
const DEFAULT_VOLUME := 0.5
const DEFAULT_MUTED := false

## Master volume 0..1 (linear). Invalid values fall back to the default.
var volume: float = DEFAULT_VOLUME:
	set(value):
		volume = clampf(value, 0.0, 1.0) if is_finite(value) else DEFAULT_VOLUME
		_apply_volume()
var muted: bool = DEFAULT_MUTED
## False in headless runs: no AudioStreamPlayer.play() call is ever made.
var playback_enabled: bool = DisplayServer.get_name() != "headless"
## Every play() call per sound, before mute and interval gates.
var requests := {}
## Calls that passed the gates (audible on a real device).
var plays := {}
## Tests may set a fixed clock (seconds); negative uses the engine clock.
var test_clock := -1.0
var _last_played := {}
var _pools := {}
var _next_player := {}


func _init() -> void:
	for id in SOUNDS:
		requests[id] = 0
		plays[id] = 0


func _ready() -> void:
	for id in SOUNDS:
		var stream: AudioStream = load(SOUNDS[id])
		var pool: Array[AudioStreamPlayer] = []
		for index in POOL_SIZE:
			var player := AudioStreamPlayer.new()
			player.name = "%s_%d" % [id, index]
			player.stream = stream
			add_child(player)
			pool.append(player)
		_pools[id] = pool
		_next_player[id] = 0
	_apply_volume()


func apply_settings(new_volume: float, new_muted: bool) -> void:
	volume = new_volume
	muted = new_muted


## Request one sound. Returns true when it passed mute and the interval limit.
func play(id: String) -> bool:
	if not SOUNDS.has(id): return false
	requests[id] += 1
	if muted or volume <= 0.0: return false
	var now := _now()
	if _last_played.has(id) and now - float(_last_played[id]) < float(MIN_INTERVAL[id]): return false
	_last_played[id] = now
	plays[id] += 1
	if playback_enabled and _pools.has(id):
		var pool: Array = _pools[id]
		var player: AudioStreamPlayer = pool[_next_player[id]]
		_next_player[id] = (int(_next_player[id]) + 1) % pool.size()
		player.play()
	return true


func reset_counts() -> void:
	for id in SOUNDS:
		requests[id] = 0
		plays[id] = 0
	_last_played.clear()


func _now() -> float:
	return test_clock if test_clock >= 0.0 else Time.get_ticks_usec() / 1000000.0


func _apply_volume() -> void:
	var decibels := linear_to_db(maxf(volume, 0.0001))
	for id in _pools:
		for player in _pools[id]:
			player.volume_db = decibels
