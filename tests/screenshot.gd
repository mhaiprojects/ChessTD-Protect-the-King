extends SceneTree
## Renders the main scene mid-wave and saves a PNG (needs a display, e.g. xvfb-run).
## godot --path . --script res://tests/screenshot.gd -- /tmp/shot.png
const P := preload("res://scripts/pieces.gd")

func _initialize() -> void:
	_run()

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	var g = scene.get_node("Game")
	g.gold += 900
	g.place(P.KING, Vector2i(3, 11))
	g.place(P.QUEEN, Vector2i(4, 9))
	g.place(P.ROOK, Vector2i(2, 9))
	g.place(P.PAWN, Vector2i(3, 8))
	for x in [0, 1, 6, 7]:
		g.place(P.WALL, Vector2i(x, 6))
	g.place(P.KNIGHT, Vector2i(5, 7))
	g.place(P.BISHOP, Vector2i(1, 8))
	g.upgrade(Vector2i(4, 9))
	g.start_wave()
	g.selected = Vector2i(4, 9)
	for i in 240:
		await process_frame
	var out := "/tmp/chess-td-shot.png"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	if args.size() > 1 and str(args[1]) == "--settings":
		var ui = scene.get_node("UI")
		ui.open_settings_dialog()
		for i in 8:
			await process_frame
	root.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
