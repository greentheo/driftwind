extends Node2D

## Driftwind Links — disc golf prototype in a 2.5D (3/4 view) world.
##
## Projection: world (x, y, z) -> screen (x, HORIZON + y*YSCALE - z*ZSCALE).
## Lateral y reads as screen-vertical, altitude z lifts a sprite off its
## shadow, and everything is painter-sorted by world y so the disc flies
## in front of and behind trees correctly.

enum State { AIMING, FLYING, SETTLED, HOLED }

const HORIZON := 330.0
const YSCALE := 0.55
const ZSCALE := 0.9
## View yaw: 0 would be a pure side view, 90 a straight behind-the-thrower
## view. ~40 degrees splits the difference so the hole runs diagonally away.
const VIEW_YAW := 0.7        # radians (~40 deg)

const SKY := Color(0.70, 0.80, 0.86)
const ROUGH := Color(0.45, 0.58, 0.37)
const FAIRWAY := Color(0.58, 0.71, 0.43)
const TREELINE := Color(0.33, 0.44, 0.31)
const WATER_COL := Color(0.44, 0.60, 0.79)
const TRUNK := Color(0.42, 0.32, 0.24)
const CANOPY := Color(0.30, 0.47, 0.28)
const DISC_COL := Color(0.95, 0.55, 0.35)

const HEADING_RATE := 1.1     # rad/s
const LOFT_RATE := 22.0       # deg/s
const SPIN_RATE := 1.1
const POWER_MIN := 300.0
const POWER_MAX := 950.0
const CHARGE_RATE := 430.0    # power gained per second while charging

# Touch layout (viewport coords): the throw circle and the tap buttons.
const THROW_BTN := Vector2(1165, 560)
const THROW_BTN_R := 56.0
const ROLL_DECEL := 260.0
const ROUGH_DECEL := 620.0

var course := DGCourse.new()
var wind := DGWind.new()
var disc := DGDisc.new()

var state := State.AIMING
var hole := 1
var stroke := 0
var total_vs_par := 0
var lie := Vector2.ZERO
var prev_lie := Vector2.ZERO
var heading := 0.0
var loft := 14.0
var power := 700.0
var spin_strength := 0.6     # 0.2 .. 1.0, set with A/D
var forehand := false        # F toggles; sets the spin direction
var tilt_deg := 0.0          # -35 .. 35, set with Q/E (hyzer / anhyzer)
var t := 0.0

var _cy := cos(VIEW_YAW)
var _sy := sin(VIEW_YAW)
var _roll := 0.0             # visual spin angle for the disc spokes
var _fit_center := Vector2.ZERO
var _fit_zoom := 1.0
var _advance_at := -1.0      # auto-continue time after a shot settles

# Hold-to-charge throw state. _charge_touch is the finger on the throw
# button (-1 while charging via spacebar); _swipe_touch aims by dragging.
var _charging := false
var _charge_touch := -2
var _swipe_touch := -2
var _throw_btn_node: Node2D
var _fhbh_btn: Button

var camera: Camera2D
var _trail: Array[Vector3] = []
var _streaks: Array[Vector3] = []
var _hit_trees := {}
var _rng := RandomNumberGenerator.new()

var _info_label: Label
var _wind_label: Label
var _throw_label: Label
var _message_label: Label
var _wind_arrow: Node2D


func _spin_signed() -> float:
	return spin_strength * (1.0 if forehand else -1.0)


func _ready() -> void:
	# With the rotated 3/4 view the ground plane fills the frame, so the
	# clear color is grass, not sky.
	RenderingServer.set_default_clear_color(ROUGH.darkened(0.06))
	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 4.0
	add_child(camera)
	camera.make_current()
	_build_hud()
	_start_hole()


func _start_hole() -> void:
	var difficulty := clampf((hole - 1) / 17.0, 0.0, 1.0)
	var hole_seed := randi()
	course.generate(hole_seed, difficulty)
	wind.setup(hole_seed, difficulty)
	_rng.seed = hole_seed + 999
	lie = course.tee
	prev_lie = lie
	stroke = 0
	state = State.AIMING
	heading = _angle_to_basket()
	loft = 14.0
	power = 700.0
	spin_strength = 0.6
	tilt_deg = 0.0
	disc.active = false
	disc.pos = _lie_pos3()
	_trail.clear()
	_hit_trees.clear()
	_make_streaks()
	_compute_hole_framing()
	camera.position = _fit_center
	camera.zoom = Vector2(_fit_zoom, _fit_zoom)
	camera.reset_smoothing()
	_set_message("Hole %d — par %d, %d m." % [
			hole, course.par, _dist_m(lie, course.basket)])


func _lie_pos3() -> Vector3:
	return Vector3(lie.x, lie.y, course.elevation(lie.x) + 25.0)


func _angle_to_basket() -> float:
	return (course.basket - lie).angle()


func _dist_m(a: Vector2, b: Vector2) -> int:
	return int(a.distance_to(b) / 10.0)


func _process(delta: float) -> void:
	t += delta
	match state:
		State.AIMING:
			_handle_aiming(delta)
		State.SETTLED:
			# Auto-continue after a short beat; space skips the wait.
			if Input.is_action_just_pressed("ui_accept") or t >= _advance_at:
				_next_shot()
		State.HOLED:
			if Input.is_action_just_pressed("ui_accept") or t >= _advance_at:
				hole += 1
				_start_hole()

	# Visual spin: the spokes rotate at a rate and direction matching the
	# disc's actual (or configured) spin.
	var s := disc.spin if state == State.FLYING else _spin_signed()
	_roll += s * 9.0 * delta

	_advect_streaks(delta)
	_update_camera()
	_update_hud()
	queue_redraw()


func _handle_aiming(delta: float) -> void:
	if Input.is_key_pressed(KEY_LEFT):
		heading -= HEADING_RATE * delta
	if Input.is_key_pressed(KEY_RIGHT):
		heading += HEADING_RATE * delta
	if Input.is_key_pressed(KEY_UP):
		loft = clampf(loft + LOFT_RATE * delta, 4.0, 42.0)
	if Input.is_key_pressed(KEY_DOWN):
		loft = clampf(loft - LOFT_RATE * delta, 4.0, 42.0)
	if Input.is_key_pressed(KEY_A):
		spin_strength = clampf(spin_strength - SPIN_RATE * delta, 0.2, 1.0)
	if Input.is_key_pressed(KEY_D):
		spin_strength = clampf(spin_strength + SPIN_RATE * delta, 0.2, 1.0)
	if Input.is_key_pressed(KEY_Q):
		tilt_deg = clampf(tilt_deg - 40.0 * delta, -35.0, 35.0)
	if Input.is_key_pressed(KEY_E):
		tilt_deg = clampf(tilt_deg + 40.0 * delta, -35.0, 35.0)
	if Input.is_key_pressed(KEY_F) and not _f_held:
		forehand = not forehand
	_f_held = Input.is_key_pressed(KEY_F)

	# Hold-to-charge, release-to-throw (spacebar mirrors the touch button).
	if Input.is_action_just_pressed("ui_accept") and not _charging:
		_charging = true
		_charge_touch = -1
		power = POWER_MIN
	if _charging:
		power = clampf(power + CHARGE_RATE * delta, POWER_MIN, POWER_MAX)
		if _charge_touch == -1 and Input.is_action_just_released("ui_accept"):
			_charging = false
			_throw()


var _f_held := false


## Touch controls: hold the throw circle to charge (release = throw), swipe
## anywhere else to aim (horizontal = direction, vertical = loft). A second
## finger can aim while the first charges. Mouse emulates touch.
func _unhandled_input(event: InputEvent) -> void:
	if state != State.AIMING:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.position.distance_to(THROW_BTN) <= THROW_BTN_R + 12.0:
				if not _charging:
					_charging = true
					_charge_touch = event.index
					power = POWER_MIN
			elif _swipe_touch == -2:
				_swipe_touch = event.index
		else:
			if _charging and event.index == _charge_touch:
				_charging = false
				_charge_touch = -2
				_throw()
			elif event.index == _swipe_touch:
				_swipe_touch = -2
	elif event is InputEventScreenDrag and event.index == _swipe_touch:
		heading += event.relative.x * 0.0022
		loft = clampf(loft - event.relative.y * 0.14, 4.0, 42.0)


func _next_shot() -> void:
	state = State.AIMING
	heading = _angle_to_basket()
	disc.pos = _lie_pos3()
	_trail.clear()
	# Re-frame for the remaining shot: from just behind the new lie to the
	# basket — the part of the hole already played drops out of view.
	_compute_hole_framing()
	_set_message("")


func _throw() -> void:
	_charging = false
	_charge_touch = -2
	stroke += 1
	prev_lie = lie
	disc.launch(_lie_pos3(), heading, loft, power, _spin_signed(),
			deg_to_rad(tilt_deg))
	_trail.clear()
	_hit_trees.clear()
	_chain_rolled = false
	state = State.FLYING
	_set_message("")


func _physics_process(delta: float) -> void:
	if state != State.FLYING:
		return
	var w := wind.at(disc.pos, t)
	disc.step(delta, w)
	_trail.append(disc.pos)
	if _trail.size() > 700:
		_trail.remove_at(0)
	_check_trees()
	_check_basket()
	_check_ground(delta)


func _check_trees() -> void:
	for i in course.trees.size():
		if _hit_trees.has(i):
			continue
		var tr: Dictionary = course.trees[i]
		var tp: Vector2 = tr["pos"]
		if absf(tp.x - disc.pos.x) > 120.0:
			continue
		var e := course.elevation(tp.x)
		var horiz := Vector2(disc.pos.x - tp.x, disc.pos.y - tp.y)
		# Trunk strike: hard stop.
		if horiz.length() < 8.0 and disc.pos.z < e + float(tr["trunk_h"]):
			_hit_trees[i] = true
			disc.vel.x *= -0.25
			disc.vel.y *= -0.25
			disc.vel.z = minf(disc.vel.z, 0.0)
			disc.spin *= 0.4
			_set_message("Smacked the trunk!")
			continue
		# Canopy: sometimes you thread a gap clean, usually you kick a branch.
		var canopy_center := Vector3(tp.x, tp.y,
				e + float(tr["trunk_h"]) + float(tr["canopy_r"]) * 0.4)
		if disc.pos.distance_to(canopy_center) < float(tr["canopy_r"]):
			_hit_trees[i] = true
			if _rng.randf() < 0.30:
				_set_message("Threaded the branches!")
			else:
				disc.vel *= 0.25
				disc.vel += Vector3(_rng.randf_range(-25, 25),
						_rng.randf_range(-25, 25), 0.0)
				disc.spin *= 0.5
				_set_message("Kicked off a branch!")


## The basket takes skill: a smaller catch window, and a single probability
## roll per approach. Chance scales with how centered the hit is and how
## long the throw was — tap-ins from close drop ~70-95% of the time, bombs
## from way out mostly rattle the chains and spit out beside the basket.
const CATCH_RADIUS := 16.0

var _chain_rolled := false


func _check_basket() -> void:
	if _chain_rolled:
		return
	var b := course.basket
	var e := course.elevation(b.x)
	var d := Vector2(disc.pos.x - b.x, disc.pos.y - b.y).length()
	if d >= CATCH_RADIUS or disc.pos.z < e + 12.0 or disc.pos.z > e + 50.0:
		return
	_chain_rolled = true
	var hspeed := Vector2(disc.vel.x, disc.vel.y).length()
	if hspeed > 650.0:
		disc.vel.x *= 0.35
		disc.vel.y *= 0.35
		disc.spin *= 0.4
		_set_message("Blasted through the chains!")
		return
	var centered := 1.0 - d / CATCH_RADIUS
	var throw_dist := prev_lie.distance_to(b)
	var range_factor := clampf(1.0 - (throw_dist - 250.0) / 1300.0, 0.30, 1.0)
	var p_catch := clampf((0.55 + 0.40 * centered) * range_factor, 0.10, 0.95)
	if _rng.randf() < p_catch:
		_holed()
	else:
		# Chain spit-out: the disc dies on the chains and drops beside.
		var hn := Vector2(disc.vel.x, disc.vel.y).normalized()
		disc.vel = Vector3(-hn.x * _rng.randf_range(30.0, 70.0),
				-hn.y * _rng.randf_range(30.0, 70.0), 20.0)
		disc.spin *= 0.3
		_set_message("Spit out!")


func _check_ground(delta: float) -> void:
	var e := course.elevation(disc.pos.x)
	if disc.pos.z > e:
		return
	disc.pos.z = e
	if disc.vel.z < -60.0 and not disc.grounded:
		# Skip bounce.
		disc.vel.z = -disc.vel.z * 0.25
		disc.vel.x *= 0.55
		disc.vel.y *= 0.55
		return
	disc.vel.z = 0.0
	disc.grounded = true
	var h := Vector2(disc.vel.x, disc.vel.y)
	var off := course.lateral_off_fairway(Vector2(disc.pos.x, disc.pos.y))
	var decel := (ROUGH_DECEL if off > 0.0 else ROLL_DECEL) * delta
	var sp := maxf(h.length() - decel, 0.0)
	if sp < 30.0:
		_settle()
	else:
		h = h.normalized() * sp
		disc.vel.x = h.x
		disc.vel.y = h.y


func _settle() -> void:
	disc.active = false
	var p := Vector2(disc.pos.x, disc.pos.y)
	if course.in_water(p):
		stroke += 1
		lie = prev_lie
		state = State.SETTLED
		_advance_at = t + 2.0
		_set_message("Splash! Penalty stroke — rethrow from your last lie.")
	elif p.x < -50.0 or p.x > course.length + 150.0 \
			or course.lateral_off_fairway(p) > 300.0:
		stroke += 1
		lie = prev_lie
		state = State.SETTLED
		_advance_at = t + 2.0
		_set_message("Out of bounds! Penalty stroke — rethrow from your last lie.")
	elif p.distance_to(course.basket) < 12.0:
		_holed()  # came to rest against the basket: drop-in
	else:
		lie = p
		state = State.SETTLED
		_advance_at = t + 1.3
		_set_message("%d m to the basket." % _dist_m(p, course.basket))


func _holed() -> void:
	disc.active = false
	state = State.HOLED
	var diff := stroke - course.par
	total_vs_par += diff
	var names := {-3: "Albatross!", -2: "Eagle!", -1: "Birdie!", 0: "Par.",
			1: "Bogey.", 2: "Double bogey."}
	var label: String = names.get(diff, "%+d." % diff)
	if stroke == 1:
		label = "ACE!!"
	_advance_at = t + 3.0
	_set_message("Chains! %s (%d/%d)" % [label, stroke, course.par])


## Frame the REMAINING shot in screen space: from just behind the current
## lie to the basket. On the tee that's the whole hole (lie lower-left,
## basket upper-right); later shots tighten as the hole shrinks.
func _compute_hole_framing() -> void:
	var rect := Rect2(_ground_pt(lie.x, lie.y), Vector2.ZERO)
	rect = rect.expand(_ground_pt(lie.x, lie.y - 140.0))
	rect = rect.expand(_ground_pt(lie.x, lie.y + 140.0))
	var x := clampf(lie.x - 160.0, 0.0, course.length)
	while x <= course.length:
		var cl := course.centerline_at(x)
		rect = rect.expand(_ground_pt(x, cl - course.half_width - 130.0))
		rect = rect.expand(_ground_pt(x, cl + course.half_width + 130.0))
		x += 160.0
	rect = rect.grow(70.0)
	_fit_center = rect.get_center()
	var vp := get_viewport_rect().size
	_fit_zoom = clampf(minf(vp.x / rect.size.x, vp.y / rect.size.y), 0.34, 1.0)


func _update_camera() -> void:
	# Aiming shows the whole hole; flight tightens onto the disc.
	var target_pos := _fit_center
	var target_zoom := _fit_zoom
	if state == State.FLYING:
		target_pos = _project(disc.pos)
		target_zoom = maxf(_fit_zoom, 0.75)
	elif Input.is_key_pressed(KEY_TAB):
		target_pos = _ground_pt(course.basket.x, course.basket.y)
		target_zoom = 1.0
	camera.position = target_pos
	var z: float = lerpf(camera.zoom.x, target_zoom,
			1.0 - exp(-4.0 * get_process_delta_time()))
	camera.zoom = Vector2(z, z)


## Inflate small markers when the camera is zoomed out so they stay legible.
func _vis_scale() -> float:
	return clampf(1.0 / camera.zoom.x, 1.0, 1.9)


# ---------- projection & drawing ----------

## Rotate the world by VIEW_YAW, then squash depth and lift by altitude.
func _project(wp: Vector3) -> Vector2:
	var u := wp.x * _cy + wp.y * _sy
	var v := -wp.x * _sy + wp.y * _cy
	return Vector2(u, HORIZON + v * YSCALE - wp.z * ZSCALE)


## Painter-sort depth: larger = closer to the viewer.
func _depth(x: float, y: float) -> float:
	return -x * _sy + y * _cy


func _ground_pt(x: float, y: float) -> Vector2:
	return _project(Vector3(x, y, course.elevation(x)))


func _draw() -> void:
	_draw_ground()
	# Painter-sort everything with a vertical footprint by view depth.
	var items: Array = []
	for i in course.trees.size():
		var tp: Vector2 = course.trees[i]["pos"]
		items.append({"y": _depth(tp.x, tp.y), "kind": "tree", "i": i})
	items.append({"y": _depth(course.basket.x, course.basket.y), "kind": "basket", "i": 0})
	items.append({"y": _depth(disc.pos.x, disc.pos.y), "kind": "disc", "i": 0})
	items.sort_custom(func(a, b): return a["y"] < b["y"])
	_draw_trail()
	for it in items:
		match it["kind"]:
			"tree":
				_draw_tree(course.trees[it["i"]])
			"basket":
				_draw_basket()
			"disc":
				_draw_disc()
	_draw_streaks()
	if state == State.AIMING:
		_draw_aim_guide()


func _draw_ground() -> void:
	# Fairway ribbon along the centerline.
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	var x := 0.0
	while x <= course.length:
		var cl := course.centerline_at(x)
		top.append(_ground_pt(x, cl - course.half_width))
		bottom.append(_ground_pt(x, cl + course.half_width))
		x += 32.0
	var poly := PackedVector2Array()
	poly.append_array(top)
	for i in range(bottom.size() - 1, -1, -1):
		poly.append(bottom[i])
	draw_colored_polygon(poly, FAIRWAY)

	# Water hazards.
	for wtr in course.waters:
		var c: Vector2 = wtr["center"]
		var pts := PackedVector2Array()
		for k in 26:
			var a := k * TAU / 26.0
			pts.append(_ground_pt(c.x + cos(a) * float(wtr["rx"]),
					c.y + sin(a) * float(wtr["ry"])))
		draw_colored_polygon(pts, WATER_COL)
		draw_polyline(pts, WATER_COL.lightened(0.25), 2.0, true)

	# Tee pad: a world-space quad so it follows the view rotation.
	var tee := course.tee
	draw_colored_polygon(PackedVector2Array([
		_ground_pt(tee.x - 24, tee.y - 14), _ground_pt(tee.x + 24, tee.y - 14),
		_ground_pt(tee.x + 24, tee.y + 14), _ground_pt(tee.x - 24, tee.y + 14),
	]), Color(0.62, 0.60, 0.55))


func _draw_tree(tr: Dictionary) -> void:
	var p: Vector2 = tr["pos"]
	var base := _ground_pt(p.x, p.y)
	var trunk_h := float(tr["trunk_h"])
	var canopy_r := float(tr["canopy_r"])
	var shade := float(tr["shade"])
	# Shadow.
	draw_set_transform(base + Vector2(6, 4), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, canopy_r * 0.8, Color(0, 0, 0, 0.13))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Trunk and canopy blobs.
	var top := base - Vector2(0, trunk_h * ZSCALE)
	draw_line(base, top, TRUNK, 5.0, true)
	var col := Color(CANOPY.r * shade, CANOPY.g * shade, CANOPY.b * shade)
	draw_circle(top + Vector2(0, -canopy_r * 0.35), canopy_r, col)
	draw_circle(top + Vector2(-canopy_r * 0.5, 0), canopy_r * 0.7, col.darkened(0.08))
	draw_circle(top + Vector2(canopy_r * 0.5, 0), canopy_r * 0.7, col.lightened(0.06))


func _draw_basket() -> void:
	var b := course.basket
	var base := _ground_pt(b.x, b.y)
	var pole_top := base - Vector2(0, 46.0 * ZSCALE)
	draw_set_transform(base + Vector2(3, 2), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 16.0, Color(0, 0, 0, 0.15))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_line(base, pole_top, Color(0.55, 0.55, 0.58), 3.0, true)
	# Cage.
	var cage_y := base.y - 24.0 * ZSCALE
	draw_rect(Rect2(base.x - 15, cage_y, 30, 10), Color(0.62, 0.62, 0.66))
	# Chains from the band down into the cage.
	var band_y := base.y - 40.0 * ZSCALE
	draw_line(Vector2(base.x - 14, band_y), Vector2(base.x + 14, band_y),
			Color(0.7, 0.7, 0.74), 3.0, true)
	for k in 5:
		var cx: float = lerpf(base.x - 11.0, base.x + 11.0, k / 4.0)
		draw_line(Vector2(cx, band_y), Vector2(base.x + (cx - base.x) * 0.3, cage_y),
				Color(0.75, 0.75, 0.8), 1.5, true)
	# Little flag so it pops.
	draw_line(pole_top, pole_top - Vector2(0, 14), Color(0.5, 0.5, 0.54), 2.0)
	draw_colored_polygon(PackedVector2Array([
		pole_top - Vector2(0, 14), pole_top - Vector2(-16, 9), pole_top - Vector2(0, 4),
	]), Color(0.90, 0.35, 0.30))


func _draw_disc() -> void:
	var e := course.elevation(disc.pos.x)
	var shadow := _project(Vector3(disc.pos.x, disc.pos.y, e))
	var alt := disc.pos.z - e
	var srad := clampf(10.0 - alt * 0.03, 4.0, 10.0)
	draw_set_transform(shadow, 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, srad, Color(0, 0, 0, 0.22))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var sp := _project(disc.pos)
	var vs := _vis_scale()
	# The ellipse leans with the disc's bank (tilt) so hyzer/anhyzer reads.
	var lean := (disc.tilt if state == State.FLYING else deg_to_rad(tilt_deg)) * 0.6
	draw_set_transform(sp, lean, Vector2(vs, 0.55 * vs))
	draw_circle(Vector2.ZERO, 10.0, DISC_COL)
	draw_arc(Vector2.ZERO, 9.0, 0.0, TAU, 24, DISC_COL.darkened(0.35), 2.0, true)
	# Spokes rotating with the actual spin: direction and rate are visible.
	for k in 3:
		var a := _roll + k * TAU / 3.0
		draw_line(Vector2.ZERO, Vector2.from_angle(a) * 8.0,
				DISC_COL.darkened(0.45), 1.8, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_trail() -> void:
	if _trail.size() < 2:
		return
	var pts := PackedVector2Array()
	for wp in _trail:
		pts.append(_project(wp))
	draw_polyline(pts, Color(1, 1, 1, 0.30), 2.0, true)


func _draw_aim_guide() -> void:
	# Wind-free preview including spin curve and tilt, so players learn
	# their disc. Each arc dot casts a shadow dot on the ground (reads the
	# left/right line) with connector ticks (reads the height).
	var probe := DGDisc.new()
	probe.launch(_lie_pos3(), heading, loft, power, _spin_signed(),
			deg_to_rad(tilt_deg))
	# Deliberately shows only the early flight — where the disc actually
	# ends up is the player's read, not the UI's.
	var pts: Array[Vector3] = []
	for i in 21:
		for k in 3:
			probe.step(1.0 / 60.0, Vector2.ZERO)
		pts.append(probe.pos)
		if probe.pos.z <= course.elevation(probe.pos.x):
			break
	var vs := _vis_scale()
	for i in pts.size():
		var fade := 1.0 - i / float(pts.size() + 2)
		var wp := pts[i]
		var arc_pt := _project(wp)
		var ground := _ground_pt(wp.x, wp.y)
		draw_circle(ground, 2.4 * vs, Color(0.05, 0.08, 0.05, 0.45 * fade))
		if i % 3 == 1:
			draw_line(ground, arc_pt, Color(0.08, 0.10, 0.13, 0.18 * fade), 1.0, true)
		draw_circle(arc_pt, 3.2 * vs, Color(0.08, 0.10, 0.13, 0.6 * fade))


func _make_streaks() -> void:
	_streaks.clear()
	for i in 34:
		_streaks.append(Vector3(
				_rng.randf_range(0.0, course.length),
				_rng.randf_range(-320.0, 320.0), _rng.randf_range(40.0, 110.0)))


func _advect_streaks(delta: float) -> void:
	for i in _streaks.size():
		var s := _streaks[i]
		var w := wind.at(s, t)
		s.x += w.x * delta * 1.6
		s.y += w.y * delta * 1.6
		s.x = wrapf(s.x, -100.0, course.length + 100.0)
		s.y = wrapf(s.y, -340.0, 340.0)
		_streaks[i] = s


func _draw_streaks() -> void:
	var vs := _vis_scale()
	for s in _streaks:
		var w := wind.at(s, t)
		var mag := w.length()
		if mag < 1.0:
			continue
		var p := _project(s)
		var tail := _project(Vector3(s.x - w.x * 0.30, s.y - w.y * 0.30, s.z))
		var alpha := clampf(0.18 + mag / 130.0, 0.22, 0.7)
		draw_line(p, tail, Color(0.16, 0.26, 0.38, alpha), 2.5 * vs, true)
		draw_circle(p, 2.2 * vs, Color(0.16, 0.26, 0.38, alpha))


# ---------- HUD ----------

func _build_hud() -> void:
	var hud := CanvasLayer.new()
	add_child(hud)
	_info_label = _make_label(hud, Vector2(16, 12))
	_wind_label = _make_label(hud, Vector2(560, 12))
	_throw_label = _make_label(hud, Vector2(16, 638))
	_message_label = _make_label(hud, Vector2(340, 64))
	_message_label.custom_minimum_size = Vector2(600, 0)
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.add_theme_font_size_override("font_size", 24)
	var help := _make_label(hud, Vector2(16, 668))
	help.text = "swipe or LEFT/RIGHT + UP/DOWN: aim & loft    hold THROW / SPACE: charge power, release to throw\nA/D spin strength    Q/E or buttons: tilt    F: forehand-backhand    hold TAB: view basket"
	help.add_theme_font_size_override("font_size", 13)
	help.modulate = Color(1, 1, 1, 0.85)

	_wind_arrow = Node2D.new()
	_wind_arrow.position = Vector2(540, 22)
	_wind_arrow.draw.connect(_draw_wind_arrow)
	hud.add_child(_wind_arrow)

	# Throw circle with a charging power ring.
	_throw_btn_node = Node2D.new()
	_throw_btn_node.position = THROW_BTN
	_throw_btn_node.draw.connect(_draw_throw_btn)
	hud.add_child(_throw_btn_node)

	# Tap buttons: tilt left / tilt right / forehand-backhand.
	var tilt_l := _make_tap_button(hud, "tilt L", Vector2(1000, 460))
	tilt_l.pressed.connect(func() -> void:
		tilt_deg = clampf(tilt_deg - 5.0, -35.0, 35.0))
	var tilt_r := _make_tap_button(hud, "tilt R", Vector2(1000, 512))
	tilt_r.pressed.connect(func() -> void:
		tilt_deg = clampf(tilt_deg + 5.0, -35.0, 35.0))
	_fhbh_btn = _make_tap_button(hud, "backhand", Vector2(1000, 564))
	_fhbh_btn.pressed.connect(func() -> void:
		forehand = not forehand)


func _make_tap_button(parent: Node, text: String, pos: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = Vector2(100, 44)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	b.modulate = Color(1, 1, 1, 0.85)
	parent.add_child(b)
	return b


func _draw_throw_btn() -> void:
	var n := _throw_btn_node
	n.draw_circle(Vector2.ZERO, THROW_BTN_R, Color(0.16, 0.26, 0.20, 0.80))
	n.draw_arc(Vector2.ZERO, THROW_BTN_R - 4.0, 0.0, TAU, 40,
			Color(1, 1, 1, 0.25), 3.0, true)
	if _charging:
		var frac := (power - POWER_MIN) / (POWER_MAX - POWER_MIN)
		n.draw_arc(Vector2.ZERO, THROW_BTN_R - 4.0, -PI / 2.0,
				-PI / 2.0 + frac * TAU, 40, Color(0.98, 0.80, 0.35), 6.0, true)
	var f := ThemeDB.fallback_font
	n.draw_string(f, Vector2(-THROW_BTN_R, 6), "THROW",
			HORIZONTAL_ALIGNMENT_CENTER, THROW_BTN_R * 2.0, 17,
			Color(1, 1, 1, 0.9))


func _draw_wind_arrow() -> void:
	var w := wind.at(disc.pos if state == State.FLYING else _lie_pos3(), t)
	var ang := w.angle()
	var mag := clampf(w.length() / 150.0, 0.25, 1.3)
	var dir := Vector2.from_angle(ang)
	var perp := Vector2(-dir.y, dir.x)
	var tip := dir * 16.0 * mag
	_wind_arrow.draw_line(-tip, tip, Color(0.15, 0.22, 0.34), 3.0, true)
	_wind_arrow.draw_colored_polygon(PackedVector2Array([
		tip + dir * 7.0, tip + perp * 4.0, tip - perp * 4.0,
	]), Color(0.15, 0.22, 0.34))


func _make_label(parent: Node, pos: Vector2) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color(0.14, 0.18, 0.22))
	parent.add_child(l)
	return l


func _update_hud() -> void:
	var vs := "E" if total_vs_par == 0 else "%+d" % total_vs_par
	_info_label.text = "hole %d   par %d   stroke %d   total %s" % [
			hole, course.par, stroke, vs]
	var wv := wind.at(disc.pos if state == State.FLYING else _lie_pos3(), t)
	_wind_label.text = "      wind %d (%s)" % [int(wv.length()), wind.description()]
	var style := "forehand" if forehand else "backhand"
	var tilt_desc := "flat"
	if tilt_deg > 2.0:
		tilt_desc = "tilt R %.0f" % tilt_deg
	elif tilt_deg < -2.0:
		tilt_desc = "tilt L %.0f" % absf(tilt_deg)
	_throw_label.text = "%s   loft %.0f   power %.0f   spin %.1f   %s   |   %d m to basket" % [
			style, loft, power, spin_strength, tilt_desc, _dist_m(
			Vector2(disc.pos.x, disc.pos.y) if state != State.AIMING else lie,
			course.basket)]
	_wind_arrow.queue_redraw()
	_throw_btn_node.visible = state == State.AIMING
	_throw_btn_node.queue_redraw()
	_fhbh_btn.text = "forehand" if forehand else "backhand"


func _set_message(text: String) -> void:
	_message_label.text = text
