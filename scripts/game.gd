extends Node2D
## Core game: board state, placement, waves, mob AI, tower combat and _draw() rendering.
## All simulation goes through step(delta) so it can be driven headlessly by tests.

const P := preload("res://scripts/pieces.gd")
const M := preload("res://scripts/mobs.gd")
const DA := preload("res://scripts/draw_art.gd")
const SC := preload("res://scripts/scoring.gd")
const HS := preload("res://scripts/highscores.gd")

const COLS := 8
const ROWS := 12
const BASE_TILE := 56.0
const BASE_MARGIN := 16.0
var tile_size := BASE_TILE
var board_origin := Vector2(BASE_MARGIN, BASE_MARGIN)
const PLAYER_MIN_ROW := 3          # rows 0..2 = enemy spawn zone, 3..11 = player side
const MAX_WAVES := 20
const START_GOLD := 200
const PIECE_PATH_WEIGHT := 12.0    # mobs path around pieces, but will smash through if fully walled
const SPAWN_INTERVAL := 1.2
const MOB_ATTACK_RATE := 1.0
## Castling: King swaps with a Rook on the same rank, horizontal distance 2–4 tiles (once per match).
const CASTLING_MIN_H := 2
const CASTLING_MAX_H := 4
## Game speed multipliers (Engine.time_scale). Simulation sub-steps keep x10 stable.
const SPEED_OPTIONS := [1.0, 2.0, 3.0, 5.0, 10.0]
const MAX_SIM_STEP := 1.0 / 30.0
const MAX_FRAME_DELTA := 0.25

enum Phase { SETUP, WAVE, BETWEEN, GAME_OVER, VICTORY }
const PHASE_NAMES := ["Setup", "Wave running", "Build (between waves)", "GAME OVER", "VICTORY"]


class Piece:
	var type: int
	var cell: Vector2i
	var level := 1
	var hp := 0.0
	var max_hp := 0.0
	var cd := 0.0
	var spent := 0
	var flash := 0.0


class Mob:
	var cell: Vector2i      # last tile centre reached
	var target: Vector2i    # tile currently walking into (== cell when idle)
	var pos: Vector2        # continuous position in tile units
	var mob_type: int = M.GRUNT
	var hp: float
	var max_hp: float
	var speed: float        # tiles / second
	var damage: float
	var reward: int
	var wall_mult := 1.0
	var prefers_walls := false
	var atk_cd := 0.0
	var alive := true
	var promoted := false
	var flash := 0.0

	func tile() -> Vector2i:
		return Vector2i(roundi(pos.x), roundi(pos.y))


var pieces: Dictionary = {}     # Vector2i -> Piece
var mobs: Array = []
var shots: Array = []           # {from: Vector2, to: Vector2, t: float}
var gold := START_GOLD
var wave := 0
var phase: int = Phase.SETUP
var king_cell := Vector2i(-1, -1)
var selected := Vector2i(-1, -1)
var build_type: int = P.KING
var hover := Vector2i(-1, -1)
var spawn_left := 0
var spawn_timer := 0.0
var spawn_types: Array = []     # mob type per remaining spawn (same length as spawn_left)
var wave_hp := 18.0              # legacy default HP for tests that override hp only
var kills := 0
var gold_from_kills := 0
var score := 0
var score_from_kills := 0
var score_from_waves := 0
var match_result := ""          # "", "win", or "loss" after first end
var last_message := ""
var _match_recorded := false
var castling_used := false
var rng := RandomNumberGenerator.new()
var astar := AStarGrid2D.new()
var _tiles_cache: Dictionary = {}
var synergy: Dictionary = {}    # Vector2i -> {dmg, spd, hp, range, from: Array[Vector2i]}
var speed_index := 0


func _init() -> void:
	astar.region = Rect2i(0, 0, COLS, ROWS)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.update()
	rng.randomize()
	reset()


func reset() -> void:
	pieces.clear()
	mobs.clear()
	shots.clear()
	gold = START_GOLD
	wave = 0
	phase = Phase.SETUP
	king_cell = Vector2i(-1, -1)
	selected = Vector2i(-1, -1)
	build_type = P.KING
	spawn_left = 0
	spawn_types.clear()
	kills = 0
	gold_from_kills = 0
	score = 0
	score_from_kills = 0
	score_from_waves = 0
	match_result = ""
	_match_recorded = false
	castling_used = false
	_board_changed()
	_msg("Setup: place your King (mandatory), then towers and walls. Press Start Wave.")


# ---------------------------------------------------------------- helpers

func _msg(t: String) -> void:
	last_message = t


func _refresh_score() -> void:
	score = SC.final_score(score_from_kills, score_from_waves)


func _record_match_end() -> void:
	if _match_recorded:
		return
	_match_recorded = true
	_refresh_score()
	if phase == Phase.VICTORY:
		match_result = "win"
	else:
		match_result = "loss"
	HS.add_entry(score, wave, match_result)


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < COLS and c.y < ROWS


func has_king() -> bool:
	return pieces.has(king_cell)


func get_piece(c: Vector2i):
	return pieces.get(c)


func cell_center(c: Vector2) -> Vector2:
	return board_origin + (c + Vector2(0.5, 0.5)) * tile_size


func world_to_cell(p: Vector2) -> Vector2i:
	var q := (p - board_origin) / tile_size
	return Vector2i(floori(q.x), floori(q.y))


## Fit the board grid into `area` (viewport/canvas coordinates). Keeps mouse mapping aligned with drawing.
func fit_to_rect(area: Rect2) -> void:
	if area.size.x < 32.0 or area.size.y < 32.0:
		return
	var pad := 8.0
	var inner := Rect2(area.position + Vector2(pad, pad), area.size - Vector2(pad * 2.0, pad * 2.0))
	var margin := maxf(8.0, BASE_MARGIN * 0.5)
	var tw := (inner.size.x - margin * 2.0) / float(COLS)
	var th := (inner.size.y - margin * 2.0) / float(ROWS)
	tile_size = maxf(20.0, minf(tw, th))
	var grid := Vector2(COLS * tile_size, ROWS * tile_size)
	board_origin = inner.position + (inner.size - grid) * 0.5
	queue_redraw()


func board_viewport_rect() -> Rect2:
	var grid := Vector2(COLS * tile_size, ROWS * tile_size)
	return Rect2(board_origin, grid).grow(BASE_MARGIN * 0.75)


func _paths_exist_to_goal(goal: Vector2i, extra: Array) -> bool:
	if not in_bounds(goal):
		return false
	var restore: Array = []
	for c in pieces:
		if c == goal:
			continue
		astar.set_point_solid(c, true)
		restore.append(c)
	for c in extra:
		if c == goal:
			continue
		if in_bounds(c) and not c in restore:
			astar.set_point_solid(c, true)
			restore.append(c)
	var found := false
	for x in COLS:
		for y in PLAYER_MIN_ROW:
			var s := Vector2i(x, y)
			if pieces.has(s) or extra.has(s):
				continue
			var path := astar.get_id_path(s, goal)
			if path.size() >= 2:
				found = true
				break
		if found:
			break
	for c in restore:
		astar.set_point_solid(c, false)
	return found


func _board_changed() -> void:
	_tiles_cache.clear()
	for y in ROWS:
		for x in COLS:
			astar.set_point_weight_scale(Vector2i(x, y), 1.0)
	for c in pieces:
		astar.set_point_weight_scale(c, PIECE_PATH_WEIGHT)
	_recompute_synergy()


# ---------------------------------------------------------------- synergy

func _empty_bonus() -> Dictionary:
	return {"dmg": 0.0, "spd": 0.0, "hp": 0.0, "range": 0, "from": []}


## Rebuild synergy buffs: each piece buffs friendly pieces on its support squares.
## Max HP follows the HP buff while keeping each piece's current HP ratio.
func _recompute_synergy() -> void:
	synergy.clear()
	var size := Vector2i(COLS, ROWS)
	for c in pieces:
		var src = pieces[c]
		var buff: Dictionary = P.SYNERGY.get(src.type, {})
		if buff.is_empty():
			continue
		for t in P.support_tiles(src.type, c, src.level, size, pieces):
			if t == c or not pieces.has(t):
				continue
			var b: Dictionary = synergy.get(t, _empty_bonus())
			for k in ["dmg", "spd", "hp"]:
				b[k] = minf(float(P.SYNERGY_CAP[k]), b[k] + float(buff.get(k, 0.0)))
			b["range"] = mini(int(P.SYNERGY_CAP["range"]), b["range"] + int(buff.get("range", 0)))
			b["from"].append(c)
			synergy[t] = b
	for c in pieces:
		var p = pieces[c]
		var new_max := effective_max_hp(p.type, p.level, c)
		if p.max_hp > 0.0 and absf(new_max - p.max_hp) > 0.001:
			p.hp = p.hp * new_max / p.max_hp
		p.max_hp = new_max


func synergy_at(c: Vector2i) -> Dictionary:
	return synergy.get(c, _empty_bonus())


func effective_max_hp(type: int, level: int, c: Vector2i) -> float:
	return P.max_hp(type, level) * (1.0 + float(synergy_at(c).hp))


func effective_damage(type: int, level: int, c: Vector2i) -> float:
	return P.damage(type, level) * (1.0 + float(synergy_at(c).dmg))


func effective_cooldown(type: int, c: Vector2i) -> float:
	return P.COOLDOWN[type] / (1.0 + float(synergy_at(c).spd))


func effective_range(level: int, c: Vector2i) -> int:
	return P.slide_range(level) + int(synergy_at(c).range)


## Human-readable synergy line for the piece dialog ("" when unbuffed).
func synergy_text(c: Vector2i) -> String:
	var b := synergy_at(c)
	if b.from.is_empty():
		return ""
	var parts: PackedStringArray = []
	if b.dmg > 0.0:
		parts.append("+%d%% DMG" % roundi(b.dmg * 100.0))
	if b.spd > 0.0:
		parts.append("+%d%% speed" % roundi(b.spd * 100.0))
	if b.hp > 0.0:
		parts.append("+%d%% HP" % roundi(b.hp * 100.0))
	if b.range > 0:
		parts.append("+%d range" % b.range)
	var names: PackedStringArray = []
	for f in b.from:
		if pieces.has(f):
			names.append(P.NAMES[pieces[f].type])
	return "Synergy: %s (from %s)" % [", ".join(parts), ", ".join(names)]


## Number of friendly pieces the piece at `c` currently buffs.
func supports_count(c: Vector2i) -> int:
	var n := 0
	for t in synergy:
		if synergy[t].from.has(c):
			n += 1
	return n


## Attack tiles for the piece at `c` (cached; invalidated whenever the board changes).
func attack_tiles_for(c: Vector2i) -> Dictionary:
	if _tiles_cache.has(c):
		return _tiles_cache[c]
	var d := {}
	var p = pieces.get(c)
	if p != null:
		var rb := int(synergy_at(c).range)
		for t in P.attack_tiles(p.type, c, p.level, Vector2i(COLS, ROWS), pieces, rb):
			d[t] = true
	_tiles_cache[c] = d
	return d


# ---------------------------------------------------------------- player actions

func _tower_adjacent(c: Vector2i) -> bool:
	for d in P.ORTHO + P.DIAG:
		var n: Vector2i = c + d
		if pieces.has(n) and P.is_tower(pieces[n].type):
			return true
	return false


func can_place(type: int, c: Vector2i) -> String:
	if phase == Phase.GAME_OVER or phase == Phase.VICTORY:
		return "Game is over - press Restart."
	if not in_bounds(c):
		return "Outside the board."
	if c.y < PLAYER_MIN_ROW:
		return "Cannot build in the enemy zone (top 3 rows)."
	if pieces.has(c):
		return "Tile is occupied."
	if type == P.KING and has_king():
		return "Only one King is allowed."
	for m in mobs:
		if m.alive and (m.cell == c or m.target == c or m.tile() == c):
			return "A mob is on that tile."
	if _tower_adjacent(c):
		return "Too close to a tower — leave a one-tile gap."
	if has_king() or type == P.KING:
		var goal: Vector2i = c if type == P.KING else king_cell
		if not _paths_exist_to_goal(goal, [c]):
			return "Would block all paths to the King."
	if gold < P.COST[type]:
		return "Not enough gold (%d needed)." % P.COST[type]
	return ""


func place(type: int, c: Vector2i) -> bool:
	var err := can_place(type, c)
	if err != "":
		_msg(err)
		return false
	var p := Piece.new()
	p.type = type
	p.cell = c
	p.max_hp = P.max_hp(type, 1)
	p.hp = p.max_hp
	p.spent = P.COST[type]
	p.cd = 0.3
	gold -= p.spent
	pieces[c] = p
	if type == P.KING:
		king_cell = c
	_board_changed()
	_msg("Placed %s." % P.NAMES[type])
	return true


func upgrade(c: Vector2i) -> bool:
	var p = pieces.get(c)
	if p == null:
		_msg("Nothing to upgrade.")
		return false
	if phase == Phase.GAME_OVER or phase == Phase.VICTORY:
		return false
	if p.level >= P.MAX_LEVEL:
		_msg("Already max level.")
		return false
	var cost := P.upgrade_cost(p.type, p.level)
	if gold < cost:
		_msg("Not enough gold (%d needed)." % cost)
		return false
	gold -= cost
	p.spent += cost
	var old_max: float = p.max_hp
	p.level += 1
	p.max_hp = effective_max_hp(p.type, p.level, c)
	p.hp += p.max_hp - old_max
	_board_changed()
	_msg("%s upgraded to level %d." % [P.NAMES[p.type], p.level])
	return true


func sell(c: Vector2i) -> bool:
	var p = pieces.get(c)
	if p == null:
		return false
	if phase == Phase.GAME_OVER or phase == Phase.VICTORY:
		return false
	if p.type == P.KING and phase != Phase.SETUP:
		_msg("The King can only be moved/removed during setup.")
		return false
	var refund: int = p.spent / 2
	gold += refund
	pieces.erase(c)
	if p.type == P.KING:
		king_cell = Vector2i(-1, -1)
	if selected == c:
		selected = Vector2i(-1, -1)
	_board_changed()
	_msg("Removed %s (+%d gold)." % [P.NAMES[p.type], refund])
	return true


func _mob_on_tile(c: Vector2i) -> bool:
	return _tile_occupied_by_mob(c)


func _rook_on_kings_row(c: Vector2i) -> bool:
	if not has_king():
		return false
	var p = pieces.get(c)
	if p == null or p.type != P.ROOK:
		return false
	if c.y != king_cell.y:
		return false
	var dx: int = absi(c.x - king_cell.x)
	return dx >= CASTLING_MIN_H and dx <= CASTLING_MAX_H


func castle_rooks_eligible() -> Array:
	if castling_used or not has_king():
		return []
	if phase == Phase.GAME_OVER or phase == Phase.VICTORY:
		return []
	var out: Array = []
	for c in pieces:
		if _rook_on_kings_row(c) and can_castle_to(c) == "":
			out.append(c)
	return out


func can_castle_to(rook_c: Vector2i) -> String:
	if castling_used:
		return "Castling already used this match."
	if phase == Phase.GAME_OVER or phase == Phase.VICTORY:
		return "Game is over."
	if not has_king():
		return "No King on the board."
	if not _rook_on_kings_row(rook_c):
		return "Rook must be on the King's row, 2–4 tiles away horizontally."
	if _mob_on_tile(king_cell) or _mob_on_tile(rook_c):
		return "Cannot castle — a mob occupies the King or Rook."
	if not _paths_exist_to_goal(rook_c, []):
		return "Would block all paths to the King."
	return ""


func perform_castle(rook_c: Vector2i) -> bool:
	var err := can_castle_to(rook_c)
	if err != "":
		_msg(err)
		return false
	var king_c: Vector2i = king_cell
	var k = pieces[king_c]
	var r = pieces[rook_c]
	pieces.erase(king_c)
	pieces.erase(rook_c)
	k.cell = rook_c
	r.cell = king_c
	pieces[rook_c] = k
	pieces[king_c] = r
	king_cell = rook_c
	castling_used = true
	if selected == king_c:
		selected = rook_c
	elif selected == rook_c:
		selected = king_c
	_board_changed()
	_msg("Castling! King and Rook swapped.")
	return true


func try_castle() -> bool:
	if castling_used:
		_msg("Castling already used this match.")
		return false
	var rook_c := Vector2i(-1, -1)
	var p = get_piece(selected)
	if p == null:
		_msg("Select your King or an eligible Rook, then press C or Castle.")
		return false
	if p.type == P.ROOK:
		rook_c = selected
	elif p.type == P.KING:
		var best_dx := 999
		for c in castle_rooks_eligible():
			var dx: int = absi(c.x - king_cell.x)
			if dx < best_dx:
				best_dx = dx
				rook_c = c
		if rook_c.x < 0:
			_msg("No eligible Rook to castle with (same row, 2–4 tiles away).")
			return false
	else:
		_msg("Select your King or a Rook to castle.")
		return false
	return perform_castle(rook_c)


func start_wave() -> bool:
	if phase != Phase.SETUP and phase != Phase.BETWEEN:
		_msg("A wave is already running." if phase == Phase.WAVE else "Game is over.")
		return false
	if not has_king():
		_msg("Place your King first!")
		return false
	wave += 1
	spawn_types = M.wave_spawn_list(wave)
	spawn_left = spawn_types.size()
	wave_hp = 18.0 * M.hp_scale_for_wave(wave)
	spawn_timer = 0.0
	phase = Phase.WAVE
	_msg("Wave %d: %d mobs incoming!" % [wave, spawn_left])
	return true


func spawn_mob(c: Vector2i, hp: float = -1.0, mob_type: int = M.GRUNT) -> Mob:
	var m := Mob.new()
	m.cell = c
	m.target = c
	m.pos = Vector2(c)
	m.mob_type = mob_type
	var st := M.mob_stats(mob_type, maxi(wave, 1))
	m.hp = hp if hp > 0.0 else st.hp
	m.max_hp = m.hp
	if hp > 0.0:
		# Test/manual override: keep type stats except HP.
		m.speed = st.speed
		m.damage = st.damage
		m.reward = st.reward
		m.wall_mult = st.wall_mult
		m.prefers_walls = st.prefers_walls
	else:
		m.speed = st.speed
		m.damage = st.damage
		m.reward = st.reward
		m.wall_mult = st.wall_mult
		m.prefers_walls = st.prefers_walls
	m.atk_cd = 0.5
	m.promoted = mob_type == M.PROMOTED
	mobs.append(m)
	return m


func _apply_mob_stats(m, mob_type: int) -> void:
	var st := M.mob_stats(mob_type, maxi(wave, 1))
	m.mob_type = mob_type
	m.max_hp = st.hp
	m.hp = st.hp
	m.speed = st.speed
	m.damage = st.damage
	m.reward = st.reward
	m.wall_mult = st.wall_mult
	m.prefers_walls = st.prefers_walls


func _try_promote(m) -> bool:
	if m.promoted or m.mob_type == M.PROMOTED:
		return false
	if m.cell.y != ROWS - 1:
		return false
	_apply_mob_stats(m, M.PROMOTED)
	m.promoted = true
	_msg("A mob was promoted!")
	return true


# ---------------------------------------------------------------- simulation

func _process(delta: float) -> void:
	advance(delta)
	queue_redraw()


## Advance the simulation by a (time-scaled) frame delta in small fixed-size sub-steps,
## so high game speeds (x10) never skip spawns, shots or collisions.
func advance(delta: float) -> int:
	var total := minf(delta, MAX_FRAME_DELTA * float(SPEED_OPTIONS[speed_index]))
	if total <= 0.0:
		return 0
	var n := maxi(1, ceili(total / MAX_SIM_STEP))
	var dt := total / float(n)
	for i in n:
		step(dt)
	return n


func game_speed() -> float:
	return float(SPEED_OPTIONS[speed_index])


func set_speed_index(i: int) -> void:
	speed_index = posmod(i, SPEED_OPTIONS.size())
	Engine.time_scale = game_speed()


func cycle_speed() -> float:
	set_speed_index(speed_index + 1)
	_msg("Game speed x%d." % int(game_speed()))
	return game_speed()


func speed_label() -> String:
	return "x%d" % int(game_speed())


# ---------------------------------------------------------------- layouts

## Serialise the current board as a layout: [{type, x, y, level}], King first.
func export_layout() -> Array:
	var out: Array = []
	for c in pieces:
		var p = pieces[c]
		var e := {"type": P.NAMES[p.type], "x": c.x, "y": c.y, "level": p.level}
		if p.type == P.KING:
			out.push_front(e)
		else:
			out.append(e)
	return out


## Replace the board with a saved layout (setup phase only). Pieces are bought with normal
## rules and gold; anything unaffordable or illegal is skipped. Returns pieces placed.
func apply_layout(entries: Array) -> int:
	if phase != Phase.SETUP:
		_msg("Layouts can only be loaded during setup.")
		return 0
	pieces.clear()
	king_cell = Vector2i(-1, -1)
	selected = Vector2i(-1, -1)
	castling_used = false
	gold = START_GOLD
	_board_changed()
	var by_name := {}
	for t in P.ORDER:
		by_name[P.NAMES[t]] = t
	var sorted := entries.duplicate()
	sorted.sort_custom(func(a, b): return str(a.get("type", "")) == "King" and str(b.get("type", "")) != "King")
	var placed := 0
	var skipped := 0
	for e in sorted:
		if not (e is Dictionary) or not by_name.has(str(e.get("type", ""))):
			skipped += 1
			continue
		var t: int = by_name[str(e.type)]
		var c := Vector2i(int(e.get("x", -1)), int(e.get("y", -1)))
		if place(t, c):
			placed += 1
			for i in range(1, clampi(int(e.get("level", 1)), 1, P.MAX_LEVEL)):
				if not upgrade(c):
					break
		else:
			skipped += 1
	build_type = -1 if has_king() else P.KING
	_msg("Layout loaded: %d pieces placed%s." % [placed, (", %d skipped" % skipped) if skipped > 0 else ""])
	return placed


# ---------------------------------------------------------------- upgrade preview

## Before/after stat rows for upgrading the piece at `c`: [{label, before, after, diff}].
func upgrade_preview(c: Vector2i) -> Array:
	var p = pieces.get(c)
	if p == null or p.level >= P.MAX_LEVEL:
		return []
	var rows: Array = []
	var nl: int = p.level + 1
	rows.append(_stat_row("Level", p.level, nl, 0))
	rows.append(_stat_row("HP", p.max_hp, effective_max_hp(p.type, nl, c), 0))
	if P.is_tower(p.type):
		rows.append(_stat_row("DMG", effective_damage(p.type, p.level, c), effective_damage(p.type, nl, c), 1))
		if P.is_slider(p.type):
			rows.append(_stat_row("Range", effective_range(p.level, c), effective_range(nl, c), 0))
	return rows


func _stat_row(label: String, before: float, after: float, decimals: int) -> Dictionary:
	var fmt := "%." + str(decimals) + "f"
	var diff := after - before
	var sgn := "+" if diff >= 0.0 else "-"
	var txt := "%s %s -> %s (%s%s)" % [label, fmt % before, fmt % after, sgn, fmt % absf(diff)]
	return {"label": label, "before": before, "after": after, "diff": diff, "text": txt}


func step(dt: float) -> void:
	for s in shots:
		s.t -= dt
	shots = shots.filter(func(s): return s.t > 0.0)
	for c in pieces:
		pieces[c].flash = max(0.0, pieces[c].flash - dt)
	for m in mobs:
		m.flash = max(0.0, m.flash - dt)
	if phase == Phase.GAME_OVER or phase == Phase.VICTORY:
		return
	if phase == Phase.WAVE and spawn_left > 0:
		spawn_timer -= dt
		if spawn_timer <= 0.0:
			if _try_spawn_wave_mob():
				spawn_timer = SPAWN_INTERVAL
				spawn_left -= 1
			else:
				spawn_timer = 0.0
	for m in mobs.duplicate():
		if m.alive:
			_update_mob(m, dt)
		if phase == Phase.GAME_OVER:
			return
	_update_towers(dt)
	mobs = mobs.filter(func(m): return m.alive)
	if phase == Phase.WAVE and spawn_left == 0 and mobs.is_empty():
		var bonus := M.wave_clear_bonus(wave)
		gold += bonus
		var wp := SC.wave_clear_points(wave)
		score_from_waves += wp
		_refresh_score()
		if wave >= MAX_WAVES:
			phase = Phase.VICTORY
			_msg("VICTORY! All %d waves cleared. Final score: %d." % [MAX_WAVES, score])
			_record_match_end()
		else:
			phase = Phase.BETWEEN
			_msg("Wave %d cleared! +%d bonus gold, +%d score. Build, then start the next wave." % [wave, bonus, wp])


func _mob_claims_tile(m, c: Vector2i) -> bool:
	return m.alive and (m.cell == c or m.target == c)


func _tile_occupied_by_mob(c: Vector2i, ignore = null) -> bool:
	for m in mobs:
		if m != ignore and _mob_claims_tile(m, c):
			return true
	return false


func _try_spawn_wave_mob() -> bool:
	var order: Array = []
	for x in COLS:
		order.append(x)
	for i in COLS:
		var j := i + rng.randi_range(0, COLS - 1 - i)
		var tmp: int = order[i]
		order[i] = order[j]
		order[j] = tmp
	for x in order:
		var c := Vector2i(x, 0)
		if not _tile_occupied_by_mob(c):
			var t: int = spawn_types[spawn_types.size() - spawn_left]
			spawn_mob(c, -1.0, t)
			return true
	return false


## Next tile on the weighted A* path from `c` to the King (or `c` if none).
## Other mobs' tiles are treated as blocked so followers can sidestep when possible.
func next_step(c: Vector2i, ignore = null) -> Vector2i:
	if not has_king() or c == king_cell:
		return c
	var blocked: Array = []
	for m in mobs:
		if m == ignore or not m.alive:
			continue
		for t in [m.cell, m.target]:
			if in_bounds(t) and not blocked.has(t):
				astar.set_point_solid(t, true)
				blocked.append(t)
	var path := astar.get_id_path(c, king_cell)
	for t in blocked:
		astar.set_point_solid(t, false)
	if path.size() >= 2:
		return path[1]
	return c


func _update_mob(m, dt: float) -> void:
	m.atk_cd -= dt
	var blocker := Vector2i(-1, -1)
	if m.target == m.cell:
		var nxt := next_step(m.cell, m)
		if nxt != m.cell:
			if pieces.has(nxt):
				blocker = nxt          # path goes through a piece (the King, or a wall when boxed in)
			elif _tile_occupied_by_mob(nxt, m):
				pass                   # wait for the tile to clear
			else:
				m.target = nxt
	if m.target != m.cell:
		var goal := Vector2(m.target)
		var to: Vector2 = goal - m.pos
		var d: float = m.speed * dt
		if to.length() <= d:
			m.pos = goal
			m.cell = m.target
			if _try_promote(m):
				return
		else:
			m.pos += to.normalized() * d
	if m.atk_cd <= 0.0:
		var victim = _pick_victim(m, blocker)
		if victim != null:
			m.atk_cd = MOB_ATTACK_RATE
			shots.append({"from": cell_center(m.pos), "to": cell_center(Vector2(victim.cell)), "t": 0.12, "enemy": true})
			var dmg: float = m.damage
			if victim.type == P.WALL:
				dmg *= m.wall_mult
			_damage_piece(victim, dmg)


## Mobs hit: the King if adjacent (8-neighbourhood), else whatever blocks their path,
## else the weakest orthogonally adjacent piece.
func _pick_victim(m, blocker: Vector2i):
	var t: Vector2i = m.cell if m.target == m.cell else m.tile()
	if has_king() and abs(king_cell.x - t.x) <= 1 and abs(king_cell.y - t.y) <= 1:
		return pieces[king_cell]
	if m.prefers_walls:
		var wall_best = null
		for d in P.ORTHO + P.DIAG:
			var p = pieces.get(t + d)
			if p != null and p.type == P.WALL and (wall_best == null or p.hp < wall_best.hp):
				wall_best = p
		if wall_best != null:
			return wall_best
	if pieces.has(blocker):
		return pieces[blocker]
	var best = null
	for d in P.ORTHO:
		var p = pieces.get(t + d)
		if p != null and (best == null or p.hp < best.hp):
			best = p
	return best


func _damage_piece(p, amount: float) -> void:
	p.hp -= amount
	p.flash = 0.15
	if p.hp > 0.0:
		return
	pieces.erase(p.cell)
	if selected == p.cell:
		selected = Vector2i(-1, -1)
	if p.type == P.KING:
		king_cell = Vector2i(-1, -1)
		phase = Phase.GAME_OVER
		_refresh_score()
		_msg("Your King has fallen - GAME OVER (wave %d). Score: %d. Press Restart." % [wave, score])
		_record_match_end()
	else:
		_msg("Your %s was destroyed!" % P.NAMES[p.type])
	_board_changed()


func _update_towers(dt: float) -> void:
	for c in pieces.keys():
		var p = pieces.get(c)
		if p == null or not P.is_tower(p.type):
			continue
		p.cd -= dt
		if p.cd > 0.0:
			continue
		var tiles := attack_tiles_for(c)
		var best = null
		for m in mobs:
			if m.alive and tiles.has(m.tile()) and (best == null or m.pos.y > best.pos.y):
				best = m
		if best == null:
			continue
		p.cd = effective_cooldown(p.type, c)
		best.hp -= effective_damage(p.type, p.level, c)
		best.flash = 0.18
		shots.append({"from": cell_center(Vector2(c)), "to": cell_center(best.pos), "t": 0.12, "enemy": false})
		if best.hp <= 0.0:
			best.alive = false
			gold += best.reward
			gold_from_kills += best.reward
			kills += 1
			var pts := SC.kill_points(best.mob_type, maxi(wave, 1))
			score_from_kills += pts
			_refresh_score()


# ---------------------------------------------------------------- input

func _pointer_canvas_pos(event: InputEventMouse) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * event.position


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hover = world_to_cell(_pointer_canvas_pos(event))
	elif event is InputEventMouseButton and event.pressed:
		handle_click(world_to_cell(_pointer_canvas_pos(event)), event.button_index)
	elif event is InputEventKey and event.pressed and not event.echo and not event.shift_pressed:
		match event.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7:
				build_type = P.ORDER[event.keycode - KEY_1]
			KEY_U:
				upgrade(selected)
			KEY_S, KEY_DELETE:
				sell(selected)
			KEY_SPACE, KEY_ENTER:
				start_wave()
			KEY_C:
				try_castle()
			KEY_ESCAPE:
				var ui = get_parent().get_node_or_null("UI")
				if ui != null and ui.has_method("piece_options_open") and ui.piece_options_open():
					ui.close_piece_options()
				else:
					selected = Vector2i(-1, -1)
					build_type = -1


func handle_click(c: Vector2i, button: int) -> void:
	if button == MOUSE_BUTTON_RIGHT:
		selected = Vector2i(-1, -1)
		build_type = -1
		return
	if button != MOUSE_BUTTON_LEFT or not in_bounds(c):
		return
	if pieces.has(c):
		selected = c
		build_type = -1
		var ui = get_parent().get_node_or_null("UI")
		if ui != null and ui.has_method("open_piece_options"):
			ui.open_piece_options(c)
	elif build_type >= 0:
		var t := build_type
		if place(t, c):
			selected = c
			if t == P.KING:
				build_type = P.PAWN
	else:
		selected = Vector2i(-1, -1)


# ---------------------------------------------------------------- drawing (vector only)

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var board := Rect2(board_origin, Vector2(COLS, ROWS) * tile_size)
	draw_rect(board.grow(6), DA.BG_DARK)
	for y in ROWS:
		for x in COLS:
			var r := Rect2(board_origin + Vector2(x, y) * tile_size, Vector2(tile_size, tile_size))
			var light: bool = (x + y) % 2 == 0
			var col: Color = DA.SQ_LIGHT if light else DA.SQ_DARK
			if y < PLAYER_MIN_ROW:
				col = DA.SPAWN_LIGHT if light else DA.SPAWN_DARK
			draw_rect(r, col)
			draw_rect(r.grow(-1), DA.GRID_LINE, false, 1.0)
	var spawn_r := Rect2(board_origin, Vector2(COLS * tile_size, PLAYER_MIN_ROW * tile_size))
	for i in range(COLS * 2 + PLAYER_MIN_ROW * 2):
		var t: float = float(i) * 14.0
		draw_line(spawn_r.position + Vector2(t, 0), spawn_r.position + Vector2(t - 28, spawn_r.size.y), Color(0.55, 0.15, 0.15, 0.12), 1.0)
	draw_rect(board, DA.FRAME_LINE, false, 3.0)
	var div_y := board_origin + Vector2(0, PLAYER_MIN_ROW * tile_size)
	draw_line(div_y, div_y + Vector2(COLS * tile_size, 0), DA.SPAWN_DIVIDER, 3.0)
	var lbl_scale := maxf(0.65, tile_size / BASE_TILE)
	draw_string(
		font, board_origin + Vector2(6, 14 * lbl_scale), "SPAWN", HORIZONTAL_ALIGNMENT_LEFT, 80, int(11 * lbl_scale),
		Color(0.95, 0.55, 0.55, 0.75)
	)

	var hl := {}
	if pieces.has(selected):
		hl = attack_tiles_for(selected)
	elif build_type >= 0 and in_bounds(hover):
		var ok: String = can_place(build_type, hover)
		var tile_r := Rect2(board_origin + Vector2(hover) * tile_size, Vector2(tile_size, tile_size)).grow(-2)
		var hover_col := DA.HOVER_OK if ok == "" else DA.HOVER_BAD
		draw_rect(tile_r, hover_col)
		draw_rect(tile_r, hover_col.lightened(0.2), false, 2.0)
		var prev_a: float = 0.5 if ok == "" else 0.42
		if P.is_tower(build_type) and ok == "":
			for t in P.attack_tiles(build_type, hover, 1, Vector2i(COLS, ROWS), pieces):
				hl[t] = true
		_draw_piece_shape(build_type, cell_center(Vector2(hover)), 1, 1.0, 0.0, prev_a)
	for t in hl:
		var ar := Rect2(board_origin + Vector2(t) * tile_size, Vector2(tile_size, tile_size)).grow(-4)
		draw_rect(ar, DA.ATTACK_FILL)
		draw_rect(ar, DA.ATTACK_RING, false, 1.5)
		draw_circle(cell_center(Vector2(t)), 4.5, DA.ATTACK_RING)

	_draw_synergy_links()
	for c in pieces:
		var p = pieces[c]
		_draw_piece_shape(p.type, cell_center(Vector2(c)), p.level, p.hp / p.max_hp, p.flash, 1.0)
		_draw_piece_stats(p, c)
	if pieces.has(selected):
		var sr := Rect2(board_origin + Vector2(selected) * tile_size, Vector2(tile_size, tile_size)).grow(-3)
		draw_rect(sr, DA.SELECT_RING, false, 3.0)

	if not castling_used and has_king():
		for c in castle_rooks_eligible():
			var cr := Rect2(board_origin + Vector2(c) * tile_size, Vector2(tile_size, tile_size)).grow(-5)
			draw_rect(cr, DA.CASTLE_FILL)
			draw_rect(cr, DA.CASTLE_BORDER, false, 2.0)

	for m in mobs:
		var cp := cell_center(m.pos)
		var fill: Color = M.COLORS[m.mob_type]
		if m.flash > 0.0:
			fill = fill.lerp(Color(1.0, 0.85, 0.7), clampf(m.flash / 0.18, 0.0, 0.7))
		M.draw_mob(self, cp, m.mob_type, fill, Color(0.12, 0.08, 0.1), m.flash)
		var ms := _art_scale()
		draw_set_transform(cp, 0.0, Vector2(ms, ms))
		DA.draw_hp_bar(self, Vector2(-18, -28), 36, m.hp / m.max_hp, Color(0.88, 0.22, 0.22), 10.0, DA.hp_text(m.hp, m.max_hp))
		draw_set_transform(Vector2.ZERO)

	for s in shots:
		var col := Color(1, 0.35, 0.25, 0.95) if s.enemy else Color(1, 0.92, 0.42, 0.95)
		draw_line(s.from, s.to, col.darkened(0.2), 5.0)
		draw_line(s.from, s.to, col, 2.5)
		draw_circle(s.to, 4.0, col)

	if phase == Phase.GAME_OVER or phase == Phase.VICTORY:
		var box := Rect2(board_origin + Vector2(0, 4.5 * tile_size), Vector2(COLS * tile_size, 2.5 * tile_size))
		draw_rect(box, Color(0.05, 0.05, 0.07, 0.82))
		draw_rect(box.grow(-4), DA.UI_BORDER, false, 2.0)
		var head: String = PHASE_NAMES[phase]
		draw_string(font, box.position + Vector2(0, 40), head, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 34, DA.UI_TEXT)
		draw_string(
			font, box.position + Vector2(0, 84), "Score: %d" % score,
			HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 26, DA.UI_ACCENT
		)


func _art_scale() -> float:
	return clampf(tile_size / BASE_TILE, 0.5, 2.0)


func _draw_piece_shape(type: int, c: Vector2, _level: int, _hp_ratio: float, flash: float, alpha: float) -> void:
	var k := _art_scale()
	draw_set_transform(c, 0.0, Vector2(k, k))
	DA.draw_piece(self, Vector2.ZERO, type, P.COLORS[type], alpha, flash)
	draw_set_transform(Vector2.ZERO)


## HP bar with numbers (top), weapon icon + damage (bottom-left), level n/max (bottom-right).
func _draw_piece_stats(p, c: Vector2i) -> void:
	var k := _art_scale()
	draw_set_transform(cell_center(Vector2(c)), 0.0, Vector2(k, k))
	var bar_col := Color(0.25, 0.82, 0.38) if p.type != P.WALL else Color(0.55, 0.72, 0.82)
	DA.draw_hp_bar(self, Vector2(-25, -27), 50, p.hp / p.max_hp, bar_col, 10.0, DA.hp_text(p.hp, p.max_hp))
	if P.is_tower(p.type):
		DA.draw_weapon_stat(self, Vector2(-26, 26), effective_damage(p.type, p.level, c), synergy_at(c).dmg > 0.0)
	DA.draw_level_badge(self, Vector2(26, 26), p.level, P.MAX_LEVEL)
	draw_set_transform(Vector2.ZERO)


## Subtle gold links from each supporter to the friendly pieces it buffs, plus a soft glow.
func _draw_synergy_links() -> void:
	var sel_on := pieces.has(selected)
	for t in synergy:
		if not pieces.has(t):
			continue
		var b: Dictionary = synergy[t]
		var to := cell_center(Vector2(t))
		var strong: bool = sel_on and (t == selected or b.from.has(selected))
		draw_circle(to, tile_size * 0.46, DA.SYNERGY_GLOW if not strong else DA.SYNERGY_GLOW_STRONG)
		for f in b.from:
			var involved: bool = sel_on and (f == selected or t == selected)
			if sel_on and not involved:
				continue
			DA.draw_synergy_link(self, cell_center(Vector2(f)), to, tile_size, involved)
