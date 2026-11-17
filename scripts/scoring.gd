extends RefCounted
## Match score: kill points by mob strength and wave-clear bonuses.

const M := preload("res://scripts/mobs.gd")

## Base kill score by mob type (promoted and brutes worth more).
const KILL_BASE := {
	M.GRUNT: 10,
	M.RUNNER: 7,
	M.BRUTE: 24,
	M.SAPPER: 13,
	M.PROMOTED: 32,
}


static func kill_points(mob_type: int, wave: int) -> int:
	var base: int = int(KILL_BASE.get(mob_type, 10))
	var w: int = maxi(1, wave)
	return base + w


static func wave_clear_points(wave: int) -> int:
	return 20 + 6 * wave


static func final_score(kill_total: int, wave_bonus_total: int) -> int:
	return kill_total + wave_bonus_total