extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.title = "투명 영역 클릭 검사 · 임시 문서"
	root.size = Vector2i(700, 600)
	root.content_scale_size = Vector2i(700, 600)
	root.position = Vector2i(100, 90)
	root.always_on_top = false
	root.transparent_bg = false
	var bg := ColorRect.new()
	bg.color = Color("f2f0e9")
	bg.size = Vector2(700, 600)
	root.add_child(bg)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Malgun Gothic"])
	var button := Button.new()
	button.text = "투명 영역 클릭 검사: 아직 클릭되지 않음\n가게 사물 사이에서 이 글자가 보여야 합니다."
	button.position = Vector2(100, 120)
	button.size = Vector2(408, 210)
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", Color("30273c"))
	var style := StyleBoxFlat.new()
	style.bg_color = bg.color
	button.add_theme_stylebox_override("normal", style)
	button.pressed.connect(func(): button.text = "클릭 통과 확인됨"; print("OS PASSTHROUGH CLICK RECEIVED"))
	root.add_child(button)
