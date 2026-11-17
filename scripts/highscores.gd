extends RefCounted
## Local JSON leaderboard (top 10). Override save path for tests.

const MAX_ENTRIES := 10
const DEFAULT_PATH := "user://highscores.json"

static var _path_override: String = ""


static func set_save_path(path: String) -> void:
	_path_override = path


static func reset_save_path() -> void:
	_path_override = ""


static func get_save_path() -> String:
	if _path_override != "":
		return _path_override
	return DEFAULT_PATH


static func load_entries() -> Array:
	var path := get_save_path()
	if not FileAccess.file_exists(path):
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed == null or not (parsed is Array):
		return []
	return parsed.duplicate(true)


static func save_entries(entries: Array) -> bool:
	var trimmed := trim_top(sort_entries(entries))
	var f := FileAccess.open(get_save_path(), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(trimmed, "\t"))
	return true


static func trimmed_copy(entries: Array) -> Array:
	return trim_top(entries.duplicate(true))


static func sort_entries(entries: Array) -> Array:
	var out: Array = entries.duplicate(true)
	out.sort_custom(func(a, b):
		var sa: int = int(a.get("score", 0))
		var sb: int = int(b.get("score", 0))
		if sa != sb:
			return sa > sb
		var wa: int = int(a.get("waves", 0))
		var wb: int = int(b.get("waves", 0))
		return wa > wb
	)
	return out


static func trim_top(entries: Array) -> Array:
	if entries.size() <= MAX_ENTRIES:
		return entries
	return entries.slice(0, MAX_ENTRIES)


static func add_entry(score: int, waves: int, result: String, datetime: String = "") -> Array:
	var when := datetime
	if when == "":
		when = Time.get_datetime_string_from_system()
	var entry := {
		"score": score,
		"waves": waves,
		"result": result,
		"datetime": when,
	}
	var all := load_entries()
	all.append(entry)
	all = sort_entries(all)
	all = trim_top(all)
	save_entries(all)
	return all


static func normalize_entry(d: Dictionary) -> Dictionary:
	return {
		"score": int(d.get("score", 0)),
		"waves": int(d.get("waves", 0)),
		"result": str(d.get("result", "loss")),
		"datetime": str(d.get("datetime", "")),
	}