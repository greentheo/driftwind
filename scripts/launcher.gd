class_name Launcher
extends Node2D

## The launcher the player aims. Holds the three shot parameters (angle,
## power, spin) and draws itself plus a short no-wind aim guide — the guide
## deliberately ignores wind and Magnus so reading the air stays a skill.

const BARREL_LENGTH := 46.0

const ANGLE_MIN := 10.0
const ANGLE_MAX := 85.0
const POWER_MIN := 180.0
const POWER_MAX := 1050.0
const SPIN_MAX := 25.0    # rad/s either direction

var angle_deg := 45.0     # up from horizontal, firing right
var power := 520.0
var spin := -10.0         # negative = counter-clockwise = backspin


func muzzle_direction() -> Vector2:
	var a := deg_to_rad(angle_deg)
	return Vector2(cos(a), -sin(a))


func muzzle_velocity() -> Vector2:
	return muzzle_direction() * power


func muzzle_position() -> Vector2:
	return position + muzzle_direction() * (BARREL_LENGTH + Disc.RADIUS * 0.5)


func adjust(angle_delta: float, power_delta: float, spin_delta: float) -> void:
	angle_deg = clampf(angle_deg + angle_delta, ANGLE_MIN, ANGLE_MAX)
	power = clampf(power + power_delta, POWER_MIN, POWER_MAX)
	spin = clampf(spin + spin_delta, -SPIN_MAX, SPIN_MAX)
	queue_redraw()


func _draw() -> void:
	# Base.
	draw_circle(Vector2.ZERO, 14.0, Color(0.36, 0.34, 0.40))
	draw_rect(Rect2(-18.0, 6.0, 36.0, 10.0), Color(0.30, 0.28, 0.34))

	# Barrel.
	var tip := muzzle_direction() * BARREL_LENGTH
	draw_line(Vector2.ZERO, tip, Color(0.44, 0.42, 0.50), 10.0, true)
	draw_line(Vector2.ZERO, tip, Color(0.55, 0.53, 0.62), 4.0, true)

	# Power hint: a brighter core the harder the shot.
	var t := (power - POWER_MIN) / (POWER_MAX - POWER_MIN)
	draw_line(Vector2.ZERO, tip * (0.25 + 0.75 * t), Color(0.95, 0.80, 0.40, 0.9), 4.0, true)

	# Aim guide: gravity-only arc drawn as dark arrows. Arrow size scales
	# with power so the charge level reads at a glance.
	var v := muzzle_velocity()
	var p := muzzle_position() - position
	var power_frac := (power - POWER_MIN) / (POWER_MAX - POWER_MIN)
	var arrow_size := 5.0 + 8.0 * power_frac
	for i in 8:
		var dt := 0.06 * (i + 1)
		var pt := p + v * dt + Vector2(0.0, 0.5 * Disc.GRAVITY * dt * dt)
		var dir := (v + Vector2(0.0, Disc.GRAVITY * dt)).normalized()
		var perp := Vector2(-dir.y, dir.x)
		var alpha := 0.85 * (1.0 - i / 9.0)
		draw_colored_polygon(PackedVector2Array([
			pt + dir * arrow_size,
			pt - dir * arrow_size * 0.5 + perp * arrow_size * 0.55,
			pt - dir * arrow_size * 0.5 - perp * arrow_size * 0.55,
		]), Color(0.08, 0.10, 0.13, alpha))

	# Spin indicator: arc near the base, green = backspin, orange = topspin.
	if absf(spin) > 0.5:
		var frac := absf(spin) / SPIN_MAX
		var col := Color(0.55, 0.85, 0.55) if spin < 0.0 else Color(0.95, 0.65, 0.35)
		var sweep := frac * TAU * 0.7
		if spin < 0.0:
			draw_arc(Vector2.ZERO, 22.0, -PI / 2.0, -PI / 2.0 - sweep, 20, col, 3.0, true)
		else:
			draw_arc(Vector2.ZERO, 22.0, -PI / 2.0, -PI / 2.0 + sweep, 20, col, 3.0, true)
