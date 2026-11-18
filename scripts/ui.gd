extends CanvasLayer
## HUD: responsive side panel + overlays; notifies Game to fit the board in the left pane.

const P := preload("res://scripts/pieces.gd")
const HS := preload("res://scripts/highscores.gd")
const DA := preload("res://scripts/draw_art.gd")

var game
var layout_root: Control
var board_host: Control
var hud_scroll: ScrollContainer
var hud_panel: PanelContainer
var lbl_stats: Label
var lbl_msg: Label
var build_buttons := {}
var btn_start: Button
var btn_upgrade: Button
var btn_sell: Button
var btn_restart: Button
var btn_dialog_castle: Button
var btn_dialog_close: Button
var btn_leaderboard: Button
var piece_dimmer: ColorRect
var piece_dialog: PanelContainer
var lbl_piece_title: Label
var lbl_piece_body: Label
var _piece_dialog_open := false
var overlay_final: PanelContainer
var overlay_leaderboard: PanelContainer
var lbl_final_body: Label
var lbl_leaderboard_body: Label
var _end_overlay_shown := false
var _ui_styles: Dictionary = {}


func _ready() -> void:
	game = get_parent().get_node("Game")
	_ui_styles = DA.make_ui_styles()
	_build_responsive_shell()
	call_deferred("_refresh_layout")


func _build_responsive_shell() -> void:
	layout_root = Control.new()
	layout_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layout_root)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 8)
	layout_root.add_child(hbox)

	board_host = Control.new()
	board_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(board_host)

	hud_scroll = ScrollContainer.new()
	hud_scroll.custom_minimum_size = Vector2(228, 0)
	hud_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hud_scroll.size_flags_horizontal = Control.SIZE_SHRINK_END
	hud_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hbox.add_child(hud_scroll)

	hud_panel = PanelContainer.new()
	hud_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud_panel.custom_minimum_size = Vector2(228, 0)
	hud_panel.add_theme_stylebox_override("panel", _ui_styles.panel)
	hud_scroll.add_child(hud_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	hud_panel.add_child(v)

	v.add_child(_label("ChessTD : Protect the King", 18, true))
	lbl_stats = _label("", 15)
	v.add_child(lbl_stats)
	v.add_child(HSeparator.new())
	v.add_child(_label("Build (click a tile on your side):", 13, false))
	var grid := GridContainer.new()
	grid.columns = 2
	v.add_child(grid)
	var group := ButtonGroup.new()
	group.allow_unpress = true
	for i in P.ORDER.size():
		var t: int = P.ORDER[i]
		var b := _button("%d %s %dg" % [i + 1, P.NAMES[t], P.COST[t]])
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_on_build.bind(t))
		build_buttons[t] = b
		grid.add_child(b)
	v.add_child(HSeparator.new())
	btn_start = _button("Start Wave  [Space]")
	btn_start.pressed.connect(func(): game.start_wave())
	v.add_child(btn_start)
	v.add_child(HSeparator.new())
	lbl_msg = _label("", 13)
	lbl_msg.add_theme_color_override("font_color", Color(0.98, 0.86, 0.52))
	v.add_child(lbl_msg)
	v.add_child(
		_label(
			"Left-click: place / select piece   Right-click: cancel\nPiece menu pauses the game.  Esc closes it.",
			11, false, DA.UI_TEXT_DIM
		)
	)
	btn_leaderboard = _button("Leaderboard [L]")
	btn_leaderboard.pressed.connect(toggle_leaderboard)
	v.add_child(btn_leaderboard)
	btn_restart = _button("Restart")
	btn_restart.pressed.connect(_on_restart)
	v.add_child(btn_restart)

	overlay_final = _overlay_panel()
	overlay_final.z_index = 5
	lbl_final_body = _overlay_label(overlay_final)
	overlay_leaderboard = _overlay_panel()
	overlay_leaderboard.z_index = 4
	lbl_leaderboard_body = _overlay_label(overlay_leaderboard)
	var lb_close := _button("Close [L / Esc]")
	lb_close.pressed.connect(func(): overlay_leaderboard.visible = false)
	overlay_leaderboard.get_child(0).add_child(lb_close)

	_build_piece_dialog()

	get_viewport().size_changed.connect(_refresh_layout)


func _build_piece_dialog() -> void:
	piece_dimmer = ColorRect.new()
	piece_dimmer.color = Color(0.04, 0.05, 0.07, 0.62)
	piece_dimmer.visible = false
	piece_dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	piece_dimmer.z_index = 6
	add_child(piece_dimmer)

	piece_dialog = PanelContainer.new()
	piece_dialog.visible = false
	piece_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	piece_dialog.z_index = 7
	var dlg_style: StyleBoxFlat = _ui_styles.panel.duplicate()
	dlg_style.bg_color = Color(0.08, 0.09, 0.12, 0.97)
	dlg_style.border_width_left = 2
	dlg_style.border_width_top = 2
	dlg_style.border_width_right = 2
	dlg_style.border_width_bottom = 2
	dlg_style.border_color = DA.UI_BORDER
	piece_dialog.add_theme_stylebox_override("panel", dlg_style)
	add_child(piece_dialog)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	piece_dialog.add_child(box)

	lbl_piece_title = _label("Piece", 17, true)
	box.add_child(lbl_piece_title)
	lbl_piece_body = _label("", 14)
	box.add_child(lbl_piece_body)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	btn_upgrade = _button("Upgrade [U]")
	btn_upgrade.pressed.connect(_dialog_upgrade)
	btn_sell = _button("Sell [S]")
	btn_sell.pressed.connect(_dialog_sell)
	row.add_child(btn_upgrade)
	row.add_child(btn_sell)
	box.add_child(row)

	btn_dialog_castle = _button("Castle [C]")
	btn_dialog_castle.pressed.connect(_dialog_castle)
	box.add_child(btn_dialog_castle)

	btn_dialog_close = _button("Close [Esc]")
	btn_dialog_close.pressed.connect(close_piece_options)
	box.add_child(btn_dialog_close)


func _refresh_layout() -> void:
	if layout_root == null or board_host == null or game == null:
		return
	call_deferred("_apply_layout")


func _apply_layout() -> void:
	if layout_root == null or board_host == null or game == null:
		return
	var vp := get_viewport().get_visible_rect()
	layout_root.set_deferred("size", vp.size)
	var board_rect := board_host.get_global_rect()
	if board_rect.size.x < 1.0:
		board_rect = Rect2(Vector2.ZERO, Vector2(vp.size.x - hud_scroll.size.x, vp.size.y))
	game.fit_to_rect(board_rect)
	_position_overlays(vp)
	_position_piece_dialog(vp)


func apply_layout_now() -> void:
	if layout_root == null:
		return
	var vp := get_viewport().get_visible_rect()
	layout_root.size = vp.size
	layout_root.get_parent()  # flush
	var board_rect := board_host.get_global_rect()
	game.fit_to_rect(board_rect)
	_position_overlays(vp)
	_position_piece_dialog(vp)


func _position_overlays(vp: Rect2) -> void:
	var board_r: Rect2 = game.board_viewport_rect()
	var final_sz := Vector2(minf(400, vp.size.x * 0.55), minf(220, vp.size.y * 0.35))
	overlay_final.custom_minimum_size = final_sz
	overlay_final.size = final_sz
	overlay_final.position = board_r.position + (board_r.size - final_sz) * 0.5
	var lb_sz := Vector2(minf(480, vp.size.x * 0.82), minf(560, vp.size.y * 0.88))
	overlay_leaderboard.custom_minimum_size = lb_sz
	overlay_leaderboard.size = lb_sz
	overlay_leaderboard.position = (vp.size - lb_sz) * 0.5


func _position_piece_dialog(vp: Rect2) -> void:
	if piece_dimmer == null:
		return
	piece_dimmer.position = Vector2.ZERO
	piece_dimmer.size = vp.size
	var dlg_sz := Vector2(minf(320, vp.size.x * 0.9), minf(300, vp.size.y * 0.55))
	piece_dialog.custom_minimum_size = dlg_sz
	piece_dialog.size = dlg_sz
	piece_dialog.position = (vp.size - dlg_sz) * 0.5


func piece_options_open() -> bool:
	return _piece_dialog_open


func open_piece_options(c: Vector2i) -> void:
	var p = game.get_piece(c)
	if p == null:
		return
	game.selected = c
	_piece_dialog_open = true
	piece_dimmer.visible = true
	piece_dialog.visible = true
	get_tree().paused = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	_refresh_piece_dialog()


func close_piece_options() -> void:
	if not _piece_dialog_open:
		return
	_piece_dialog_open = false
	piece_dimmer.visible = false
	piece_dialog.visible = false
	get_tree().paused = false
	process_mode = Node.PROCESS_MODE_INHERIT


func _refresh_piece_dialog() -> void:
	var p = game.get_piece(game.selected)
	if p == null:
		close_piece_options()
		return
	lbl_piece_title.text = "%s  ·  Level %d" % [P.NAMES[p.type], p.level]
	var lines: PackedStringArray = ["HP: %d / %d" % [ceili(p.hp), ceili(p.max_hp)]]
	if P.is_tower(p.type):
		lines.append("Damage: %.1f every %.1fs" % [P.damage(p.type, p.level), P.COOLDOWN[p.type]])
		if p.level < P.MAX_LEVEL:
			lines.append(
				"Next level: %.1f damage  ·  %dg" % [P.damage(p.type, p.level + 1), P.upgrade_cost(p.type, p.level)]
			)
		else:
			lines.append("Damage: max level")
	elif p.type == P.WALL:
		if p.level < P.MAX_LEVEL:
			lines.append(
				"Next level: %d HP  ·  %dg" % [ceili(P.max_hp(P.WALL, p.level + 1)), P.upgrade_cost(p.type, p.level)]
			)
		else:
			lines.append("Wall: max level")
	if p.level < P.MAX_LEVEL and not P.is_tower(p.type) and p.type != P.WALL:
		lines.append("Upgrade cost: %dg" % P.upgrade_cost(p.type, p.level))
	lbl_piece_body.text = "\n".join(lines)
	btn_upgrade.disabled = p.level >= P.MAX_LEVEL or game.gold < P.upgrade_cost(p.type, p.level)
	btn_sell.disabled = p.type == P.KING and game.phase != game.Phase.SETUP
	var show_castle: bool = (
		not game.castling_used
		and (p.type == P.KING or p.type == P.ROOK)
		and not game.castle_rooks_eligible().is_empty()
	)
	btn_dialog_castle.visible = show_castle
	btn_dialog_castle.disabled = not show_castle


func _dialog_upgrade() -> void:
	if game.upgrade(game.selected):
		_refresh_piece_dialog()


func _dialog_sell() -> void:
	if game.sell(game.selected):
		close_piece_options()


func _dialog_castle() -> void:
	if game.try_castle():
		_refresh_piece_dialog()


func _controls_inside_viewport() -> bool:
	var vp := get_viewport().get_visible_rect()
	if hud_scroll == null:
		return true
	var hud_r := hud_scroll.get_global_rect()
	if hud_r.position.y < -1.0:
		return false
	if hud_r.end.y > vp.size.y + 2.0:
		return false
	if hud_r.end.x > vp.size.x + 2.0:
		return false
	return true


func _label(text: String, size: int, title: bool = false, col: Color = DA.UI_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_color_override("font_color", DA.UI_ACCENT if title else col)
	return l


func _overlay_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.visible = false
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(p)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	p.add_child(box)
	var style: StyleBoxFlat = DA.make_ui_styles().panel.duplicate()
	style.bg_color = Color(0.06, 0.07, 0.09, 0.94)
	p.add_theme_stylebox_override("panel", style)
	return p


func _overlay_label(panel: PanelContainer) -> Label:
	var box: VBoxContainer = panel.get_child(0)
	var t := _label("", 14)
	box.add_child(t)
	return t


func _on_restart() -> void:
	close_piece_options()
	overlay_final.visible = false
	_end_overlay_shown = false
	game.reset()
	_refresh_leaderboard_text()


func toggle_leaderboard() -> void:
	overlay_leaderboard.visible = not overlay_leaderboard.visible
	if overlay_leaderboard.visible:
		_refresh_leaderboard_text()


func _refresh_leaderboard_text() -> void:
	var lines: PackedStringArray = ["TOP SCORES (local)", " #   SCORE  WAVE  RESULT  DATE", ""]
	var rows := HS.load_entries()
	if rows.is_empty():
		lines.append("No scores yet — finish a run!")
	else:
		for i in rows.size():
			var e: Dictionary = HS.normalize_entry(rows[i])
			var tag := "WIN" if e.result == "win" else "LOSS"
			lines.append("%2d.  %5d  W%-2d  %s  %s" % [i + 1, e.score, e.waves, tag, e.datetime])
	lbl_leaderboard_body.text = "\n".join(lines)


func _refresh_final_overlay() -> void:
	var title := "VICTORY" if game.phase == game.Phase.VICTORY else "GAME OVER"
	var res: String = game.match_result if game.match_result != "" else ("win" if game.phase == game.Phase.VICTORY else "loss")
	lbl_final_body.text = (
		"%s\n\nFinal score: %d\n(+%d from kills, +%d from waves)\nWaves reached: %d / %d\nResult: %s\n\nPress Leaderboard [L] or Restart."
		% [
			title, game.score, game.score_from_kills, game.score_from_waves,
			game.wave, game.MAX_WAVES, res.to_upper(),
		]
	)
	overlay_final.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if _piece_dialog_open:
			match event.keycode:
				KEY_ESCAPE, KEY_ENTER:
					close_piece_options()
					get_viewport().set_input_as_handled()
				KEY_U:
					_dialog_upgrade()
					get_viewport().set_input_as_handled()
				KEY_S, KEY_DELETE:
					_dialog_sell()
					get_viewport().set_input_as_handled()
				KEY_C:
					_dialog_castle()
					get_viewport().set_input_as_handled()
			return
		match event.keycode:
			KEY_L:
				toggle_leaderboard()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				if overlay_leaderboard.visible:
					overlay_leaderboard.visible = false
					get_viewport().set_input_as_handled()
				else:
					game.selected = Vector2i(-1, -1)
					game.build_type = -1
					get_viewport().set_input_as_handled()
			KEY_U:
				if game.get_piece(game.selected) != null:
					open_piece_options(game.selected)
				get_viewport().set_input_as_handled()
			KEY_S, KEY_DELETE:
				if game.sell(game.selected):
					get_viewport().set_input_as_handled()
			KEY_C:
				game.try_castle()
				get_viewport().set_input_as_handled()


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_stylebox_override("normal", _ui_styles.btn_normal)
	b.add_theme_stylebox_override("hover", _ui_styles.btn_hover)
	b.add_theme_stylebox_override("pressed", _ui_styles.btn_pressed)
	b.add_theme_stylebox_override("disabled", _ui_styles.btn_disabled)
	b.add_theme_color_override("font_color", DA.UI_TEXT)
	b.add_theme_color_override("font_hover_color", DA.UI_TEXT)
	b.add_theme_color_override("font_pressed_color", DA.UI_ACCENT)
	b.add_theme_color_override("font_disabled_color", DA.UI_TEXT_DIM)
	return b


func _on_build(t: int) -> void:
	close_piece_options()
	game.build_type = t if build_buttons[t].button_pressed else -1
	game.selected = Vector2i(-1, -1)


func _process(_delta: float) -> void:
	var king_hp := "-"
	if game.has_king():
		var k = game.pieces[game.king_cell]
		king_hp = "%d / %d" % [ceili(k.hp), ceili(k.max_hp)]
	var castle_txt := "used" if game.castling_used else ("available" if game.castle_rooks_eligible().size() > 0 else "unavailable")
	lbl_stats.text = (
		"Gold: %d\nScore: %d  (+%d kills, +%d waves)\nKing HP (lives): %s\nWave: %d / %d\nPhase: %s\nCastling: %s\nMobs: %d alive, %d to spawn\nKills: %d"
		% [
			game.gold, game.score, game.score_from_kills, game.score_from_waves,
			king_hp, game.wave, game.MAX_WAVES, game.PHASE_NAMES[game.phase], castle_txt,
			game.mobs.size(), game.spawn_left, game.kills,
		]
	)
	if (game.phase == game.Phase.GAME_OVER or game.phase == game.Phase.VICTORY) and not _end_overlay_shown:
		_end_overlay_shown = true
		_refresh_final_overlay()
		overlay_leaderboard.visible = true
		_refresh_leaderboard_text()
	for t in build_buttons:
		var b: Button = build_buttons[t]
		b.set_pressed_no_signal(game.build_type == t)
		b.disabled = game.gold < P.COST[t] or (t == P.KING and game.has_king())
	btn_start.disabled = not (game.phase == game.Phase.SETUP or game.phase == game.Phase.BETWEEN) or not game.has_king()
	if _piece_dialog_open:
		_refresh_piece_dialog()
	if game.build_type >= 0 and game.in_bounds(game.hover):
		var err: String = game.can_place(game.build_type, game.hover)
		lbl_msg.text = err if err != "" else game.last_message
	else:
		lbl_msg.text = game.last_message