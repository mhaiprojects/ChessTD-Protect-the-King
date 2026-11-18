extends RefCounted
## Enemy mob types, wave table and stats — balance filled from config/game_data.json.
## Drawing helpers stay here (vector shapes).

enum { GRUNT, RUNNER, BRUTE, SAPPER, PROMOTED }

const ID_BY_NAME := {
	"grunt": GRUNT, "runner": RUNNER, "brute": BRUTE, "sapper": SAPPER, "promoted": PROMOTED,
}

static var NAMES := {
	GRUNT: "Grunt", RUNNER: "Runner", BRUTE: "Brute", SAPPER: "Sapper", PROMOTED: "Promoted",
}
static var COLORS := {
	GRUNT: Color(0.55, 0.05, 0.1),
	RUNNER: Color(0.95, 0.45, 0.1),
	BRUTE: Color(0.35, 0.05, 0.15),
	SAPPER: Color(0.5, 0.15, 0.55),
	PROMOTED: Color(0.82, 0.62, 0.12),
}
static var TYPE_DEFS := {}
static var WAVE_DEFS: Array = []
static var WAVE_TYPE_ORDER: Array = [GRUNT, RUNNER, BRUTE, SAPPER]
static var HP_SCALE_PER_WAVE := 0.06
static var WAVE_CLEAR_GOLD := {"base": 14, "per_wave": 3, "extra_after_wave": 3, "extra_per_wave": 1}


static func apply_data(data: Dictionary) -> void:
	var mobs: Dictionary = data.get("mobs", {})
	HP_SCALE_PER_WAVE = float(mobs.get("hp_scale_per_wave", 0.06))
	var wcg: Dictionary = mobs.get("wave_clear_gold", {})
	WAVE_CLEAR_GOLD = {
		"base": int(wcg.get("base", 14)),
		"per_wave": int(wcg.get("per_wave", 3)),
		"extra_after_wave": int(wcg.get("extra_after_wave", 3)),
		"extra_per_wave": int(wcg.get("extra_per_wave", 1)),
	}
	var types: Dictionary = mobs.get("types", {})
	NAMES = {}
	COLORS = {}
	TYPE_DEFS = {}
	for key in ID_BY_NAME:
		var t: int = ID_BY_NAME[key]
		var d: Dictionary = types.get(key, {})
		NAMES[t] = str(d.get("name", key.capitalize()))
		COLORS[t] = _color(d.get("color", [0.7, 0.1, 0.1]))
		TYPE_DEFS[t] = {
			"hp": float(d.get("hp", 10.0)),
			"speed": float(d.get("speed", 1.0)),
			"speed_growth": float(d.get("speed_growth", 0.0)),
			"damage": float(d.get("damage", 1.0)),
			"damage_growth": float(d.get("damage_growth", 0.0)),
			"reward": int(d.get("reward", 1)),
			"reward_growth": float(d.get("reward_growth", 0.0)),
			"wall_mult": float(d.get("wall_mult", 1.0)),
			"prefers_walls": bool(d.get("prefers_walls", false)),
			"kill_score": int(d.get("kill_score", 10)),
		}
	WAVE_TYPE_ORDER = []
	for id in mobs.get("wave_type_order", ["grunt", "runner", "brute", "sapper"]):
		var key := str(id).to_lower()
		if ID_BY_NAME.has(key) and ID_BY_NAME[key] != PROMOTED:
			WAVE_TYPE_ORDER.append(ID_BY_NAME[key])
	if WAVE_TYPE_ORDER.is_empty():
		WAVE_TYPE_ORDER = [GRUNT, RUNNER, BRUTE, SAPPER]
	WAVE_DEFS = []
	for w in mobs.get("waves", []):
		if not (w is Dictionary):
			continue
		var row := {}
		for key in w:
			var k := str(key).to_lower()
			if ID_BY_NAME.has(k):
				row[ID_BY_NAME[k]] = int(w[key])
		WAVE_DEFS.append(row)
	if WAVE_DEFS.is_empty():
		WAVE_DEFS = [{GRUNT: 6}]


static func _color(v) -> Color:
	if v is Color:
		return v
	if v is Array and v.size() >= 3:
		var a := float(v[3]) if v.size() > 3 else 1.0
		return Color(float(v[0]), float(v[1]), float(v[2]), a)
	return Color(0.7, 0.1, 0.1)


static func hp_scale_for_wave(wave: int) -> float:
	var w: float = maxf(1.0, float(wave))
	return 1.0 + HP_SCALE_PER_WAVE * (w - 1.0)


static func wave_def(wave: int) -> Dictionary:
	return WAVE_DEFS[clampi(wave - 1, 0, WAVE_DEFS.size() - 1)]


static func wave_mob_count(wave: int) -> int:
	var def: Dictionary = wave_def(wave)
	var n := 0
	for t in WAVE_TYPE_ORDER:
		n += int(def.get(t, 0))
	return n


static func wave_clear_bonus(wave: int) -> int:
	var base: int = int(WAVE_CLEAR_GOLD.base)
	var per: int = int(WAVE_CLEAR_GOLD.per_wave)
	var after: int = int(WAVE_CLEAR_GOLD.extra_after_wave)
	var extra: int = int(WAVE_CLEAR_GOLD.extra_per_wave)
	return base + per * wave + maxi(0, wave - after) * extra


static func mob_stats(type: int, wave: int) -> Dictionary:
	var w: float = maxf(1.0, float(wave))
	var hp_scale: float = hp_scale_for_wave(wave)
	var d: Dictionary = TYPE_DEFS.get(type, TYPE_DEFS.get(GRUNT, {}))
	if d.is_empty():
		return {"hp": 10.0, "speed": 1.0, "damage": 1.0, "reward": 1, "wall_mult": 1.0, "prefers_walls": false}
	return {
		"hp": float(d.hp) * hp_scale,
		"speed": float(d.speed) + float(d.speed_growth) * w,
		"damage": float(d.damage) + float(d.damage_growth) * w,
		"reward": int(d.reward) + int(float(d.reward_growth) * w),
		"wall_mult": float(d.wall_mult),
		"prefers_walls": bool(d.prefers_walls),
	}


## Ordered list of mob types spawned for a given wave (interleaved mix).
static func wave_spawn_list(wave: int) -> Array:
	var def: Dictionary = wave_def(wave)
	var queues: Dictionary = {}
	var total := 0
	for t in WAVE_TYPE_ORDER:
		var c: int = int(def.get(t, 0))
		if c > 0:
			queues[t] = []
			for i in c:
				queues[t].append(t)
			total += c
	var list: Array = []
	list.resize(total)
	var idx := 0
	while idx < total:
		for t in WAVE_TYPE_ORDER:
			var q: Array = queues.get(t, [])
			if q.is_empty():
				continue
			list[idx] = q.pop_front()
			queues[t] = q
			idx += 1
	return list


static func draw_mob(canvas: CanvasItem, center: Vector2, type: int, fill: Color, outline: Color, flash: float = 0.0) -> void:
	var ink := outline
	if flash > 0.0:
		ink = ink.lerp(Color(1.0, 0.5, 0.35), clampf(flash / 0.18, 0.0, 0.65))
	match type:
		PROMOTED:
			var r := 15.0
			canvas.draw_circle(center, r, fill)
			canvas.draw_arc(center, r, 0, TAU, 32, ink, 2.2)
			var crown := PackedVector2Array([
				center + Vector2(-15, -5), center + Vector2(-9, -19), center + Vector2(-4, -8),
				center + Vector2(0, -18), center + Vector2(4, -8), center + Vector2(9, -19), center + Vector2(15, -5),
			])
			canvas.draw_colored_polygon(crown, fill.lightened(0.12))
			canvas.draw_polyline(crown, ink, 2.0)
			for i in [1, 3, 5]:
				canvas.draw_circle(crown[i] + Vector2(0, -1), 2.2, Color(0.95, 0.82, 0.25))
		RUNNER:
			var dia := PackedVector2Array([
				center + Vector2(0, -15), center + Vector2(14, 0),
				center + Vector2(0, 15), center + Vector2(-14, 0),
			])
			canvas.draw_colored_polygon(dia, fill)
			canvas.draw_polyline(PackedVector2Array([dia[0], dia[1], dia[2], dia[3], dia[0]]), ink, 2.2)
		BRUTE:
			var sq := Rect2(center - Vector2(16, 16), Vector2(32, 32))
			canvas.draw_rect(sq, fill)
			canvas.draw_line(sq.position + Vector2(0, 11), sq.position + Vector2(32, 11), ink, 2.0)
			canvas.draw_line(sq.position + Vector2(0, 21), sq.position + Vector2(32, 21), ink, 2.0)
			canvas.draw_rect(sq, ink, false, 2.2)
		SAPPER:
			var hex := PackedVector2Array()
			for k in 6:
				var a: float = float(k) / 6.0 * TAU - PI / 2.0
				hex.append(center + Vector2(cos(a), sin(a)) * 15.5)
			canvas.draw_colored_polygon(hex, fill)
			canvas.draw_polyline(PackedVector2Array([hex[0], hex[1], hex[2], hex[3], hex[4], hex[5], hex[0]]), ink, 2.2)
			canvas.draw_line(center + Vector2(-6, 0), center + Vector2(6, 0), ink.lightened(0.2), 2.0)
		_:  # GRUNT
			var tri := PackedVector2Array([
				center + Vector2(-16, -11), center + Vector2(16, -11), center + Vector2(0, 17),
			])
			canvas.draw_colored_polygon(tri, fill)
			canvas.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), ink, 2.2)
