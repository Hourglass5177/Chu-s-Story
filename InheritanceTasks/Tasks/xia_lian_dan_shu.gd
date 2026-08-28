extends HeritageTaskBase

var _heat: float = 0.35
var _heat_velocity: float = 0.0
var _holding: bool = false
var _controller_holding: bool = false
var _target_center: float = 0.55
var _last_feedback_second: int = -1


func on_task_started() -> void:
	_heat = 0.35
	_heat_velocity = 0.0
	_holding = false
	_controller_holding = false
	_last_feedback_second = -1


func task_tick(delta: float) -> void:
	var active_heat: bool = _holding or _controller_holding or Input.is_action_pressed(&"ui_accept")
	var acceleration: float = 1.30 if active_heat else -0.92
	_heat_velocity += acceleration * delta
	_heat_velocity = clampf(_heat_velocity, -0.62, 0.72)
	_heat_velocity = move_toward(_heat_velocity, 0.0, 0.28 * delta)
	_heat = clampf(_heat + _heat_velocity * delta, 0.0, 1.0)
	_target_center = 0.52 + sin(elapsed_seconds * 0.72) * 0.20 + sin(elapsed_seconds * 0.21 + 0.8) * 0.08
	var inside: bool = absf(_heat - _target_center) <= 0.105
	var next_progress: float = progress + delta * 0.072 if inside else progress - delta * 0.022
	set_progress(next_progress)
	var current_second: int = int(floor(elapsed_seconds))
	if inside and current_second != _last_feedback_second:
		_last_feedback_second = current_second
		pulse_feedback(&"steady_fire", Vector2(size.x * 0.5, size.y * (1.0 - _heat)))
	if progress >= 1.0:
		complete_success({"final_heat": _heat}, "炉火稳住了")


func task_gui_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_holding = button.pressed
			return true
	return false


func task_input(event: InputEvent) -> bool:
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == JOY_BUTTON_A:
		_controller_holding = (event as InputEventJoypadButton).pressed
		return true
	return false


func on_suspension_changed(suspended: bool) -> void:
	if suspended:
		_holding = false
		_controller_holding = false


func on_time_expired() -> void:
	var reason: StringName = &"heat_too_low" if _heat < _target_center else &"heat_too_high"
	var message: String = "回落过久" if _heat < _target_center else "升温过快"
	complete_failure(reason, message, {"final_heat": _heat, "furnace_progress": progress})


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.18, 0.11, 0.09, 1.0), true)
	var gauge := Rect2(size.x * 0.40, size.y * 0.10, size.x * 0.20, size.y * 0.78)
	draw_rect(gauge, Color(0.30, 0.22, 0.18, 1.0), true)
	var band_center_y: float = gauge.position.y + gauge.size.y * (1.0 - _target_center)
	var band := Rect2(gauge.position.x, band_center_y - gauge.size.y * 0.105, gauge.size.x, gauge.size.y * 0.21)
	draw_rect(band, Color(0.91, 0.62, 0.19, 0.58), true)
	var marker_y: float = gauge.position.y + gauge.size.y * (1.0 - _heat)
	draw_line(Vector2(gauge.position.x - 22.0, marker_y), Vector2(gauge.end.x + 22.0, marker_y), Color(1.0, 0.86, 0.48, 1.0), 10.0, true)
	var flame_center := Vector2(size.x * 0.5, size.y * 0.93)
	draw_circle(flame_center, 34.0 + _heat * 28.0, Color(0.92, 0.24, 0.08, 0.82))
	draw_circle(flame_center, 18.0 + _heat * 14.0, Color(1.0, 0.74, 0.16, 0.92))
