extends SceneTree
## Headless test suite.  Run:  godot --headless --path . --script res://tests/test_runner.gd
## Exit code 0 = all passed.

const P := preload("res://scripts/pieces.gd")
const M := preload("res://scripts/mobs.gd")
const GameScript := preload("res://scripts/game.gd")
const SC := preload("res://scripts/scoring.gd")
const HS := preload("res://scripts/highscores.gd")
const LS := preload("res://scripts/layouts.gd")
const DA := preload("res://scripts/draw_art.gd")
const CFG := preload("res://scripts/config.gd")
const SIZE := Vector2i(8, 12)

var passed := 0
var failed := 0


func _initialize() -> void:
	CFG.ensure_loaded()
	_clear_hs_test_file()
	HS.set_save_path(_hs_test_path())
	LS.set_save_path(_ls_test_path())
	_clear_ls_test_file()
	_clear_user_configs()
	await _run()
	CFG.reload_defaults()
	HS.reset_save_path()
	_clear_hs_test_file()
	_clear_ls_test_file()
	LS.reset_save_path()
	_clear_user_configs()
	Engine.time_scale = 1.0


func _user_config_dir() -> String:
	return "user://configs"


func _clear_user_configs() -> void:
	var dir := DirAccess.open(_user_config_dir())
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.begins_with("test_"):
			dir.remove(name)
		name = dir.get_next()
	dir.list_dir_end()


func _ls_test_path() -> String:
	return "user://test_layouts.json"


func _clear_ls_test_file() -> void:
	if FileAccess.file_exists(_ls_test_path()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_ls_test_path()))


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
	print("== Score & leaderboard ==")
	test_scoring_and_highscores()
	print("== Phase A: HUD stats, order, costs ==")
	test_hud_stats_and_order()
	print("== Phase A: game speed ==")
	test_game_speed()
	print("== Phase A: layouts ==")
	test_layouts()
	print("== Phase A: upgrade preview ==")
	test_upgrade_preview()
	print("== Phase A: synergy ==")
	test_synergy()
	print("== Main scene + UI + mouse input ==")
	await test_scene()
	print("== Responsive layout ==")
	await test_responsive_layout()
	print("== Piece options dialog ==")
	await test_piece_options_dialog()
	print("== Phase A: UI labels, keys, layouts ==")
	await test_phase_a_ui()
	print("== Phase B: config JSON loader ==")
	test_config_loader()
	print("== Phase B: config UI apply ==")
	await test_config_ui()
	print("== Settings window ==")
	await test_settings_window()
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
	check(g.place(P.WALL, Vector2i(2, 6)) and g.gold == 40, "Place Wall (-100 gold)")
	check(g.place(P.PAWN, Vector2i(5, 7)) and g.gold == 20, "Place Pawn (-20 gold)")
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
	g.gold = 1000
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
	g.gold = 1000
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
	check(g.score >= 0 and g.match_result == "loss", "Game over sets match result and score")
	check(not g.place(P.PAWN, Vector2i(1, 9)), "No building after game over")
	g.reset()
	check(g.phase == g.Phase.SETUP and g.pieces.is_empty() and g.gold == 200 and g.score == 0, "Restart resets the game")
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


func _hs_test_path() -> String:
	return "user://_test_highscores_runner.json"


func _clear_hs_test_file() -> void:
	var p := _hs_test_path()
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func test_scoring_and_highscores() -> void:
	check(SC.kill_points(M.GRUNT, 1) == 11, "Grunt kill score wave 1")
	check(SC.kill_points(M.PROMOTED, 3) > SC.kill_points(M.GRUNT, 3), "Promoted worth more than Grunt")
	check(SC.kill_points(M.BRUTE, 2) > SC.kill_points(M.RUNNER, 2), "Brute worth more than Runner")
	check(SC.wave_clear_points(5) == 50, "Wave 5 clear score bonus")
	check(SC.final_score(80, 50) == 130, "Final score sums kill and wave parts")

	var g = new_game()
	g.place(P.KING, Vector2i(3, 11))
	g.place(P.ROOK, Vector2i(3, 8))
	var rook = g.pieces[Vector2i(3, 8)]
	rook.cd = 0.0
	g.wave = 2
	var brute = g.spawn_mob(Vector2i(3, 6), 1.0, M.BRUTE)
	brute.speed = 0.0
	var pts: int = SC.kill_points(M.BRUTE, 2)
	g.step(0.01)
	check(g.score_from_kills == pts and g.score == pts, "Kill adds mob-type score to match")
	g.free()

	g = new_game()
	g.place(P.KING, Vector2i(3, 11))
	g.wave = 1
	g.phase = g.Phase.WAVE
	g.spawn_left = 0
	g.mobs.clear()
	var wpts := SC.wave_clear_points(1)
	g.step(0.05)
	check(g.score_from_waves == wpts and g.score == wpts, "Wave clear adds score bonus")
	g.free()

	g = new_game()
	g.place(P.KING, Vector2i(0, 11))
	var king = g.pieces[g.king_cell]
	king.hp = 0.01
	g.spawn_mob(Vector2i(0, 10), 100000.0).speed = 0.0
	run_for(g, 3.0)
	check(g.phase == g.Phase.GAME_OVER and g.match_result == "loss" and g._match_recorded, "Game over records loss")
	g.free()

	_clear_hs_test_file()
	HS.add_entry(50, 1, "loss", "2020-01-01 12:00:00")
	HS.add_entry(200, 10, "win", "2021-06-15 08:30:00")
	HS.add_entry(120, 4, "loss", "2022-03-03 18:45:00")
	var loaded := HS.load_entries()
	check(loaded.size() == 3 and int(loaded[0].score) == 200, "High scores sorted by score descending")
	var sorted := HS.sort_entries([
		{"score": 10, "waves": 1, "result": "loss", "datetime": "a"},
		{"score": 99, "waves": 2, "result": "win", "datetime": "b"},
		{"score": 50, "waves": 5, "result": "loss", "datetime": "c"},
	])
	check(int(sorted[0].score) == 99 and int(sorted[1].score) == 50, "sort_entries orders high to low")
	for i in 12:
		HS.add_entry(i * 10, 1, "loss", "t%d" % i)
	check(HS.load_entries().size() == 10, "Leaderboard trims to top 10")
	check(HS.save_entries([{"score": 1, "waves": 1, "result": "win", "datetime": "x"}]), "save_entries writes JSON")
	check(FileAccess.file_exists(_hs_test_path()), "High score file created at override path")


func _set_viewport_size(scene: Node, sz: Vector2i) -> void:
	DisplayServer.window_set_size(sz)
	var vp: Viewport = scene.get_viewport()
	vp.size = sz
	vp.size = sz


func test_responsive_layout() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	var g = scene.get_node("Game")
	var ui = scene.get_node("UI")
	for sz in [Vector2i(760, 704), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(640, 480)]:
		_set_viewport_size(scene, sz)
		for i in 2:
			await process_frame
		ui.apply_layout_now()
		await process_frame
		check(ui._controls_inside_viewport(), "HUD panel visible inside viewport at %s" % sz)
		var br: Rect2 = g.board_viewport_rect()
		var vp_r: Rect2 = scene.get_viewport().get_visible_rect()
		check(
			br.position.x >= -2.0 and br.position.y >= -2.0
			and br.end.x <= vp_r.size.x + 2.0 and br.end.y <= vp_r.size.y + 2.0,
			"Board rect inside viewport at %s" % sz
		)
		g.reset()
		g.build_type = P.KING
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		ev.position = g.cell_center(Vector2(3, 11))
		g._unhandled_input(ev)
		check(g.king_cell == Vector2i(3, 11), "Mouse-to-tile correct at viewport %s" % sz)
	scene.queue_free()
	await process_frame


func test_piece_options_dialog() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	var g = scene.get_node("Game")
	var ui = scene.get_node("UI")
	ui.apply_layout_now()
	await process_frame
	g.place(P.KING, Vector2i(3, 11))
	g.place(P.ROOK, Vector2i(3, 8))
	g.start_wave()
	var spawn0: int = g.spawn_left
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = g.cell_center(Vector2(3, 8))
	g._unhandled_input(ev)
	await process_frame
	check(ui.piece_options_open() and scene.get_tree().paused, "Dialog pauses during wave")
	for i in 20:
		await process_frame
	check(g.spawn_left == spawn0, "Spawning frozen while dialog open")
	g.gold = 500
	var lv0: int = g.pieces[Vector2i(3, 8)].level
	ui.btn_upgrade.pressed.emit()
	ui.btn_upgrade.pressed.emit()
	check(g.pieces[Vector2i(3, 8)].level == lv0 + 2, "Repeated dialog upgrades work")
	var key := InputEventKey.new()
	key.pressed = true
	key.echo = false
	key.keycode = KEY_U
	ui._unhandled_input(key)
	check(g.pieces[Vector2i(3, 8)].level == lv0 + 3, "Hotkey U upgrades via dialog")
	ui.close_piece_options()
	await process_frame
	check(not scene.get_tree().paused, "Game unpauses after close")
	for i in 10:
		await process_frame
	check(g.spawn_left < spawn0, "Spawning resumes after dialog closes")
	scene.queue_free()
	await process_frame


func test_scene() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	for i in 3: await process_frame
	var g = scene.get_node("Game")
	var ui = scene.get_node("UI")
	ui.apply_layout_now()
	await process_frame
	check(g != null and ui.build_buttons.size() == 7 and ui.btn_start != null and ui.btn_leaderboard != null, "Main scene loads with HUD (7 build buttons)")
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
	check(ui.piece_options_open() and scene.get_tree().paused, "Piece click opens paused dialog")
	ui.btn_upgrade.pressed.emit()
	check(g.pieces[Vector2i(3, 8)].level == 2, "Upgrade button upgrades selection")
	ui.close_piece_options()
	check(not ui.piece_options_open() and not scene.get_tree().paused, "Close dialog resumes game")
	ui.btn_start.pressed.emit()
	check(g.phase == g.Phase.WAVE, "Start Wave button starts wave")
	for i in 30: await process_frame
	check(true, "Scene ran 30 frames with _process/_draw")
	scene.queue_free()
	await process_frame


# ---------------------------------------------------------------- Phase A features

func test_hud_stats_and_order() -> void:
	check(DA.hp_text(36.2, 40.0) == "37/40" and DA.hp_text(-3.0, 40.0) == "0/40", "HP bar text is hp/max")
	check(P.level_text(2) == "Lv 2/5", "Level shown as current/max")
	check(P.ORDER[0] == P.PAWN and P.ORDER[1] == P.KNIGHT and P.ORDER[4] == P.QUEEN and P.ORDER[5] == P.KING,
		"Piece order reversed: Pawn first, Queen/King last")
	check(P.ORDER[6] == P.WALL and P.ORDER.size() == 7, "Wall stays on key 7")
	check(P.COST[P.WALL] == 100, "Wall costs 100g")
	var g = new_game()
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_1
	g._unhandled_input(key)
	check(g.build_type == P.PAWN, "Key 1 selects Pawn")
	key.keycode = KEY_6
	g._unhandled_input(key)
	check(g.build_type == P.KING, "Key 6 selects King")
	g.free()


func test_game_speed() -> void:
	var g = new_game()
	check(g.game_speed() == 1.0 and g.speed_label() == "x1", "Speed starts at x1")
	var seen: Array = []
	for i in 5:
		seen.append(g.cycle_speed())
	check(seen == [2.0, 3.0, 5.0, 10.0, 1.0], "Speed cycles x2 x3 x5 x10 x1")
	g.set_speed_index(4)
	check(Engine.time_scale == 10.0, "x10 sets Engine.time_scale")
	check(g.advance(10.0 * 0.1) >= 30, "x10 frame is split into small sub-steps")
	check(g.advance(1000.0) <= int(ceil(g.MAX_FRAME_DELTA * 10.0 / g.MAX_SIM_STEP)) + 1, "Huge frame delta is clamped")
	# Same outcome at x10 (big frames) as at x1 (small frames)
	var a = new_game()
	var b = new_game()
	for gg in [a, b]:
		gg.place(P.KING, Vector2i(3, 11))
		gg.place(P.ROOK, Vector2i(3, 7))
		gg.start_wave()
	b.set_speed_index(4)
	for i in 400:
		a.advance(1.0 / 60.0)
	for i in 40:
		b.advance(10.0 / 60.0)
	check(absi(a.kills - b.kills) <= 1 and b.phase != b.Phase.GAME_OVER, "x10 simulation matches x1 (kills %d vs %d)" % [a.kills, b.kills])
	g.set_speed_index(0)
	check(Engine.time_scale == 1.0, "Speed back to x1")
	for gg in [g, a, b]:
		gg.free()


func test_layouts() -> void:
	_clear_ls_test_file()
	var g = new_game()
	g.place(P.KING, Vector2i(3, 11))
	g.place(P.ROOK, Vector2i(3, 8))
	g.upgrade(Vector2i(3, 8))
	var lay: Array = g.export_layout()
	check(lay.size() == 2 and lay[0].type == "King", "Export layout (King first)")
	check(LS.save_layout("Layout 1", lay) and LS.names() == PackedStringArray(["Layout 1"]), "Save layout to user://")
	check(LS.next_name() == "Layout 2", "Next layout name")
	check(LS.get_default() == "" and LS.set_default("Layout 1") and LS.get_default() == "Layout 1", "Set default layout")
	check(not LS.set_default("missing"), "Unknown default rejected")
	var g2 = new_game()
	var n: int = g2.apply_layout(LS.default_pieces())
	check(n == 2 and g2.has_king() and g2.pieces[Vector2i(3, 8)].level == 2, "Default layout restores pieces and levels")
	check(g2.gold == g.gold, "Layout load charges the same gold")
	g2.start_wave()
	check(g2.apply_layout(lay) == 0, "Layouts only load during setup")
	check(LS.delete_layout("Layout 1") and LS.get_default() == "", "Delete clears default")
	g.free()
	g2.free()


func test_upgrade_preview() -> void:
	var g = new_game()
	g.place(P.KING, Vector2i(3, 11))
	g.place(P.ROOK, Vector2i(3, 7))
	var rows: Array = g.upgrade_preview(Vector2i(3, 7))
	var by := {}
	for r in rows:
		by[r.label] = r
	check(by.has("HP") and by.has("DMG") and by.has("Range") and by.has("Level"), "Preview has HP, DMG, Range rows")
	check(by.DMG.text == "DMG 7.0 -> 11.2 (+4.2)", "DMG row shows before -> after (+diff): " + by.DMG.text)
	check(by.Range.after - by.Range.before == 1.0, "Range +1 per level")
	var hp_after: float = by.HP.after
	g.upgrade(Vector2i(3, 7))
	check(absf(g.pieces[Vector2i(3, 7)].max_hp - hp_after) < 0.01, "Preview matches real upgrade")
	g.pieces[Vector2i(3, 7)].level = P.MAX_LEVEL
	check(g.upgrade_preview(Vector2i(3, 7)).is_empty(), "No preview at max level")
	g.free()


func test_synergy() -> void:
	var g = new_game()
	g.gold = 5000
	g.place(P.KING, Vector2i(3, 11))
	g.place(P.ROOK, Vector2i(1, 6))
	var base_dmg: float = g.effective_damage(P.ROOK, 1, Vector2i(1, 6))
	# Knight at (2,8) jumps to (1,6): buffs Rook attack speed.
	g.place(P.KNIGHT, Vector2i(2, 8))
	check(is_equal_approx(g.synergy_at(Vector2i(1, 6)).spd, 0.12), "Knight buffs attack speed of piece on its L-square")
	check(g.effective_cooldown(P.ROOK, Vector2i(1, 6)) < P.COOLDOWN[P.ROOK], "Buffed Rook fires faster")
	# Rook at (1,6) defends along its rank: Bishop at (4,6) gets +15% HP.
	g.place(P.BISHOP, Vector2i(4, 6))
	var bs = g.pieces[Vector2i(4, 6)]
	check(is_equal_approx(g.synergy_at(Vector2i(4, 6)).hp, 0.15), "Rook buffs HP of piece on its line")
	check(absf(bs.max_hp - P.max_hp(P.BISHOP, 1) * 1.15) < 0.01 and absf(bs.hp - bs.max_hp) < 0.01, "HP buff raises max HP")
	check(g.synergy_at(Vector2i(4, 6)).from.has(Vector2i(1, 6)), "Synergy sources tracked")
	check(g.synergy_text(Vector2i(4, 6)).begins_with("Synergy: +15% HP"), "Synergy line text for dialog")
	check(g.supports_count(Vector2i(1, 6)) >= 1, "Supporter counts its allies")
	check(g.synergy_at(Vector2i(6, 9)).from.is_empty(), "Empty squares get nothing")
	bs.hp = bs.max_hp * 0.5
	g.sell(Vector2i(1, 6))
	check(absf(bs.max_hp - P.max_hp(P.BISHOP, 1)) < 0.01 and absf(bs.hp / bs.max_hp - 0.5) < 0.01, "Losing a buff keeps HP ratio")
	# Pawn reaches 2 squares diagonally forward (tower gap rule), King has a radius-2 aura.
	var g2 = new_game()
	g2.gold = 5000
	g2.place(P.KING, Vector2i(3, 11))
	g2.place(P.KNIGHT, Vector2i(1, 9))
	check(is_equal_approx(g2.synergy_at(Vector2i(1, 9)).dmg, 0.08), "King aura buffs piece two squares away")
	check(g2.effective_damage(P.KNIGHT, 1, Vector2i(1, 9)) > P.damage(P.KNIGHT, 1), "Aura raises damage")
	g2.place(P.PAWN, Vector2i(3, 7))
	g2.place(P.BISHOP, Vector2i(5, 5))
	check(is_equal_approx(g2.synergy_at(Vector2i(5, 5)).dmg, 0.10), "Pawn buffs piece 2 squares diagonally forward")
	g2.place(P.BISHOP, Vector2i(7, 7))
	check(g2.synergy_at(Vector2i(5, 5)).range == 1 and g2.effective_range(1, Vector2i(5, 5)) == 4, "Bishop gives +1 range")
	var tiles: Dictionary = g2.attack_tiles_for(Vector2i(5, 5))
	check(tiles.has(Vector2i(1, 1)), "Range buff extends slider attack squares")
	g2.sell(Vector2i(3, 7))
	check(is_equal_approx(g2.synergy_at(Vector2i(5, 5)).dmg, 0.0), "Selling the supporter removes the buff")
	var cap = new_game()
	check(P.SYNERGY_CAP.dmg <= 0.5 and P.SYNERGY[P.WALL].is_empty(), "Synergy capped; walls give nothing")
	g.free()
	g2.free()
	cap.free()


func test_phase_a_ui() -> void:
	_clear_ls_test_file()
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var g = scene.get_node("Game")
	var ui = scene.get_node("UI")
	check(ui.build_buttons[P.PAWN].text.begins_with("[1] Pawn"), "Build button shows [1] Pawn")
	check(ui.build_buttons[P.WALL].text == "[7] Wall 100g", "Wall button shows key and 100g")
	check(ui.btn_speed.text == "Speed x1 [F]" and ui.btn_settings.text == "Settings [G]", "Speed/Settings HUD buttons show keys")
	check(ui.btn_restart.text.contains("["), "Restart button in Settings shows key")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_F
	ui._unhandled_input(key)
	check(g.game_speed() == 2.0 and ui.btn_speed.text == "Speed x2 [F]", "F cycles speed")
	g.set_speed_index(0)
	g.place(P.KING, Vector2i(3, 11))
	g.place(P.ROOK, Vector2i(3, 8))
	var name: String = ui.save_current_layout()
	check(name == "Layout 1" and ui.selected_layout_name() == "Layout 1", "Save layout from HUD")
	ui.toggle_default_layout()
	check(LS.get_default() == "Layout 1", "Set default from HUD")
	ui._on_restart()
	check(g.pieces.size() == 2 and g.has_king(), "Default layout auto-loads on restart")
	ui.open_piece_options(Vector2i(3, 8))
	check(ui.lbl_piece_title.text.contains("Lv 1/5"), "Dialog title shows Lv n/max")
	check(ui.lbl_piece_upgrade.text.contains("DMG 7.0 -> 11.2 (+4.2)"), "Dialog shows upgrade before/after diff")
	ui.close_piece_options()
	var skey := InputEventKey.new()
	skey.pressed = true
	skey.shift_pressed = true
	skey.keycode = KEY_S
	ui._unhandled_input(skey)
	check(g.pieces.has(Vector2i(3, 8)), "Shift+S saves instead of selling")
	check(LS.names().size() == 2, "Shift+S saved a second layout")
	scene.queue_free()
	await process_frame
	_clear_ls_test_file()


func test_config_loader() -> void:
	CFG.reload_defaults()
	check(FileAccess.file_exists(CFG.GAME_DATA_PATH), "Bundled game_data.json exists")
	check(FileAccess.file_exists(CFG.SETTINGS_PATH), "Bundled settings.json exists")
	check(CFG.game_data.get("schema", "") == "game_data", "game_data schema tag")
	check(CFG.settings.get("schema", "") == "settings", "settings schema tag")
	check(P.COST[P.PAWN] == 20 and P.COST[P.WALL] == 100 and P.COST[P.QUEEN] == 120, "Piece costs loaded from JSON")
	check(P.MAX_LEVEL == 5 and is_equal_approx(P.SYNERGY[P.KNIGHT].spd, 0.12), "Max level and synergy from JSON")
	check(M.WAVE_DEFS.size() == 20 and M.wave_mob_count(1) == 6, "Wave table loaded from JSON")
	check(SC.KILL_BASE[M.PROMOTED] == 32 and SC.wave_clear_points(1) == 26, "Scoring loaded from JSON")
	check(CFG.start_gold() == 200 and CFG.max_waves() == 20, "Match settings from JSON")
	check(CFG.speed_options().size() == 5 and float(CFG.speed_options()[4]) == 10.0, "Speed options from JSON")
	check(CFG.key_label("config") == "O" and CFG.key_label("speed") == "F" and CFG.key_label("settings") == "G",
		"Keybindings from JSON")
	var listed := CFG.list_configs()
	var paths: Array = []
	for e in listed:
		paths.append(e.path)
	check(paths.has(CFG.GAME_DATA_PATH) and paths.has(CFG.SETTINGS_PATH), "list_configs includes bundled files")
	# Invalid JSON falls back / rejects without corrupting tables.
	var bad_path := "user://configs/test_bad.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://configs"))
	var bf := FileAccess.open(bad_path, FileAccess.WRITE)
	bf.store_string("{not json")
	bf.close()
	var err := CFG.apply_file(bad_path)
	check(err != "", "Invalid JSON apply returns error")
	check(P.COST[P.PAWN] == 20, "Invalid apply leaves piece costs intact")
	# Valid user game_data override changes a value, then restore defaults.
	var custom := CFG.game_data.duplicate(true)
	custom.pieces.defs.pawn.cost = 33
	var good_path := "user://configs/test_pawn33.json"
	var gf := FileAccess.open(good_path, FileAccess.WRITE)
	gf.store_string(JSON.stringify(custom, "\t"))
	gf.close()
	check(CFG.apply_file(good_path) == "" and P.COST[P.PAWN] == 33, "User game_data apply changes pawn cost")
	var g = new_game()
	check(g.START_GOLD == 200 and g.gold == 200, "Game reads start gold from settings")
	check(g.SPEED_OPTIONS.size() == 5, "Game speed options from settings")
	g.free()
	# Settings override: starting gold.
	var st := CFG.settings.duplicate(true)
	st["match"]["start_gold"] = 350
	var st_path := "user://configs/test_gold350.json"
	var sf := FileAccess.open(st_path, FileAccess.WRITE)
	sf.store_string(JSON.stringify(st, "\t"))
	sf.close()
	check(CFG.apply_file(st_path) == "", "User settings apply ok")
	var g2 = new_game()
	check(g2.START_GOLD == 350 and g2.gold == 350, "Custom start gold applied on the fly")
	g2.free()
	CFG.reload_defaults()
	check(P.COST[P.PAWN] == 20 and CFG.start_gold() == 200, "reload_defaults restores bundled values")
	# Reject unrecognized schema.
	var junk_path := "user://configs/test_junk.json"
	var jf := FileAccess.open(junk_path, FileAccess.WRITE)
	jf.store_string("{\"schema\":\"nope\",\"hello\":1}")
	jf.close()
	check(CFG.apply_file(junk_path) != "", "Unrecognized schema rejected")
	_clear_user_configs()


func test_config_ui() -> void:
	CFG.reload_defaults()
	_clear_user_configs()
	var custom := CFG.game_data.duplicate(true)
	custom.pieces.defs.wall.cost = 77
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://configs"))
	var path := "user://configs/test_wall77.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(custom, "\t"))
	f.close()
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var g = scene.get_node("Game")
	var ui = scene.get_node("UI")
	check(ui.btn_config != null and ui.btn_config.text == "Config [O]", "Config button shows [O]")
	ui.open_config_dialog()
	check(ui._config_dialog_open and ui.config_list.item_count >= 3, "Config dialog lists bundled + user files")
	var found := -1
	for i in ui.config_list.item_count:
		if str(ui.config_list.get_item_metadata(i)) == path:
			found = i
			break
	check(found >= 0, "User config appears in list")
	ui.config_list.select(found)
	ui.apply_selected_config()
	await process_frame
	check(not ui._config_dialog_open, "Apply closes config dialog")
	check(P.COST[P.WALL] == 77 and ui.build_buttons[P.WALL].text.ends_with("77g"), "Apply updates wall cost and button")
	check(g.phase == g.Phase.SETUP and g.gold == g.START_GOLD, "Apply restarts the match")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_O
	ui._unhandled_input(key)
	check(ui._config_dialog_open, "O opens config dialog")
	ui.close_config_dialog()
	scene.queue_free()
	await process_frame
	CFG.reload_defaults()
	_clear_user_configs()


func test_settings_window() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var ui = scene.get_node("UI")
	var tree = scene.get_tree()
	check(ui.btn_settings != null and ui.btn_speed != null and ui.lbl_msg != null, "Settings, Speed, message line on HUD")
	check(ui.btn_settings.text == "Settings [G]", "Settings button shows [G]")
	var hud_v: VBoxContainer = ui.hud_panel.get_child(0) as VBoxContainer
	var hud_button_texts: PackedStringArray = []
	for c in hud_v.get_children():
		if c is Button:
			hud_button_texts.append((c as Button).text)
	check(
		not hud_button_texts.has(ui.btn_config.text) and hud_button_texts.has(ui.btn_speed.text),
		"Config not on main HUD; Speed stays"
	)
	check(ui.btn_config != null and ui.layout_select != null and ui.btn_leaderboard != null, "Moved controls exist in Settings")
	check(not ui.settings_dialog_open(), "Settings closed at start")
	ui.open_settings_dialog()
	check(ui.settings_dialog_open() and tree.paused, "Open Settings pauses game")
	var gkey := InputEventKey.new()
	gkey.pressed = true
	gkey.keycode = KEY_G
	ui._unhandled_input(gkey)
	check(not ui.settings_dialog_open() and not tree.paused, "G toggles Settings closed")
	ui.open_settings_dialog()
	var okey := InputEventKey.new()
	okey.pressed = true
	okey.keycode = KEY_O
	ui._unhandled_input(okey)
	check(ui._config_dialog_open and ui.settings_dialog_open() and tree.paused, "Config nests inside Settings pause")
	var esc := InputEventKey.new()
	esc.pressed = true
	esc.keycode = KEY_ESCAPE
	ui._unhandled_input(esc)
	check(not ui._config_dialog_open and ui.settings_dialog_open() and tree.paused, "Esc closes Config first")
	ui._unhandled_input(esc)
	check(not ui.settings_dialog_open() and not tree.paused, "Esc closes Settings and unpauses")
	ui.open_settings_dialog()
	ui.btn_settings_close.pressed.emit()
	check(not ui.settings_dialog_open() and not tree.paused, "Close [Esc] button works")
	scene.queue_free()
	await process_frame
