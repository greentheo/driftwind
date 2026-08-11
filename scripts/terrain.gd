class_name Terrain
extends Node2D

## Procedurally generated side-view terrain.
##
## The ground is a heightmap sampled every STEP pixels: heights[i] is the
## screen-space y of the surface at x = i * STEP (remember: smaller y = higher).
## Everything else in the game queries the ground through height_at(),
## slope_at() and surface_normal() instead of doing polygon collision —
## it's cheap, robust, and plenty for a heightmap world.

const STEP := 4.0

## Scoring zones for the target pad: [radius_px, points], smallest first.
const ZONES := [[20.0, 50], [45.0, 25], [75.0, 10], [115.0, 5]]

const GROUND_COLOR := Color(0.45, 0.58, 0.38)
const GROUND_DARK := Color(0.33, 0.44, 0.30)
const ZONE_COLORS := [
	Color(0.98, 0.83, 0.30),  # bullseye - warm gold
	Color(0.92, 0.55, 0.35),
	Color(0.62, 0.68, 0.85),
	Color(0.55, 0.60, 0.62),
]

var heights := PackedFloat32Array()
var width := 1280.0
var screen_h := 720.0
var launch_x := 90.0
var target_x := 1100.0

var _noise := FastNoiseLite.new()


## target_frac places the target at that fraction of the map width
## (negative = classic far-right placement); pad_radius controls how much
## flat ground surrounds it (negative = default generous pad).
func generate(level_seed: int, difficulty: float, w: float, h: float,
		target_frac: float = -1.0, pad_radius: float = -1.0) -> void:
	width = w
	screen_h = h
	var rng := RandomNumberGenerator.new()
	rng.seed = level_seed

	_noise.seed = level_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.002 + 0.003 * difficulty
	_noise.fractal_octaves = 4

	launch_x = 90.0
	if target_frac > 0.0:
		target_x = w * clampf(target_frac, 0.30, 0.95)
	else:
		target_x = w - rng.randf_range(120.0, 220.0)

	var base_y := h * 0.80
	var amp: float = lerp(72.0, 240.0, clampf(difficulty, 0.0, 1.0))
	# A deliberate main ridge so there is always something to fly over, plus
	# a second ridge (growing with difficulty) guarding the target's approach.
	var ridge_amp := amp * rng.randf_range(0.8, 1.5)
	var ridge_center := w * rng.randf_range(0.38, 0.58)
	var ridge_width := w * rng.randf_range(0.16, 0.28)
	var ridge2_amp := amp * rng.randf_range(0.4, 0.8) * (0.35 + 0.85 * difficulty)
	var ridge2_center := w * rng.randf_range(0.64, 0.84)
	var ridge2_width := w * rng.randf_range(0.09, 0.16)

	var count := int(w / STEP) + 2
	heights.resize(count)
	for i in count:
		var x := i * STEP
		var y := base_y + _noise.get_noise_1d(x) * amp
		var t := clampf(1.0 - absf(x - ridge_center) / ridge_width, 0.0, 1.0)
		y -= ridge_amp * t * t * (3.0 - 2.0 * t)  # smoothstep-shaped ridge
		var t2 := clampf(1.0 - absf(x - ridge2_center) / ridge2_width, 0.0, 1.0)
		y -= ridge2_amp * t2 * t2 * (3.0 - 2.0 * t2)
		heights[i] = clampf(y, h * 0.22, h - 30.0)

	# Flat pads so the launcher sits level and the target is fair. A smaller
	# pad radius leaves the outer rings running up the surrounding slopes.
	_flatten_around(launch_x, 80.0)
	var pad_r: float = pad_radius if pad_radius > 0.0 else ZONES[ZONES.size() - 1][0] + 20.0
	_flatten_around(target_x, pad_r)
	queue_redraw()


func _flatten_around(x: float, radius: float) -> void:
	var pad_y := height_at(x)
	var i0 := maxi(int((x - radius) / STEP), 0)
	var i1 := mini(int((x + radius) / STEP) + 1, heights.size() - 1)
	for i in range(i0, i1 + 1):
		var d := absf(i * STEP - x) / radius
		var blend := clampf(1.0 - d, 0.0, 1.0)
		blend = blend * blend * (3.0 - 2.0 * blend)
		heights[i] = lerpf(heights[i], pad_y, blend)


func height_at(x: float) -> float:
	var fi := clampf(x / STEP, 0.0, float(heights.size() - 2))
	var i := int(fi)
	return lerpf(heights[i], heights[i + 1], fi - i)


func slope_at(x: float) -> float:
	var d := 6.0
	return (height_at(x + d) - height_at(x - d)) / (2.0 * d)


## Unit normal pointing away from the ground (up-ish, i.e. negative y).
func surface_normal(x: float) -> Vector2:
	return Vector2(slope_at(x), -1.0).normalized()


func target_center() -> Vector2:
	return Vector2(target_x, height_at(target_x))


func _draw() -> void:
	if heights.is_empty():
		return

	# Ground body.
	var pts := PackedVector2Array()
	for i in heights.size():
		pts.append(Vector2(i * STEP, heights[i]))
	pts.append(Vector2(width + STEP, screen_h + 50.0))
	pts.append(Vector2(-STEP, screen_h + 50.0))
	draw_colored_polygon(pts, GROUND_COLOR)

	# Surface line for definition.
	var line := PackedVector2Array()
	for i in heights.size():
		line.append(Vector2(i * STEP, heights[i]))
	draw_polyline(line, GROUND_DARK, 3.0, true)

	# Target pad: colored stripes painted along the surface, widest zone first
	# so smaller zones draw on top.
	for zi in range(ZONES.size() - 1, -1, -1):
		var radius: float = ZONES[zi][0]
		var stripe := PackedVector2Array()
		var x := target_x - radius
		while x <= target_x + radius:
			stripe.append(Vector2(x, height_at(x) - 1.0))
			x += STEP
		if stripe.size() >= 2:
			draw_polyline(stripe, ZONE_COLORS[zi], 7.0, true)

	# Flag at the bullseye.
	var c := target_center()
	draw_line(c + Vector2(0, -2), c + Vector2(0, -46), Color(0.35, 0.30, 0.28), 3.0)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -46), c + Vector2(26, -39), c + Vector2(0, -32),
	]), Color(0.90, 0.35, 0.30))
