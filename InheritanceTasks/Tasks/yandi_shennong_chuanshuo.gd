extends HeritageTaskBase

const PLAYER_SIZE := Vector2(34.0, 48.0)
const GRAVITY: float = 1150.0
const MOVE_SPEED: float = 245.0
const JUMP_SPEED: float = 470.0

var _player_position: Vector2 = Vector2.ZERO
var _velocity: Vector2 = Vector2.ZERO
var _platforms: Array[Rect2] = []
var _hazards: Array[Rect2] = []
var _goal_area: Rect2 = Rect2()
var _checkpoint: Vector2 = Vector2.ZERO
var _coyote_time: float = 0.0
var _jump_buffer: float = 0.0
var _mouse_target_x: float = -1.0
var _hazard_hits: int = 0
var _falls: int = 0


func on_task_started() -> void:
	_build_level()
	_player_position = Vector2(size.x * 0.10, size.y * 0.80 - PLAYER_SIZE.y)
	_checkpoint = _player_position
	_velocity = Vector2.ZERO
	_mouse_target_x = -1.0
	_hazard_hits = 0
	_falls = 0


func task_tick(delta: float) -> void:
	_coyote_time = maxf(0.0, _coyote_time - delta)
	_jump_buffer = maxf(0.0, _jump_buffer - delta)
	var input_x: float = Input.get_axis(&"ui_left", &"ui_right")
	if not is_zero_approx(input_x):
		_mouse_target_x = -1.0
	if is_zero_approx(input_x) and _mouse_target_x >= 0.0:
		input_x = clampf((_mouse_target_x - _player_position.x) / 90.0, -1.0, 1.0)
	_velocity.x = move_toward(_velocity.x, input_x * MOVE_SPEED, 980.0 * delta)
	_velocity.y += GRAVITY * delta
	if _jump_buffer > 0.0 and _coyote_time > 0.0:
		_velocity.y = -JUMP_SPEED
		_jump_buffer = 0.0
		_coyote_time = 0.0
	var previous_bottom: float = _player_position.y + PLAYER_SIZE.y
	_player_position += _velocity * delta
	_player_position.x = clampf(_player_position.x, 0.0, maxf(0.0, size.x - PLAYER_SIZE.x))
	var landed: bool = false
	var landed_platform: Rect2 = Rect2()
	if _velocity.y >= 0.0:
		for platform: Rect2 in _platforms:
			var player_left: float = _player_position.x + 4.0
			var player_right: float = _player_position.x + PLAYER_SIZE.x - 4.0
			var new_bottom: float = _player_position.y + PLAYER_SIZE.y
			if player_right >= platform.position.x and player_left <= platform.end.x \
					and previous_bottom <= platform.position.y + 5.0 \
					and new_bottom >= platform.position.y:
				_player_position.y = platform.position.y - PLAYER_SIZE.y
				_velocity.y = 0.0
				_coyote_time = 0.12
				landed = true
				landed_platform = platform
				break
	if landed:
		pulse_feedback(&"land", _player_position)
	var hit_hazard: bool = false
	var player_rect := Rect2(_player_position, PLAYER_SIZE)
	for hazard: Rect2 in _hazards:
		if player_rect.intersects(hazard):
			_hazard_hits += 1
			hit_hazard = true
			_respawn()
			break
	if landed and not hit_hazard \
			and landed_platform.position.y < _checkpoint.y + PLAYER_SIZE.y - 24.0:
		_checkpoint = _player_position
	if not hit_hazard and _player_position.y > size.y + 80.0:
		_falls += 1
		_respawn()
	var height_progress: float = clampf(1.0 - _player_position.y / maxf(size.y, 1.0), 0.0, 1.0)
	set_progress(height_progress)
	if _goal_area.intersects(Rect2(_player_position, PLAYER_SIZE)):
		complete_success({
			"height_progress": height_progress,
			"hazard_hits": _hazard_hits,
			"falls": _falls,
		}, "踏上采药台")


func task_input(event: InputEvent) -> bool:
	var joy_accept: bool = event is InputEventJoypadButton \
			and (event as InputEventJoypadButton).button_index == JOY_BUTTON_A \
			and (event as InputEventJoypadButton).pressed
	if event.is_action_pressed(&"ui_accept") or joy_accept:
		_jump_buffer = 0.14
		return true
	return false


func task_gui_input(event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		_mouse_target_x = (event as InputEventMouseMotion).position.x
		return true
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
			_jump_buffer = 0.14
			_mouse_target_x = button.position.x
			return true
	return false


func on_suspension_changed(suspended: bool) -> void:
	if suspended:
		_mouse_target_x = -1.0


func on_time_expired() -> void:
	var reason: StringName = &"summit_not_reached"
	var message: String = "还差一段山路"
	if _hazard_hits > 0:
		reason = &"hit_mountain_spikes"
		message = "山路尖石挡住了去路"
	elif _falls > 0:
		reason = &"fell_from_trail"
		message = "失足后没能及时登顶"
	complete_failure(reason, message, {
		"height_progress": progress,
		"hazard_hits": _hazard_hits,
		"falls": _falls,
	})


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_build_level()


func _build_level() -> void:
	var w: float = maxf(size.x, 900.0)
	var h: float = maxf(size.y, 600.0)
	_platforms = [
		Rect2(w * 0.04, h * 0.80, w * 0.24, 24),
		Rect2(w * 0.24, h * 0.67, w * 0.18, 22),
		Rect2(w * 0.47, h * 0.57, w * 0.16, 22),
		Rect2(w * 0.62, h * 0.43, w * 0.18, 22),
		Rect2(w * 0.44, h * 0.30, w * 0.16, 22),
		Rect2(w * 0.72, h * 0.18, w * 0.23, 26),
	]
	_hazards = [
		Rect2(w * 0.18, h * 0.80 - 18.0, w * 0.045, 18.0),
		Rect2(w * 0.54, h * 0.57 - 18.0, w * 0.045, 18.0),
		Rect2(w * 0.70, h * 0.43 - 18.0, w * 0.045, 18.0),
	]
	_goal_area = Rect2(w * 0.72, h * 0.04, w * 0.23, h * 0.15)


func _respawn() -> void:
	_player_position = _checkpoint
	_velocity = Vector2.ZERO
	time_left = maxf(0.0, time_left - 2.0)
	pulse_feedback(&"respawn", _player_position)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.69, 0.82, 0.72, 1.0), true)
	for layer: int in 4:
		var points := PackedVector2Array()
		points.append(Vector2(0, size.y))
		for index: int in 9:
			var x: float = size.x * float(index) / 8.0
			var y: float = size.y * (0.52 + layer * 0.10) + sin(index * 1.7 + layer) * 52.0
			points.append(Vector2(x, y))
		points.append(Vector2(size.x, size.y))
		draw_colored_polygon(points, Color(0.24 + layer * 0.06, 0.39 + layer * 0.05, 0.28, 0.38))
	for platform: Rect2 in _platforms:
		draw_rect(platform, Color(0.42, 0.25, 0.12, 1.0), true)
		draw_line(platform.position, Vector2(platform.end.x, platform.position.y), Color(0.79, 0.60, 0.31, 1.0), 5.0, true)
	for hazard: Rect2 in _hazards:
		var spike_width: float = hazard.size.x / 3.0
		for spike_index: int in 3:
			var spike_left: float = hazard.position.x + spike_width * float(spike_index)
			draw_colored_polygon(PackedVector2Array([
				Vector2(spike_left, hazard.end.y),
				Vector2(spike_left + spike_width * 0.5, hazard.position.y),
				Vector2(spike_left + spike_width, hazard.end.y),
			]), Color(0.67, 0.25, 0.14, 1.0))
	var player_rect := Rect2(_player_position, PLAYER_SIZE)
	draw_rect(player_rect, Color(0.88, 0.65, 0.25, 1.0), true)
	draw_circle(_player_position + Vector2(PLAYER_SIZE.x * 0.5, 7.0), 13.0, Color(0.95, 0.81, 0.57, 1.0))
	var goal := Vector2(size.x * 0.84, size.y * 0.12)
	draw_line(goal, goal + Vector2(0, -75), Color(0.31, 0.20, 0.12, 1.0), 6.0)
	draw_colored_polygon(PackedVector2Array([goal + Vector2(5, -70), goal + Vector2(70, -50), goal + Vector2(5, -30)]), Color(0.77, 0.19, 0.12, 1.0))
