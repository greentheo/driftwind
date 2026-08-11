class_name Wind
extends Node2D

## The wind field over the level. Query wind_at(pos) for the air velocity
## (px/s) at any point. Three layers combine:
##
##  1. Base wind — a per-level constant, left or right.
##  2. Gusts — the whole field breathes over time (noise sampled along the
##     time axis), with mild spatial variation so gusts arrive as fronts.
##  3. Terrain interaction — near the ground, air follows the slope:
##     updrafts on the windward face of a hill, downdrafts and chaotic
##     turbulence in the lee. This is what makes flying over a ridge
##     interesting instead of just "aim higher".
##
## Drifting streaks are drawn so the player can actually read the air.

const TERRAIN_INFLUENCE_HEIGHT := 300.0
const STREAK_COUNT := 90

var terrain: Terrain
var base_wind := 40.0        # px/s, positive blows to the right
var gust_strength := 30.0
var turbulence := 30.0
var gust_tempo := 0.35       # how fast gusts evolve over time
var wander_strength := 0.0   # px/s the prevailing wind drifts over a level
var churn_tempo := 0.6       # how fast lee-side eddies boil

var _t := 0.0
var _gust_noise := FastNoiseLite.new()
var _turb_noise := FastNoiseLite.new()
var _wander_noise := FastNoiseLite.new()
var _streaks: Array[Vector2] = []
var _rng := RandomNumberGenerator.new()


func setup(level_seed: int, difficulty: float, terrain_ref: Terrain) -> void:
	terrain = terrain_ref
	_rng.seed = level_seed + 1000

	var strength: float = lerpf(50.0, 170.0, difficulty)
	base_wind = (1.0 if _rng.randf() < 0.5 else -1.0) * _rng.randf_range(0.4, 1.0) * strength
	gust_strength = lerpf(35.0, 140.0, difficulty)
	turbulence = lerpf(25.0, 120.0, difficulty)
	# Higher levels aren't just stronger — the air is less predictable:
	# gusts arrive faster, eddies churn quicker, and the prevailing wind
	# itself wanders (at the top end it can flip direction mid-level).
	gust_tempo = lerpf(0.22, 0.75, difficulty)
	churn_tempo = lerpf(0.55, 1.45, difficulty)
	wander_strength = lerpf(8.0, 115.0, difficulty)

	_gust_noise.seed = level_seed + 7
	_gust_noise.frequency = 1.0
	_turb_noise.seed = level_seed + 13
	_turb_noise.frequency = 1.0
	_wander_noise.seed = level_seed + 21
	_wander_noise.frequency = 1.0

	_streaks.clear()
	for i in STREAK_COUNT:
		_streaks.append(Vector2(
			_rng.randf_range(0.0, terrain.width),
			_rng.randf_range(20.0, terrain.screen_h * 0.85)))


func wind_at(pos: Vector2) -> Vector2:
	# Time-varying gust with spatial variation (gust fronts drift across),
	# on top of a slowly wandering prevailing wind.
	var wander := _wander_noise.get_noise_1d(_t * 0.05) * wander_strength
	var gust := _gust_noise.get_noise_2d(_t * gust_tempo, pos.x * 0.004) * gust_strength
	var wx := base_wind + wander + gust
	var wy := 0.0

	if terrain != null:
		var ground_y := terrain.height_at(pos.x)
		var h_above := ground_y - pos.y
		if h_above > -20.0 and h_above < TERRAIN_INFLUENCE_HEIGHT:
			var influence := clampf(1.0 - h_above / TERRAIN_INFLUENCE_HEIGHT, 0.0, 1.0)
			var slope := terrain.slope_at(pos.x)

			# Air flowing along the ground follows the slope (screen y is
			# down, so uphill-in-wind-direction produces negative wy = lift).
			wy += wx * slope * influence * 1.8

			# Lee-side turbulence: when the slope falls away downwind, the
			# flow separates into eddies. `lee` is 0 on the windward side.
			var lee := clampf(signf(wx) * slope * 3.0, 0.0, 1.0)
			var chaos_x := _turb_noise.get_noise_2d(
					pos.x * 0.012 + _t * 0.7 * churn_tempo, pos.y * 0.012)
			var chaos_y := _turb_noise.get_noise_2d(
					pos.y * 0.012 - _t * 0.55 * churn_tempo, pos.x * 0.012 + 99.0)
			var churn := turbulence * (0.35 + lee * influence * 1.3)
			wx += chaos_x * churn
			wy += chaos_y * churn

	return Vector2(wx, wy)


## One-word character of this level's air, for the HUD.
func description() -> String:
	if gust_strength < 55.0:
		return "steady"
	elif gust_strength < 90.0:
		return "breezy"
	elif gust_strength < 125.0:
		return "gusty"
	return "wild"


func _process(delta: float) -> void:
	_t += delta
	if terrain == null:
		return
	# Advect the visible streaks with the local wind (slightly sped up so the
	# motion reads clearly), respawning any that drift into the ground.
	for i in _streaks.size():
		var p := _streaks[i]
		p += wind_at(p) * delta * 1.6
		p.x = wrapf(p.x, -20.0, terrain.width + 20.0)
		if p.y > terrain.height_at(p.x) - 8.0 or p.y < 10.0:
			p = Vector2(_rng.randf_range(0.0, terrain.width),
					_rng.randf_range(20.0, terrain.height_at(p.x) - 40.0))
		_streaks[i] = p
	queue_redraw()


func _draw() -> void:
	for p in _streaks:
		var w := wind_at(p)
		var speed := w.length()
		if speed < 1.0:
			continue
		var alpha := clampf(0.18 + speed / 140.0, 0.22, 0.75)
		var col := Color(0.16, 0.26, 0.38, alpha)
		draw_line(p, p - w * 0.30, col, 2.5, true)
		draw_circle(p, 2.2, col)  # head dot marks the direction of travel
