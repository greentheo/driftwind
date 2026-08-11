class_name LevelGen
extends RefCounted

## Level generation with shot-profile variety.
##
## Each level draws a random "intended solution" profile — a band of power,
## angle, and spin — then rolls terrain / wind / target-placement seeds until
## the autopilot can land a shot on the pad USING ONLY that profile.
## Verifying against the narrow profile (instead of the full grid) is what
## forces variety level to level: one level's answer is a gentle high-arc
## backspin lob, the next wants a flat max-power topspin drive.
##
## If a profile draw turns out to be cruel for the current difficulty, a
## fresh profile is drawn; the final round uses the full broad grid so level
## generation can never hang on an impossible combination.

const ROUNDS := 3               # profile draws per level (last one is broad)
const ATTEMPTS_PER_ROUND := 5   # terrain/wind seed rolls per profile draw

const POWER_BANDS := [Vector2(0.45, 0.62), Vector2(0.60, 0.80), Vector2(0.80, 1.0)]
const ANGLE_BANDS := [Vector2(15.0, 35.0), Vector2(35.0, 55.0), Vector2(55.0, 78.0)]
const SPIN_BANDS := [Vector2(-25.0, -8.0), Vector2(-7.0, 7.0), Vector2(8.0, 25.0)]
const BROAD := {
	"power": Vector2(0.45, 1.0),
	"angle": Vector2(15.0, 78.0),
	"spin": Vector2(-25.0, 25.0),
}


static func draw_profile(rng: RandomNumberGenerator) -> Dictionary:
	return {
		"power": POWER_BANDS[rng.randi_range(0, POWER_BANDS.size() - 1)],
		"angle": ANGLE_BANDS[rng.randi_range(0, ANGLE_BANDS.size() - 1)],
		"spin": SPIN_BANDS[rng.randi_range(0, SPIN_BANDS.size() - 1)],
	}


## Configures `terrain` and `wind` in place for a new, verified-solvable
## level. `probe` is a hidden Disc used for simulation. Returns diagnostics:
## { ok, broad, profile, best: {dist, angle, power, spin} }.
static func build_level(terrain: Terrain, wind: Wind, probe: Disc,
		difficulty: float, view: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	var outer: float = Terrain.ZONES[Terrain.ZONES.size() - 1][0]
	for round_i in ROUNDS:
		var profile: Dictionary = BROAD if round_i == ROUNDS - 1 else draw_profile(rng)
		for attempt in ATTEMPTS_PER_ROUND:
			# Target placement gets more adventurous with difficulty: it can
			# sit anywhere from mid-map (short, awkward chips over a single
			# ridge) to the far edge, and its flat pad shrinks until the
			# outer rings climb the surrounding slopes.
			var level_seed := rng.randi()
			var target_frac := rng.randf_range(lerpf(0.72, 0.48, difficulty), 0.92)
			var pad_radius := lerpf(outer + 45.0, outer + 5.0, difficulty) \
					* rng.randf_range(0.85, 1.15)
			terrain.generate(level_seed, difficulty, view.x, view.y,
					target_frac, pad_radius)
			wind.setup(level_seed, difficulty, terrain)
			var best := best_shot(terrain, wind, probe, profile)
			if best["dist"] <= outer:
				return {"ok": true, "broad": round_i == ROUNDS - 1,
						"profile": profile, "best": best}
	# Statistically unreachable: even the broad round found nothing. Keep the
	# last rolled level rather than looping forever.
	return {"ok": false, "broad": true, "profile": BROAD, "best": {}}


## Coarse grid search within the profile's bands; returns the closest-landing
## shot found: {dist, angle, power, spin}.
static func best_shot(terrain: Terrain, wind: Wind, probe: Disc,
		profile: Dictionary) -> Dictionary:
	var best := {"dist": 1.0e9, "angle": 0.0, "power": 0.0, "spin": 0.0}
	var pb: Vector2 = profile["power"]
	var ab: Vector2 = profile["angle"]
	var sb: Vector2 = profile["spin"]
	for a_i in 4:
		var angle := lerpf(ab.x, ab.y, a_i / 3.0)
		for p_i in 3:
			var power := lerpf(pb.x, pb.y, p_i / 2.0) * Launcher.POWER_MAX
			for s_i in 3:
				var spin := lerpf(sb.x, sb.y, s_i / 2.0)
				var d := _fly(terrain, wind, probe, angle, power, spin)
				if d < best["dist"]:
					best = {"dist": d, "angle": angle, "power": power, "spin": spin}
	return best


static func _fly(terrain: Terrain, wind: Wind, probe: Disc,
		angle_deg: float, power: float, spin: float) -> float:
	var dir := Vector2(cos(deg_to_rad(angle_deg)), -sin(deg_to_rad(angle_deg)))
	var start := Vector2(terrain.launch_x,
			terrain.height_at(terrain.launch_x) - 12.0) + dir * 53.0
	probe.launch(start, dir * power, spin)
	var t := 0.0
	while probe.active and t < 8.0:
		probe._physics_process(1.0 / 60.0)
		t += 1.0 / 60.0
	return probe.position.distance_to(terrain.target_center())
