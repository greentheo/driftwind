class_name Disc
extends Node2D

## The flying cylinder, integrated by hand each physics tick so the
## aerodynamics stay fully under our control.
##
## All aerodynamic forces use the AIR-RELATIVE velocity (velocity - wind),
## which is what makes wind matter: a gust changes drag AND lift at once.
##
##   gravity:  constant down.
##   drag:     quadratic, opposing air-relative motion.
##   Magnus:   perpendicular to air-relative motion, sign set by spin.
##
## Spin convention (screen coords, y down): spin > 0 is CLOCKWISE on screen.
## For a disc flying right, clockwise = topspin (dives), counter-clockwise =
## backspin (floats). The Magnus force ω × v_rel works out to
## spin * (-v_rel.y, v_rel.x) in these coordinates.

signal settled(landing_pos: Vector2)
signal bullseye_stick(pos: Vector2)

const RADIUS := 14.0
const GRAVITY := 420.0
const DRAG_COEFF := 0.00075
const MAGNUS_COEFF := 0.042
const SPIN_AIR_DECAY := 0.06     # fraction of spin lost per second in flight
const RESTITUTION := 0.38
const TANGENT_KEEP := 0.78       # tangential velocity kept on each bounce
const SPIN_KICK := 0.10          # how much surface spin converts to motion on contact
const SETTLE_SPEED := 32.0
const SETTLE_TIME := 0.55
const TRAIL_MAX := 500

var velocity := Vector2.ZERO
var spin := 0.0                  # rad/s, + = clockwise on screen
var active := false

var terrain: Terrain
var wind: Wind

var _rest_time := 0.0
var _roll_angle := 0.0
var _trail := PackedVector2Array()


func launch(from: Vector2, initial_velocity: Vector2, initial_spin: float) -> void:
	position = from
	velocity = initial_velocity
	spin = initial_spin
	active = true
	_rest_time = 0.0
	_trail.clear()


func park(at: Vector2, shown_spin: float) -> void:
	position = at
	velocity = Vector2.ZERO
	spin = shown_spin
	active = false
	_trail.clear()
	queue_redraw()


func _physics_process(delta: float) -> void:
	_roll_angle += spin * delta
	if not active:
		queue_redraw()
		return

	var w := wind.wind_at(global_position)
	var v_rel := velocity - w
	var air_speed := v_rel.length()

	var accel := Vector2(0.0, GRAVITY)
	accel += -DRAG_COEFF * air_speed * v_rel
	accel += MAGNUS_COEFF * spin * Vector2(-v_rel.y, v_rel.x)

	velocity += accel * delta
	position += velocity * delta
	spin *= exp(-SPIN_AIR_DECAY * delta)

	_handle_ground_contact()
	_check_out_of_bounds()
	_check_settled(delta)

	_trail.append(position)
	if _trail.size() > TRAIL_MAX:
		_trail.remove_at(0)
	queue_redraw()


func _handle_ground_contact() -> void:
	var ground_y := terrain.height_at(position.x)
	if position.y < ground_y - RADIUS:
		return
	position.y = ground_y - RADIUS

	var n := terrain.surface_normal(position.x)
	var vn := velocity.dot(n)
	if vn < 0.0:
		var pad_d := position.distance_to(terrain.target_center())

		# A hit on (or nearly on) the gold dead-sticks: no lucky bounce-outs
		# off the bullseye.
		if pad_d <= Terrain.ZONES[0][0] * 1.4:
			velocity = Vector2.ZERO
			spin *= 0.2
			active = false
			bullseye_stick.emit(position)
			settled.emit(position)
			return

		# The rest of the pad plays like a sand pit: bounces die quickly.
		var on_pad: bool = pad_d <= Terrain.ZONES[Terrain.ZONES.size() - 1][0]
		var restitution := RESTITUTION * (0.30 if on_pad else 1.0)
		var tangent_keep := TANGENT_KEEP * (0.60 if on_pad else 1.0)
		var spin_kick := SPIN_KICK * (0.40 if on_pad else 1.0)

		# Bounce: reflect the normal component, damp the tangential one.
		velocity -= (1.0 + restitution) * vn * n
		var tangent := Vector2(-n.y, n.x)  # points in the +x-ish direction
		var vt := velocity.dot(tangent)
		velocity -= vt * (1.0 - tangent_keep) * tangent
		# The spinning surface grips the ground: clockwise spin skitters the
		# disc to the right, like a washer with roll on it.
		velocity += tangent * spin * RADIUS * spin_kick
		spin *= 0.65


func _check_out_of_bounds() -> void:
	if position.x < -150.0 or position.x > terrain.width + 150.0 \
			or position.y > terrain.screen_h + 150.0:
		active = false
		settled.emit(position)


func _check_settled(delta: float) -> void:
	if not active:
		return
	var on_ground := position.y >= terrain.height_at(position.x) - RADIUS - 1.5
	if on_ground and velocity.length() < SETTLE_SPEED:
		_rest_time += delta
		if _rest_time >= SETTLE_TIME:
			active = false
			velocity = Vector2.ZERO
			settled.emit(position)
	else:
		_rest_time = 0.0


func _draw() -> void:
	# Flight trail (drawn in local space, so shift world points back).
	if _trail.size() >= 2:
		var local := PackedVector2Array()
		for p in _trail:
			local.append(p - position)
		draw_polyline(local, Color(0.25, 0.32, 0.42, 0.40), 2.5, true)

	# The cylinder, end-on: body, rim, and spokes so spin is visible.
	draw_circle(Vector2.ZERO, RADIUS, Color(0.93, 0.60, 0.45))
	draw_arc(Vector2.ZERO, RADIUS - 1.0, 0.0, TAU, 32, Color(0.55, 0.32, 0.25), 2.5, true)
	for i in 3:
		var a := _roll_angle + i * TAU / 3.0
		draw_line(Vector2.ZERO, Vector2.from_angle(a) * (RADIUS - 3.0),
				Color(0.62, 0.38, 0.28), 2.0, true)
	draw_circle(Vector2.ZERO, 3.0, Color(0.55, 0.32, 0.25))
