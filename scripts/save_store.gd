extends RefCounted

const State = preload("res://scripts/shop_state.gd")


static func _parse(text: String) -> Variant:
	var parser := JSON.new()
	return parser.data if parser.parse(text) == OK else null


static func read_into(state: RefCounted, path: String) -> String:
	for candidate in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var file := FileAccess.open(candidate, FileAccess.READ)
		if file != null and state.load_data(_parse(file.get_as_text())):
			return "loaded" if candidate == path else "recovered"
	return "invalid" if FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak") else "new"


static func write_from(state: RefCounted, path: String) -> Error:
	# Write a temporary file first. Keep the last valid save as a backup.
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(state.to_data(), "\t", true, true))
	file.flush()
	var result := file.get_error()
	file.close()
	if result != OK:
		return result
	if FileAccess.file_exists(path):
		var previous := FileAccess.open(path, FileAccess.READ)
		var validator := State.new()
		var valid: bool = previous != null and validator.load_data(_parse(previous.get_as_text()))
		if previous != null:
			previous.close()
		if valid:
			result = DirAccess.copy_absolute(path, path + ".bak")
			if result != OK:
				return result
	return DirAccess.rename_absolute(temp_path, path)
