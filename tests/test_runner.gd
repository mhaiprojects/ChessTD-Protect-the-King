extends SceneTree
## Headless test suite.  Run:  godot --headless --path . --script res://tests/test_runner.gd
## Exit code 0 = all passed.

const P := preload("res://scripts/pieces.gd")
const M := preload("res://scripts/mobs.gd")
const GameScript := preload("res://scripts/game.gd")
const SIZE := Vector2i(8, 12)

var passed := 0
var failed := 0


func _initialize() -> void:
	_run()


func check(cond: bool, name: String) -> void:
	if cond:
		passed += 1
		print("  PASS  ", name)
	else:
		failed += 1
		print("  FAIL  ", name)


func same_tiles(got: Array, expected: Array) -> bool:
	if got.size() != expected.size():
		print("        got ", got, "\n        expected ", expected)
		return false
	for e in expected:
		if not got.has(e):
			print("        missing ", e, " in ", got)
			return false
	return true


func new_game():
	var g = GameScript.new()
	g.rng.seed = 12345
	return g


func run_for(g, seconds: float, dt := 0.05, stop := Callable()) -> void:
	var t := 0.0
	while t < seconds:
		g.step(dt)
		t += dt
		if stop.is_valid() and stop.call():
			return


func _run() -> void:
	print("== Attack patterns ==")
	test_patterns()
	print("== Placement / setup ==")
	test_placement()
	test_tower_adjacency()
	test_path_validation()
	print("== Mob types ==")
	test_mob_types()
	print("== Difficulty curve ==")
	test_difficulty_curve()
	print("== 20-wave campaign ==")
	test_twenty_waves()
	print("== Waves, mob movement & pathfinding ==")
	test_wave_and_movement()
	print("== Mob tile occupation ==")
	test_mob_tile_occupation()
	print("== Mobs attack pieces ==")
	test_mob_attacks()
	print("== Castling ==")
	test_castling()
	print("== Promotion ==")
	test_promotion()
	print("== Combat, gold, upgrades ==")
	test_combat_gold_upgrade()
	print("== Full wave simulation ==")
	test_full_wave()
	print("== Main scene + UI + mouse input ==")
	await test_scene()
	print("\nRESULT: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func test_patterns() -> void:
	var c := Vector2i(3, 8)
	var empty := {}
	# Rook with unlimited range = full row + column
	var exp_rook := []
	for y in 12:
		if y != 8: exp_rook.append(Vector2i(3, y))
	for x in 8:
		if x != 3: exp_rook.append(Vector2i(x, 8))
	check(same_tiles(P.attack_tiles(P.ROOK, c, 99, SIZE, empty), exp_rook), "Rook (unlimited range) attacks whole rank+file (18 tiles)")
	var r5 := P.attack_tiles(P.ROOK, c, 5, SIZE, empty)
	check(r5.size() == 17 and r5.has(Vector2i(3, 1)) and not r5.has(Vector2i(3, 0)), "Rook L5 range is 7 squares")
	# Rook level 1: range 3
	var exp_r1 := [Vector2i(3, 7), Vector2i(3, 6), Vector2i(3, 5), Vector2i(3, 9), Vector2i(3, 10), Vector2i(3, 11),
		Vector2i(2, 8), Vector2i(1, 8), Vector2i(0, 8), Vector2i(4, 8), Vector2i(5, 8), Vector2i(6, 8)]
	check(same_tiles(P.attack_tiles(P.ROOK, c, 1, SIZE, empty), exp_r1), "Rook L1 limited to 3 squares")
	# Rook blocked by own pieces
	var occ := {Vector2i(3, 6): true, Vector2i(5, 8): true}
	var blocked := P.attack_tiles(P.ROOK, c, 5, SIZE, occ)
	check(blocked.has(Vector2i(3, 7)) and not blocked.has(Vector2i(3, 6)) and not blocked.has(Vector2i(3, 5)), "Rook line of sight blocked vertically")
	check(blocked.has(Vector2i(4, 8)) and not blocked.has(Vector2i(5, 8)) and not blocked.has(Vector2i(6, 8)), "Rook line of sight blocked horizontally")
	# Bishop
	var exp_b := [Vector2i(2, 7), Vector2i(1, 6), Vector2i(0, 5), Vector2i(4, 7), Vector2i(5, 6), Vector2i(6, 5), Vector2i(7, 4),
		Vector2i(2, 9), Vector2i(1, 10), Vector2i(0, 11), Vector2i(4, 9), Vector2i(5, 10), Vector2i(6, 11)]
	check(same_tiles(P.attack_tiles(P.BISHOP, c, 5, SIZE, empty), exp_b), "Bishop L5 diagonals (13 tiles)")
	var b_occ := P.attack_tiles(P.BISHOP, c, 5, SIZE, {Vector2i(5, 6): true})
	check(b_occ.has(Vector2i(4, 7)) and not b_occ.has(Vector2i(5, 6)) and not b_occ.has(Vector2i(7, 4)), "Bishop blocked by piece")
	# Queen = rook + bishop
	check(same_tiles(P.attack_tiles(P.QUEEN, c, 99, SIZE, empty), exp_rook + exp_b), "Queen = Rook + Bishop (31 tiles)")
	# Knight
	var exp_n := [Vector2i(1, 7), Vector2i(1, 9), Vector2i(5, 7), Vector2i(5, 9), Vector2i(2, 6), Vector2i(4, 6), Vector2i(2, 10), Vector2i(4, 10)]
	check(same_tiles(P.attack_tiles(P.KNIGHT, c, 1, SIZE, empty), exp_n), "Knight L-jumps (8 tiles)")
	check(same_tiles(P.attack_tiles(P.KNIGHT, Vector2i(0, 11), 1, SIZE, empty), [Vector2i(1, 9), Vector2i(2, 10)]), "Knight clipped at corner")
	var n_occ := {}
	for d in P.ORTHO + P.DIAG: n_occ[c + d] = true
	check(same_tiles(P.attack_tiles(P.KNIGHT, c, 1, SIZE, n_occ), exp_n), "Knight jumps over pieces")
	# King
	var exp_k := []
	for d in P.ORTHO + P.DIAG: exp_k.append(c + d)
	check(same_tiles(P.attack_tiles(P.KING, c, 1, SIZE, empty), exp_k), "King one square around (8 tiles)")
	check(same_tiles(P.attack_tiles(P.KING, Vector2i(0, 11), 1, SIZE, empty), [Vector2i(0, 10), Vector2i(1, 10), Vector2i(1, 11)]), "King clipped at corner")
	# Pawn captures diagonally forward (toward the mobs = up)
	check(same_tiles(P.attack_tiles(P.PAWN, c, 1, SIZE, empty), [Vector2i(2, 7), Vector2i(4, 7)]), "Pawn diagonal-forward captures")
	check(same_tiles(P.attack_tiles(P.PAWN, Vector2i(0, 5), 3, SIZE, empty), [Vector2i(1, 4)]), "Pawn clipped at edge")
	check(P.attack_tiles(P.WALL, c, 1, SIZE, empty).is_empty(), "Wall never attacks")


func test_mob_types() -> void:
	var g = new_game()
	g.wave = 1
	var grunt = g.spawn_mob(Vector2i(0, 0), -1.0, M.GRUNT)
	var runner = g.spawn_mob(Vector2i(1, 0), -1.0, M.RUNNER)
	var brute = g.spawn_mob(Vector2i(2, 0), -1.0, M.BRUTE)
	check(runner.speed > grunt.speed and runner.hp < grunt.hp, "Runner faster and lower HP than Grunt")
	check(brute.hp > grunt.hp * 1.5 and brute.speed < grunt.speed, "Brute tankier and slower than Grunt")
	check(brute.reward > grunt.reward, "Brute pays more gold than Grunt")
	var mix := M.wave_spawn_list(1)
	check(mix.size() == 6, "Wave 1 has 6 mobs in spawn list")
	check(mix.count(M.GRUNT) == 6, "Wave 1 spawn table is all Grunts")
	var g2 = new_game()
	g2.place(P.KING, Vector2i(3, 11))
	g2.start_wave()
	check(g2.spawn_types.size() == 6, "start_wave uses wave table spawn_types")
	g2.phase = g2.Phase.BETWEEN
	g2.spawn_left = 0
	g2.mobs.clear()
	g2.start_wave()
	check(g2.wave == 2 and g2.spawn_types.has(M.RUNNER), "Wave 2 spawn mix includes Runner")
	g2.free()
	var w5 := M.wave_spawn_list(5)
	check(w5.has(M.BRUTE) and w5.has(M.SAPPER), "Wave 5 includes Brute and Sapper")
	g.free()
	# Sapper prefers walls over other pieces when King not adjacent
	g = new_game()
	g.place(P.KING, Vector2i(3, 11))
	_force_wall(g, Vector2i(3, 9))
	var wall0 = g.pieces[Vector2i(3, 9)]
	wall0.max_hp = 5000.0
	wall0.hp = 5000.0
	var sap = g.spawn_mob(Vector2i(3, 8), 100000.0, M.SAPPER)
	sap.speed = 0.0
	sap.damage = 5.0
	run_for(g, 2.5)
	var wall = g.get_piece(Vector2i(3, 9))
	check(wall != null and wall.hp < wall.max_hp, "Sapper attacks adjacent wall preferentially")
	g.free()


func test_twenty_waves() -> void:
	var g = new_game()
	check(g.MAX_WAVES == 20, "Campaign length is 20 waves")
	check(M.WAVE_DEFS.size() == 20, "Wave table has 20 entries")
	check(M.wave_mob_count(1) == 6 and M.wave_mob_count(20) == 18, "Wave 1 has 6 mobs, wave 20 has 18")
	check(M.wave_spawn_list(5).has(M.BRUTE) and M.wave_spawn_list(5).has(M.SAPPER), "Wave 5 table includes Brute and Sapper")
	g.wave = 20
	g.phase = g.Phase.WAVE
	g.spawn_left = 0
	g.mobs.clear()
	g.step(0.05)
	check(g.phase == g.Phase.VICTORY, "Victory triggers exactly after wave 20 is cleared")
	check(g.last_message.contains("VICTORY"), "Victory message shown")
	g.reset()
	check(g.wave == 0 and g.phase == g.Phase.SETUP, "Restart after victory resets campaign")
	g.free()


func test_difficulty_curve() -> void:
	for w in 9:
		var h0: float = M.mob_stats(M.GRUNT, w).hp
		var h1: float = M.mob_stats(M.GRUNT, w + 1).hp
		var jump: float = (h1 - h0) / h0
		check(jump < 0.12, "Wave %d->%d Grunt HP rise %.1f%% stays gentle" % [w, w + 1, jump * 100.0])
	var c5: int = M.wave_mob_count(5)
	var c6: int = M.wave_mob_count(6)
	check(c6 - c5 <= 1, "Mob count after wave 5 rises by at most 1 (%d -> %d)" % [c5, c6])
	check(M.hp_scale_for_wave(6) / M.hp_scale_for_wave(5) < 1.12, "No HP cliff between waves 5 and 6")


func test_placement() -> void:
	var g = new_game()
	check(g.phase == g.Phase.SETUP and g.gold == 200, "Starts in setup with 200 gold")
	check(not g.start_wave(), "Cannot start wave without King")
	check(not g.place(P.KING, Vector2i(3, 1)), "Cannot build in enemy zone")
	check(g.place(P.KING, Vector2i(3, 11)), "Place King")
	check(not g.place(P.KING, Vector2i(4, 11)), "Second King rejected (unique)")
	check(not g.place(P.PAWN, Vector2i(3, 11)), "Occupied tile rejected")
	check(g.place(P.ROOK, Vector2i(3, 8)) and g.gold == 140, "Place Rook (-60 gold)")
	check(g.place(P.WALL, Vector2i(2, 6)) and g.gold == 130, "Place Wall (-10 gold)")
	check(g.place(P.PAWN, Vector2i(5, 7)) and g.gold == 110, "Place Pawn (-20 gold)")
	g.gold = 5
	check(not g.place(P.QUEEN, Vector2i(6, 9)), "Not enough gold rejected")
	g.gold = 110
	check(g.sell(Vector2i(3, 11)) and not g.has_king(), "King can be removed during setup")
	check(g.place(P.KING, Vector2i(6, 10)) and g.king_cell == Vector2i(6, 10), "King re-placed elsewhere (free arrangement)")
	check(g.sell(Vector2i(3, 8)) and g.gold == 140, "Sell Rook refunds 50%")
	check(g.start_wave() and g.phase == g.Phase.WAVE and g.wave == 1, "Start wave 1")
	check(not g.sell(Vector2i(6, 10)), "King locked once waves start")
	check(g.place(P.BISHOP, Vector2i(0, 9)), "Can place towers during a wave")
	g.free()


func test_tower_adjacency() -> void:
	var g = new_game()
	g.place(P.KING, Vector2i(3, 11))
	g.place(P.ROOK, Vector2i(3, 8))
	check(not g.place(P.PAWN, Vector2i(3, 7)), "Cannot place tower adjacent to Rook")
	check(not g.place(P.WALL, Vector2i(4, 8)), "Cannot place wall adjacent to tower")
	check(g.place(P.WALL, Vector2i(3, 6)), "May place wall two tiles from tower")
	check(g.place(P.WALL, Vector2i(2, 6)) and g.place(P.WALL, Vector2i(1, 6)), "Walls may touch other walls")
	check(g.can_place(P.BISHOP, Vector2i(4, 8)) != "", "can_place reports adjacency violation")
	g.free()


func _force_wall(g, c: Vector2i) -> void:
	var p = g.Piece.new()
	p.type = P.WALL
	p.cell = c
	p.max_hp = P.max_hp(P.WALL, 1)
	p.hp = p.max_hp
	p.spent = P.COST[P.WALL]
	g.pieces[c] = p
	g._board_changed()


func test_path_validation() -> void:
	var g = new_game()
	g.place(P.KING, Vector2i(3, 11))
	g.place(P.ROOK, Vector2i(1, 9))
	check(not g.place(P.WALL, Vector2i(3, 10)), "Cannot seal King with a wall")
	check(g.place(P.WALL, Vector2i(0, 6)), "Wall allowed when a path remains")
	g.sell(Vector2i(3, 11))
	for x in 8:
		_force_wall(g, Vector2i(x, 5))
	check(not g.place(P.KING, Vector2i(3, 11)), "King placement rejected when spawn is fully cut off")
	g.free()


func test_wave_and_movement() -> void:
	var g = new_game()
	g.place(P.KING, Vector2i(3, 11))
	g.start_wave()
	run_for(g, 1.0)
	var expected: int = M.wave_mob_count(1)
	check(g.mobs.size() >= 1 and g.spawn_left == expected - g.mobs.size(), "Mobs spawn at top during wave")
	var m = g.mobs[0]
	var y0: float = m.pos.y
	run_for(g, 2.0)
	check(m.pos.y > y0 + 1.0, "Mob moves downward toward the King (y %.2f -> %.2f)" % [y0, m.pos.y])
	g.free()

	# Pathfinding around a wall line with a gap at column 7
	g = new_game()
	g.place(P.KING, Vector2i(3, 11))
	for x in 7:
		g.place(P.WALL, Vector2i(x, 6))
	var mob = g.spawn_mob(Vector2i(0, 0), 100000.0)
	var visited := {}
	run_for(g, 40.0, 0.05, func(): visited[mob.cell] = true; return mob.cell.y >= 8)
	check(visited.has(Vector2i(7, 6)), "Mob paths around walls through the gap (7,6)")
	check(g.pieces.size() >= 7, "No wall had to be destroyed when a gap exists")
	g.free()

	# Fully walled: mob must smash a wall instead of soft-locking
	g = new_game()
	g.place(P.KING, Vector2i(3, 11))
	for x in 8:
		_force_wall(g, Vector2i(x, 6))
	mob = g.spawn_mob(Vector2i(3, 0), 100000.0)
	run_for(g, 60.0, 0.05, func(): return mob.cell.y >= 7)
	var walls := 0
	for c in g.pieces:
		if g.pieces[c].type == P.WALL: walls += 1
	check(walls < 8 and mob.cell.y >= 7, "Fully blocked path: mob breaks through a wall (walls left %d)" % walls)
	g.free()


func mob_claim_count(g, c: Vector2i) -> int:
	var n := 0
	for m in g.mobs:
		if m.alive and (m.cell == c or m.target == c):
			n += 1
	return n


func test_mob_tile_occupation() -> void:
	var g = new_game()
	g.place(P.KING, Vector2i(3, 11))
	for x in 8:
		g.spawn_mob(Vector2i(x, 0), 100000.0).speed = 0.0
	g.start_wave()
	var left0: int = g.spawn_left
	run_for(g, 3.0)
	check(g.spawn_left == left0 and g.mobs.size() == 8, "Spawn waits while every spawn tile is busy")
	g.mobs[0].speed = 1.0 + 0.05 * g.wave
	run_for(g, 6.0)
	check(g.spawn_left < left0 and g.mobs.size() > 8, "Spawn resumes once a spawn tile opens")
	for m in g.mobs:
		if m.alive:
			check(mob_claim_count(g, m.cell) == 1, "At most one mob claims cell %s" % m.cell)
	g.free()

	g = new_game()
	g.place(P.KING, Vector2i(3, 11))
	var a = g.spawn_mob(Vector2i(3, 0), 100000.0)
	var b = g.spawn_mob(Vector2i(3, 1), 100000.0)
	a.speed = 0.4
	b.speed = 0.4
	run_for(g, 12.0, 0.05)
	var stacked := false
	for c in [Vector2i(3, 2), Vector2i(3, 3), Vector2i(3, 4), Vector2i(3, 5), Vector2i(3, 6)]:
		if mob_claim_count(g, c) > 1:
			stacked = true
	check(not stacked, "Single-file column: mobs do not share a tile")
	check(a.cell.y >= 2 and b.cell.y >= 1, "Trailing mob queues behind leader (y %d, %d)" % [a.cell.y, b.cell.y])
	g.free()

	g = new_game()
	g.place(P.KING, Vector2i(3, 11))
	g.place(P.ROOK, Vector2i(3, 7))
	g.start_wave()
	run_for(g, 240.0, 0.05, func(): return g.spawn_left == 0 and g.mobs.is_empty())
	check(g.phase == g.Phase.BETWEEN, "Wave clears without spawn deadlock")
	check(g.kills == 6, "All wave-1 mobs killed while respecting tile caps")
	g.free()


func test_mob_attacks() -> void:
	var g = new_game()
	g.place(P.KING, Vector2i(3, 11))
	g.place(P.WALL, Vector2i(2, 9))
	var m = g.spawn_mob(Vector2i(3, 9), 100000.0)
	m.speed = 0.0
	var wall = g.pieces[Vector2i(2, 9)]
	run_for(g, 3.0)
	check(wall.hp < wall.max_hp, "Mob attacks adjacent wall (hp %.0f/%.0f)" % [wall.hp, wall.max_hp])
	g.free()

	g = new_game()
	g.place(P.KING, Vector2i(3, 11))
	var king = g.pieces[Vector2i(3, 11)]
	m = g.spawn_mob(Vector2i(3, 6), 100000.0)
	run_for(g, 8.0)
	check(king.hp < king.max_hp, "Mob targets and attacks the King (hp %.0f)" % king.hp)
	run_for(g, 150.0, 0.05, func(): return g.phase == g.Phase.GAME_OVER)
	check(g.phase == g.Phase.GAME_OVER and not g.has_king(), "King destroyed -> GAME OVER")
	check(not g.place(P.PAWN, Vector2i(1, 9)), "No building after game over")
	g.reset()
	check(g.phase == g.Phase.SETUP and g.pieces.is_empty() and g.gold == 200, "Restart resets the game")
	g.free()


func test_castling() -> void:
	var g = new_game()
	g.place(P.KING, Vector2i(3, 11))
	g.place(P.ROOK, Vector2i(1, 11))
	check(g.castle_rooks_eligible().has(Vector2i(1, 11)), "Rook two tiles left on King row is eligible")
	g.place(P.ROOK, Vector2i(6, 8))
	check(not g.castle_rooks_eligible().has(Vector2i(6, 8)), "Rook not on King row is ineligible")
	g.selected = Vector2i(1, 11)
	check(g.perform_castle(Vector2i(1, 11)) and g.king_cell == Vector2i(1, 11), "Castling swaps King to Rook tile")
	check(g.pieces[Vector2i(1, 11)].type == P.KING and g.pieces[Vector2i(3, 11)].type == P.ROOK, "Pieces swapped positions")
	check(g.castling_used and g.castle_rooks_eligible().is_empty(), "Only one castle per match")
	check(not g.perform_castle(Vector2i(3, 11)), "Second castle rejected")
	g.reset()
	check(not g.castling_used and g.pieces.is_empty(), "Restart resets castling flag")
	g.free()

	g = new_game()
	g.place(P.KING, Vector2i(3, 11))
	g.place(P.ROOK, Vector2i(7, 11))
	check(g.castle_rooks_eligible().has(Vector2i(7, 11)), "Rook four tiles away is eligible")
	g.place(P.ROOK, Vector2i(0, 8))
	check(not g.castle_rooks_eligible().has(Vector2i(0, 8)), "Rook on wrong row is ineligible")
	g.sell(Vector2i(7, 11))
	g.sell(Vector2i(3, 11))
	g.place(P.KING, Vector2i(0, 11))
	g.place(P.ROOK, Vector2i(5, 11))
	check(g.castle_rooks_eligible().is_empty(), "Rook five tiles away is ineligible")
	g.free()

	g = new_game()
	g.place(P.KING, Vector2i(3, 11))
	g.place(P.ROOK, Vector2i(6, 11))
	var mob = g.spawn_mob(Vector2i(3, 11), 100.0)
	mob.speed = 0.0
	check(g.can_castle_to(Vector2i(6, 11)) != "", "Cannot castle with mob on King tile")
	g.free()

	g = new_game()
	g.place(P.KING, Vector2i(3, 11))
	g.place(P.ROOK, Vector2i(6, 11))
	g.place(P.ROOK, Vector2i(1, 11))
	g.place(P.ROOK, Vector2i(7, 11))
	_force_wall(g, Vector2i(6, 10))
	_force_wall(g, Vector2i(7, 10))
	for y in range(3, 11):
		_force_wall(g, Vector2i(6, y))
	check(g.can_castle_to(Vector2i(7, 11)) != "", "Castle rejected when swap leaves no path to King")
	g.selected = Vector2i(3, 11)
	check(g.try_castle() and g.king_cell == Vector2i(1, 11), "try_castle from King picks nearest eligible rook")
	g.free()

	g = new_game()
	g.place(P.KING, Vector2i(3, 11))
	g.place(P.ROOK, Vector2i(6, 11))
	g.start_wave()
	g.selected = Vector2i(6, 11)
	check(g.perform_castle(Vector2i(6, 11)) and g._paths_exist_to_goal(g.king_cell, []), "Post-castle path to King remains")
	g.free()


func test_promotion() -> void:
	var g = new_game()
	g.place(P.KING, Vector2i(3, 11))
	var m = g.spawn_mob(Vector2i(5, 10), -1.0, M.GRUNT)
	m.speed = 4.0
	run_for(g, 2.0, 0.05, func(): return m.mob_type == M.PROMOTED)
	check(m.promoted and m.mob_type == M.PROMOTED and m.hp == m.max_hp, "Mob promotes on bottom row with full HP")
	check(g.last_message.contains("promoted"), "Promotion HUD message")
	check(M.mob_stats(M.PROMOTED, 1).speed > M.mob_stats(M.GRUNT, 1).speed, "Promoted mob is faster than Grunt")
	check(M.mob_stats(M.PROMOTED, 1).hp > M.mob_stats(M.RUNNER, 1).hp, "Promoted mob is tankier than Runner")
	run_for(g, 4.0, 0.05)
	check(m.alive and m.mob_type == M.PROMOTED, "Promoted mob promotes at most once")
	var king = g.pieces[g.king_cell]
	var hp0: float = king.hp
	run_for(g, 30.0, 0.05, func(): return king.hp < hp0 - 1.0 or g.phase == g.Phase.GAME_OVER)
	check(m.cell.y == g.ROWS - 1 or m.cell == g.king_cell or king.hp < hp0, "Promoted mob leaves bottom row or pressures King (not stuck)")
	g.free()

	g = new_game()
	g.place(P.KING, Vector2i(3, 8))
	m = g.spawn_mob(Vector2i(7, 11), 50.0, M.GRUNT)
	m.cell = Vector2i(7, 11)
	m.target = Vector2i(7, 11)
	m.pos = Vector2(7, 11)
	var khp: float = g.pieces[g.king_cell].hp
	check(g._try_promote(m) and g.pieces[g.king_cell].hp == khp, "Promotion heals mob without dealing King damage")
	check(m.mob_type == M.PROMOTED and m.hp == m.max_hp, "Promoted mob receives full HP")
	g.free()


func test_combat_gold_upgrade() -> void:
	var g = new_game()
	g.place(P.KING, Vector2i(3, 11))
	g.place(P.ROOK, Vector2i(3, 8))
	var rook = g.pieces[Vector2i(3, 8)]
	rook.cd = 0.0
	# mob NOT on the rook's lines is not hit
	var off = g.spawn_mob(Vector2i(1, 5), 50.0)
	off.speed = 0.0
	g.step(0.01)
	check(off.hp == 50.0, "Tower ignores mobs outside its chess pattern")
	off.alive = false
	g.step(0.01)
	# kill + gold
	var m = g.spawn_mob(Vector2i(3, 6), 1.0)
	m.speed = 0.0
	var gold0: int = g.gold
	var reward: int = m.reward
	rook.cd = 0.0
	g.step(0.01)
	check(not m.alive and g.kills == 1, "Rook kills mob on its file")
	check(g.gold == gold0 + reward and g.gold_from_kills == reward, "Kill grants %d gold" % reward)
	# damage before / after upgrade
	var tough = g.spawn_mob(Vector2i(3, 6), 1000.0)
	tough.speed = 0.0
	rook.cd = 0.0
	g.step(0.01)
	var d1: float = 1000.0 - tough.hp
	var tiles_l1: int = g.attack_tiles_for(Vector2i(3, 8)).size()
	var gold1: int = g.gold
	var cost := P.upgrade_cost(P.ROOK, 1)
	check(g.upgrade(Vector2i(3, 8)) and rook.level == 2 and g.gold == gold1 - cost, "Upgrade Rook to L2 for %d gold" % cost)
	rook.cd = 0.0
	var hp_before: float = tough.hp
	g.step(0.01)
	var d2: float = hp_before - tough.hp
	check(d2 > d1 and is_equal_approx(d2, P.damage(P.ROOK, 2)), "Upgrade raises damage (%.1f -> %.1f)" % [d1, d2])
	check(g.attack_tiles_for(Vector2i(3, 8)).size() > tiles_l1, "Upgrade extends slider range (%d -> %d tiles)" % [tiles_l1, g.attack_tiles_for(Vector2i(3, 8)).size()])
	g.gold = 10000
	for i in 10: g.upgrade(Vector2i(3, 8))
	check(rook.level == P.MAX_LEVEL, "Upgrades cap at level %d" % P.MAX_LEVEL)
	check(g.place(P.WALL, Vector2i(1, 7)), "Place wall for upgrade test")
	var w = g.pieces[Vector2i(1, 7)]
	var w_hp0: float = w.max_hp
	g.gold = 500
	check(g.upgrade(Vector2i(1, 7)) and w.level == 2 and w.max_hp > w_hp0, "Wall upgrade raises max HP")
	# each tower type hits only in-pattern: bishop vs orthogonal / diagonal mob
	var g2 = new_game()
	g2.place(P.KING, Vector2i(0, 11))
	g2.place(P.BISHOP, Vector2i(4, 8))
	var b = g2.pieces[Vector2i(4, 8)]
	var ortho = g2.spawn_mob(Vector2i(4, 6), 50.0); ortho.speed = 0.0
	var diag = g2.spawn_mob(Vector2i(6, 6), 50.0); diag.speed = 0.0
	b.cd = 0.0
	g2.step(0.01)
	check(ortho.hp == 50.0 and diag.hp < 50.0, "Bishop hits diagonal mob only")
	var g3 = new_game()
	g3.place(P.KING, Vector2i(0, 11))
	g3.place(P.KNIGHT, Vector2i(4, 8))
	var kn = g3.pieces[Vector2i(4, 8)]
	var near = g3.spawn_mob(Vector2i(4, 7), 50.0); near.speed = 0.0
	var lj = g3.spawn_mob(Vector2i(5, 6), 50.0); lj.speed = 0.0
	kn.cd = 0.0
	g3.step(0.01)
	check(near.hp == 50.0 and lj.hp < 50.0, "Knight hits L-jump tile, not adjacent tile")
	var g4 = new_game()
	g4.place(P.KING, Vector2i(0, 11))
	g4.place(P.PAWN, Vector2i(4, 8))
	var pw = g4.pieces[Vector2i(4, 8)]
	var fwd = g4.spawn_mob(Vector2i(4, 7), 50.0); fwd.speed = 0.0
	var cap = g4.spawn_mob(Vector2i(3, 7), 50.0); cap.speed = 0.0
	var back = g4.spawn_mob(Vector2i(5, 9), 50.0); back.speed = 0.0
	pw.cd = 0.0
	g4.step(0.01)
	check(fwd.hp == 50.0 and back.hp == 50.0 and cap.hp < 50.0, "Pawn hits forward-diagonal only")
	g.free(); g2.free(); g3.free(); g4.free()


func test_full_wave() -> void:
	var g = new_game()
	g.place(P.KING, Vector2i(3, 11))
	g.place(P.ROOK, Vector2i(1, 9))
	g.place(P.QUEEN, Vector2i(5, 9))
	g.place(P.PAWN, Vector2i(7, 8))
	check(g.gold == 0, "Spent all starting gold on a defence")
	for w in 3:
		check(g.start_wave(), "Start wave %d" % (w + 1))
		var kills0: int = g.kills
		run_for(g, 180.0, 0.05, func(): return g.phase != g.Phase.WAVE)
		check(g.phase == g.Phase.BETWEEN, "Wave %d cleared (phase=%s, King hp %.0f)" % [g.wave, g.PHASE_NAMES[g.phase], g.pieces[g.king_cell].hp if g.has_king() else 0.0])
		var n: int = M.wave_mob_count(g.wave)
		check(g.kills - kills0 == n, "All %d mobs of wave %d killed" % [n, g.wave])
		# spend gold between waves: round-robin upgrades, cheapest first
		var spent := true
		while spent:
			spent = false
			for cell in [Vector2i(7, 8), Vector2i(1, 9), Vector2i(5, 9)]:
				if g.upgrade(cell): spent = true
	print("        after 3 waves: gold=%d kills=%d gold_from_kills=%d levels P%d R%d Q%d" % [g.gold, g.kills, g.gold_from_kills, g.pieces[Vector2i(7, 8)].level, g.pieces[Vector2i(1, 9)].level, g.pieces[Vector2i(5, 9)].level])
	g.free()


func test_scene() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	for i in 3: await process_frame
	var g = scene.get_node("Game")
	var ui = scene.get_node("UI")
	check(g != null and ui.build_buttons.size() == 7 and ui.btn_start != null, "Main scene loads with HUD (7 build buttons)")
	# Simulate a real left click on tile (3,11) with King selected
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = g.cell_center(Vector2(3, 11))
	g._unhandled_input(ev)
	check(g.has_king() and g.king_cell == Vector2i(3, 11), "Mouse click places King")
	check(g.build_type == P.PAWN, "Build palette advances to Pawn after King")
	ui.build_buttons[P.ROOK].button_pressed = true
	ui.build_buttons[P.ROOK].pressed.emit()
	ev.position = g.cell_center(Vector2(3, 8))
	g._unhandled_input(ev)
	check(g.pieces.has(Vector2i(3, 8)) and g.pieces[Vector2i(3, 8)].type == P.ROOK, "UI button + click places Rook")
	g._unhandled_input(ev)
	check(g.selected == Vector2i(3, 8), "Clicking a piece selects it")
	ui.btn_upgrade.pressed.emit()
	check(g.pieces[Vector2i(3, 8)].level == 2, "Upgrade button upgrades selection")
	ui.btn_start.pressed.emit()
	check(g.phase == g.Phase.WAVE, "Start Wave button starts wave")
	for i in 30: await process_frame
	check(true, "Scene ran 30 frames with _process/_draw")
	scene.queue_free()
	await process_frame
