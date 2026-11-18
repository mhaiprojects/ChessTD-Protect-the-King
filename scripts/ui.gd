extends CanvasLayer
## HUD: responsive side panel + overlays; notifies Game to fit the board in the left pane.

const P := preload("res://scripts/pieces.gd")
const HS := preload("res://scripts/highscores.gd")
const DA := preload("res://scripts/draw_art.gd")
const LS := preload("res://scripts/layouts.gd")
const CFG := preload("res://scripts/config.gd")

var game
var layout_root: Control
var board_host: Control
var hud_scroll: ScrollContainer
var hud_panel: PanelContainer
var lbl_stats: Label
var lbl_msg: Label
var lbl_title: Label
var lbl_help: Label
var build_buttons := {}
var btn_start: Button
var btn_upgrade: Button
var btn_sell: Button
var btn_restart: Button
var btn_dialog_castle: Button
var btn_dialog_close: Button
var btn_leaderboard: Button
var btn_speed: Button
var btn_config: Button
var layout_select: OptionButton
var btn_layout_save: Button
var btn_layout_load: Button
var btn_layout_default: Button
var btn_layout_delete: Button
var stat_strip: Control
var lbl_piece_upgrade: Label
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
var config_dimmer: ColorRect
var config_dialog: PanelContainer
var config_list: ItemList
var btn_config_apply: Button
var btn_config_close: Button
var lbl_config_status: Label
var _config_dialog_open := false
var _config_entries: Array = []


func _ready() -> void:
	CFG.ensure_loaded()
	game = get_parent().get_node("Game")
	_ui_styles = DA.make_ui_styles()
	_build_responsive_shell()
	_load_default_layout()
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

	var hud_w: float = float(CFG.settings.get("ui", {}).get("hud_min_width", 228))
	hud_scroll = ScrollContainer.new()
	hud_scroll.custom_minimum_size = Vector2(hud_w, 0)
	hud_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hud_scroll.size_flags_horizontal = Control.SIZE_SHRINK_END
	hud_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hbox.add_child(hud_scroll)

	hud_panel = PanelContainer.new()
	hud_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud_panel.custom_minimum_size = Vector2(hud_w, 0)
	hud_panel.add_theme_stylebox_override("panel", _ui_styles.panel)
	hud_scroll.add_child(hud_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	hud_panel.add_child(v)

	var ui_cfg: Dictionary = CFG.settings.get("ui", {})
	lbl_title = _label(str(ui_cfg.get("title", "ChessTD : Protect the King")), 18, true)
	v.add_child(lbl_title)
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
		var b := _button(build_button_text(i, t))
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_on_build.bind(t))
		build_buttons[t] = b
		grid.add_child(b)
	v.add_child(HSeparator.new())
	btn_start = _button(start_button_text())
	btn_start.pressed.connect(func(): game.start_wave())
	v.add_child(btn_start)
	btn_speed = _button(speed_button_text())
	btn_speed.pressed.connect(_on_speed)
	v.add_child(btn_speed)
	btn_config = _button(config_button_text())
	btn_config.pressed.connect(open_config_dialog)
	v.add_child(btn_config)
	v.add_child(HSeparator.new())
	_build_layout_section(v)
	v.add_child(HSeparator.new())
	lbl_msg = _label("", 13)
	lbl_msg.add_theme_color_override("font_color", Color(0.98, 0.86, 0.52))
	v.add_child(lbl_msg)
	lbl_help = _label(str(ui_cfg.get("help_text", "")), 11, false, DA.UI_TEXT_DIM)
	v.add_child(lbl_help)
	btn_leaderboard = _button(leaderboard_button_text())
	btn_leaderboard.pressed.connect(toggle_leaderboard)
	v.add_child(btn_leaderboard)
	btn_restart = _button(restart_button_text())
	btn_restart.pressed.connect(_on_restart)
	v.add_child(btn_restart)

	overlay_final = _overlay_panel()
	overlay_final.z_index = 5
	lbl_final_body = _overlay_label(overlay_final)
	overlay_leaderboard = _overlay_panel()
	overlay_leaderboard.z_index = 4
	lbl_leaderboard_body = _overlay_label(overlay_leaderboard)
	var lb_close := _button("Close [%s / %s]" % [CFG.key_label("leaderboard"), CFG.key_label("cancel")])
	lb_close.pressed.connect(func(): overlay_leaderboard.visible = false)
	overlay_leaderboard.get_child(0).add_child(lb_close)

	_build_piece_dialog()
	_build_config_dialog()

	get_viewport().size_changed.connect(_refresh_layout)


func build_button_text(i: int, t: int) -> String:
	var keys: Array = CFG.settings.get("keys", {}).get("build", [])
	var key := str(keys[i]) if i < keys.size() else str(i + 1)
	return "[%s] %s %dg" % [key, P.NAMES[t], P.COST[t]]


func speed_button_text() -> String:
	return "Speed %s [%s]" % [game.speed_label(), CFG.key_label("speed")]


func start_button_text() -> String:
	return "Start Wave  [%s]" % CFG.key_label("start_wave")


func config_button_text() -> String:
	return "Config [%s]" % CFG.key_label("config")


func leaderboard_button_text() -> String:
	return "Leaderboard [%s]" % CFG.key_label("leaderboard")


func restart_button_text() -> String:
	return "Restart [%s]" % CFG.key_label("restart")


func refresh_action_labels() -> void:
	if btn_start != null:
		btn_start.text = start_button_text()
	if btn_speed != null:
		btn_speed.text = speed_button_text()
	if btn_config != null:
		btn_config.text = config_button_text()
	if btn_leaderboard != null:
		btn_leaderboard.text = leaderboard_button_text()
	if btn_restart != null:
		btn_restart.text = restart_button_text()
	if btn_layout_save != null:
		btn_layout_save.text = "Save [%s]" % CFG.key_label("layout_save")
		btn_layout_load.text = "Load [%s]" % CFG.key_label("layout_load")
		btn_layout_default.text = "Default [%s]" % CFG.key_label("layout_default")
		btn_layout_delete.text = "Delete [%s]" % CFG.key_label("layout_delete")
	if btn_upgrade != null:
		btn_upgrade.text = "Upgrade [%s]" % CFG.key_label("upgrade")
		btn_sell.text = "Sell [%s]" % CFG.key_label("sell")
		btn_dialog_castle.text = "Castle [%s]" % CFG.key_label("castle")
		btn_dialog_close.text = "Close [%s]" % CFG.key_label("cancel")
	for i in P.ORDER.size():
		var t: int = P.ORDER[i]
		if build_buttons.has(t):
			build_buttons[t].text = build_button_text(i, t)
	var ui_cfg: Dictionary = CFG.settings.get("ui", {})
	if lbl_title != null:
		lbl_title.text = str(ui_cfg.get("title", lbl_title.text))
	if lbl_help != null:
		lbl_help.text = str(ui_cfg.get("help_text", lbl_help.text))


func _on_speed() -> void:
	game.cycle_speed()
	btn_speed.text = speed_button_text()


func _build_layout_section(v: VBoxContainer) -> void:
	v.add_child(_label("Starting layouts (default loads at match start):", 12, false, DA.UI_TEXT_DIM))
	layout_select = OptionButton.new()
	layout_select.focus_mode = Control.FOCUS_NONE
	layout_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout_select.add_theme_stylebox_override("normal", _ui_styles.btn_normal)
	layout_select.add_theme_stylebox_override("hover", _ui_styles.btn_hover)
	layout_select.add_theme_color_override("font_color", DA.UI_TEXT)
	v.add_child(layout_select)
	var grid := GridContainer.new()
	grid.columns = 2
	v.add_child(grid)
	btn_layout_save = _button("Save [%s]" % CFG.key_label("layout_save"))
	btn_layout_save.pressed.connect(save_current_layout)
	btn_layout_load = _button("Load [%s]" % CFG.key_label("layout_load"))
	btn_layout_load.pressed.connect(load_selected_layout)
	btn_layout_default = _button("Default [%s]" % CFG.key_label("layout_default"))
	btn_layout_default.pressed.connect(toggle_default_layout)
	btn_layout_delete = _button("Delete [%s]" % CFG.key_label("layout_delete"))
	btn_layout_delete.pressed.connect(delete_selected_layout)
	for b in [btn_layout_save, btn_layout_load, btn_layout_default, btn_layout_delete]:
		grid.add_child(b)
	refresh_layout_list()


func refresh_layout_list(select: String = "") -> void:
	if layout_select == null:
		return
	var prev := select if select != "" else selected_layout_name()
	var def := LS.get_default()
	layout_select.clear()
	var names := LS.names()
	for n in names:
		layout_select.add_item(n + ("  (default)" if n == def else ""))
		layout_select.set_item_metadata(layout_select.item_count - 1, n)
	if names.is_empty():
		layout_select.add_item("(no saved layouts)")
		layout_select.set_item_metadata(0, "")
		layout_select.disabled = true
	else:
		layout_select.disabled = false
		var idx := names.find(prev)
		layout_select.select(idx if idx >= 0 else 0)


func selected_layout_name() -> String:
	if layout_select == null or layout_select.item_count == 0 or layout_select.selected < 0:
		return ""
	return str(layout_select.get_item_metadata(layout_select.selected))


func save_current_layout() -> String:
	if game.pieces.is_empty():
		game.last_message = "Nothing to save — place some pieces first."
		return ""
	var n := LS.next_name()
	if LS.save_layout(n, game.export_layout()):
		game.last_message = "Saved %s (%d pieces). Set it as Default to auto-load." % [n, game.pieces.size()]
		refresh_layout_list(n)
		return n
	game.last_message = "Could not save layout."
	return ""


func load_selected_layout() -> int:
	var n := selected_layout_name()
	if n == "":
		game.last_message = "No layout selected."
		return 0
	close_piece_options()
	return game.apply_layout(LS.get_layout(n))


func toggle_default_layout() -> void:
	var n := selected_layout_name()
	if n == "":
		game.last_message = "No layout selected."
		return
	if LS.get_default() == n:
		LS.set_default("")
		game.last_message = "%s is no longer the default layout." % n
	else:
		LS.set_default(n)
		game.last_message = "%s will load at the start of every match." % n
	refresh_layout_list(n)


func delete_selected_layout() -> void:
	var n := selected_layout_name()
	if n != "" and LS.delete_layout(n):
		game.last_message = "Deleted %s." % n
		refresh_layout_list()


func _load_default_layout() -> void:
	var pieces := LS.default_pieces()
	if not pieces.is_empty():
		game.apply_layout(pieces)
		game.last_message = "Default layout '%s' loaded. %s" % [LS.get_default(), game.last_message]


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
	stat_strip = Control.new()
	stat_strip.custom_minimum_size = Vector2(0, 22)
	stat_strip.draw.connect(_draw_stat_strip)
	box.add_child(stat_strip)
	lbl_piece_body = _label("", 14)
	box.add_child(lbl_piece_body)
	lbl_piece_upgrade = _label("", 13, false, DA.UI_ACCENT)
	box.add_child(lbl_piece_upgrade)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	btn_upgrade = _button("Upgrade [%s]" % CFG.key_label("upgrade"))
	btn_upgrade.pressed.connect(_dialog_upgrade)
	btn_sell = _button("Sell [%s]" % CFG.key_label("sell"))
	btn_sell.pressed.connect(_dialog_sell)
	row.add_child(btn_upgrade)
	row.add_child(btn_sell)
	box.add_child(row)

	btn_dialog_castle = _button("Castle [%s]" % CFG.key_label("castle"))
	btn_dialog_castle.pressed.connect(_dialog_castle)
	box.add_child(btn_dialog_castle)

	btn_dialog_close = _button("Close [%s]" % CFG.key_label("cancel"))
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
	var dlg_sz := Vector2(minf(340, vp.size.x * 0.9), minf(400, vp.size.y * 0.8))
	piece_dialog.custom_minimum_size = dlg_sz
	piece_dialog.size = dlg_sz
	piece_dialog.position = (vp.size - dlg_sz) * 0.5
	if config_dimmer != null:
		config_dimmer.position = Vector2.ZERO
		config_dimmer.size = vp.size
		var cfg_sz := Vector2(minf(420, vp.size.x * 0.92), minf(460, vp.size.y * 0.85))
		config_dialog.custom_minimum_size = cfg_sz
		config_dialog.size = cfg_sz
		config_dialog.position = (vp.size - cfg_sz) * 0.5


func _build_config_dialog() -> void:
	config_dimmer = ColorRect.new()
	config_dimmer.color = Color(0.04, 0.05, 0.07, 0.62)
	config_dimmer.visible = false
	config_dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	config_dimmer.z_index = 8
	add_child(config_dimmer)

	config_dialog = PanelContainer.new()
	config_dialog.visible = false
	config_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	config_dialog.z_index = 9
	var dlg_style: StyleBoxFlat = _ui_styles.panel.duplicate()
	dlg_style.bg_color = Color(0.08, 0.09, 0.12, 0.97)
	dlg_style.set_border_width_all(2)
	dlg_style.border_color = DA.UI_BORDER
	config_dialog.add_theme_stylebox_override("panel", dlg_style)
	add_child(config_dialog)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	config_dialog.add_child(box)
	box.add_child(_label("Config files", 17, true))
	box.add_child(_label("Bundled res://config/*.json and user://configs/*.json. Apply reloads data and restarts the match.", 12, false, DA.UI_TEXT_DIM))
	config_list = ItemList.new()
	config_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	config_list.custom_minimum_size = Vector2(0, 180)
	config_list.focus_mode = Control.FOCUS_NONE
	box.add_child(config_list)
	lbl_config_status = _label("", 12, false, DA.UI_ACCENT)
	box.add_child(lbl_config_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	btn_config_apply = _button("Apply & Restart")
	btn_config_apply.pressed.connect(apply_selected_config)
	row.add_child(btn_config_apply)
	btn_config_close = _button("Close [%s]" % CFG.key_label("cancel"))
	btn_config_close.pressed.connect(close_config_dialog)
	row.add_child(btn_config_close)


func open_config_dialog() -> void:
	close_piece_options()
	_config_dialog_open = true
	config_dimmer.visible = true
	config_dialog.visible = true
	get_tree().paused = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	refresh_config_list()
	lbl_config_status.text = "Active game data: %s\nActive settings: %s" % [
		CFG.active_game_data_path.get_file(), CFG.active_settings_path.get_file(),
	]
	_refresh_layout()


func close_config_dialog() -> void:
	if not _config_dialog_open:
		return
	_config_dialog_open = false
	config_dimmer.visible = false
	config_dialog.visible = false
	if not _piece_dialog_open:
		get_tree().paused = false
		process_mode = Node.PROCESS_MODE_INHERIT


func refresh_config_list(select_path: String = "") -> void:
	if config_list == null:
		return
	_config_entries = CFG.list_configs()
	config_list.clear()
	var select_i := 0
	for i in _config_entries.size():
		var e: Dictionary = _config_entries[i]
		config_list.add_item(str(e.label))
		config_list.set_item_metadata(i, str(e.path))
		if select_path != "" and str(e.path) == select_path:
			select_i = i
	if _config_entries.size() > 0:
		config_list.select(select_i)


func apply_selected_config() -> void:
	if config_list == null or not config_list.is_anything_selected():
		lbl_config_status.text = "Select a config file first."
		return
	var path := str(config_list.get_item_metadata(config_list.get_selected_items()[0]))
	var err := CFG.apply_file(path)
	if err != "":
		lbl_config_status.text = err
		game.last_message = err
		return
	game.apply_settings()
	close_config_dialog()
	_on_restart()
	refresh_action_labels()
	game.last_message = "Applied %s — match restarted." % path.get_file()
	lbl_msg.text = game.last_message


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
	lbl_piece_title.text = "%s  ·  %s" % [P.NAMES[p.type], P.level_text(p.level)]
	var c: Vector2i = game.selected
	var lines: PackedStringArray = ["HP: %d / %d" % [ceili(p.hp), ceili(p.max_hp)]]
	if P.is_tower(p.type):
		lines.append(
			"DMG: %.1f every %.2fs" % [game.effective_damage(p.type, p.level, c), game.effective_cooldown(p.type, c)]
		)
		if P.is_slider(p.type):
			lines.append("Range: %d squares" % game.effective_range(p.level, c))
	var syn: String = game.synergy_text(c)
	if syn != "":
		lines.append(syn)
	var buff: Dictionary = P.SYNERGY.get(p.type, {})
	if not buff.is_empty():
		lines.append("Buffs %d allies it defends (%s)" % [game.supports_count(c), synergy_buff_text(p.type)])
	lbl_piece_body.text = "\n".join(lines)
	lbl_piece_upgrade.text = upgrade_preview_text(c)
	stat_strip.queue_redraw()
	btn_upgrade.disabled = p.level >= P.MAX_LEVEL or game.gold < P.upgrade_cost(p.type, p.level)
	btn_sell.disabled = p.type == P.KING and game.phase != game.Phase.SETUP
	var show_castle: bool = (
		not game.castling_used
		and (p.type == P.KING or p.type == P.ROOK)
		and not game.castle_rooks_eligible().is_empty()
	)
	btn_dialog_castle.visible = show_castle
	btn_dialog_castle.disabled = not show_castle


func synergy_buff_text(t: int) -> String:
	var b: Dictionary = P.SYNERGY.get(t, {})
	var parts: PackedStringArray = []
	if b.has("dmg"):
		parts.append("+%d%% DMG" % roundi(b.dmg * 100.0))
	if b.has("spd"):
		parts.append("+%d%% speed" % roundi(b.spd * 100.0))
	if b.has("hp"):
		parts.append("+%d%% HP" % roundi(b.hp * 100.0))
	if b.has("range"):
		parts.append("+%d range" % int(b.range))
	return ", ".join(parts)


## "Upgrade to Lv 3/5 (48g):" followed by before -> after (diff) rows.
func upgrade_preview_text(c: Vector2i) -> String:
	var p = game.get_piece(c)
	if p == null:
		return ""
	if p.level >= P.MAX_LEVEL:
		return "Max level reached."
	var lines: PackedStringArray = ["Upgrade to %s  (%dg):" % [P.level_text(p.level + 1), P.upgrade_cost(p.type, p.level)]]
	for row in game.upgrade_preview(c):
		if row.label != "Level":
			lines.append("  " + row.text)
	return "\n".join(lines)


## Dialog stat strip: HP bar with numbers, weapon icon + damage, level n/max (all vector).
func _draw_stat_strip() -> void:
	var p = game.get_piece(game.selected)
	if p == null or stat_strip == null:
		return
	var w := stat_strip.size.x
	var bar_w := maxf(80.0, w * 0.5)
	var bar_col := Color(0.25, 0.82, 0.38) if p.type != P.WALL else Color(0.55, 0.72, 0.82)
	DA.draw_hp_bar(stat_strip, Vector2(0, 3), bar_w, p.hp / p.max_hp, bar_col, 16.0, DA.hp_text(p.hp, p.max_hp))
	if P.is_tower(p.type):
		var c: Vector2i = game.selected
		DA.draw_weapon_stat(stat_strip, Vector2(bar_w + 10, 16), game.effective_damage(p.type, p.level, c),
			game.synergy_at(c).dmg > 0.0)
	DA.draw_level_badge(stat_strip, Vector2(w, 16), p.level, P.MAX_LEVEL)


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
	_load_default_layout()
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
		"%s\n\nFinal score: %d\n(+%d from kills, +%d from waves)\nWaves reached: %d / %d\nResult: %s\n\nPress Leaderboard [%s] or Restart."
		% [
			title, game.score, game.score_from_kills, game.score_from_waves,
			game.wave, game.MAX_WAVES, res.to_upper(), CFG.key_label("leaderboard"),
		]
	)
	overlay_final.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if _config_dialog_open:
			if CFG.matches_key(event, "cancel") or event.keycode == KEY_ENTER:
				close_config_dialog()
				get_viewport().set_input_as_handled()
			return
		if not _piece_dialog_open:
			if CFG.matches_key(event, "layout_save"):
				save_current_layout()
				get_viewport().set_input_as_handled()
				return
			if CFG.matches_key(event, "layout_load"):
				load_selected_layout()
				get_viewport().set_input_as_handled()
				return
			if CFG.matches_key(event, "layout_default"):
				toggle_default_layout()
				get_viewport().set_input_as_handled()
				return
			if CFG.matches_key(event, "layout_delete"):
				delete_selected_layout()
				get_viewport().set_input_as_handled()
				return
			if CFG.matches_key(event, "restart"):
				_on_restart()
				get_viewport().set_input_as_handled()
				return
		if _piece_dialog_open:
			if CFG.matches_key(event, "cancel") or CFG.matches_key(event, "start_wave_alt"):
				close_piece_options()
				get_viewport().set_input_as_handled()
			elif CFG.matches_key(event, "upgrade"):
				_dialog_upgrade()
				get_viewport().set_input_as_handled()
			elif CFG.matches_key(event, "sell") or CFG.matches_key(event, "sell_alt"):
				_dialog_sell()
				get_viewport().set_input_as_handled()
			elif CFG.matches_key(event, "castle"):
				_dialog_castle()
				get_viewport().set_input_as_handled()
			return
		if CFG.matches_key(event, "config"):
			open_config_dialog()
			get_viewport().set_input_as_handled()
		elif CFG.matches_key(event, "speed"):
			_on_speed()
			get_viewport().set_input_as_handled()
		elif CFG.matches_key(event, "leaderboard"):
			toggle_leaderboard()
			get_viewport().set_input_as_handled()
		elif CFG.matches_key(event, "cancel"):
			if overlay_leaderboard.visible:
				overlay_leaderboard.visible = false
				get_viewport().set_input_as_handled()
			else:
				game.selected = Vector2i(-1, -1)
				game.build_type = -1
				get_viewport().set_input_as_handled()
		elif CFG.matches_key(event, "upgrade"):
			if game.get_piece(game.selected) != null:
				open_piece_options(game.selected)
			get_viewport().set_input_as_handled()
		elif CFG.matches_key(event, "sell") or CFG.matches_key(event, "sell_alt"):
			if game.sell(game.selected):
				get_viewport().set_input_as_handled()
		elif CFG.matches_key(event, "castle"):
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
	btn_speed.text = speed_button_text()
	var has_sel := selected_layout_name() != ""
	btn_layout_load.disabled = not has_sel or game.phase != game.Phase.SETUP
	btn_layout_default.disabled = not has_sel
	btn_layout_delete.disabled = not has_sel
	btn_layout_save.disabled = game.pieces.is_empty()
	if _piece_dialog_open:
		_refresh_piece_dialog()
	if game.build_type >= 0 and game.in_bounds(game.hover):
		var err: String = game.can_place(game.build_type, game.hover)
		lbl_msg.text = err if err != "" else game.last_message
	else:
		lbl_msg.text = game.last_message