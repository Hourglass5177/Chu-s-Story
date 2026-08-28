extends HeritageTaskBase

const PATH_COLOR := Color(0.72, 0.18, 0.12, 1.0)
const PAPER_COLOR := Color(0.96, 0.84, 0.62, 1.0)

var _path: PackedVector2Array = PackedVector2Array()
var _pointer: Vector2 = Vector2.ZERO
var _last_pointer: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _controller_cutting: bool = false
var _off_path_seconds: float = 0.0
var _path_progress: float = 0.0


func on_task_started() -> void:
	_build_path()
	_pointer = _path[0]
	_last_pointer = _pointer
	_dragging = false
	_controller_cutting = false
	_off_path_seconds = 0.0
	_path_progress = 0.0
	queue_redraw()


func task_tick(delta: float) -> void:
	if _path.is_empty():
		return
	var direction := Input.get_vector(&"ui_left", &"ui_right", &"ui_up", &"ui_down")
	var keyboard_cutting: bool = Input.is_action_pressed(&"ui_accept") or _controller_cutting
	if keyboard_cutting and direction != Vector2.ZERO:
		_pointer += direction * 270.0 * delta
		_pointer.x = clampf(_pointer.x, 0.0, size.x)
		_pointer.y = clampf(_pointer.y, 0.0, size.y)
	if _dragging or keyboard_cutting:
		_update_trace(delta)
	else:
		_last_pointer = _pointer
	if _path_progress >= 0.995:
		if _off_path_seconds <= 2.8:
			complete_success({"off_path_seconds": _off_path_seconds}, "一刀成花")
		else:
			complete_failure(&"paper_bridge_cut", "纸桥被切断了", {
				"off_path_seconds": _off_path_seconds,
			})


func task_gui_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return false
		_dragging = button.pressed
		_pointer = button.position
		if button.pressed:
			_last_pointer = _pointer
		return true
	if event is InputEventMouseMotion and _dragging:
		_pointer = (event as InputEventMouseMotion).position
		return true
	return false


func task_input(event: InputEvent) -> bool:
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == JOY_BUTTON_A:
		_controller_cutting = (event as InputEventJoypadButton).pressed
		return true
	return false


func on_suspension_changed(suspended: bool) -> void:
	if suspended:
		_dragging = false
		_controller_cutting = false
		_last_pointer = _pointer


func on_time_expired() -> void:
	complete_failure(&"trace_incomplete", "刻线还没有走完", {
		"trace_progress": _path_progress,
		"off_path_seconds": _off_path_seconds,
	})


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready() and run_state == RunState.RUNNING:
		_build_path()


func _build_path() -> void:
	var w: float = maxf(size.x, 800.0)
	var h: float = maxf(size.y, 500.0)
	_path = PackedVector2Array([
		Vector2(w * 0.10, h * 0.72),
		Vector2(w * 0.18, h * 0.43),
		Vector2(w * 0.33, h * 0.25),
		Vector2(w * 0.47, h * 0.45),
		Vector2(w * 0.58, h * 0.24),
		Vector2(w * 0.75, h * 0.38),
		Vector2(w * 0.88, h * 0.68),
	])


func _update_trace(delta: float) -> void:
	var travel_distance: float = _last_pointer.distance_to(_pointer)
	var sample_count: int = maxi(1, int(ceil(travel_distance / 18.0)))
	for sample_index: int in sample_count:
		var ratio: float = float(sample_index + 1) / float(sample_count)
		var sample: Vector2 = _last_pointer.lerp(_pointer, ratio)
		_update_trace_sample(sample, delta / float(sample_count))
	_last_pointer = _pointer


func _update_trace_sample(sample: Vector2, delta: float) -> void:
	var nearest_distance: float = INF
	var nearest_progress: float = 0.0
	var traversed: float = 0.0
	var total_length: float = 0.0
	for index: int in range(_path.size() - 1):
		total_length += _path[index].distance_to(_path[index + 1])
	for index: int in range(_path.size() - 1):
		var from: Vector2 = _path[index]
		var to: Vector2 = _path[index + 1]
		var segment: Vector2 = to - from
		var length_squared: float = segment.length_squared()
		var ratio: float = clampf((sample - from).dot(segment) / maxf(length_squared, 0.001), 0.0, 1.0)
		var closest: Vector2 = from + segment * ratio
		var distance: float = sample.distance_to(closest)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_progress = (traversed + segment.length() * ratio) / maxf(total_length, 0.001)
		traversed += segment.length()
	var tolerance: float = 42.0 if _dragging else 58.0
	var follows_cut_edge: bool = nearest_progress + 0.07 >= _path_progress \
			and nearest_progress <= _path_progress + 0.12
	if nearest_distance <= tolerance and follows_cut_edge:
		_path_progress = maxf(_path_progress, nearest_progress)
		set_progress(_path_progress)
	else:
		_off_path_seconds += delta


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PAPER_COLOR, true)
	for offset: float in [0.0, 9.0, 18.0]:
		var shifted := PackedVector2Array()
		for point: Vector2 in _path:
			shifted.append(point + Vector2(offset * 0.35, offset))
		if shifted.size() > 1:
			draw_polyline(shifted, Color(0.56, 0.33, 0.20, 0.18), 3.0, true)
	if _path.size() > 1:
		draw_polyline(_path, Color(0.55, 0.34, 0.22, 0.45), 38.0, true)
		draw_polyline(_path, PATH_COLOR, 5.0, true)
	var completed_points := PackedVector2Array()
	var last_index: int = clampi(int(floor(_path_progress * float(_path.size() - 1))) + 1, 1, _path.size())
	for index: int in last_index:
		completed_points.append(_path[index])
	if completed_points.size() > 1:
		draw_polyline(completed_points, Color(0.91, 0.60, 0.12, 1.0), 8.0, true)
	draw_circle(_pointer, 17.0 + feedback_strength * 4.0, Color(0.24, 0.18, 0.14, 1.0))
	draw_circle(_path[0] if not _path.is_empty() else Vector2.ZERO, 11.0, Color(0.18, 0.55, 0.35, 1.0))
	draw_circle(_path[-1] if not _path.is_empty() else Vector2.ZERO, 13.0, Color(0.82, 0.32, 0.12, 1.0))
