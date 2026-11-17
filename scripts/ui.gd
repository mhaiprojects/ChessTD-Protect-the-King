extends CanvasLayer
## Side panel HUD built in code: stats, build palette, wave/upgrade/sell controls.

const P := preload("res://scripts/pieces.gd")
const HS := preload("res://scripts/highscores.gd")
const DA := preload("res://scripts/draw_art.gd")

var game
var lbl_stats: Label
var lbl_sel: Label
var lbl_msg: Label
var build_buttons := {}
var btn_start: Button
var btn_upgrade: Button
var btn_sell: Button
var btn_restart: Button
var btn_castle: Button
var btn_leaderboard: Button
var overlay_final: PanelContainer
var overlay_leaderboard: PanelContainer
var lbl_final_body: Label
var lbl_leaderboard_body: Label
var _end_overlay_shown := false
var _ui_styles: Dictionary = {}


func _ready() -> void:
	game = get_parent().get_node("Game")
	_ui_styles = DA.make_ui_styles()
	var panel := PanelContainer.new()
	panel.position = Vector2(480, 16)
	panel.custom_minimum_size = Vector2(264, 672)
	panel.add_theme_stylebox_override("panel", _ui_styles.panel)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)

	v.add_child(_label("CHESS TOWER DEFENSE", 18, true))
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
	lbl_sel = _label("", 13)
	v.add_child(lbl_sel)
	var h := HBoxContainer.new()
	btn_upgrade = _button("Upgrade [U]")
	btn_upgrade.pressed.connect(func(): game.upgrade(game.selected))
	btn_sell = _button("Sell [S]")
	btn_sell.pressed.connect(func(): game.sell(game.selected))
	h.add_child(btn_upgrade)
	h.add_child(btn_sell)
	v.add_child(h)
	btn_castle = _button("Castle [C]")
	btn_castle.pressed.connect(func(): game.try_castle())
	v.add_child(btn_castle)
	v.add_child(HSeparator.new())
	lbl_msg = _label("", 13)
	lbl_msg.add_theme_color_override("font_color", Color(0.98, 0.86, 0.52))
	v.add_child(lbl_msg)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	v.add_child(
		_label(
			"Left-click: place / select   Right-click/Esc: cancel\nAttack squares highlight in red.",
			11, false, DA.UI_TEXT_DIM
		)
	)
	btn_leaderboard = _button("Leaderboard [L]")
	btn_leaderboard.pressed.connect(toggle_leaderboard)
	v.add_child(btn_leaderboard)
	btn_restart = _button("Restart")
	btn_restart.pressed.connect(_on_restart)
	v.add_child(btn_restart)

	overlay_final = _overlay_panel(Vector2(56, 420), Vector2(368, 200))
	overlay_final.z_index = 5
	lbl_final_body = _overlay_label(overlay_final)
	overlay_leaderboard = _overlay_panel(Vector2(24, 48), Vector2(432, 560))
	overlay_leaderboard.z_index = 4
	lbl_leaderboard_body = _overlay_label(overlay_leaderboard)
	var lb_close := _button("Close [L / Esc]")
	lb_close.pressed.connect(func(): overlay_leaderboard.visible = false)
	overlay_leaderboard.get_child(0).add_child(lb_close)


func _label(text: String, size: int, title: bool = false, col: Color = DA.UI_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 232
	l.add_theme_color_override("font_color", DA.UI_ACCENT if title else col)
	return l


func _overlay_panel(pos: Vector2, size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.visible = false
	p.position = pos
	p.custom_minimum_size = size
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
		match event.keycode:
			KEY_L:
				toggle_leaderboard()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				if overlay_leaderboard.visible:
					overlay_leaderboard.visible = false
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
	btn_castle.disabled = game.castling_used or game.castle_rooks_eligible().is_empty()
	var p = game.get_piece(game.selected)
	if p == null:
		lbl_sel.text = "Selected: none"
		btn_upgrade.disabled = true
		btn_sell.disabled = true
	else:
		var info := "Selected: %s  Lv %d\nHP %d / %d" % [P.NAMES[p.type], p.level, ceili(p.hp), ceili(p.max_hp)]
		if P.is_tower(p.type):
			info += "\nDamage %.1f every %.1fs" % [P.damage(p.type, p.level), P.COOLDOWN[p.type]]
			if p.level < P.MAX_LEVEL:
				info += "  (next: %.1f)" % P.damage(p.type, p.level + 1)
		elif p.type == P.WALL and p.level < P.MAX_LEVEL:
			info += "\nNext upgrade: HP %d" % ceili(P.max_hp(P.WALL, p.level + 1))
		if p.level < P.MAX_LEVEL:
			info += "\nUpgrade cost: %dg" % P.upgrade_cost(p.type, p.level)
		else:
			info += "\nMax level"
		lbl_sel.text = info
		btn_upgrade.disabled = p.level >= P.MAX_LEVEL or game.gold < P.upgrade_cost(p.type, p.level)
		btn_sell.disabled = p.type == P.KING and game.phase != game.Phase.SETUP
	if game.build_type >= 0 and game.in_bounds(game.hover):
		var err: String = game.can_place(game.build_type, game.hover)
		lbl_msg.text = err if err != "" else game.last_message
	else:
		lbl_msg.text = game.last_message
