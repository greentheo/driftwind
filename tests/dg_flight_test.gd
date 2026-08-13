extends SceneTree

## Headless sanity check for the frisbee flight model: throw with CCW, flat,
## and CW spin in still air over flat ground and report carry, lateral drift,
## and flight time. CW and CCW should mirror; both should show the S-curve
## (early turn one way, late fade the other). Run with:
##   godot --headless --path . --script tests/dg_flight_test.gd

func _initialize() -> void:
	for spin in [-1.0, 0.0, 1.0]:
		var d := DGDisc.new()
		d.launch(Vector3(0, 0, 25), 0.0, 14.0, 800.0, spin)
		var t := 0.0
		var max_lat := 0.0
		var min_lat := 0.0
		var apex := 0.0
		while d.pos.z > 0.0 and t < 15.0:
			d.step(1.0 / 60.0, Vector2.ZERO)
			t += 1.0 / 60.0
			max_lat = maxf(max_lat, d.pos.y)
			min_lat = minf(min_lat, d.pos.y)
			apex = maxf(apex, d.pos.z)
		print("spin %5.1f -> carry %6.1f  lateral end %6.1f (range %6.1f..%5.1f)  apex %5.1f  time %4.2fs" % [
				spin, d.pos.x, d.pos.y, min_lat, max_lat, apex, t])
	# Tilt (hyzer/anhyzer): banked lift should carve big lateral arcs even
	# with flat spin, and land shorter than a flat throw.
	for tilt_deg in [-25.0, 25.0]:
		var d := DGDisc.new()
		d.launch(Vector3(0, 0, 25), 0.0, 14.0, 800.0, 0.0, deg_to_rad(tilt_deg))
		var t := 0.0
		while d.pos.z > 0.0 and t < 15.0:
			d.step(1.0 / 60.0, Vector2.ZERO)
			t += 1.0 / 60.0
		print("tilt %5.1f -> carry %6.1f  lateral end %6.1f  time %4.2fs" % [
				tilt_deg, d.pos.x, d.pos.y, t])
	# A headwind vs tailwind comparison, flat spin.
	for wx in [-120.0, 120.0]:
		var d := DGDisc.new()
		d.launch(Vector3(0, 0, 25), 0.0, 14.0, 800.0, 0.0)
		var t := 0.0
		while d.pos.z > 0.0 and t < 15.0:
			d.step(1.0 / 60.0, Vector2(wx, 0))
			t += 1.0 / 60.0
		print("wind x %6.1f -> carry %6.1f  time %4.2fs" % [wx, d.pos.x, t])
	quit()
