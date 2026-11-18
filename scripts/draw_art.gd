extends RefCounted
## Vector-only drawing helpers: board theme, piece silhouettes, bars and pips.

const P := preload("res://scripts/pieces.gd")

const BG_DARK := Color(0.11, 0.12, 0.15)
const SQ_LIGHT := Color(0.90, 0.88, 0.82)
const SQ_DARK := Color(0.58, 0.54, 0.48)
const SPAWN_LIGHT := Color(0.86, 0.62, 0.62)
const SPAWN_DARK := Color(0.68, 0.38, 0.38)
const GRID_LINE := Color(0.22, 0.20, 0.18, 0.45)
const FRAME_LINE := Color(0.18, 0.16, 0.14)
const SPAWN_DIVIDER := Color(0.72, 0.22, 0.22, 0.85)

const UI_PANEL_BG := Color(0.10, 0.11, 0.13, 0.96)
const UI_BORDER := Color(0.48, 0.46, 0.42)
const UI_ACCENT := Color(0.78, 0.68, 0.42)
const UI_BUTTON_BG := Color(0.20, 0.22, 0.26)
const UI_BUTTON_HOVER := Color(0.28, 0.30, 0.35)
const UI_BUTTON_PRESSED := Color(0.34, 0.36, 0.42)
const UI_BUTTON_DISABLED := Color(0.16, 0.17, 0.19)
const UI_TEXT := Color(0.93, 0.91, 0.87)
const UI_TEXT_DIM := Color(0.72, 0.70, 0.66)

const ATTACK_FILL := Color(0.92, 0.28, 0.22, 0.22)
const ATTACK_RING := Color(0.85, 0.15, 0.12, 0.55)
const HOVER_OK := Color(0.35, 0.78, 0.45, 0.28)
const HOVER_BAD := Color(0.92, 0.18, 0.18, 0.32)
const SELECT_RING := Color(0.98, 0.88, 0.28)
const CASTLE_FILL := Color(0.28, 0.58, 0.95, 0.32)
const CASTLE_BORDER := Color(0.35, 0.65, 1.0, 0.9)
const SYNERGY_LINE := Color(1.0, 0.84, 0.32, 0.30)
const SYNERGY_LINE_STRONG := Color(1.0, 0.86, 0.35, 0.85)
const SYNERGY_GLOW := Color(1.0, 0.85, 0.35, 0.10)
const SYNERGY_GLOW_STRONG := Color(1.0, 0.85, 0.35, 0.22)
const STAT_TEXT := Color(0.98, 0.97, 0.94)
const STAT_OUTLINE := Color(0.06, 0.06, 0.08, 0.95)
const BUFF_TEXT := Color(1.0, 0.86, 0.4)


static func _a(col: Color, alpha: float) -> Color:
	var c := col
	c.a *= alpha
	return c


static func _lerp_flash(col: Color, flash: float) -> Color:
	if flash <= 0.0:
		return col
	return col.lerp(Color(1.0, 0.35, 0.25, col.a), clampf(flash / 0.18, 0.0, 0.75))


static func _xf(center: Vector2, pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(pts.size())
	for i in pts.size():
		out[i] = center + pts[i]
	return out


static func _outline_poly(canvas: CanvasItem, pts: PackedVector2Array, col: Color, w: float = 1.8) -> void:
	var closed := pts.duplicate()
	closed.append(pts[0])
	canvas.draw_polyline(closed, col, w)


static func hp_text(hp: float, max_hp: float) -> String:
	return "%d/%d" % [maxi(0, ceili(hp)), ceili(max_hp)]


static func _stat_string(canvas: CanvasItem, pos: Vector2, text: String, size: int, width: float,
		align: int, col: Color = STAT_TEXT) -> void:
	var font := ThemeDB.fallback_font
	canvas.draw_string_outline(font, pos, text, align, width, size, 3, STAT_OUTLINE)
	canvas.draw_string(font, pos, text, align, width, size, col)


## HP bar; when `text` is given it is drawn centred inside the bar (bar should be >= 9 px tall).
static func draw_hp_bar(canvas: CanvasItem, p: Vector2, w: float, ratio: float, col: Color, h: float = 5.0, text: String = "") -> void:
	var rr := clampf(ratio, 0.0, 1.0)
	canvas.draw_rect(Rect2(p, Vector2(w, h)), Color(0.05, 0.05, 0.06, 0.85))
	canvas.draw_rect(Rect2(p, Vector2(w, h)).grow(-0.5), Color(0.25, 0.25, 0.28, 0.9), false, 1.0)
	if rr > 0.001:
		canvas.draw_rect(Rect2(p + Vector2(1, 1), Vector2((w - 2) * rr, h - 2)), col)
	if text != "":
		var fs := int(maxf(7.0, h - 1.0))
		_stat_string(canvas, p + Vector2(0, h - 1.5), text, fs, w, HORIZONTAL_ALIGNMENT_CENTER)


## Small vector sword (blade, guard, grip, pommel) with its tip pointing up-right.
static func draw_weapon_icon(canvas: CanvasItem, c: Vector2, s: float = 1.0, col: Color = Color(0.86, 0.88, 0.93)) -> void:
	var ink := Color(0.1, 0.1, 0.12, 0.95)
	var d := Vector2(0.7071, -0.7071)
	var n := Vector2(0.7071, 0.7071)
	var tip := c + d * 6.0 * s
	var base := c - d * 1.5 * s
	var blade := PackedVector2Array([tip, base + n * 1.6 * s, base - n * 1.6 * s])
	canvas.draw_colored_polygon(blade, col)
	_outline_poly(canvas, blade, ink, 1.0)
	canvas.draw_line(base + n * 3.2 * s, base - n * 3.2 * s, Color(0.78, 0.62, 0.3), 2.0 * s)
	canvas.draw_line(base, c - d * 4.5 * s, Color(0.45, 0.3, 0.2), 1.8 * s)
	canvas.draw_circle(c - d * 5.2 * s, 1.3 * s, Color(0.78, 0.62, 0.3))


## Weapon icon followed by the damage value; `left_base` is the left edge at the text baseline.
static func draw_weapon_stat(canvas: CanvasItem, left_base: Vector2, dmg: float, buffed: bool = false) -> void:
	draw_weapon_icon(canvas, left_base + Vector2(5, -4), 0.9)
	var txt := ("%.0f" % dmg) if dmg >= 10.0 else ("%.1f" % dmg)
	_stat_string(canvas, left_base + Vector2(11, 0), txt, 9, 24, HORIZONTAL_ALIGNMENT_LEFT, BUFF_TEXT if buffed else STAT_TEXT)


## "level/max" right-aligned at `right_base` (right edge, baseline).
static func draw_level_badge(canvas: CanvasItem, right_base: Vector2, level: int, max_level: int) -> void:
	_stat_string(canvas, right_base - Vector2(26, 0), "%d/%d" % [level, max_level], 9, 26, HORIZONTAL_ALIGNMENT_RIGHT)


## Dashed link from a supporter to a buffed piece, ending in a small diamond.
static func draw_synergy_link(canvas: CanvasItem, from: Vector2, to: Vector2, tile: float, strong: bool) -> void:
	var col := SYNERGY_LINE_STRONG if strong else SYNERGY_LINE
	var dir := (to - from)
	var dist := dir.length()
	if dist < 1.0:
		return
	dir /= dist
	var a := from + dir * tile * 0.3
	var b := to - dir * tile * 0.3
	canvas.draw_dashed_line(a, b, col, 2.0 if strong else 1.5, 5.0)
	var nrm := Vector2(-dir.y, dir.x) * 3.5
	canvas.draw_colored_polygon(PackedVector2Array([b + dir * 4.0, b + nrm, b - dir * 4.0, b - nrm]), col)


static func draw_piece(
	canvas: CanvasItem, center: Vector2, type: int, fill: Color, alpha: float, flash: float = 0.0
) -> void:
	fill = _lerp_flash(_a(fill, alpha), flash)
	var ink := _a(Color(0.12, 0.11, 0.14), alpha)
	if type == P.WALL:
		_draw_wall(canvas, center, fill, ink, alpha)
		return
	# Pedestal shared by chess silhouettes
	var base := _xf(center, PackedVector2Array([
		Vector2(-14, 16), Vector2(14, 16), Vector2(11, 10), Vector2(-11, 10),
	]))
	canvas.draw_colored_polygon(base, fill.darkened(0.08))
	_outline_poly(canvas, base, ink)
	match type:
		P.PAWN:
			var body := _xf(center, PackedVector2Array([
				Vector2(-7, 10), Vector2(7, 10), Vector2(5, 0), Vector2(-5, 0),
			]))
			canvas.draw_colored_polygon(body, fill)
			_outline_poly(canvas, body, ink)
			canvas.draw_circle(center + Vector2(0, -8), 7.0, fill)
			canvas.draw_arc(center + Vector2(0, -8), 7.0, 0, TAU, 20, ink, 1.8)
		P.ROOK:
			var body := _xf(center, PackedVector2Array([
				Vector2(-11, 10), Vector2(11, 10), Vector2(11, -2), Vector2(-11, -2),
			]))
			canvas.draw_colored_polygon(body, fill)
			_outline_poly(canvas, body, ink)
			for i in 3:
				var x := -10.0 + i * 10.0
				var cren := _xf(center, PackedVector2Array([
					Vector2(x - 3.5, -2), Vector2(x + 3.5, -2), Vector2(x + 3.5, -12), Vector2(x - 3.5, -12),
				]))
				canvas.draw_colored_polygon(cren, fill.lightened(0.05))
				_outline_poly(canvas, cren, ink, 1.4)
		P.BISHOP:
			var body := _xf(center, PackedVector2Array([
				Vector2(-10, 10), Vector2(10, 10), Vector2(8, -4), Vector2(0, -14), Vector2(-8, -4),
			]))
			canvas.draw_colored_polygon(body, fill)
			_outline_poly(canvas, body, ink)
			canvas.draw_line(center + Vector2(-5, -2), center + Vector2(6, 8), _a(Color(0.05, 0.05, 0.08), alpha), 2.0)
		P.KNIGHT:
			var head := _xf(center, PackedVector2Array([
				Vector2(-12, 10), Vector2(4, 10), Vector2(14, 4), Vector2(12, -6),
				Vector2(4, -12), Vector2(-6, -10), Vector2(-10, -2), Vector2(-14, 2),
			]))
			canvas.draw_colored_polygon(head, fill)
			_outline_poly(canvas, head, ink)
			canvas.draw_circle(center + Vector2(6, -2), 2.2, ink)
		P.KING:
			var body := _xf(center, PackedVector2Array([
				Vector2(-10, 10), Vector2(10, 10), Vector2(9, -2), Vector2(-9, -2),
			]))
			canvas.draw_colored_polygon(body, fill)
			_outline_poly(canvas, body, ink)
			var cross_v := _xf(center, PackedVector2Array([
				Vector2(-2.5, -2), Vector2(2.5, -2), Vector2(2.5, -16), Vector2(-2.5, -16),
			]))
			var cross_h := _xf(center, PackedVector2Array([
				Vector2(-7, -8), Vector2(7, -8), Vector2(7, -11), Vector2(-7, -11),
			]))
			canvas.draw_colored_polygon(cross_v, fill.lightened(0.06))
			canvas.draw_colored_polygon(cross_h, fill.lightened(0.06))
			_outline_poly(canvas, cross_v, ink, 1.4)
			_outline_poly(canvas, cross_h, ink, 1.4)
		P.QUEEN:
			var body := _xf(center, PackedVector2Array([
				Vector2(-11, 10), Vector2(11, 10), Vector2(10, 0), Vector2(-10, 0),
			]))
			canvas.draw_colored_polygon(body, fill)
			_outline_poly(canvas, body, ink)
			var crown := _xf(center, PackedVector2Array([
				Vector2(-14, 0), Vector2(-10, -14), Vector2(-5, -4), Vector2(0, -16),
				Vector2(5, -4), Vector2(10, -14), Vector2(14, 0),
			]))
			canvas.draw_colored_polygon(crown, fill.lightened(0.08))
			canvas.draw_polyline(crown, ink, 1.8)
			for i in 5:
				canvas.draw_circle(crown[i] + Vector2(0, -1.5), 1.8, _a(Color(0.95, 0.85, 0.35), alpha))
		_:
			canvas.draw_circle(center, 18, fill)
			canvas.draw_arc(center, 18, 0, TAU, 24, ink, 2.0)


static func _draw_wall(canvas: CanvasItem, center: Vector2, fill: Color, ink: Color, alpha: float) -> void:
	var r := Rect2(center - Vector2(22, 22), Vector2(44, 44))
	canvas.draw_rect(r, fill)
	var mortar := _a(Color(0.28, 0.28, 0.32), alpha)
	for row in 3:
		for col in 3:
			var br := Rect2(
				r.position + Vector2(2 + col * 14, 2 + row * 14), Vector2(12, 12)
			)
			canvas.draw_rect(br, fill.lightened(-0.04 + row * 0.02))
			canvas.draw_rect(br, mortar, false, 1.2)
	canvas.draw_rect(r, ink, false, 2.0)


static func make_ui_styles() -> Dictionary:
	var panel := StyleBoxFlat.new()
	panel.bg_color = UI_PANEL_BG
	panel.border_color = UI_BORDER
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(6)
	panel.content_margin_left = 14
	panel.content_margin_right = 14
	panel.content_margin_top = 12
	panel.content_margin_bottom = 12

	var btn_n := StyleBoxFlat.new()
	btn_n.bg_color = UI_BUTTON_BG
	btn_n.border_color = UI_BORDER.darkened(0.15)
	btn_n.set_border_width_all(1)
	btn_n.set_corner_radius_all(4)
	btn_n.content_margin_left = 8
	btn_n.content_margin_right = 8
	btn_n.content_margin_top = 6
	btn_n.content_margin_bottom = 6

	var btn_h := btn_n.duplicate()
	btn_h.bg_color = UI_BUTTON_HOVER
	var btn_p := btn_n.duplicate()
	btn_p.bg_color = UI_BUTTON_PRESSED
	var btn_d := btn_n.duplicate()
	btn_d.bg_color = UI_BUTTON_DISABLED
	btn_d.border_color = UI_BORDER.darkened(0.3)

	return {
		"panel": panel,
		"btn_normal": btn_n,
		"btn_hover": btn_h,
		"btn_pressed": btn_p,
		"btn_disabled": btn_d,
	}