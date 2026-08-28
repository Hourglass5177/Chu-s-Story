extends HeritageTaskBase

var _pick_y: float = 0.5
var _target_y: float = 0.5
var _inside_seconds: float = 0.0
var _mouse_active: bool = false


func on_task_started() -> void:
	_pick_y = 0.5
	_target_y = 0.5
	_inside_seconds = 0.0
	_mouse_active = false


func task_tick(delta: float) -> void:
	_target_y = 0.5 + sin(elapsed_seconds * 0.83) * 0.27 + sin(elapsed_seconds * 0.31 + 0.7) * 0.09
	var input_y: float = Input.get_axis(&"ui_up", &"ui_down")
	if not is_zero_approx(input_y):
		_mouse_active = false
		_pick_y = clampf(_pick_y + input_y * delta * 0.74, 0.10, 0.90)
	elif not _mouse_active:
		_pick_y = clampf(_pick_y + input_y * delta * 0.74, 0.10, 0.90)
	if absf(_pick_y - _target_y) <= 0.105:
		_inside_seconds += delta
	set_progress(elapsed_seconds / duration_seconds)


func task_gui_input(event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		_pick_y = clampf((event as InputEventMouseMotion).position.y / maxf(size.y, 1.0), 0.10, 0.90)
		_mouse_active = true
		return true
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_mouse_active = button.pressed
			_pick_y = clampf(button.position.y / maxf(size.y, 1.0), 0.10, 0.90)
			return true
	return false


func on_suspension_changed(suspended: bool) -> void:
	if suspended:
		_mouse_active = false


func on_time_expired() -> void:
	var ratio: float = _inside_seconds / maxf(duration_seconds, 0.001)
	if ratio >= 0.75:
		complete_success({"inside_ratio": ratio}, "一拨成曲")
	else:
		complete_failure(&"melody_lost", "拨片还可以再贴近光带", {"inside_ratio": ratio})


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.14, 0.11, 0.09, 1.0), true)
	for string_index: int in 3:
		var y: float = size.y * (0.30 + string_index * 0.20)
		draw_line(Vector2(size.x * 0.08, y), Vector2(size.x * 0.92, y), Color(0.86, 0.68, 0.34, 0.72), 5.0, true)
	var target := Vector2(size.x * 0.55, size.y * _target_y)
	draw_circle(target, 48.0, Color(0.87, 0.51, 0.19, 0.30))
	draw_circle(Vector2(size.x * 0.55, size.y * _pick_y), 22.0 + feedback_strength * 4.0, Color(0.98, 0.82, 0.34, 1.0))
	draw_line(Vector2(size.x * 0.20, size.y * _pick_y), Vector2(size.x * 0.55, size.y * _pick_y), Color(0.92, 0.72, 0.32, 0.84), 7.0, true)
