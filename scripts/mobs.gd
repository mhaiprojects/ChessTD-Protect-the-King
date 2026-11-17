extends RefCounted
## Enemy mob types: stats, wave composition and drawing helpers.

enum { GRUNT, RUNNER, BRUTE, SAPPER, PROMOTED }

const NAMES := {
	GRUNT: "Grunt", RUNNER: "Runner", BRUTE: "Brute", SAPPER: "Sapper", PROMOTED: "Promoted",
}
const COLORS := {
	GRUNT: Color(0.55, 0.05, 0.1),
	RUNNER: Color(0.95, 0.45, 0.1),
	BRUTE: Color(0.35, 0.05, 0.15),
	SAPPER: Color(0.5, 0.15, 0.55),
	PROMOTED: Color(0.82, 0.62, 0.12),
}


## Gentle HP ramp: ~6% per wave, no post-wave-5 jump.
static func hp_scale_for_wave(wave: int) -> float:
	var w: float = maxf(1.0, float(wave))
	return 1.0 + 0.06 * (w - 1.0)


## Data-driven 20-wave progression (counts per mob type).
const WAVE_DEFS: Array = [
	{GRUNT: 6},
	{GRUNT: 4, RUNNER: 2},
	{GRUNT: 5, RUNNER: 2},
	{GRUNT: 4, RUNNER: 2, SAPPER: 1},
	{GRUNT: 4, RUNNER: 2, BRUTE: 1, SAPPER: 1},
	{GRUNT: 5, RUNNER: 2, BRUTE: 1, SAPPER: 1},
	{GRUNT: 5, RUNNER: 3, BRUTE: 1, SAPPER: 1},
	{GRUNT: 6, RUNNER: 2, BRUTE: 2, SAPPER: 1},
	{GRUNT: 5, RUNNER: 3, BRUTE: 2, SAPPER: 1},
	{GRUNT: 5, RUNNER: 3, BRUTE: 2, SAPPER: 2},
	{GRUNT: 6, RUNNER: 3, BRUTE: 2, SAPPER: 2},
	{GRUNT: 5, RUNNER: 4, BRUTE: 2, SAPPER: 2},
	{GRUNT: 6, RUNNER: 3, BRUTE: 3, SAPPER: 2},
	{GRUNT: 5, RUNNER: 4, BRUTE: 3, SAPPER: 2},
	{GRUNT: 6, RUNNER: 4, BRUTE: 3, SAPPER: 3},
	{GRUNT: 5, RUNNER: 4, BRUTE: 4, SAPPER: 3},
	{GRUNT: 6, RUNNER: 4, BRUTE: 4, SAPPER: 3},
	{GRUNT: 5, RUNNER: 5, BRUTE: 4, SAPPER: 3},
	{GRUNT: 6, RUNNER: 4, BRUTE: 4, SAPPER: 4},
	{GRUNT: 6, RUNNER: 4, BRUTE: 4, SAPPER: 4},
]

const WAVE_TYPE_ORDER := [GRUNT, RUNNER, BRUTE, SAPPER]


static func wave_def(wave: int) -> Dictionary:
	return WAVE_DEFS[clampi(wave - 1, 0, WAVE_DEFS.size() - 1)]


static func wave_mob_count(wave: int) -> int:
	var def: Dictionary = wave_def(wave)
	var n := 0
	for t in WAVE_TYPE_ORDER:
		n += int(def.get(t, 0))
	return n


static func wave_clear_bonus(wave: int) -> int:
	return 14 + 3 * wave + maxi(0, wave - 3)


static func mob_stats(type: int, wave: int) -> Dictionary:
	var w: float = maxf(1.0, float(wave))
	var hp_scale: float = hp_scale_for_wave(wave)
	match type:
		GRUNT:
			return {
				"hp": 18.0 * hp_scale,
				"speed": 1.0 + 0.04 * w,
				"damage": 3.0 + 0.35 * w,
				"reward": 6 + int(w * 1.2),
				"wall_mult": 1.0,
				"prefers_walls": false,
			}
		RUNNER:
			return {
				"hp": 10.0 * hp_scale,
				"speed": 1.65 + 0.05 * w,
				"damage": 2.0 + 0.2 * w,
				"reward": 5 + int(w),
				"wall_mult": 1.0,
				"prefers_walls": false,
			}
		BRUTE:
			return {
				"hp": 38.0 * hp_scale,
				"speed": 0.72 + 0.02 * w,
				"damage": 7.0 + 0.55 * w,
				"reward": 11 + int(w * 1.3),
				"wall_mult": 1.6,
				"prefers_walls": false,
			}
		SAPPER:
			return {
				"hp": 14.0 * hp_scale,
				"speed": 0.95 + 0.03 * w,
				"damage": 2.5 + 0.25 * w,
				"reward": 7 + int(w),
				"wall_mult": 2.2,
				"prefers_walls": true,
			}
		PROMOTED:
			return {
				"hp": 34.0 * hp_scale,
				"speed": 1.4 + 0.045 * w,
				"damage": 6.5 + 0.5 * w,
				"reward": 15 + int(w * 1.6),
				"wall_mult": 1.3,
				"prefers_walls": false,
			}
	return mob_stats(GRUNT, wave)


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


static func draw_mob(canvas: CanvasItem, center: Vector2, type: int, fill: Color, outline: Color) -> void:
	match type:
		PROMOTED:
			var r := 16.0
			canvas.draw_circle(center, r, fill)
			canvas.draw_arc(center, r, 0, TAU, 32, outline, 2.0)
			var crown := PackedVector2Array([
				center + Vector2(-14, -6), center + Vector2(-7, -18), center + Vector2(0, -10),
				center + Vector2(7, -18), center + Vector2(14, -6),
			])
			canvas.draw_colored_polygon(crown, fill.lightened(0.15))
			canvas.draw_polyline(PackedVector2Array([crown[0], crown[1], crown[2], crown[3], crown[4]]), outline, 2.0)
		RUNNER:
			var dia := PackedVector2Array([
				center + Vector2(0, -14), center + Vector2(13, 0),
				center + Vector2(0, 14), center + Vector2(-13, 0),
			])
			canvas.draw_colored_polygon(dia, fill)
			canvas.draw_polyline(PackedVector2Array([dia[0], dia[1], dia[2], dia[3], dia[0]]), outline, 2.0)
		BRUTE:
			var r := Rect2(center - Vector2(17, 17), Vector2(34, 34))
			canvas.draw_rect(r, fill)
			canvas.draw_rect(r, outline, false, 2.0)
		SAPPER:
			var hex := PackedVector2Array()
			for k in 6:
				var a: float = float(k) / 6.0 * TAU - PI / 2.0
				hex.append(center + Vector2(cos(a), sin(a)) * 15.0)
			canvas.draw_colored_polygon(hex, fill)
			canvas.draw_polyline(PackedVector2Array([hex[0], hex[1], hex[2], hex[3], hex[4], hex[5], hex[0]]), outline, 2.0)
		_:  # GRUNT
			var tri := PackedVector2Array([
				center + Vector2(-15, -12), center + Vector2(15, -12), center + Vector2(0, 16),
			])
			canvas.draw_colored_polygon(tri, fill)
			canvas.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), outline, 2.0)