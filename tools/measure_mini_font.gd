extends SceneTree
const FONT = preload("res://assets/fonts/pretendard/Pretendard-Regular.otf")
func _initialize() -> void:
	assert(DisplayServer.get_name() == "headless")
	for value in ["99,999", "14.9만", "999.9만", "9999.9만", "10000만", "10000.0억", "10000억", "1.0조", "999.9조"]:
		print(value, ": ", FONT.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 15))
	quit()
