# Driftwind

**Play it in your browser: https://greentheo.github.io/driftwind/**

A relaxing physics toss game (working title). Launch a spinning cylinder over
procedurally generated terrain and land it on the target pad — like washers,
but the air is alive: gusting winds curl around the hills and interact with
your disc's spin.

Built with **Godot 4.7** (GDScript). Targeting an eventual Steam release.

## Run it

Open the project in Godot and press play, or from a terminal:

```
/Applications/Godot.app/Contents/MacOS/Godot --path .
```

## Controls

**Touch / mouse**: drag from the launcher toward where you want to throw —
direction sets the angle, distance sets the power — and release to let fly.
Tap to advance between shots. On-screen buttons adjust spin.

| Key | Action |
|---|---|
| ← / → | Raise / lower launch angle |
| ↑ / ↓ | More / less power |
| A / D | More backspin / more topspin |
| Space | Launch (and advance after a shot settles) |
| N | Re-roll the current level (while aiming) |
| R | Abandon a shot in flight |

Landing on the gold dead-sticks the disc (no bounce-outs) with a burst of
gold; the rest of the pad plays soft, like a sand pit.

Score by landing near the flag: gold bullseye 50, then 25 / 10 / 5 for the
outer rings. Three shots per level; each level is procedurally generated and
slightly harder (rougher terrain, stronger and more chaotic wind).

## How the physics work

All aerodynamics use **air-relative velocity** (`velocity - wind`), so wind
changes drag and lift together, the way real air does.

- **Gravity** — constant downward pull.
- **Drag** — quadratic, opposing air-relative motion.
- **Magnus lift** — the spinning cylinder deflects air, producing a force
  perpendicular to its air-relative motion: `F ∝ spin * perp(v_rel)`.
  Backspin (counter-clockwise for a rightward shot) floats the disc higher
  and farther; topspin dives it — then grips the ground and skitters it
  forward on landing.
- **Wind** — three layers, all queryable at any point via `Wind.wind_at()`:
  1. a per-level base wind (left or right),
  2. time-varying gusts that drift across the map as fronts,
  3. terrain interaction near the ground: updrafts on the windward face of
     a hill, downdrafts and chaotic turbulence in the lee.

  Difficulty scales the wind's *character*, not just its strength: higher
  levels gust faster, churn harder in the lee, and the prevailing wind
  wanders — at the top end it can flip direction mid-level. The HUD labels
  each level's air: steady / breezy / gusty / wild.

The white streaks on screen are advected by the actual wind field — learning
to read them is the core skill of the game.

## Project layout

```
scenes/main.tscn      entry scene (one node; everything is built in code)
scripts/main.gd       game flow, input, HUD, scoring
scripts/terrain.gd    procedural heightmap, ground queries, target pad
scripts/wind.gd       layered wind field + visible streaks
scripts/disc.gd       hand-integrated flight physics and bouncing
scripts/launcher.gd   aim/power/spin state and launcher drawing
tests/sim_test.gd     headless physics sanity check (spin -> apex/range)
tests/solvability.gd  autopilot fairness sweep: grid-searches shots across
                      every difficulty level and reports unsolvable seeds
tests/timing_check.gd measures the in-game reachability probe's cost
```

Run any of them headless, e.g.:

```
godot --headless --path . --script tests/solvability.gd
```

The same autopilot logic runs in-game (`_level_is_reachable` in main.gd):
each generated level is verified beatable and re-rolled if not, so the
occasional unfair seed the sweep finds at max difficulty never reaches a
player. After any physics or wind tuning change, re-run the sweep.

## Building & sharing

Export templates for Godot 4.7.1 are installed under
`~/Library/Application Support/Godot/export_templates/`. Presets live in
`export_presets.cfg`. To rebuild everything:

```
godot --headless --path . --export-release "Web" build/web/index.html
godot --headless --path . --export-release "macOS" build/mac/Driftwind.zip
godot --headless --path . --export-release "Windows Desktop" build/win/Driftwind.exe
```

- **Web** (`build/web/`) — upload the folder's contents to itch.io as an
  HTML game (or any static host). To playtest on a phone on the same WiFi:
  `python3 -m http.server 8090` inside `build/web/`, then open
  `http://<this-mac's-ip>:8090` on the phone.
- **macOS** (`build/mac/Driftwind.zip`) — ad-hoc signed; friends must
  right-click → Open the first time (unidentified developer).
- **Windows** (`build/win/Driftwind-windows.zip`) — contains the .exe and
  .pck, which must stay in the same folder. SmartScreen will warn once.

## Roadmap

- [x] Core mechanics: terrain, wind, Magnus flight, scoring, levels
- [ ] Look & feel: palette, parallax background, particles, juice
- [ ] Relaxing music + soft sound effects
- [ ] Menus, pause, settings, save (high scores / progression)
- [ ] Steam export + Steamworks integration (achievements, cloud saves)
