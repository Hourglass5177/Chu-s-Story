extends HeritageTaskBase

var _boat_x: float = 0.5
var _boat_velocity: float = 0.0
var _steer: float = 0.0
var _safe_seconds: float = 0.0
var _dragging: bool = false


func on_task_started() -> void:
	_boat_x = 0.5
	_boat_velocity = 0.0
	_steer = 0.0
	_safe_seconds = 0.0
	_dragging = false


func task_tick(delta: float) -> void:
	if not _dragging:
		_steer = Input.get_axis(&"ui_left", &"ui_right")
	var current: float = sin(elapsed_seconds * 1.8) * 0.55 + sin(elapsed_seconds * 0.63 + 1.2) * 0.35
	_boat_velocity += (current * 0.80 + _steer * 1.10) * delta
	_boat_velocity = move_toward(_boat_velocity, 0.0, 0.03 * delta)
	_boat_x = clampf(_boat_x + _boat_velocity * delta, 0.04, 0.96)
	if absf(_boat_x - 0.5) <= 0.22:
		_safe_seconds += delta
	set_progress(elapsed_seconds / duration_seconds)


func task_gui_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return false
		_dragging = button.pressed
		return true
	if event is InputEventMouseMotion and _dragging:
		_steer = clampf((event as InputEventMouseMotion).relative.x / 24.0, -1.0, 1.0)
		return true
	return false


func on_suspension_changed(suspended: bool) -> void:
	if suspended:
		_dragging = false
		_steer = 0.0


func on_time_expired() -> void:
	var safe_ratio: float = _safe_seconds / maxf(duration_seconds, 0.001)
	if safe_ratio >= 0.70:
		complete_success({"safe_ratio": safe_ratio}, "神舟稳稳抵达江心")
	else:
		complete_failure(&"left_safe_channel", "顺水势回正", {"safe_ratio": safe_ratio})


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.60, 0.82, 0.85, 1.0), true)
	var safe_rect := Rect2(size.x * 0.28, size.y * 0.08, size.x * 0.44, size.y * 0.84)
	draw_rect(safe_rect, Color(0.80, 0.92, 0.86, 0.72), true)
	for row: int in 9:
		var y: float = size.y * (0.10 + float(row) * 0.10)
		var phase: float = elapsed_seconds * (1.1 + row * 0.06)
		draw_arc(Vector2(size.x * 0.5 + sin(phase) * 80.0, y), size.x * 0.35, 0.1, 3.04, 32, Color(0.23, 0.59, 0.66, 0.42), 3.0, true)
	var boat_position := Vector2(size.x * _boat_x, size.y * 0.64)
	var hull := PackedVector2Array([
		boat_position + Vector2(-54, -10),
		boat_position + Vector2(54, -10),
		boat_position + Vector2(34, 22),
		boat_position + Vector2(-34, 22),
	])
	draw_colored_polygon(hull, Color(0.54, 0.23, 0.12, 1.0))
	draw_line(boat_position + Vector2(0, -12), boat_position + Vector2(0, -78), Color(0.31, 0.17, 0.12, 1.0), 6.0)
	draw_colored_polygon(PackedVector2Array([
		boat_position + Vector2(4, -75),
		boat_position + Vector2(48, -54),
		boat_position + Vector2(4, -36),
	]), Color(0.86, 0.43, 0.18, 1.0))
