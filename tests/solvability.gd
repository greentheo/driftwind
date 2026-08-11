extends SceneTree

## End-to-end check of the real level generation flow (LevelGen): for sampled
## levels across the 30-level ramp, build several levels each and report the
## accepted solution profile — verifying both that every level is beatable
## and that the intended solutions VARY (power/angle/spin should differ level
## to level, not cluster at max power). Run with:
##   godot --headless --path . --script tests/solvability.gd

const LEVELS := [1, 5, 10, 15, 20, 25, 30]
const BUILDS_PER_LEVEL := 4


func _initialize() -> void:
	var terrain := Terrain.new()
	var wind := Wind.new()
	var probe := Disc.new()
	probe.terrain = terrain
	probe.wind = wind
	root.add_child(terrain)
	root.add_child(wind)
	root.add_child(probe)
	probe.set_physics_process(false)

	var rng := RandomNumberGenerator.new()
	rng.seed = 424242

	var failures := 0
	var broad_fallbacks := 0
	var powers: Array[float] = []
	var angles: Array[float] = []
	var spins: Array[float] = []

	for level in LEVELS:
		var difficulty: float = clampf((level - 1) / 29.0, 0.0, 1.0)
		for b in BUILDS_PER_LEVEL:
			var result: Dictionary = LevelGen.build_level(terrain, wind, probe,
					difficulty, Vector2(1280.0, 720.0), rng)
			if not result["ok"]:
				failures += 1
				print("level %2d build %d: ** FAILED TO GENERATE **" % [level, b])
				continue
			if result["broad"]:
				broad_fallbacks += 1
			var best: Dictionary = result["best"]
			powers.append(best["power"])
			angles.append(best["angle"])
			spins.append(best["spin"])
			print("level %2d build %d: target@%3.0f%%  angle %4.1f  power %4.0f (%3.0f%%)  spin %5.1f  dist %3.0f%s" % [
					level, b, 100.0 * terrain.target_x / 1280.0,
					best["angle"], best["power"],
					100.0 * best["power"] / Launcher.POWER_MAX,
					best["spin"], best["dist"],
					"  [broad fallback]" if result["broad"] else ""])

	print("\n==== summary ====")
	print("builds: %d   failures: %d   broad fallbacks: %d" % [
			LEVELS.size() * BUILDS_PER_LEVEL, failures, broad_fallbacks])
	print("power  spread: min %4.0f  max %4.0f  mean %4.0f" % _stats(powers))
	print("angle  spread: min %4.1f  max %4.1f  mean %4.1f" % _stats(angles))
	print("spin   spread: min %4.1f  max %4.1f  mean %4.1f" % _stats(spins))
	var max_power_share := 0.0
	for p in powers:
		if p > Launcher.POWER_MAX * 0.95:
			max_power_share += 1.0
	max_power_share /= maxf(powers.size(), 1.0)
	print("shots needing >95%% power: %.0f%%" % (100.0 * max_power_share))
	quit()


func _stats(values: Array[float]) -> Array:
	if values.is_empty():
		return [0.0, 0.0, 0.0]
	var lo := values[0]
	var hi := values[0]
	var sum := 0.0
	for v in values:
		lo = minf(lo, v)
		hi = maxf(hi, v)
		sum += v
	return [lo, hi, sum / values.size()]
