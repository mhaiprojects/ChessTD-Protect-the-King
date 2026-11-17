extends RefCounted
## Static piece data + chess attack patterns (pure functions, no game state).

enum { KING, QUEEN, ROOK, BISHOP, KNIGHT, PAWN, WALL }

const ORDER := [KING, QUEEN, ROOK, BISHOP, KNIGHT, PAWN, WALL]
const NAMES := {KING: "King", QUEEN: "Queen", ROOK: "Rook", BISHOP: "Bishop", KNIGHT: "Knight", PAWN: "Pawn", WALL: "Wall"}
const LETTERS := {KING: "K", QUEEN: "Q", ROOK: "R", BISHOP: "B", KNIGHT: "N", PAWN: "P", WALL: ""}
const COST := {KING: 0, QUEEN: 120, ROOK: 60, BISHOP: 50, KNIGHT: 45, PAWN: 20, WALL: 10}
const DAMAGE := {KING: 5.0, QUEEN: 8.0, ROOK: 7.0, BISHOP: 6.0, KNIGHT: 12.0, PAWN: 6.0, WALL: 0.0}
const COOLDOWN := {KING: 0.8, QUEEN: 0.8, ROOK: 0.9, BISHOP: 0.8, KNIGHT: 1.1, PAWN: 0.7, WALL: 0.0}
const HP := {KING: 200.0, QUEEN: 60.0, ROOK: 60.0, BISHOP: 50.0, KNIGHT: 50.0, PAWN: 40.0, WALL: 100.0}
const COLORS := {
	KING: Color(0.95, 0.78, 0.25), QUEEN: Color(0.85, 0.45, 0.9), ROOK: Color(0.35, 0.6, 0.95),
	BISHOP: Color(0.35, 0.85, 0.55), KNIGHT: Color(0.95, 0.55, 0.3), PAWN: Color(0.85, 0.85, 0.85),
	WALL: Color(0.5, 0.5, 0.55)}
const MAX_LEVEL := 5

const ORTHO := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DIAG := [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]
const KNIGHT_JUMPS := [Vector2i(1, 2), Vector2i(2, 1), Vector2i(-1, 2), Vector2i(-2, 1),
	Vector2i(1, -2), Vector2i(2, -1), Vector2i(-1, -2), Vector2i(-2, -1)]
## Pawns face the mobs (top of the board = negative y) and capture diagonally forward.
const PAWN_CAPTURES := [Vector2i(-1, -1), Vector2i(1, -1)]


static func damage(type: int, level: int) -> float:
	return DAMAGE[type] * (1.0 + 0.6 * (level - 1))


static func max_hp(type: int, level: int) -> float:
	var per_level := 0.5 if type == WALL else 0.25
	return HP[type] * (1.0 + per_level * (level - 1))


static func upgrade_cost(type: int, level: int) -> int:
	return int(max(COST[type], 40) * 0.8 * level)


## Max sliding distance for Rook/Bishop/Queen: grows with level (L1=3 ... L5=7).
static func slide_range(level: int) -> int:
	return 2 + level


static func is_tower(type: int) -> bool:
	return type != WALL


## Tiles a piece of `type` at `cell` may attack, like legal chess moves.
## `occupied` is any Dictionary keyed by Vector2i of board pieces (walls/towers):
## sliders stop BEFORE an occupied tile (own pieces block line of sight).
static func attack_tiles(type: int, cell: Vector2i, level: int, board_size: Vector2i, occupied: Dictionary) -> Array:
	var out: Array = []
	match type:
		ROOK:
			_slide(out, cell, ORTHO, slide_range(level), board_size, occupied)
		BISHOP:
			_slide(out, cell, DIAG, slide_range(level), board_size, occupied)
		QUEEN:
			_slide(out, cell, ORTHO + DIAG, slide_range(level), board_size, occupied)
		KNIGHT:
			_jumps(out, cell, KNIGHT_JUMPS, board_size)
		KING:
			_jumps(out, cell, ORTHO + DIAG, board_size)
		PAWN:
			_jumps(out, cell, PAWN_CAPTURES, board_size)
	return out


static func _inside(c: Vector2i, size: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y


static func _slide(out: Array, cell: Vector2i, dirs: Array, rng: int, size: Vector2i, occupied: Dictionary) -> void:
	for d in dirs:
		for i in range(1, rng + 1):
			var c: Vector2i = cell + d * i
			if not _inside(c, size) or occupied.has(c):
				break
			out.append(c)


static func _jumps(out: Array, cell: Vector2i, offsets: Array, size: Vector2i) -> void:
	for o in offsets:
		var c: Vector2i = cell + o
		if _inside(c, size):
			out.append(c)
