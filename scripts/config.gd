extends RefCounted
## Loads / validates game_data + settings JSON. Bundled defaults live in res://config/;
## user overrides in user://configs/. Invalid applies fall back to the last good (or bundled) data.

const P := preload("res://scripts/pieces.gd")
const M := preload("res://scripts/mobs.gd")
const SC := preload("res://scripts/scoring.gd")

const GAME_DATA_PATH := "res://config/game_data.json"
const SETTINGS_PATH := "res://config/settings.json"
const USER_CONFIG_DIR := "user://configs"

static var game_data: Dictionary = {}
static var settings: Dictionary = {}
static var last_error := ""
static var active_game_data_path := GAME_DATA_PATH
static var active_settings_path := SETTINGS_PATH
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	reload_defaults()


static func reload_defaults() -> bool:
	var ok_gd := _load_and_apply_game_data(GAME_DATA_PATH)
	var ok_st := _load_and_apply_settings(SETTINGS_PATH)
	_loaded = ok_gd and ok_st
	if not ok_gd:
		_apply_builtin_game_data()
		active_game_data_path = GAME_DATA_PATH
	if not ok_st:
		_apply_builtin_settings()
		active_settings_path = SETTINGS_PATH
	_loaded = true
	return ok_gd and ok_st


## List selectable config files: bundled res://config/*.json then user://configs/*.json.
static func list_configs() -> Array:
	ensure_loaded()
	var out: Array = []
	for p in _list_json_in("res://config"):
		out.append({"path": p, "label": "%s  (bundled)" % p.get_file(), "source": "bundled"})
	_ensure_user_dir()
	for p in _list_json_in(USER_CONFIG_DIR):
		out.append({"path": p, "label": "%s  (user)" % p.get_file(), "source": "user"})
	return out


## Apply one JSON file (game_data, settings, or bundle with both). Returns "" on success.
static func apply_file(path: String) -> String:
	ensure_loaded()
	last_error = ""
	if path == "" or not FileAccess.file_exists(path):
		last_error = "Config file not found."
		return last_error
	var parsed = _parse_json_file(path)
	if parsed == null:
		return last_error
	if not (parsed is Dictionary):
		last_error = "Config root must be a JSON object."
		return last_error
	var data: Dictionary = parsed
	var schema := str(data.get("schema", ""))
	var prev_gd: Dictionary = game_data.duplicate(true)
	var prev_st: Dictionary = settings.duplicate(true)
	var prev_gd_path := active_game_data_path
	var prev_st_path := active_settings_path

	var applied_gd := false
	var applied_st := false
	if schema == "bundle" or (data.has("game_data") and data.has("settings")):
		var gd: Dictionary = data.get("game_data", {})
		var st: Dictionary = data.get("settings", {})
		if not _validate_game_data(gd):
			return last_error
		if not _validate_settings(st):
			return last_error
		_commit_game_data(gd, path)
		_commit_settings(st, path)
		applied_gd = true
		applied_st = true
	elif schema == "game_data" or data.has("pieces") or data.has("mobs"):
		if not _validate_game_data(data):
			return last_error
		_commit_game_data(data, path)
		applied_gd = true
	elif schema == "settings" or data.has("keys") or data.has("speed") or data.has("match"):
		if not _validate_settings(data):
			return last_error
		_commit_settings(data, path)
		applied_st = true
	else:
		last_error = "Unrecognized config schema (expected game_data, settings, or bundle)."
		return last_error

	if not applied_gd and not applied_st:
		last_error = "Nothing to apply."
		return last_error
	# Re-validate runtime tables; roll back on failure.
	if not P.COST.has(P.KING) or M.WAVE_DEFS.is_empty():
		_commit_game_data(prev_gd, prev_gd_path)
		_commit_settings(prev_st, prev_st_path)
		last_error = "Apply failed — restored previous config."
		return last_error
	return ""


static func key_label(action: String) -> String:
	ensure_loaded()
	var keys: Dictionary = settings.get("keys", {})
	return str(keys.get(action, "?"))


static func keycode(action: String) -> int:
	return _keycode_from_token(key_label(action))


static func matches_key(event: InputEventKey, action: String) -> bool:
	var token := key_label(action)
	if token == "" or token == "?":
		return false
	var want_shift := token.begins_with("Shift+")
	var name := token.trim_prefix("Shift+") if want_shift else token
	if want_shift != event.shift_pressed:
		return false
	return event.keycode == _keycode_from_token(name) or event.physical_keycode == _keycode_from_token(name)


static func build_hotkey_index(event: InputEventKey) -> int:
	ensure_loaded()
	if event.shift_pressed or event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		return -1
	var keys: Array = settings.get("keys", {}).get("build", [])
	for i in keys.size():
		if event.keycode == _keycode_from_token(str(keys[i])):
			return i
	return -1


static func sell_refund_ratio() -> float:
	ensure_loaded()
	return float(settings.get("match", {}).get("sell_refund_ratio", 0.5))


static func start_gold() -> int:
	ensure_loaded()
	return int(settings.get("match", {}).get("start_gold", 200))


static func max_waves() -> int:
	ensure_loaded()
	return int(settings.get("match", {}).get("max_waves", 20))


static func speed_options() -> Array:
	ensure_loaded()
	return settings.get("speed", {}).get("options", [1.0, 2.0, 3.0, 5.0, 10.0])


# ---------------------------------------------------------------- load / apply

static func _load_and_apply_game_data(path: String) -> bool:
	var parsed = _parse_json_file(path)
	if parsed == null or not (parsed is Dictionary):
		return false
	if not _validate_game_data(parsed):
		return false
	_commit_game_data(parsed, path)
	return true


static func _load_and_apply_settings(path: String) -> bool:
	var parsed = _parse_json_file(path)
	if parsed == null or not (parsed is Dictionary):
		return false
	if not _validate_settings(parsed):
		return false
	_commit_settings(parsed, path)
	return true


static func _commit_game_data(data: Dictionary, path: String) -> void:
	game_data = data.duplicate(true)
	active_game_data_path = path
	P.apply_data(game_data)
	M.apply_data(game_data)
	SC.apply_data(game_data)


static func _commit_settings(data: Dictionary, path: String) -> void:
	settings = data.duplicate(true)
	active_settings_path = path


static func _parse_json_file(path: String):
	if not FileAccess.file_exists(path):
		last_error = "Missing file: %s" % path
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		last_error = "Cannot open: %s" % path
		return null
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed == null:
		last_error = "Invalid JSON: %s" % path
		return null
	return parsed


static func _list_json_in(dir_path: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".json"):
			out.append(dir_path.path_join(name))
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


static func _ensure_user_dir() -> void:
	var abs := ProjectSettings.globalize_path(USER_CONFIG_DIR)
	if not DirAccess.dir_exists_absolute(abs):
		DirAccess.make_dir_recursive_absolute(abs)


# ---------------------------------------------------------------- validation

static func _validate_game_data(data: Dictionary) -> bool:
	if not (data.get("pieces") is Dictionary):
		last_error = "game_data.pieces missing."
		return false
	var pieces: Dictionary = data.pieces
	if not (pieces.get("defs") is Dictionary) or not (pieces.get("order") is Array):
		last_error = "game_data.pieces.defs/order missing."
		return false
	for id in pieces.order:
		if not pieces.defs.has(str(id)):
			last_error = "game_data missing piece def: %s" % id
			return false
		var d: Dictionary = pieces.defs[str(id)]
		for k in ["name", "cost", "damage", "cooldown", "hp"]:
			if not d.has(k):
				last_error = "piece %s missing %s" % [id, k]
				return false
	if not (data.get("upgrades") is Dictionary) or not (data.get("synergy_cap") is Dictionary):
		last_error = "game_data upgrades/synergy_cap missing."
		return false
	if not (data.get("mobs") is Dictionary):
		last_error = "game_data.mobs missing."
		return false
	var mobs: Dictionary = data.mobs
	if not (mobs.get("types") is Dictionary) or not (mobs.get("waves") is Array):
		last_error = "game_data.mobs.types/waves missing."
		return false
	for id in ["grunt", "runner", "brute", "sapper", "promoted"]:
		if not mobs.types.has(id):
			last_error = "game_data missing mob type: %s" % id
			return false
	if mobs.waves.is_empty():
		last_error = "game_data.mobs.waves empty."
		return false
	if not (data.get("scoring") is Dictionary):
		last_error = "game_data.scoring missing."
		return false
	return true


static func _validate_settings(data: Dictionary) -> bool:
	for section in ["board", "match", "castling", "speed", "ui", "keys"]:
		if not (data.get(section) is Dictionary):
			last_error = "settings.%s missing." % section
			return false
	var speed_opts = data.speed.get("options", null)
	if not (speed_opts is Array) or speed_opts.is_empty():
		last_error = "settings.speed.options must be a non-empty array."
		return false
	var keys: Dictionary = data.keys
	if not (keys.get("build") is Array) or keys.build.size() < 1:
		last_error = "settings.keys.build missing."
		return false
	for action in ["upgrade", "sell", "speed", "leaderboard", "config", "restart", "start_wave"]:
		if str(keys.get(action, "")) == "":
			last_error = "settings.keys.%s missing." % action
			return false
	if int(data.match.get("start_gold", -1)) < 0:
		last_error = "settings.match.start_gold invalid."
		return false
	if int(data.match.get("max_waves", 0)) < 1:
		last_error = "settings.match.max_waves invalid."
		return false
	return true


static func _keycode_from_token(token: String) -> int:
	var t := token.strip_edges()
	if t.begins_with("Shift+"):
		t = t.trim_prefix("Shift+")
	t = t.to_upper()
	match t:
		"1": return KEY_1
		"2": return KEY_2
		"3": return KEY_3
		"4": return KEY_4
		"5": return KEY_5
		"6": return KEY_6
		"7": return KEY_7
		"8": return KEY_8
		"9": return KEY_9
		"0": return KEY_0
		"A": return KEY_A
		"B": return KEY_B
		"C": return KEY_C
		"D": return KEY_D
		"E": return KEY_E
		"F": return KEY_F
		"G": return KEY_G
		"H": return KEY_H
		"I": return KEY_I
		"J": return KEY_J
		"K": return KEY_K
		"L": return KEY_L
		"M": return KEY_M
		"N": return KEY_N
		"O": return KEY_O
		"P": return KEY_P
		"Q": return KEY_Q
		"R": return KEY_R
		"S": return KEY_S
		"T": return KEY_T
		"U": return KEY_U
		"V": return KEY_V
		"W": return KEY_W
		"X": return KEY_X
		"Y": return KEY_Y
		"Z": return KEY_Z
		"SPACE": return KEY_SPACE
		"ENTER", "RETURN": return KEY_ENTER
		"ESCAPE", "ESC": return KEY_ESCAPE
		"DELETE", "DEL": return KEY_DELETE
		"BACKSPACE": return KEY_BACKSPACE
		"TAB": return KEY_TAB
		_:
			return KEY_NONE


# ---------------------------------------------------------------- builtin fallback (mirrors bundled JSON)

static func _apply_builtin_game_data() -> void:
	var text := FileAccess.get_file_as_string(GAME_DATA_PATH) if FileAccess.file_exists(GAME_DATA_PATH) else ""
	var parsed = JSON.parse_string(text) if text != "" else null
	if parsed is Dictionary and _validate_game_data(parsed):
		_commit_game_data(parsed, GAME_DATA_PATH)
		return
	# Minimal emergency stub so the game can boot if JSON is missing.
	var stub := {
		"schema": "game_data",
		"version": 1,
		"pieces": {
			"order": ["pawn", "knight", "bishop", "rook", "queen", "king", "wall"],
			"max_level": 5,
			"defs": {
				"pawn": {"name": "Pawn", "letter": "P", "cost": 20, "damage": 6.0, "cooldown": 0.7, "hp": 40.0, "color": [0.85, 0.85, 0.85], "synergy": {"dmg": 0.1}},
				"knight": {"name": "Knight", "letter": "N", "cost": 45, "damage": 12.0, "cooldown": 1.1, "hp": 50.0, "color": [0.95, 0.55, 0.3], "synergy": {"spd": 0.12}},
				"bishop": {"name": "Bishop", "letter": "B", "cost": 50, "damage": 6.0, "cooldown": 0.8, "hp": 50.0, "color": [0.35, 0.85, 0.55], "synergy": {"range": 1}},
				"rook": {"name": "Rook", "letter": "R", "cost": 60, "damage": 7.0, "cooldown": 0.9, "hp": 60.0, "color": [0.35, 0.6, 0.95], "synergy": {"hp": 0.15}},
				"queen": {"name": "Queen", "letter": "Q", "cost": 120, "damage": 8.0, "cooldown": 0.8, "hp": 60.0, "color": [0.85, 0.45, 0.9], "synergy": {"dmg": 0.05, "spd": 0.05, "hp": 0.05}},
				"king": {"name": "King", "letter": "K", "cost": 0, "damage": 5.0, "cooldown": 0.8, "hp": 200.0, "color": [0.95, 0.78, 0.25], "synergy": {"dmg": 0.08, "spd": 0.08}},
				"wall": {"name": "Wall", "letter": "", "cost": 100, "damage": 0.0, "cooldown": 0.0, "hp": 100.0, "color": [0.5, 0.5, 0.55], "synergy": {}},
			},
		},
		"upgrades": {"damage_per_level": 0.6, "hp_per_level": 0.25, "wall_hp_per_level": 0.5, "cost_factor": 0.8, "cost_floor": 40, "slide_range_base": 2},
		"synergy_cap": {"dmg": 0.5, "spd": 0.5, "hp": 0.6, "range": 2},
		"mobs": {
			"hp_scale_per_wave": 0.06,
			"wave_clear_gold": {"base": 14, "per_wave": 3, "extra_after_wave": 3, "extra_per_wave": 1},
			"wave_type_order": ["grunt", "runner", "brute", "sapper"],
			"types": {
				"grunt": {"name": "Grunt", "color": [0.55, 0.05, 0.1], "hp": 18.0, "speed": 1.0, "speed_growth": 0.04, "damage": 3.0, "damage_growth": 0.35, "reward": 6, "reward_growth": 1.2, "wall_mult": 1.0, "prefers_walls": false, "kill_score": 10},
				"runner": {"name": "Runner", "color": [0.95, 0.45, 0.1], "hp": 10.0, "speed": 1.65, "speed_growth": 0.05, "damage": 2.0, "damage_growth": 0.2, "reward": 5, "reward_growth": 1.0, "wall_mult": 1.0, "prefers_walls": false, "kill_score": 7},
				"brute": {"name": "Brute", "color": [0.35, 0.05, 0.15], "hp": 38.0, "speed": 0.72, "speed_growth": 0.02, "damage": 7.0, "damage_growth": 0.55, "reward": 11, "reward_growth": 1.3, "wall_mult": 1.6, "prefers_walls": false, "kill_score": 24},
				"sapper": {"name": "Sapper", "color": [0.5, 0.15, 0.55], "hp": 14.0, "speed": 0.95, "speed_growth": 0.03, "damage": 2.5, "damage_growth": 0.25, "reward": 7, "reward_growth": 1.0, "wall_mult": 2.2, "prefers_walls": true, "kill_score": 13},
				"promoted": {"name": "Promoted", "color": [0.82, 0.62, 0.12], "hp": 34.0, "speed": 1.4, "speed_growth": 0.045, "damage": 6.5, "damage_growth": 0.5, "reward": 15, "reward_growth": 1.6, "wall_mult": 1.3, "prefers_walls": false, "kill_score": 32},
			},
			"waves": [{"grunt": 6}],
		},
		"scoring": {"wave_clear_base": 20, "wave_clear_per_wave": 6},
	}
	_commit_game_data(stub, GAME_DATA_PATH)


static func _apply_builtin_settings() -> void:
	var text := FileAccess.get_file_as_string(SETTINGS_PATH) if FileAccess.file_exists(SETTINGS_PATH) else ""
	var parsed = JSON.parse_string(text) if text != "" else null
	if parsed is Dictionary and _validate_settings(parsed):
		_commit_settings(parsed, SETTINGS_PATH)
		return
	_commit_settings({
		"schema": "settings",
		"version": 1,
		"board": {"cols": 8, "rows": 12, "player_min_row": 3, "base_tile": 56.0, "base_margin": 16.0},
		"match": {"start_gold": 200, "max_waves": 20, "spawn_interval": 1.2, "mob_attack_rate": 1.0, "piece_path_weight": 12.0, "sell_refund_ratio": 0.5},
		"castling": {"min_h": 2, "max_h": 4},
		"speed": {"options": [1.0, 2.0, 3.0, 5.0, 10.0], "max_sim_step": 1.0 / 30.0, "max_frame_delta": 0.25},
		"ui": {"title": "ChessTD : Protect the King", "hud_min_width": 228, "help_text": "Left-click: place / select piece   Right-click: cancel\nPiece menu pauses the game.  Esc closes it."},
		"keys": {
			"build": ["1", "2", "3", "4", "5", "6", "7"],
			"upgrade": "U", "sell": "S", "sell_alt": "Delete",
			"start_wave": "Space", "start_wave_alt": "Enter", "castle": "C", "cancel": "Escape",
			"speed": "F", "leaderboard": "L", "config": "O",
			"layout_save": "Shift+S", "layout_load": "Shift+L", "layout_default": "Shift+D",
			"layout_delete": "Shift+X", "restart": "Shift+R",
		},
	}, SETTINGS_PATH)
