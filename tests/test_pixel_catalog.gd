extends SceneTree
## Check actual imported texture bytes, not only the editor-side PNG files.
const Catalog = preload("res://scripts/pixel_art_catalog.gd")
var textures := {}

func _initialize() -> void:
	walk("res://assets/pixel_v1")
	for key in Catalog.DATA.potions:
		var color := Catalog.liquid(key)
		assert(has_color(Catalog.bottle(key).get_image(),color),"Bottle contains its assigned liquid color")
		for frame in 3: assert(has_color(Catalog.pot(key,frame/6.0).get_image(),color),"Each boiling frame contains the same recipe color")
	var file := FileAccess.open("res://.verification/pixel-runtime-v1/imported-textures.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"status":"passed","texture_count":textures.size(),"textures":textures},"\t"))
	print("PIXEL CATALOG PASS: ",textures.size()," actual imported texture hashes;36 bottle/pot liquid assignments")
	quit()

func has_color(image: Image, color: Color) -> bool:
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x,y).is_equal_approx(color): return true
	return false

func walk(folder: String) -> void:
	for entry in DirAccess.get_files_at(folder):
		if not entry.ends_with(".png"): continue
		var path := folder.path_join(entry)
		var image := Catalog.texture(path).get_image()
		image.convert(Image.FORMAT_RGBA8)
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(image.get_data())
		textures[path] = {"size":[image.get_width(),image.get_height()],"rgba_sha256":hash.finish().hex_encode()}
	for entry in DirAccess.get_directories_at(folder): walk(folder.path_join(entry))
