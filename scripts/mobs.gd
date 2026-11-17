extends RefCounted
## Enemy mob types: stats, wave composition and drawing helpers.

enum { GRUNT, RUNNER, BRUTE, SAPPER }

const NAMES := {GRUNT: "Grunt", RUNNER: "Runner", BRUTE: "Brute", SAPPER: "Sapper"}
const COLORS := {
	GRUNT: Color(0.55, 0.05, 0.1),
	RUNNER: Color(0.95, 0.45, 0.1),
	BRUTE: Color(0.35, 0.05, 0.15),
	SAPPER: Color(0.5, 0.15, 0.55),
}


static func mob_stats(type: int, wave: int) -> Dictionary:
	var w: float = maxf(1.0, float(wave))
	var hp_scale: float = 1.0 + 0.08 * (w - 1.0)
	match type:
		GRUNT:
			return {
				"hp": 18.0 * hp_scale,
				"speed": 1.0 + 0.04 * w,
				"damage": 3.0 + 0.35 * w,
				"reward": 5 + int(w),
				"wall_mult": 1.0,
				"prefers_walls": false,
			}
		RUNNER:
			return {
				"hp": 10.0 * hp_scale,
				"speed": 1.65 + 0.05 * w,
				"damage": 2.0 + 0.2 * w,
				"reward": 4 + int(w * 0.8),
				"wall_mult": 1.0,
				"prefers_walls": false,
			}
		BRUTE:
			return {
				"hp": 38.0 * hp_scale,
				"speed": 0.72 + 0.02 * w,
				"damage": 7.0 + 0.55 * w,
				"reward": 10 + int(w * 1.5),
				"wall_mult": 1.6,
				"prefers_walls": false,
			}
		SAPPER:
			return {
				"hp": 14.0 * hp_scale,
				"speed": 0.95 + 0.03 * w,
				"damage": 2.5 + 0.25 * w,
				"reward": 6 + int(w),
				"wall_mult": 2.2,
				"prefers_walls": true,
			}
	return mob_stats(GRUNT, wave)


## Ordered list of mob types spawned for a given wave (mixed composition).
static func wave_spawn_list(wave: int) -> Array:
	var n: int = 4 + wave * 2
	var list: Array = []
	list.resize(n)
	list.fill(GRUNT)
	var runners: int = mini(n / 3, 1 + wave / 2)
	for i in runners:
		var idx := int((i + 1) * float(n) / float(runners + 1))
		list[idx] = RUNNER
	if wave >= 3:
		var brutes: int = mini(1 + (wave - 3) / 3, n / 4)
		for i in brutes:
			list[n - 1 - i * 2] = BRUTE
	if wave >= 4:
		var sappers: int = mini(1 + (wave - 4) / 4, n / 5)
		for i in sappers:
			list[mini(n / 2 + i, n - 1)] = SAPPER
	return list


static func draw_mob(canvas: CanvasItem, center: Vector2, type: int, fill: Color, outline: Color) -> void:
	match type:
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