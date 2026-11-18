# ChessTD : Protect the King

Minimal tower-defense proof of concept where every tower is a chess piece and can only
attack the squares it could move to in chess. Everything is drawn with `_draw()` vector
primitives (rects, circles, polygons, lines) - no image assets. Piece and mob shapes live in
`scripts/draw_art.gd` and `scripts/mobs.gd`.

Play in the browser: https://mhaiprojects.github.io/ChessTD-Protect-the-King/

Source: https://github.com/mhaiprojects/ChessTD-Protect-the-King

![screenshot](docs/screenshot.png)

## Requirements / running

* Godot **4.2+** (developed and tested with 4.3-stable, GL Compatibility renderer).
* Run: `godot --path .` from this folder, or open `project.godot` in the editor and press F5.
* Headless import check: `godot --headless --path . --quit`
* Tests: `godot --headless --path . --script res://tests/test_runner.gd` (exit code 0 = all pass)
* Balance autoplay (info only): `godot --headless --path . --script res://tests/autoplay.gd`
* Screenshot (needs a display/xvfb): `godot --path . --script res://tests/screenshot.gd -- out.png`

## Project structure

```
ChessTD-Protect-the-King/
├── project.godot          # project config, main scene, resizable window + stretch
├── config/
│   ├── game_data.json     # pieces, mobs, waves, upgrades, synergy, scoring
│   └── settings.json      # board, match defaults, speed, keys, UI
├── scenes/main.tscn       # Main(Node) -> Game(Node2D, game.gd) + UI(CanvasLayer, ui.gd)
├── scripts/
│   ├── config.gd          # JSON loader, validation, fallback, list/apply configs
│   ├── pieces.gd          # chess attack patterns + balance tables from game_data
│   ├── draw_art.gd        # vector board theme, chess silhouettes, HP bars, UI palette
│   ├── mobs.gd            # mob draw shapes + stats/waves from game_data
│   ├── game.gd            # board state, placement, waves, mob AI (A*), combat, input, _draw()
│   ├── scoring.gd         # match score (from game_data)
│   ├── highscores.gd      # local JSON leaderboard (top 10; path overridable in tests)
│   ├── layouts.gd         # saved starting layouts + default (user://layouts.json)
│   └── ui.gd              # side-panel HUD built in code (stats, build palette, buttons)
├── tests/
│   ├── test_runner.gd     # headless test suite (patterns, placement, waves, combat, UI)
│   ├── autoplay.gd        # greedy bot balance check (up to 20 waves)
│   └── screenshot.gd      # renders a mid-wave frame to PNG
└── docs/screenshot.png
```

## How to play

1. **Setup phase** — arrange the starting board on your side (rows 4–12; the reddish top 3 rows are the enemy spawn zone). The **King is mandatory and unique**; it is free and can be moved or removed until the first wave starts.
2. Buy towers and walls with gold (start: **200g**). Press **Start Wave** (or Space).
3. **Enemy mobs** spawn at the top and path toward your King using A* pathfinding. Mobs go around your pieces when a route exists. If completely boxed in, they fall back to smashing through the cheapest line (no soft-locks).
4. Towers shoot automatically at mobs on their chess attack squares. Kills and wave bonuses grant gold. Place, upgrade, and sell anytime (including mid-wave).
5. **Score** rises with each kill (stronger mob types — especially **Promoted** — are worth more) and with each wave you clear. The HUD shows your live score.
6. King HP is your lives — King destroyed = **Game Over**. Clear **all 20 waves** = **Victory**. Either way you get a **final score** overlay; the run is saved to the local top-10 leaderboard (`user://highscores.json`).

### Enemy mob types

| Type | Shape / colour | Role |
|---|---|---|
| **Grunt** | Red triangle | Baseline HP, speed, and damage |
| **Runner** | Orange diamond | Fast, low HP, low damage |
| **Brute** | Dark red square | Slow, high HP, heavy hits (extra wall damage) |
| **Sapper** | Purple hexagon | Prefers attacking walls |
| **Promoted** | Gold circle + crown | Earned in play — see **Promotion** below (not in wave spawns) |

Each type pays different gold on kill. Wave composition mixes types according to the data table in `mobs.gd` (`WAVE_DEFS`).

### Promotion

If a mob **reaches the bottom row** (row 12 on the board, `y = 11`) without being stopped, it **promotes** instead of hitting the King that frame. It becomes a **Promoted** mob: faster and tankier than a Grunt, **full HP heal**, gold colour and **crown** marker, higher kill reward. The HUD briefly shows **“A mob was promoted!”** Promoted mobs then keep pathing toward the King as usual. Each mob can promote **at most once** (they are not stuck on the bottom row — they continue along the path toward the King).

### Placement rules

* Cannot build in the top 3 rows (spawn zone).
* **Tower gap rule:** new **towers** or **walls** cannot be placed on any of the 8 tiles around an existing **tower** (any chess piece, including the King). **Walls may touch other walls.**
* **Path rule:** placement must leave at least one path from the spawn zone (rows 0–2) to the King, treating your pieces/walls as blocked. Otherwise placement is rejected with HUD feedback. The same check applies when placing the King in setup.
* Hovering with a build type selected shows a **red invalid preview** and the reason in the message line when placement is illegal.

### Pieces (towers)

| Key | Piece | Cost | Attacks (chess move pattern) |
|---|---|---|---|
| 1 | Pawn (P)   | 20  | two forward-diagonal capture squares (toward the mobs) |
| 2 | Knight (N) | 45  | L-jumps (jumps over pieces) |
| 3 | Bishop (B) | 50  | diagonal lines |
| 4 | Rook (R)   | 60  | horizontal / vertical lines |
| 5 | Queen (Q)  | 120 | Rook + Bishop lines |
| 6 | King (K)   | free | 1 square in all 8 directions |
| 7 | Wall (#)   | 100 | none — HP blocker |

Sliding pieces (R/B/Q) are blocked by your own pieces/walls and have max range `2 + level` squares (3 at L1 up to 7 at L5). **Upgrades (L1–L5):** select a piece, press **U** or the Upgrade button; cost scales per level (shown in the HUD), towers gain +60% base damage per level and +25% HP, **walls gain +50% HP per level**. Sell refunds 50% of everything spent.

Every piece shows its **HP bar with numbers** (`37/40`), a vector **sword icon + attack damage**
(gold when buffed) and its **level as current/max** (`2/5`). The piece dialog shows the same
strip plus an **upgrade preview with before → after and the difference**, e.g. `DMG 7.0 -> 11.2 (+4.2)`.

### Synergy (pieces defend each other)

Each piece buffs every friendly piece (towers and walls) standing on a square it **defends** —
its chess attack pattern, where sliders also reach the first occupied square. Because towers
need a one-tile gap, **Pawn** and **King** reach two squares out. Buffs stack additively and are capped.

| Supporter | Defends | Bonus to each defended ally |
|---|---|---|
| Pawn   | (±1,-1) and (±2,-2) diagonally forward | +10% damage |
| Knight | its 8 L-jump squares | +12% attack speed |
| Bishop | diagonal lines (up to its range) | +1 range for Rook/Bishop/Queen |
| Rook   | orthogonal lines (up to its range) | +15% max HP |
| Queen  | Rook + Bishop lines | +5% damage, +5% attack speed, +5% max HP |
| King   | royal aura, every square within 2 | +8% damage, +8% attack speed |
| Wall   | — | none |

Caps: +50% damage, +50% attack speed, +60% max HP, +2 range. HP buffs keep each piece's
current HP ratio when they appear or disappear. Buffed pieces get a soft gold glow; faint dashed
gold links run from supporters to the allies they buff (highlighted for the selected piece). The
piece dialog lists the active synergy and how many allies the piece supports.

### Game speed

**Speed [F]** cycles **x1 → x2 → x3 → x5 → x10** (`Engine.time_scale`). The simulation runs in
fixed sub-steps of at most 1/30 s and caps very long frames, so x10 behaves like x1, just faster.
It stays on the main HUD side panel (not in Settings).

### Settings window

**Settings [G]** opens a modal overlay (pauses the game; **Esc** or **Close [Esc]** dismisses it).
Config, starting-layout save/load/default/delete, help text, Leaderboard, and Restart live here.
Hotkeys for those actions still work anywhere in the match, even when Settings is closed.
**Config [O]** opened from Settings stacks on top; **Esc** closes Config first, then Settings.
Placement and wave feedback stays on the main HUD message line below Speed.

### Starting layouts

**Save [Shift+S]** stores the current board (pieces, squares, levels) as `Layout N` in
`user://layouts.json`. Pick one in the list and **Load [Shift+L]** (setup phase only — pieces are
bought again with normal rules and gold), **Default [Shift+D]** to toggle it as the layout that is
loaded automatically at every match start/restart, or **Delete [Shift+X]**.

### Controls

| Input | Action |
|---|---|
| Left click empty tile | place the selected build type |
| Left click a piece | open **piece options** dialog (pauses game; attack squares highlighted) |
| Right click / Esc | cancel selection / build type |
| 1–7 | build Pawn, Knight, Bishop, Rook, Queen, King, Wall |
| U / S (Del) | upgrade / sell in the piece dialog (or select a piece first) |
| C | **castling** in the piece dialog when shown (once per match) |
| Space / Enter | start next wave |
| G | open / close **Settings** (Config, layouts, help, Leaderboard, Restart) |
| L | open / close **Leaderboard** (also opens at game end) |
| F | cycle game speed x1 / x2 / x3 / x5 / x10 (main HUD) |
| O | open **Config** (bundled `res://config/*.json` + `user://configs/*.json`; Apply reloads and restarts) |
| Shift+S / Shift+L / Shift+D / Shift+X | save / load / set default / delete starting layout |
| Shift+R | restart the match |

Every button shows its key in `[ ]`.

Hovering with a tower type selected previews the piece and its attack squares (when legal).

### Castling (emergency escape)

Once per match you can **swap the King's position with a Rook tower** (like chess castling, but a true position swap). Click your **King** or an eligible **Rook**, then press **C** or **Castle** in the piece dialog.

* **Range:** the Rook must sit on the **same row as the King**, **2–4 tiles away horizontally** (not adjacent).
* **Safety:** neither tile may be occupied by a mob; the swap must still leave at least one path from the spawn zone to the **new** King square (same rule as placement).
* **UI:** eligible Rooks get a **blue tile highlight** while castling is still available; the HUD shows **Castling: available / unavailable / used**. The button greys out after use. **Restart** resets the flag.

## Development

Coding help runs in one persistent cursor-agent chat on buspc, chat ID
`0815bd5c-711b-490d-a6e2-892f4a3be3d4`. Resume it from this folder:

```
cursor-agent -p --trust --resume 0815bd5c-711b-490d-a6e2-892f4a3be3d4 "<request>"
```

## Limitations (PoC)

* Towers hit one mob per shot (closest to the King’s side among valid targets).
* No sound or online features. Local high-score JSON only; HUD + overlays are built in code.
* Balance is tuned via `tests/autoplay.gd`; difficulty ramps gently across 20 waves.