extends HeritageTaskBase

enum Stage {
	SHOW,
	REPEAT,
	INTERLUDE,
}

var _stage: Stage = Stage.SHOW
var _stage_time: float = 0.0
var _round_index: int = 0
var _rounds_passed: int = 0
var _pattern: Array[float] = []
var _input_times: Array[float] = []
var _last_shown_beat: int = -1


func on_task_started() -> void:
	_round_index = 0
	_rounds_passed = 0
	_prepare_round()


func task_tick(delta: float) -> void:
	_stage_time += delta
	match _stage:
		Stage.SHOW:
			_update_show()
		Stage.REPEAT:
			if _input_times.size() >= _pattern.size() or _stage_time >= _round_duration() + 0.55:
				_evaluate_round()
		Stage.INTERLUDE:
			if _stage_time >= 0.7:
				if _round_index >= 3:
					_finish_all_rounds()
				else:
					_prepare_round()
		_:
			complete_technical_error(&"invalid_stage", "鼓板流程发生错误")


func task_input(event: InputEvent) -> bool:
	var joy_accept: bool = event is InputEventJoypadButton \
			and (event as InputEventJoypadButton).button_index == JOY_BUTTON_A \
			and (event as InputEventJoypadButton).pressed
	if _stage == Stage.REPEAT and (event.is_action_pressed(&"ui_accept") or joy_accept):
		_record_hit()
		return true
	return false


func task_gui_input(event: InputEvent) -> bool:
	if _stage != Stage.REPEAT or not (event is InputEventMouseButton):
		return false
	var button := event as InputEventMouseButton
	if button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
		_record_hit()
		return true
	return false


func on_time_expired() -> void:
	_finish_all_rounds()


func _prepare_round() -> void:
	_stage = Stage.SHOW
	_stage_time = 0.0
	_input_times.clear()
	_last_shown_beat = -1
	_pattern.clear()
	var beat_count: int = 3 + _round_index
	var cursor: float = 0.55
	for beat: int in beat_count:
		_pattern.append(cursor)
		cursor += 0.48 if get_rng().randf() < 0.58 else 0.76
	queue_redraw()


func _update_show() -> void:
	for index: int in _pattern.size():
		if index > _last_shown_beat and _stage_time >= _pattern[index]:
			_last_shown_beat = index
			pulse_feedback(&"drum", Vector2(size.x * 0.5, size.y * 0.52))
	if _stage_time >= _round_duration():
		_stage = Stage.REPEAT
		_stage_time = 0.0
		_last_shown_beat = -1
		queue_redraw()


func _record_hit() -> void:
	if _input_times.size() >= _pattern.size():
		return
	_input_times.append(_stage_time)
	pulse_feedback(&"drum", Vector2(size.x * 0.5, size.y * 0.52))


func _evaluate_round() -> void:
	var total_error: float = 0.0
	for index: int in _pattern.size():
		if index >= _input_times.size():
			total_error += 0.65
		else:
			total_error += absf(_input_times[index] - _pattern[index])
	var average_error: float = total_error / float(_pattern.size())
	if average_error <= 0.28:
		_rounds_passed += 1
		pulse_feedback(&"round_success")
	_round_index += 1
	set_progress(float(_round_index) / 3.0)
	_stage = Stage.INTERLUDE
	_stage_time = 0.0


func _finish_all_rounds() -> void:
	if _rounds_passed >= 2:
		complete_success({"rounds_passed": _rounds_passed}, "鼓板接上了")
	else:
		complete_failure(&"rhythm_missed", "再听清停顿的位置", {
			"rounds_passed": _rounds_passed,
		})


func _round_duration() -> float:
	return (_pattern[-1] if not _pattern.is_empty() else 1.0) + 0.65


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.24, 0.12, 0.10, 1.0), true)
	var drum_center := Vector2(size.x * 0.5, size.y * 0.55)
	draw_circle(drum_center, 130.0 + feedback_strength * 12.0, Color(0.53, 0.24, 0.15, 1.0))
	draw_circle(drum_center, 102.0, Color(0.86, 0.70, 0.48, 1.0))
	draw_arc(drum_center, 102.0, 0.0, TAU, 64, Color(0.30, 0.15, 0.11, 1.0), 7.0, true)
	var font: Font = ThemeDB.fallback_font
	var stage_text: String = "听"
	if _stage == Stage.REPEAT:
		stage_text = "接"
	elif _stage == Stage.INTERLUDE:
		stage_text = "第%d轮" % _round_index
	draw_string(font, Vector2(0.0, size.y * 0.18), stage_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 40)
	if _stage == Stage.REPEAT:
		var timeline := Rect2(size.x * 0.18, size.y * 0.82, size.x * 0.64, 8.0)
		draw_rect(timeline, Color(0.82, 0.63, 0.38, 0.45), true)
		for hit_time: float in _input_times:
			var x: float = timeline.position.x + timeline.size.x * hit_time / maxf(_round_duration(), 0.001)
			draw_circle(Vector2(x, timeline.position.y + 4.0), 8.0, Color(0.95, 0.72, 0.24, 1.0))
