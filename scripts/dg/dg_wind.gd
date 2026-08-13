class_name DGWind
extends RefCounted

## Horizontal wind over the course, deliberately strong relative to the
## disc's floaty gravity — reading it is the game. The direction wanders
## and the magnitude gusts (both more with difficulty), and wind weakens
## near the ground, so a low "punch" throw can sneak under a gale that
## would wreck a high floaty shot.

var base_angle := 0.0
var base_mag := 60.0
var gust_mag := 40.0
var wander := 0.5    # radians of direction wander

var _gust := FastNoiseLite.new()
var _turn := FastNoiseLite.new()


func setup(hole_seed: int, difficulty: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hole_seed + 77
	base_angle = rng.randf_range(0.0, TAU)
	base_mag = lerpf(35.0, 150.0, difficulty) * rng.randf_range(0.6, 1.0)
	gust_mag = lerpf(25.0, 110.0, difficulty)
	wander = lerpf(0.25, 1.10, difficulty)
	_gust.seed = hole_seed + 78
	_gust.frequency = 1.0
	_turn.seed = hole_seed + 79
	_turn.frequency = 1.0


## Wind vector (x, y world plane) at a 3D position and time.
func at(pos: Vector3, t: float) -> Vector2:
	var ang := base_angle + _turn.get_noise_1d(t * 0.045) * wander * 2.0
	var mag := base_mag + _gust.get_noise_2d(t * 0.30, pos.x * 0.003) * gust_mag
	var ground_factor := clampf(pos.z / 90.0, 0.25, 1.0)
	return Vector2.from_angle(ang) * maxf(mag, 0.0) * ground_factor


func description() -> String:
	if base_mag + gust_mag < 80.0:
		return "steady"
	elif base_mag + gust_mag < 140.0:
		return "breezy"
	elif base_mag + gust_mag < 200.0:
		return "gusty"
	return "wild"
