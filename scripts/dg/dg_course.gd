class_name DGCourse
extends RefCounted

## One procedurally generated disc golf hole.
##
## World coordinates are 3D: x downrange from the tee, y lateral (+ drawn
## toward the bottom of the screen), z altitude. The course itself is a 2D
## layout (x, y) on gently rolling ground whose height is elevation(x).
## This class only generates and answers queries — dg_main draws everything.

const STEP := 16.0

var length := 2400.0
var half_width := 140.0
var par := 3
var tee := Vector2.ZERO
var basket := Vector2.ZERO
var trees: Array[Dictionary] = []   # {pos: Vector2, trunk_h, canopy_r, shade}
var waters: Array[Dictionary] = []  # {center: Vector2, rx, ry}

var _cl := PackedFloat32Array()
var _elev_noise := FastNoiseLite.new()
var _elev_amp := 30.0


func generate(hole_seed: int, difficulty: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hole_seed

	length = lerpf(1700.0, 3300.0, difficulty) * rng.randf_range(0.85, 1.15)
	half_width = lerpf(150.0, 95.0, difficulty)

	# Centerline: one or two doglegs from summed sines.
	var amp1 := lerpf(30.0, 190.0, difficulty) * rng.randf_range(0.6, 1.0)
	var amp2 := amp1 * rng.randf_range(0.2, 0.7)
	var f1 := TAU / length * rng.randf_range(0.7, 1.3)
	var f2 := TAU / length * rng.randf_range(1.8, 2.6)
	var p1 := rng.randf_range(0.0, TAU)
	var p2 := rng.randf_range(0.0, TAU)
	var count := int(length / STEP) + 2
	_cl.resize(count)
	for i in count:
		var x := i * STEP
		_cl[i] = amp1 * sin(x * f1 + p1) + amp2 * sin(x * f2 + p2)

	_elev_noise.seed = hole_seed + 5
	_elev_noise.frequency = 1.6 / length
	_elev_amp = lerpf(12.0, 55.0, difficulty)

	tee = Vector2(70.0, centerline_at(70.0))
	basket = Vector2(length - 90.0, centerline_at(length - 90.0))

	# Trees: plenty lining the rough, plus a few "guardians" standing right
	# in the fairway that you must shape a shot around (or gamble through).
	trees.clear()
	var edge_count := int(lerpf(16.0, 34.0, difficulty))
	for i in edge_count:
		var x := rng.randf_range(150.0, length - 150.0)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var y := centerline_at(x) + side * (half_width + rng.randf_range(-20.0, 150.0))
		trees.append(_make_tree(rng, Vector2(x, y)))
	var guardian_count := int(lerpf(1.0, 4.0, difficulty) + rng.randf())
	for i in guardian_count:
		var x := length * rng.randf_range(0.30, 0.85)
		var y := centerline_at(x) + rng.randf_range(-0.6, 0.6) * half_width
		trees.append(_make_tree(rng, Vector2(x, y)))

	waters.clear()
	if difficulty > 0.1 or rng.randf() < 0.45:
		var n := 1 + (1 if difficulty > 0.5 and rng.randf() < 0.6 else 0)
		for i in n:
			var x := length * rng.randf_range(0.30, 0.80)
			waters.append({
				"center": Vector2(x, centerline_at(x) + rng.randf_range(-60.0, 60.0)),
				"rx": rng.randf_range(90.0, 170.0),
				"ry": rng.randf_range(55.0, 100.0),
			})

	par = clampi(2 + int(length / 950.0) + (1 if waters.size() >= 2 else 0), 3, 5)


func _make_tree(rng: RandomNumberGenerator, p: Vector2) -> Dictionary:
	return {
		"pos": p,
		"trunk_h": rng.randf_range(38.0, 75.0),
		"canopy_r": rng.randf_range(26.0, 52.0),
		"shade": rng.randf_range(0.8, 1.2),
	}


func centerline_at(x: float) -> float:
	var fi := clampf(x / STEP, 0.0, float(_cl.size() - 2))
	var i := int(fi)
	return lerpf(_cl[i], _cl[i + 1], fi - i)


## Ground height (z) at downrange position x. Gentle rolling hills.
func elevation(x: float) -> float:
	return (_elev_noise.get_noise_1d(x) * 0.5 + 0.5) * _elev_amp


func in_water(p: Vector2) -> bool:
	for wtr in waters:
		var c: Vector2 = wtr["center"]
		var dx := (p.x - c.x) / float(wtr["rx"])
		var dy := (p.y - c.y) / float(wtr["ry"])
		if dx * dx + dy * dy <= 1.0:
			return true
	return false


## Positive when p is outside the fairway (distance into the rough).
func lateral_off_fairway(p: Vector2) -> float:
	return absf(p.y - centerline_at(p.x)) - half_width
