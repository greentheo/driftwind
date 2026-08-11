extends SceneTree

## Measures how long the in-game 36-shot reachability probe takes at max
## difficulty, to make sure level generation has no noticeable hitch.

func _initialize() -> void:
	var terrain := Terrain.new()
	var wind := Wind.new()
	var disc := Disc.new()
	disc.terrain = terrain
	disc.wind = wind
	root.add_child(terrain)
	root.add_child(wind)
	root.add_child(disc)
	disc.set_physics_process(false)

	var start_ms := Time.get_ticks_msec()
	var rolls := 5
	for s in rolls:
		terrain.generate(7000 + s, 1.0, 1280.0, 720.0)
		wind.setup(7000 + s, 1.0, terrain)
		var shots := 0
		for angle in [25.0, 40.0, 55.0, 70.0]:
			for power_frac in [0.6, 0.8, 1.0]:
				for spin in [-18.0, 0.0, 18.0]:
					var dir := Vector2(cos(deg_to_rad(angle)), -sin(deg_to_rad(angle)))
					var start := Vector2(terrain.launch_x,
							terrain.height_at(terrain.launch_x) - 12.0) + dir * 53.0
					disc.launch(start, dir * Launcher.POWER_MAX * power_frac, spin)
					var t := 0.0
					while disc.active and t < 8.0:
						disc._physics_process(1.0 / 60.0)
						t += 1.0 / 60.0
					shots += 1
	var elapsed := Time.get_ticks_msec() - start_ms
	print("full 36-shot probe x%d rolls: %d ms total, %.0f ms per roll" % [
			rolls, elapsed, elapsed / float(rolls)])
	quit()
