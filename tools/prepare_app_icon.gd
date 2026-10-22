extends SceneTree
## Rasterize the editable SVG with Godot's own SVG renderer.
## Run headlessly, then tools/prepare_app_icon.py to package the Windows ICO.

func _initialize() -> void:
	var image := Image.new()
	var error := image.load_svg_from_string(FileAccess.get_file_as_string("res://icon.svg"))
	if error != OK:
		push_error("Application SVG failed to render: %s" % error_string(error))
		quit(1)
		return
	error = image.save_png("res://icon.png")
	if error != OK:
		push_error("Application PNG failed to save: %s" % error_string(error))
		quit(1)
		return
	print("APP ICON: 256 x 256 transparent PNG rendered from icon.svg")
	quit()
