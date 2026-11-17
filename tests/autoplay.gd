extends SceneTree
## Greedy bot balance check. Runs until victory, game over, or max_waves.

const P := preload("res://scripts/pieces.gd")
const M := preload("res://scripts/mobs.gd")

const MAX_WAVES := 25
const WAVE_TIMEOUT := 400.0


func _initialize() -> void:
	var g = load("res://scripts/game.gd").new()
	g.rng.seed = 7
	g.place(P.KING, Vector2i(3, 11))
	var spots := [Vector2i(3, 8), Vector2i(2, 9), Vector2i(4, 9), Vector2i(1, 7), Vector2i(5, 7),
		Vector2i(3, 5), Vector2i(6, 9), Vector2i(0, 9)]
	var types := [P.PAWN, P.ROOK, P.QUEEN, P.BISHOP, P.BISHOP, P.ROOK, P.KNIGHT, P.KNIGHT]
	var cleared := 0
	for w in MAX_WAVES:
		for i in spots.size():
			if not g.pieces.has(spots[i]):
				g.place(types[i], spots[i])
		var more := true
		while more:
			more = false
			for c in g.pieces.keys():
				if g.pieces[c].type != P.KING and g.upgrade(c):
					more = true
		g.start_wave()
		var t := 0.0
		while g.phase == g.Phase.WAVE and t < WAVE_TIMEOUT:
			g.step(0.05)
			t += 0.05
		var king_hp := str(g.pieces[g.king_cell].hp) if g.has_king() else "dead"
		print(
			"wave %2d -> %-22s king_hp=%-8s gold=%4d mobs=%d/%d" % [
				g.wave, g.PHASE_NAMES[g.phase], king_hp, g.gold, M.wave_mob_count(g.wave), g.kills
			]
		)
		if g.phase == g.Phase.BETWEEN:
			cleared = g.wave
		elif g.phase == g.Phase.VICTORY:
			cleared = g.wave
			break
		else:
			break
	print("\nAUTOPLAY: cleared %d waves (ended: %s, gold=%d, kills=%d)" % [
		cleared, g.PHASE_NAMES[g.phase], g.gold, g.kills
	])
	quit(0 if cleared >= 5 else 1)