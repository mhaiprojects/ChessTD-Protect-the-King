extends SceneTree
const P := preload("res://scripts/pieces.gd")
func _initialize():
	var g = load("res://scripts/game.gd").new()
	g.rng.seed = 7
	g.place(P.KING, Vector2i(3, 11))
	var spots = [Vector2i(3,8),Vector2i(2,9),Vector2i(4,9),Vector2i(1,7),Vector2i(5,7),Vector2i(3,5),Vector2i(6,9),Vector2i(0,9)]
	var types = [P.PAWN,P.ROOK,P.QUEEN,P.BISHOP,P.BISHOP,P.ROOK,P.KNIGHT,P.KNIGHT]
	for w in 10:
		for i in spots.size():
			if not g.pieces.has(spots[i]): g.place(types[i], spots[i])
		var more := true
		while more:
			more = false
			for c in g.pieces.keys():
				if g.pieces[c].type != P.KING and g.upgrade(c): more = true
		g.start_wave()
		var t := 0.0
		while g.phase == g.Phase.WAVE and t < 300: g.step(0.05); t += 0.05
		print("wave %d -> %s king=%s gold=%d pieces=%d" % [g.wave, g.PHASE_NAMES[g.phase], str(g.pieces[g.king_cell].hp) if g.has_king() else "dead", g.gold, g.pieces.size()])
		if g.phase != g.Phase.BETWEEN: break
	quit()
