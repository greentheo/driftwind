class_name DGDisc
extends RefCounted

## Simulated frisbee flight in 3D (x downrange, y lateral, z up).
##
## Forces, all from AIR-relative velocity so wind bends everything:
##  - gravity: weak (the disc is floaty; wind matters more here)
##  - drag: quadratic
##  - lift: proportional to horizontal airspeed², capped just below gravity,
##    so a fast disc glides and a slow one sinks
##  - turn/fade: the disc-golf S-curve. Lateral force perpendicular to the
##    horizontal motion, sign = spin direction, magnitude KT*speed² - KF:
##    positive (turn) while fast, negative (fade) once it slows. A clockwise
##    (from above) throw turns one way early and fades back the other way
##    late, exactly like a real driver.
##
## Ground behavior (bounce/roll/settle) is handled by dg_main, which knows
## the course.

const G := 240.0
const KD := 0.00115
const KL := 0.0011
const LIFT_CAP := 0.92     # max lift as a fraction of G
const KT := 0.0006
const KF := 150.0
const SPIN_DECAY := 0.10

var pos := Vector3.ZERO
var vel := Vector3.ZERO
var spin := 0.0            # -1..1, + = clockwise seen from above
var tilt := 0.0            # radians of bank (hyzer/anhyzer); + pours lift
                           # toward the flight path's left-perpendicular
var active := false
var grounded := false


func launch(from: Vector3, heading_rad: float, loft_deg: float,
		power: float, spin_amt: float, tilt_rad: float = 0.0) -> void:
	pos = from
	var loft := deg_to_rad(loft_deg)
	var h := cos(loft) * power
	vel = Vector3(cos(heading_rad) * h, sin(heading_rad) * h, sin(loft) * power)
	spin = spin_amt
	tilt = tilt_rad
	active = true
	grounded = false


func step(delta: float, wind: Vector2) -> void:
	var vr := vel - Vector3(wind.x, wind.y, 0.0)
	var speed := vr.length()
	var h2 := vr.x * vr.x + vr.y * vr.y
	var a := Vector3(0.0, 0.0, -G)
	a += -KD * speed * vr
	if not grounded:
		var lift := minf(KL * h2, LIFT_CAP * G)
		var h := Vector2(vr.x, vr.y)
		if h.length_squared() > 100.0:
			var perp := Vector2(-h.y, h.x).normalized()
			# A banked disc pours part of its lift sideways: tilt WITH the
			# spin's curve gives one big sweeping arc, tilt AGAINST it makes
			# the flight fight itself into complex S-shapes.
			a.z += lift * cos(tilt)
			a.x += perp.x * lift * sin(tilt)
			a.y += perp.y * lift * sin(tilt)
			var lat := spin * (KT * h2 - KF)
			a.x += perp.x * lat
			a.y += perp.y * lat
		else:
			a.z += lift
	vel += a * delta
	pos += vel * delta
	spin *= exp(-SPIN_DECAY * delta)
