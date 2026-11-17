extends Node2D
## Core game: board state, placement, waves, mob AI, tower combat and _draw() rendering.
## All simulation goes through step(delta) so it can be driven headlessly by tests.

const P := preload("res://scripts/pieces.gd")
const M := preload("res://scripts/mobs.gd")

const COLS := 8
const ROWS := 12
const TILE := 56.0
const ORIGIN := Vector2(16, 16)
const PLAYER_MIN_ROW := 3          # rows 0..2 = enemy spawn zone, 3..11 = player side
const MAX_WAVES := 10
const START_GOLD := 200
const PIECE_PATH_WEIGHT := 12.0    # mobs path around pieces, but will smash through if fully walled
const SPAWN_INTERVAL := 1.2
const MOB_ATTACK_RATE := 1.0

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
var last_message := ""
var rng := RandomNumberGenerator.new()
var astar := AStarGrid2D.new()
var _tiles_cache: Dictionary = {}


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
	_board_changed()
	_msg("Setup: place your King (mandatory), then towers and walls. Press Start Wave.")


# ---------------------------------------------------------------- helpers

func _msg(t: String) -> void:
	last_message = t


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < COLS and c.y < ROWS


func has_king() -> bool:
	return pieces.has(king_cell)


func get_piece(c: Vector2i):
	return pieces.get(c)


func cell_center(c: Vector2) -> Vector2:
	return ORIGIN + (c + Vector2(0.5, 0.5)) * TILE


func world_to_cell(p: Vector2) -> Vector2i:
	var q := (p - ORIGIN) / TILE
	return Vector2i(floori(q.x), floori(q.y))


func _board_changed() -> void:
	_tiles_cache.clear()
	for y in ROWS:
		for x in COLS:
			astar.set_point_weight_scale(Vector2i(x, y), 1.0)
	for c in pieces:
		astar.set_point_weight_scale(c, PIECE_PATH_WEIGHT)


## Attack tiles for the piece at `c` (cached; invalidated whenever the board changes).
func attack_tiles_for(c: Vector2i) -> Dictionary:
	if _tiles_cache.has(c):
		return _tiles_cache[c]
	var d := {}
	var p = pieces.get(c)
	if p != null:
		for t in P.attack_tiles(p.type, c, p.level, Vector2i(COLS, ROWS), pieces):
			d[t] = true
	_tiles_cache[c] = d
	return d


# ---------------------------------------------------------------- player actions

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
	p.max_hp = P.max_hp(p.type, p.level)
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
	mobs.append(m)
	return m


# ---------------------------------------------------------------- simulation

func _process(delta: float) -> void:
	step(delta)
	queue_redraw()


func step(dt: float) -> void:
	for s in shots:
		s.t -= dt
	shots = shots.filter(func(s): return s.t > 0.0)
	for c in pieces:
		pieces[c].flash = max(0.0, pieces[c].flash - dt)
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
		if wave >= MAX_WAVES:
			phase = Phase.VICTORY
			_msg("VICTORY! All %d waves cleared." % MAX_WAVES)
		else:
			phase = Phase.BETWEEN
			_msg("Wave %d cleared! +%d bonus gold. Build, then start the next wave." % [wave, bonus])


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
		_msg("Your King has fallen - GAME OVER (wave %d). Press Restart." % wave)
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
		p.cd = P.COOLDOWN[p.type]
		best.hp -= P.damage(p.type, p.level)
		shots.append({"from": cell_center(Vector2(c)), "to": cell_center(best.pos), "t": 0.12, "enemy": false})
		if best.hp <= 0.0:
			best.alive = false
			gold += best.reward
			gold_from_kills += best.reward
			kills += 1


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hover = world_to_cell(to_local(event.position))
	elif event is InputEventMouseButton and event.pressed:
		handle_click(world_to_cell(to_local(event.position)), event.button_index)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7:
				build_type = P.ORDER[event.keycode - KEY_1]
			KEY_U:
				upgrade(selected)
			KEY_S, KEY_DELETE:
				sell(selected)
			KEY_SPACE, KEY_ENTER:
				start_wave()
			KEY_ESCAPE:
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
	for y in ROWS:
		for x in COLS:
			var r := Rect2(ORIGIN + Vector2(x, y) * TILE, Vector2(TILE, TILE))
			var col := Color(0.86, 0.84, 0.78) if (x + y) % 2 == 0 else Color(0.62, 0.58, 0.52)
			if y < PLAYER_MIN_ROW:
				col = col.lerp(Color(0.75, 0.3, 0.3), 0.35)
			draw_rect(r, col)
	draw_rect(Rect2(ORIGIN, Vector2(COLS, ROWS) * TILE), Color(0.1, 0.1, 0.1), false, 2.0)
	draw_line(ORIGIN + Vector2(0, PLAYER_MIN_ROW * TILE), ORIGIN + Vector2(COLS * TILE, PLAYER_MIN_ROW * TILE), Color(0.6, 0.1, 0.1), 2.0)

	# attack-tile highlight: selected piece, or placement preview under the mouse
	var hl := {}
	if pieces.has(selected):
		hl = attack_tiles_for(selected)
	elif build_type >= 0 and P.is_tower(build_type) and in_bounds(hover) and can_place(build_type, hover) == "":
		for t in P.attack_tiles(build_type, hover, 1, Vector2i(COLS, ROWS), pieces):
			hl[t] = true
		_draw_piece_shape(build_type, cell_center(Vector2(hover)), 1, 1.0, 1.0, font, 0.45)
	for t in hl:
		draw_rect(Rect2(ORIGIN + Vector2(t) * TILE, Vector2(TILE, TILE)).grow(-3), Color(1, 0.2, 0.2, 0.28))
		draw_circle(cell_center(Vector2(t)), 5, Color(0.8, 0.1, 0.1, 0.6))

	for c in pieces:
		var p = pieces[c]
		_draw_piece_shape(p.type, cell_center(Vector2(c)), p.level, p.hp / p.max_hp, p.flash, font, 1.0)
	if pieces.has(selected):
		draw_rect(Rect2(ORIGIN + Vector2(selected) * TILE, Vector2(TILE, TILE)), Color(1, 1, 0.2), false, 3.0)

	for m in mobs:
		var cp := cell_center(m.pos)
		var fill: Color = M.COLORS[m.mob_type]
		M.draw_mob(self, cp, m.mob_type, fill, Color(0.1, 0, 0))
		_draw_bar(cp + Vector2(-16, -22), 32, m.hp / m.max_hp, Color(0.9, 0.2, 0.2))

	for s in shots:
		var col := Color(1, 0.3, 0.2, 0.9) if s.enemy else Color(1, 0.95, 0.3, 0.9)
		draw_line(s.from, s.to, col, 3.0)

	if phase == Phase.GAME_OVER or phase == Phase.VICTORY:
		var box := Rect2(ORIGIN + Vector2(0, 5 * TILE), Vector2(COLS * TILE, 2 * TILE))
		draw_rect(box, Color(0, 0, 0, 0.75))
		draw_string(font, box.position + Vector2(0, 70), PHASE_NAMES[phase], HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 40, Color.WHITE)


func _draw_piece_shape(type: int, c: Vector2, level: int, hp_ratio: float, flash: float, font: Font, alpha: float) -> void:
	var base: Color = P.COLORS[type]
	base.a = alpha
	if flash > 0.0:
		base = base.lerp(Color(1, 0.2, 0.2, alpha), 0.6)
	if type == P.WALL:
		var r := Rect2(c - Vector2(24, 24), Vector2(48, 48))
		draw_rect(r, base)
		var line := Color(0.25, 0.25, 0.28, alpha)
		for i in [1, 2]:
			draw_line(r.position + Vector2(0, 16 * i), r.position + Vector2(48, 16 * i), line, 2.0)
		draw_line(c + Vector2(0, -24), c + Vector2(0, -8), line, 2.0)
		draw_line(c + Vector2(-12, -8), c + Vector2(-12, 8), line, 2.0)
		draw_line(c + Vector2(12, -8), c + Vector2(12, 8), line, 2.0)
		draw_line(c + Vector2(0, 8), c + Vector2(0, 24), line, 2.0)
		draw_rect(r, line, false, 2.0)
	else:
		draw_circle(c, 22, base)
		draw_arc(c, 22, 0, TAU, 32, Color(0.1, 0.1, 0.1, alpha), 2.0)
		draw_string(font, c + Vector2(-TILE / 2, 10), P.LETTERS[type], HORIZONTAL_ALIGNMENT_CENTER, TILE, 28, Color(0.08, 0.08, 0.1, alpha))
		for i in level:   # level pips
			draw_circle(c + Vector2(-16 + i * 8, 19), 3, Color(1, 1, 1, alpha))
	if hp_ratio < 1.0:
		_draw_bar(c + Vector2(-22, -27), 44, hp_ratio, Color(0.2, 0.85, 0.3))


func _draw_bar(p: Vector2, w: float, ratio: float, col: Color) -> void:
	draw_rect(Rect2(p, Vector2(w, 4)), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(p, Vector2(w * clampf(ratio, 0.0, 1.0), 4)), col)
