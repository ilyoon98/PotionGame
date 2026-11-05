extends TextureRect
## Keep the source grid intact inside a UI slot. Small artwork stays at native
## size unless the slot fits an exact integer enlargement (e.g. 16 -> 48).
## Unconverted large illustrations retain their legacy fitting as a fallback.

func _init() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_fit_texture)

func _ready() -> void:
	_fit_texture()

func _draw() -> void:
	# TextureRect queues redraws when its texture changes, including recipe and
	# keeper-state changes. Native drawing precedes this callback; redraw outside
	# the pending draw notification so the new mode is rendered on the next frame.
	if _fit_texture(): queue_redraw.call_deferred()

func _fit_texture() -> bool:
	var mode := TextureRect.STRETCH_KEEP_CENTERED
	if texture != null:
		var source := texture.get_size()
		if source.x > 0 and source.y > 0:
			var factor := minf(size.x / source.x, size.y / source.y)
			if source.x > size.x or source.y > size.y:
				mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			elif factor >= 2.0 and is_equal_approx(factor, floorf(factor)):
				mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if stretch_mode == mode: return false
	stretch_mode = mode
	return true

func drawn_rect() -> Rect2:
	if texture == null: return Rect2()
	var drawn := texture.get_size()
	if stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
		drawn *= minf(size.x / drawn.x, size.y / drawn.y)
	return Rect2(((size - drawn) * 0.5).floor(), drawn)
