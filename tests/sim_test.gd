extends SceneTree

## Headless physics sanity check: fly the disc with backspin / flat / topspin
## and print apex height and landing distance. Backspin should fly higher and
## farther than topspin. Run with:
##   godot --headless --path . --script tests/sim_test.gd

func _initialize() -> void:
	var terrain := Terrain.new()
	var wind := Wind.new()
	root.add_child(terrain)
	root.add_child(wind)
	terrain.generate(12345, 0.3, 1280.0, 720.0)
	wind.setup(12345, 0.3, terrain)
	print("base_wind: %.1f px/s" % wind.base_wind)
	print("launch ground y: %.1f, target_x: %.1f" % [
			terrain.height_at(terrain.launch_x), terrain.target_x])

	for spin in [-20.0, 0.0, 20.0]:
		var r := _fly(terrain, wind, spin)
		print("spin %6.1f -> apex_y %6.1f   land_x %7.1f   flight %5.2fs" % [
				spin, r.x, r.y, r.z])
	quit()


func _fly(terrain: Terrain, wind: Wind, spin: float) -> Vector3:
	var disc := Disc.new()
	disc.terrain = terrain
	disc.wind = wind
	root.add_child(disc)
	disc.set_physics_process(false)

	var start := Vector2(terrain.launch_x, terrain.height_at(terrain.launch_x) - 40.0)
	var vel := Vector2(cos(deg_to_rad(45.0)), -sin(deg_to_rad(45.0))) * 520.0
	disc.launch(start, vel, spin)

	var apex := 720.0
	var t := 0.0
	while disc.active and t < 30.0:
		disc._physics_process(1.0 / 60.0)
		t += 1.0 / 60.0
		apex = minf(apex, disc.position.y)
	var land_x := disc.position.x
	disc.queue_free()
	return Vector3(apex, land_x, t)
