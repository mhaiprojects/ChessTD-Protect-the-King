extends CanvasLayer
## Side panel HUD built in code: stats, build palette, wave/upgrade/sell controls.

const P := preload("res://scripts/pieces.gd")

var game
var lbl_stats: Label
var lbl_sel: Label
var lbl_msg: Label
var build_buttons := {}
var btn_start: Button
var btn_upgrade: Button
var btn_sell: Button
var btn_restart: Button


func _ready() -> void:
	game = get_parent().get_node("Game")
	var panel := PanelContainer.new()
	panel.position = Vector2(480, 16)
	panel.custom_minimum_size = Vector2(264, 672)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)

	v.add_child(_label("CHESS TOWER DEFENSE", 18))
	lbl_stats = _label("", 15)
	v.add_child(lbl_stats)
	v.add_child(HSeparator.new())
	v.add_child(_label("Build (click a tile on your side):", 13))
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
	v.add_child(HSeparator.new())
	lbl_msg = _label("", 13)
	lbl_msg.modulate = Color(1, 0.9, 0.5)
	v.add_child(lbl_msg)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	v.add_child(_label("Left-click: place / select   Right-click/Esc: cancel\nRed tiles = selected piece's attack squares.", 11))
	btn_restart = _button("Restart")
	btn_restart.pressed.connect(func(): game.reset())
	v.add_child(btn_restart)


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 240
	return l


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


func _on_build(t: int) -> void:
	game.build_type = t if build_buttons[t].button_pressed else -1
	game.selected = Vector2i(-1, -1)


func _process(_delta: float) -> void:
	var king_hp := "-"
	if game.has_king():
		var k = game.pieces[game.king_cell]
		king_hp = "%d / %d" % [ceili(k.hp), ceili(k.max_hp)]
	lbl_stats.text = "Gold: %d\nKing HP (lives): %s\nWave: %d / %d\nPhase: %s\nMobs: %d alive, %d to spawn\nKills: %d" % [
		game.gold, king_hp, game.wave, game.MAX_WAVES, game.PHASE_NAMES[game.phase],
		game.mobs.size(), game.spawn_left, game.kills]
	for t in build_buttons:
		var b: Button = build_buttons[t]
		b.set_pressed_no_signal(game.build_type == t)
		b.disabled = game.gold < P.COST[t] or (t == P.KING and game.has_king())
	btn_start.disabled = not (game.phase == game.Phase.SETUP or game.phase == game.Phase.BETWEEN) or not game.has_king()
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
