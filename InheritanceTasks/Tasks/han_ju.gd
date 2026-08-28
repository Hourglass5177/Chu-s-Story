extends HeritageTaskBase

var _notes: Array[Dictionary] = []
var _next_note: int = 0
var _current_lane: int = 0
var _hits: int = 0


func on_task_started() -> void:
	_notes.clear()
	_next_note = 0
	_current_lane = 0
	_hits = 0
	for index: int in 20:
		_notes.append({
			"time": 1.2 + float(index) * 1.12,
			"lane": get_rng().randi_range(0, 1),
		})


func task_tick(_delta: float) -> void:
	while _next_note < _notes.size() and elapsed_seconds >= float(_notes[_next_note]["time"]):
		if _current_lane == int(_notes[_next_note]["lane"]):
			_hits += 1
			pulse_feedback(&"note_caught")
		_next_note += 1
	set_progress(float(_next_note) / float(_notes.size()))
	if _next_note >= _notes.size():
		_finish_phrase()


func task_input(event: InputEvent) -> bool:
	var joy_accept: bool = event is InputEventJoypadButton \
			and (event as InputEventJoypadButton).button_index == JOY_BUTTON_A \
			and (event as InputEventJoypadButton).pressed
	if event.is_action_pressed(&"ui_accept") or joy_accept:
		_toggle_lane()
		return true
	return false


func task_gui_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
			_toggle_lane()
			return true
	return false


func on_time_expired() -> void:
	_finish_phrase()


func _toggle_lane() -> void:
	_current_lane = 1 - _current_lane
	pulse_feedback(&"lane_switch")


func _finish_phrase() -> void:
	var ratio: float = float(_hits) / maxf(float(_notes.size()), 1.0)
	if ratio >= 0.75:
		complete_success({"hit_ratio": ratio, "hits": _hits}, "皮黄合流")
	else:
		complete_failure(&"notes_missed", "提前看清下一条声腔", {
			"hit_ratio": ratio,
			"hits": _hits,
		})


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.16, 0.09, 0.14, 1.0), true)
	var left: float = size.x * 0.22
	var right: float = size.x * 0.78
	for lane: int in 2:
		var x: float = lerpf(left, right, float(lane))
		draw_line(Vector2(x, size.y * 0.08), Vector2(x, size.y * 0.88), Color(0.80, 0.53, 0.26, 0.55), 8.0, true)
	var catcher_x: float = left if _current_lane == 0 else right
	draw_circle(Vector2(catcher_x, size.y * 0.80), 28.0 + feedback_strength * 5.0, Color(0.96, 0.72, 0.22, 1.0))
	for index: int in range(_next_note, mini(_next_note + 8, _notes.size())):
		var note: Dictionary = _notes[index]
		var seconds_until: float = float(note["time"]) - elapsed_seconds
		var y: float = size.y * 0.80 - seconds_until * 130.0
		var x: float = left if int(note["lane"]) == 0 else right
		if y > size.y * 0.04 and y < size.y * 0.90:
			draw_circle(Vector2(x, y), 18.0, Color(0.83, 0.31, 0.29, 1.0))
	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(left - 90.0, size.y * 0.95), "西皮", HORIZONTAL_ALIGNMENT_CENTER, 180.0, 30)
	draw_string(font, Vector2(right - 90.0, size.y * 0.95), "二黄", HORIZONTAL_ALIGNMENT_CENTER, 180.0, 30)
