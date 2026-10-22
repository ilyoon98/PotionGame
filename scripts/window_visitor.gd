extends RefCounted
## Temporary visual only: no ShopState fields, save data, rewards or audio.
const PHOTO = preload("res://assets/easter_eggs/window-visitor-pixel-v1.png")
const REQUIRED_TAPS := 7
const TAP_WINDOW := 3.0
const DURATION := 2.0
const COOLDOWN := 10.0
const OPENING := Rect2(18,30,60,48) # Same window glass in both room layouts.
var taps := 0
var started_at := 0.0
var remaining := 0.0
var cooldown := 0.0
var portrait: AtlasTexture

func _init() -> void:
	portrait = AtlasTexture.new()
	portrait.atlas = PHOTO
	# Published20x16 portrait uses the same3x grid as the window and world.
	portrait.region = Rect2(Vector2.ZERO,PHOTO.get_size())

func tap(now: float = -1.0) -> bool:
	if cooldown > 0.0: return false
	if now < 0.0: now = Time.get_ticks_msec()/1000.0
	if taps == 0 or now-started_at > TAP_WINDOW:
		taps = 0
		started_at = now
	taps += 1
	if taps < REQUIRED_TAPS: return false
	taps = 0
	remaining = DURATION
	cooldown = COOLDOWN
	return true

func tick(delta: float) -> void:
	remaining = maxf(0.0,remaining-delta)
	cooldown = maxf(0.0,cooldown-delta)

func commands(window_origin: Vector2) -> Array[Dictionary]:
	if remaining <= 0.0: return []
	var opacity := minf(smoothstep(0.0,0.15,DURATION-remaining),smoothstep(0.0,0.25,remaining))
	return [{"role":"window_visitor","texture":portrait,"rect":Rect2(window_origin+OPENING.position,OPENING.size),"flip_h":false,"color":Color(1,1,1,opacity)}]
