extends HeritageTaskBase

enum Stage {
	SHOW,
	INPUT,
	INTERLUDE,
}

const ICONS: Array[String] = ["山", "河", "灯", "树", "鸟", "桥"]

var _stage: Stage = Stage.SHOW
var _stage_time: float = 0.0
var _round_index: int = 0
var _rounds_passed: int = 0
var _pattern: Array[int] = []
var _entered: Array[int] = []
var _selection: int = 0


func on_task_started() -> void:
	_round_index = 0
	_rounds_passed = 0
	_prepare_round()


func task_tick(delta: float) -> void:
	_stage_time += delta
	match _stage:
		Stage.SHOW:
			if _stage_time >= float(_pattern.size()) * 0.68 + 0.45:
				_stage = Stage.INPUT
				_stage_time = 0.0
		Stage.INPUT:
			pass
		Stage.INTERLUDE:
			if _stage_time >= 0.75:
				if _round_index >= 3:
					_finish_story()
				else:
					_prepare_round()
		_:
			complete_technical_error(&"invalid_stage", "故事传递流程发生错误")


func task_input(event: InputEvent) -> bool:
	if _stage != Stage.INPUT:
		return false
	var joy_accept: bool = event is InputEventJoypadButton \
			and (event as InputEventJoypadButton).button_index == JOY_BUTTON_A \
			and (event as InputEventJoypadButton).pressed
	if event.is_action_pressed(&"ui_left"):
		_selection = wrapi(_selection - 1, 0, ICONS.size())
		queue_redraw()
		return true
	if event.is_action_pressed(&"ui_right"):
		_selection = wrapi(_selection + 1, 0, ICONS.size())
		queue_redraw()
		return true
	if event.is_action_pressed(&"ui_up") or event.is_action_pressed(&"ui_down"):
		_selection = wrapi(_selection + (3 if event.is_action_pressed(&"ui_down") else -3), 0, ICONS.size())
		queue_redraw()
		return true
	if event.is_action_pressed(&"ui_accept") or joy_accept:
		_submit_icon(_selection)
		return true
	return false


func task_gui_input(event: InputEvent) -> bool:
	if _stage != Stage.INPUT or not (event is InputEventMouseButton):
		return false
	var button := event as InputEventMouseButton
	if button.button_index != MOUSE_BUTTON_LEFT or not button.pressed:
		return false
	var grid := Rect2(size.x * 0.20, size.y * 0.30, size.x * 0.60, size.y * 0.48)
	if not grid.has_point(button.position):
		return false
	var local: Vector2 = button.position - grid.position
	var column: int = clampi(int(local.x / (grid.size.x / 3.0)), 0, 2)
	var row: int = clampi(int(local.y / (grid.size.y / 2.0)), 0, 1)
	_selection = row * 3 + column
	_submit_icon(_selection)
	return true


func on_time_expired() -> void:
	_finish_story()


func _prepare_round() -> void:
	_stage = Stage.SHOW
	_stage_time = 0.0
	_pattern.clear()
	_entered.clear()
	_selection = 0
	var length: int = 4 + _round_index
	for index: int in length:
		_pattern.append(get_rng().randi_range(0, ICONS.size() - 1))
	queue_redraw()


func _submit_icon(icon_index: int) -> void:
	if _entered.size() >= _pattern.size():
		return
	_entered.append(icon_index)
	pulse_feedback(&"story_icon")
	var entered_index: int = _entered.size() - 1
	if _entered[entered_index] != _pattern[entered_index]:
		_finish_round(false)
	elif _entered.size() == _pattern.size():
		_finish_round(true)


func _finish_round(passed: bool) -> void:
	if passed:
		_rounds_passed += 1
		pulse_feedback(&"story_passed")
	_round_index += 1
	set_progress(float(_round_index) / 3.0)
	_stage = Stage.INTERLUDE
	_stage_time = 0.0


func _finish_story() -> void:
	if _rounds_passed >= 2:
		complete_success({"rounds_passed": _rounds_passed}, "故事传到了下一位听众")
	else:
		complete_failure(&"story_order", "先记住开头，再顺着往下传", {
			"rounds_passed": _rounds_passed,
		})


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.19, 0.13, 0.09, 1.0), true)
	var font: Font = ThemeDB.fallback_font
	if _stage == Stage.SHOW:
		if _pattern.is_empty():
			return
		var shown_index: int = clampi(int(_stage_time / 0.68), 0, _pattern.size() - 1)
		draw_string(font, Vector2(0, size.y * 0.57), ICONS[_pattern[shown_index]], HORIZONTAL_ALIGNMENT_CENTER, size.x, 92)
		draw_string(font, Vector2(0, size.y * 0.24), "听住这一串", HORIZONTAL_ALIGNMENT_CENTER, size.x, 34)
	elif _stage == Stage.INPUT:
		var grid := Rect2(size.x * 0.20, size.y * 0.30, size.x * 0.60, size.y * 0.48)
		for index: int in ICONS.size():
			var column: int = index % 3
			var row: int = index / 3
			var cell := Rect2(
				grid.position + Vector2(column * grid.size.x / 3.0, row * grid.size.y / 2.0),
				Vector2(grid.size.x / 3.0 - 10.0, grid.size.y / 2.0 - 10.0)
			)
			var color := Color(0.55, 0.31, 0.17, 0.75)
			if index == _selection:
				color = Color(0.89, 0.59, 0.18, 0.95)
			draw_rect(cell, color, true)
			draw_string(font, Vector2(cell.position.x, cell.position.y + cell.size.y * 0.64), ICONS[index], HORIZONTAL_ALIGNMENT_CENTER, cell.size.x, 44)
		draw_string(font, Vector2(0, size.y * 0.22), "%d / %d" % [_entered.size(), _pattern.size()], HORIZONTAL_ALIGNMENT_CENTER, size.x, 30)
	else:
		draw_string(font, Vector2(0, size.y * 0.55), "继续传下去", HORIZONTAL_ALIGNMENT_CENTER, size.x, 46)
