extends RefCounted
## Saved starting layouts (user://layouts.json): named piece lists plus an optional default
## that is loaded automatically at match start. Override the save path for tests.

const MAX_LAYOUTS := 10
const DEFAULT_PATH := "user://layouts.json"

static var _path_override: String = ""


static func set_save_path(path: String) -> void:
	_path_override = path


static func reset_save_path() -> void:
	_path_override = ""


static func get_save_path() -> String:
	return _path_override if _path_override != "" else DEFAULT_PATH


## {"default": String, "layouts": [{"name": String, "pieces": [{type, x, y, level}]}]}
static func load_store() -> Dictionary:
	var empty := {"default": "", "layouts": []}
	var path := get_save_path()
	if not FileAccess.file_exists(path):
		return empty
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return empty
	var parsed = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary) or not (parsed.get("layouts") is Array):
		return empty
	var out := {"default": str(parsed.get("default", "")), "layouts": []}
	for l in parsed.layouts:
		if l is Dictionary and l.get("pieces") is Array:
			out.layouts.append({"name": str(l.get("name", "Layout")), "pieces": l.pieces})
	return out


static func save_store(store: Dictionary) -> bool:
	var f := FileAccess.open(get_save_path(), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(store, "\t"))
	return true


static func names() -> PackedStringArray:
	var out: PackedStringArray = []
	for l in load_store().layouts:
		out.append(l.name)
	return out


static func next_name() -> String:
	var taken := names()
	var i := 1
	while taken.has("Layout %d" % i):
		i += 1
	return "Layout %d" % i


## Save (or overwrite by name) a layout. Oldest non-default layout is dropped past MAX_LAYOUTS.
static func save_layout(layout_name: String, pieces: Array) -> bool:
	var store := load_store()
	var replaced := false
	for l in store.layouts:
		if l.name == layout_name:
			l.pieces = pieces.duplicate(true)
			replaced = true
	if not replaced:
		store.layouts.append({"name": layout_name, "pieces": pieces.duplicate(true)})
	while store.layouts.size() > MAX_LAYOUTS:
		var drop := 0
		if store.layouts[0].name == store.default:
			drop = 1
		store.layouts.remove_at(drop)
	return save_store(store)


static func get_layout(layout_name: String) -> Array:
	for l in load_store().layouts:
		if l.name == layout_name:
			return l.pieces.duplicate(true)
	return []


static func delete_layout(layout_name: String) -> bool:
	var store := load_store()
	var keep: Array = []
	for l in store.layouts:
		if l.name != layout_name:
			keep.append(l)
	if keep.size() == store.layouts.size():
		return false
	store.layouts = keep
	if store.default == layout_name:
		store.default = ""
	return save_store(store)


## Set (or clear with "") the layout auto-loaded at match start.
static func set_default(layout_name: String) -> bool:
	var store := load_store()
	if layout_name != "" and not names().has(layout_name):
		return false
	store.default = layout_name
	return save_store(store)


static func get_default() -> String:
	return load_store().default


static func default_pieces() -> Array:
	var d := get_default()
	return get_layout(d) if d != "" else []
