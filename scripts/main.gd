extends Node2D

## Game orchestration: builds each level, routes input, tracks score.
##
## Flow: AIMING -> (space) -> FLYING -> disc settles -> SETTLED ->
## (space) -> next shot, or LEVEL_DONE -> (space) -> next, harder level.

enum State { AIMING, FLYING, SETTLED, LEVEL_DONE }

const SHOTS_PER_LEVEL := 3
const SKY_COLOR := Color(0.72, 0.82, 0.88)

const ANGLE_RATE := 30.0     # deg/s while holding a key
const POWER_RATE := 260.0    # px/s^2 of muzzle speed per second held
const SPIN_RATE := 14.0      # rad/s per second held

var state := State.AIMING
var level := 1
var shot := 1
var score_total := 0
var level_score := 0

# Launch parameters of the shot in flight, for the finesse bonus.
var _shot_power_frac := 0.0
var _shot_spin_frac := 0.0
var _bullseye_fx_played := false

# Touch / drag-to-aim state (mouse is emulated as touch too).
var _dragging := false
var _drag_aimed := false
var _spin_back_held := false
var _spin_top_held := false

var view_size := Vector2(1280, 720)

var terrain: Terrain
var wind: Wind
var launcher: Launcher
var disc: Disc
var _probe: Disc

var _info_label: Label
var _wind_label: Label
var _score_label: Label
var _message_label: Label


func _ready() -> void:
	RenderingServer.set_default_clear_color(SKY_COLOR)
	view_size = get_viewport_rect().size

	terrain = Terrain.new()
	add_child(terrain)
	wind = Wind.new()
	add_child(wind)
	launcher = Launcher.new()
	add_child(launcher)
	disc = Disc.new()
	disc.terrain = terrain
	disc.wind = wind
	disc.settled.connect(_on_disc_settled)
	disc.bullseye_stick.connect(_on_bullseye_stick)
	add_child(disc)

	# Hidden disc used by LevelGen's autopilot to verify levels.
	_probe = Disc.new()
	_probe.terrain = terrain
	_probe.wind = wind
	_probe.visible = false
	add_child(_probe)
	_probe.set_physics_process(false)

	_build_hud()
	_start_level()


func _start_level() -> void:
	# Difficulty ramps over 30 levels. LevelGen draws a random intended-
	# solution profile (power/angle/spin bands) and rolls seeds until the
	# autopilot lands that kind of shot: procedural, fair, and varied.
	var difficulty := clampf((level - 1) / 29.0, 0.0, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	LevelGen.build_level(terrain, wind, _probe, difficulty, view_size, rng)
	launcher.position = Vector2(terrain.launch_x,
			terrain.height_at(terrain.launch_x) - 12.0)
	launcher.queue_redraw()
	shot = 1
	level_score = 0
	state = State.AIMING
	disc.park(launcher.muzzle_position(), launcher.spin)
	_set_message("Level %d — space to launch" % level)


func _process(delta: float) -> void:
	match state:
		State.AIMING:
			_handle_aiming_input(delta)
		State.FLYING:
			if Input.is_key_pressed(KEY_R):
				disc.active = false
				_after_shot(0, "Shot abandoned.")
		State.SETTLED, State.LEVEL_DONE:
			if Input.is_action_just_pressed("ui_accept"):
				_advance()
	_update_hud()


func _handle_aiming_input(delta: float) -> void:
	var da := 0.0
	var dp := 0.0
	var ds := 0.0
	if Input.is_key_pressed(KEY_LEFT):
		da += ANGLE_RATE * delta
	if Input.is_key_pressed(KEY_RIGHT):
		da -= ANGLE_RATE * delta
	if Input.is_key_pressed(KEY_UP):
		dp += POWER_RATE * delta
	if Input.is_key_pressed(KEY_DOWN):
		dp -= POWER_RATE * delta
	if Input.is_key_pressed(KEY_A) or _spin_back_held:
		ds -= SPIN_RATE * delta   # more counter-clockwise (backspin)
	if Input.is_key_pressed(KEY_D) or _spin_top_held:
		ds += SPIN_RATE * delta   # more clockwise (topspin)
	if da != 0.0 or dp != 0.0 or ds != 0.0:
		launcher.adjust(da, dp, ds)
		disc.park(launcher.muzzle_position(), launcher.spin)

	if Input.is_key_pressed(KEY_N):
		_start_level()  # re-roll the level while practicing
		return
	if Input.is_action_just_pressed("ui_accept"):
		_launch_shot()


func _launch_shot() -> void:
	_shot_power_frac = (launcher.power - Launcher.POWER_MIN) \
			/ (Launcher.POWER_MAX - Launcher.POWER_MIN)
	_shot_spin_frac = absf(launcher.spin) / Launcher.SPIN_MAX
	_bullseye_fx_played = false
	disc.launch(launcher.muzzle_position(), launcher.muzzle_velocity(), launcher.spin)
	state = State.FLYING
	_set_message("")


## Touch controls: drag anywhere to slingshot-aim (pull back and away from
## the shot, like a washer toss), release to launch. Tap advances between
## shots. The editor/desktop mouse emulates touch (project setting).
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.index != 0:
			return
		if event.pressed:
			_dragging = true
			_drag_aimed = false
		else:
			if state == State.AIMING and _drag_aimed:
				_launch_shot()
			elif (state == State.SETTLED or state == State.LEVEL_DONE) \
					and not _drag_aimed:
				_advance()
			_dragging = false
			_drag_aimed = false
	elif event is InputEventScreenDrag and _dragging and state == State.AIMING:
		# Point-to-aim: drag toward where you want to throw; distance from
		# the launcher sets the power. (The launcher hugs the left edge, so
		# a pull-back slingshot would have no room.)
		var aim: Vector2 = event.position - launcher.position
		if aim.length() < 40.0:
			return  # too close to the launcher to aim meaningfully
		_drag_aimed = true
		launcher.angle_deg = clampf(rad_to_deg(atan2(-aim.y, aim.x)),
				Launcher.ANGLE_MIN, Launcher.ANGLE_MAX)
		launcher.power = clampf(aim.length() * 1.15,
				Launcher.POWER_MIN, Launcher.POWER_MAX)
		launcher.queue_redraw()
		disc.park(launcher.muzzle_position(), launcher.spin)


func _on_disc_settled(landing_pos: Vector2) -> void:
	var d := landing_pos.distance_to(terrain.target_center())
	var base_points := 0
	var zone_index := -1
	for i in Terrain.ZONES.size():
		if d <= Terrain.ZONES[i][0]:
			base_points = Terrain.ZONES[i][1]
			zone_index = i
			break
	if base_points > 0 and not _bullseye_fx_played:
		_spawn_burst(landing_pos, 30, Terrain.ZONE_COLORS[zone_index], 180.0)
	var text: String
	var points := base_points
	if base_points > 0:
		# Finesse: a gentle low-power shot ridden in on spin is worth up to
		# ~2.8x the landing zone's base value.
		var finesse := 1.0 + (1.0 - _shot_power_frac) * 1.2 + _shot_spin_frac * 0.6
		points = int(round(base_points * finesse))
		var prefix := "Bullseye! " if base_points >= 50 else ""
		text = "%s+%d pts  (%d base × %.1f finesse)" % [prefix, points, base_points, finesse]
	else:
		text = "Missed the pad (%d px off)" % int(d)
	_after_shot(points, text)


func _after_shot(points: int, text: String) -> void:
	score_total += points
	level_score += points
	if shot >= SHOTS_PER_LEVEL:
		state = State.LEVEL_DONE
		_set_message("%s\nLevel %d done — %d pts. Space for level %d."
				% [text, level, level_score, level + 1])
	else:
		state = State.SETTLED
		_set_message("%s\nSpace for next shot." % text)


func _on_bullseye_stick(pos: Vector2) -> void:
	# The disc dead-stuck on (or next to) the gold: big celebration.
	_bullseye_fx_played = true
	_spawn_burst(pos, 90, Terrain.ZONE_COLORS[0], 340.0)
	_spawn_burst(pos, 40, Color(1.0, 1.0, 1.0), 220.0)


func _spawn_burst(pos: Vector2, amount: int, color: Color, speed: float) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.one_shot = true
	p.emitting = true
	p.amount = amount
	p.lifetime = 1.0
	p.explosiveness = 1.0
	p.direction = Vector2(0, -1)
	p.spread = 85.0
	p.initial_velocity_min = speed * 0.35
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, 480)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.5
	var ramp := Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, Color(color, 0.0))
	p.color_ramp = ramp
	add_child(p)
	get_tree().create_timer(2.5).timeout.connect(p.queue_free)


func _advance() -> void:
	if state == State.LEVEL_DONE:
		level += 1
		_start_level()
	else:
		shot += 1
		state = State.AIMING
		disc.park(launcher.muzzle_position(), launcher.spin)
		_set_message("Shot %d of %d" % [shot, SHOTS_PER_LEVEL])


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	add_child(hud)

	_info_label = _make_label(hud, Vector2(16, 12), HORIZONTAL_ALIGNMENT_LEFT)
	_wind_label = _make_label(hud, Vector2(view_size.x / 2.0 - 150, 12),
			HORIZONTAL_ALIGNMENT_CENTER)
	_wind_label.custom_minimum_size = Vector2(300, 0)
	_score_label = _make_label(hud, Vector2(view_size.x - 240, 12),
			HORIZONTAL_ALIGNMENT_RIGHT)
	_score_label.custom_minimum_size = Vector2(220, 0)

	_message_label = _make_label(hud, Vector2(view_size.x / 2.0 - 320, 70),
			HORIZONTAL_ALIGNMENT_CENTER)
	_message_label.custom_minimum_size = Vector2(640, 0)
	_message_label.add_theme_font_size_override("font_size", 26)

	var help := _make_label(hud, Vector2(16, view_size.y - 34), HORIZONTAL_ALIGNMENT_LEFT)
	help.text = "drag to aim, release to throw (or arrow keys + space)   A/D spin   N new level   R abandon"
	help.add_theme_font_size_override("font_size", 14)
	help.modulate = Color(1, 1, 1, 0.75)

	# On-screen spin buttons for touch play.
	var back_btn := _make_spin_button(hud, "+ backspin",
			Vector2(view_size.x - 330, view_size.y - 110))
	back_btn.button_down.connect(func() -> void: _spin_back_held = true)
	back_btn.button_up.connect(func() -> void: _spin_back_held = false)
	var top_btn := _make_spin_button(hud, "+ topspin",
			Vector2(view_size.x - 170, view_size.y - 110))
	top_btn.button_down.connect(func() -> void: _spin_top_held = true)
	top_btn.button_up.connect(func() -> void: _spin_top_held = false)


func _make_spin_button(parent: Node, text: String, pos: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = Vector2(150, 60)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 18)
	b.modulate = Color(1, 1, 1, 0.85)
	parent.add_child(b)
	return b


func _make_label(parent: Node, pos: Vector2, align: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(0.16, 0.20, 0.24))
	parent.add_child(l)
	return l


func _update_hud() -> void:
	var spin_desc: String
	if launcher.spin < -0.5:
		spin_desc = "backspin %.0f" % absf(launcher.spin)
	elif launcher.spin > 0.5:
		spin_desc = "topspin %.0f" % launcher.spin
	else:
		spin_desc = "flat"
	_info_label.text = "angle %.0f°   power %.0f   %s" % [
			launcher.angle_deg, launcher.power, spin_desc]

	# Sample the wind where it matters: at the disc in flight, else mid-sky.
	var probe := disc.global_position if state == State.FLYING \
			else Vector2(view_size.x / 2.0, view_size.y * 0.35)
	var w := wind.wind_at(probe)
	var arrow := ">>" if w.x >= 0.0 else "<<"
	_wind_label.text = "wind %s %.0f  (%s)" % [arrow, absf(w.x), wind.description()]

	_score_label.text = "level %d   shot %d/%d   score %d" % [
			level, shot, SHOTS_PER_LEVEL, score_total]


func _set_message(text: String) -> void:
	_message_label.text = text
