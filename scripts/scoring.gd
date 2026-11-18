extends RefCounted
## Match score: kill points by mob strength and wave-clear bonuses (from game_data).

const M := preload("res://scripts/mobs.gd")

static var KILL_BASE := {
	M.GRUNT: 10,
	M.RUNNER: 7,
	M.BRUTE: 24,
	M.SAPPER: 13,
	M.PROMOTED: 32,
}
static var WAVE_CLEAR_BASE := 20
static var WAVE_CLEAR_PER_WAVE := 6


static func apply_data(data: Dictionary) -> void:
	KILL_BASE = {}
	var types: Dictionary = data.get("mobs", {}).get("types", {})
	for key in M.ID_BY_NAME:
		var t: int = M.ID_BY_NAME[key]
		var d: Dictionary = types.get(key, {})
		KILL_BASE[t] = int(d.get("kill_score", 10))
	var sc: Dictionary = data.get("scoring", {})
	WAVE_CLEAR_BASE = int(sc.get("wave_clear_base", 20))
	WAVE_CLEAR_PER_WAVE = int(sc.get("wave_clear_per_wave", 6))


static func kill_points(mob_type: int, wave: int) -> int:
	var base: int = int(KILL_BASE.get(mob_type, 10))
	var w: int = maxi(1, wave)
	return base + w


static func wave_clear_points(wave: int) -> int:
	return WAVE_CLEAR_BASE + WAVE_CLEAR_PER_WAVE * wave


static func final_score(kill_total: int, wave_bonus_total: int) -> int:
	return kill_total + wave_bonus_total
