extends RefCounted
## Piece types, chess attack patterns, and balance tables filled from config/game_data.json.

enum { KING, QUEEN, ROOK, BISHOP, KNIGHT, PAWN, WALL }

const ID_BY_NAME := {
	"king": KING, "queen": QUEEN, "rook": ROOK, "bishop": BISHOP,
	"knight": KNIGHT, "pawn": PAWN, "wall": WALL,
}
const NAME_BY_ID := {
	KING: "king", QUEEN: "queen", ROOK: "rook", BISHOP: "bishop",
	KNIGHT: "knight", PAWN: "pawn", WALL: "wall",
}

## Build palette / hotkey order — filled by apply_data().
static var ORDER: Array = [PAWN, KNIGHT, BISHOP, ROOK, QUEEN, KING, WALL]
static var NAMES := {KING: "King", QUEEN: "Queen", ROOK: "Rook", BISHOP: "Bishop", KNIGHT: "Knight", PAWN: "Pawn", WALL: "Wall"}
static var LETTERS := {KING: "K", QUEEN: "Q", ROOK: "R", BISHOP: "B", KNIGHT: "N", PAWN: "P", WALL: ""}
static var COST := {KING: 0, QUEEN: 120, ROOK: 60, BISHOP: 50, KNIGHT: 45, PAWN: 20, WALL: 100}
static var DAMAGE := {KING: 5.0, QUEEN: 8.0, ROOK: 7.0, BISHOP: 6.0, KNIGHT: 12.0, PAWN: 6.0, WALL: 0.0}
static var COOLDOWN := {KING: 0.8, QUEEN: 0.8, ROOK: 0.9, BISHOP: 0.8, KNIGHT: 1.1, PAWN: 0.7, WALL: 0.0}
static var HP := {KING: 200.0, QUEEN: 60.0, ROOK: 60.0, BISHOP: 50.0, KNIGHT: 50.0, PAWN: 40.0, WALL: 100.0}
static var COLORS := {
	KING: Color(0.95, 0.78, 0.25), QUEEN: Color(0.85, 0.45, 0.9), ROOK: Color(0.35, 0.6, 0.95),
	BISHOP: Color(0.35, 0.85, 0.55), KNIGHT: Color(0.95, 0.55, 0.3), PAWN: Color(0.85, 0.85, 0.85),
	WALL: Color(0.5, 0.5, 0.55)}
static var MAX_LEVEL := 5
static var SYNERGY := {
	PAWN: {"dmg": 0.10}, KNIGHT: {"spd": 0.12}, BISHOP: {"range": 1}, ROOK: {"hp": 0.15},
	QUEEN: {"dmg": 0.05, "spd": 0.05, "hp": 0.05}, KING: {"dmg": 0.08, "spd": 0.08}, WALL: {},
}
static var SYNERGY_CAP := {"dmg": 0.5, "spd": 0.5, "hp": 0.6, "range": 2}
static var UPGRADE := {
	"damage_per_level": 0.6,
	"hp_per_level": 0.25,
	"wall_hp_per_level": 0.5,
	"cost_factor": 0.8,
	"cost_floor": 40,
	"slide_range_base": 2,
}

const ORTHO := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DIAG := [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]
const KNIGHT_JUMPS := [Vector2i(1, 2), Vector2i(2, 1), Vector2i(-1, 2), Vector2i(-2, 1),
	Vector2i(1, -2), Vector2i(2, -1), Vector2i(-1, -2), Vector2i(-2, -1)]
## Pawns face the mobs (top of the board = negative y) and capture diagonally forward.
const PAWN_CAPTURES := [Vector2i(-1, -1), Vector2i(1, -1)]
## Tower gap rule: Pawn support reaches two squares out.


static func apply_data(data: Dictionary) -> void:
	var pieces: Dictionary = data.get("pieces", {})
	var defs: Dictionary = pieces.get("defs", {})
	var order_ids: Array = pieces.get("order", [])
	ORDER = []
	for id in order_ids:
		var key := str(id).to_lower()
		if ID_BY_NAME.has(key):
			ORDER.append(ID_BY_NAME[key])
	if ORDER.is_empty():
		ORDER = [PAWN, KNIGHT, BISHOP, ROOK, QUEEN, KING, WALL]
	MAX_LEVEL = int(pieces.get("max_level", 5))
	NAMES = {}
	LETTERS = {}
	COST = {}
	DAMAGE = {}
	COOLDOWN = {}
	HP = {}
	COLORS = {}
	SYNERGY = {}
	for key in ID_BY_NAME:
		var t: int = ID_BY_NAME[key]
		var d: Dictionary = defs.get(key, {})
		NAMES[t] = str(d.get("name", key.capitalize()))
		LETTERS[t] = str(d.get("letter", ""))
		COST[t] = int(d.get("cost", 0))
		DAMAGE[t] = float(d.get("damage", 0.0))
		COOLDOWN[t] = float(d.get("cooldown", 0.0))
		HP[t] = float(d.get("hp", 1.0))
		COLORS[t] = _color(d.get("color", [0.8, 0.8, 0.8]))
		var syn: Dictionary = d.get("synergy", {})
		SYNERGY[t] = syn.duplicate(true) if syn is Dictionary else {}
	var cap: Dictionary = data.get("synergy_cap", {})
	SYNERGY_CAP = {
		"dmg": float(cap.get("dmg", 0.5)),
		"spd": float(cap.get("spd", 0.5)),
		"hp": float(cap.get("hp", 0.6)),
		"range": int(cap.get("range", 2)),
	}
	var up: Dictionary = data.get("upgrades", {})
	UPGRADE = {
		"damage_per_level": float(up.get("damage_per_level", 0.6)),
		"hp_per_level": float(up.get("hp_per_level", 0.25)),
		"wall_hp_per_level": float(up.get("wall_hp_per_level", 0.5)),
		"cost_factor": float(up.get("cost_factor", 0.8)),
		"cost_floor": int(up.get("cost_floor", 40)),
		"slide_range_base": int(up.get("slide_range_base", 2)),
	}


static func _color(v) -> Color:
	if v is Color:
		return v
	if v is Array and v.size() >= 3:
		var a := float(v[3]) if v.size() > 3 else 1.0
		return Color(float(v[0]), float(v[1]), float(v[2]), a)
	return Color(0.8, 0.8, 0.8)


static func level_text(level: int) -> String:
	return "Lv %d/%d" % [level, MAX_LEVEL]


static func damage(type: int, level: int) -> float:
	return DAMAGE[type] * (1.0 + float(UPGRADE.damage_per_level) * (level - 1))


static func max_hp(type: int, level: int) -> float:
	var per_level: float = float(UPGRADE.wall_hp_per_level) if type == WALL else float(UPGRADE.hp_per_level)
	return HP[type] * (1.0 + per_level * (level - 1))


static func upgrade_cost(type: int, level: int) -> int:
	return int(max(COST[type], int(UPGRADE.cost_floor)) * float(UPGRADE.cost_factor) * level)


## Max sliding distance for Rook/Bishop/Queen: grows with level (L1=3 ... L5=7 at defaults).
static func slide_range(level: int) -> int:
	return int(UPGRADE.slide_range_base) + level


static func is_tower(type: int) -> bool:
	return type != WALL


## Tiles a piece of `type` at `cell` may attack, like legal chess moves.
## `occupied` is any Dictionary keyed by Vector2i of board pieces (walls/towers):
## sliders stop BEFORE an occupied tile (own pieces block line of sight).
static func attack_tiles(
	type: int, cell: Vector2i, level: int, board_size: Vector2i, occupied: Dictionary, range_bonus: int = 0
) -> Array:
	var out: Array = []
	var rng := slide_range(level) + range_bonus
	match type:
		ROOK:
			_slide(out, cell, ORTHO, rng, board_size, occupied)
		BISHOP:
			_slide(out, cell, DIAG, rng, board_size, occupied)
		QUEEN:
			_slide(out, cell, ORTHO + DIAG, rng, board_size, occupied)
		KNIGHT:
			_jumps(out, cell, KNIGHT_JUMPS, board_size)
		KING:
			_jumps(out, cell, ORTHO + DIAG, board_size)
		PAWN:
			_jumps(out, cell, PAWN_CAPTURES, board_size)
	return out


static func is_slider(type: int) -> bool:
	return type == ROOK or type == BISHOP or type == QUEEN


## Squares a piece buffs for synergy — same chess attack pattern as combat
## (sliders use base slide_range only; first occupied square on each ray counts).
static func support_tiles(type: int, cell: Vector2i, level: int, board_size: Vector2i, occupied: Dictionary) -> Array:
	if type == WALL:
		return []
	if not is_slider(type):
		return attack_tiles(type, cell, level, board_size, occupied, 0)
	var out: Array = []
	var rng := slide_range(level)
	var dirs: Array = []
	match type:
		ROOK:
			dirs = ORTHO
		BISHOP:
			dirs = DIAG
		QUEEN:
			dirs = ORTHO + DIAG
	for d in dirs:
		for i in range(1, rng + 1):
			var c: Vector2i = cell + d * i
			if not _inside(c, board_size):
				break
			out.append(c)
			if occupied.has(c):
				break
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
