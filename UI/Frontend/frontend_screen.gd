class_name FrontendScreen
extends Control

## Base class for front-end pages and modal screens.
## It owns one cancellable transition, focus hand-off, and ui_cancel routing.

signal back_requested
signal screen_state_changed(state: ScreenState)
signal transition_finished(state: ScreenState)

enum ScreenState {
	HIDDEN,
	ENTERING,
	ACTIVE,
	EXITING,
}

@export var initial_focus_path: NodePath
@export var transition_target_path: NodePath
@export_range(0.0, 1.0, 0.01) var transition_duration := 0.20
@export_range(0.0, 80.0, 1.0) var slide_distance := 18.0
@export var handle_cancel_action := true

var screen_state := ScreenState.HIDDEN
var _transition: Tween
var _transition_serial := 0
var _preferences: FrontendUIPreferences
var _interaction_enabled := false
var _saved_focus_controls: Array[Control] = []
var _saved_focus_modes: Array[int] = []
var _transition_rest_position := Vector2.ZERO


func _ready() -> void:
	set_process_unhandled_input(false)
	var target := _get_transition_target()
	if target != null:
		_transition_rest_position = target.position
	if visible:
		screen_state = ScreenState.ACTIVE
		set_interaction_enabled(true)
		call_deferred("grab_initial_focus")
	else:
		screen_state = ScreenState.HIDDEN


func set_ui_preferences(preferences: FrontendUIPreferences) -> void:
	_preferences = preferences


func enter_screen(animated := true) -> void:
	_transition_serial += 1
	_kill_transition()
	var target := _prepare_transition_target()
	visible = true
	_set_state(ScreenState.ENTERING)
	set_interaction_enabled(false)

	modulate.a = 0.0 if animated else 1.0
	if target != null and animated:
		target.position = _transition_rest_position + Vector2(0.0, slide_distance)

	var duration := _effective_duration(animated)
	if is_zero_approx(duration):
		_finish_enter(_transition_serial)
		return

	var serial := _transition_serial
	_transition = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	_transition.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_transition.tween_property(self, "modulate:a", 1.0, duration)
	if target != null:
		_transition.tween_property(target, "position", _transition_rest_position, duration)
	_transition.finished.connect(func() -> void: _finish_enter(serial), CONNECT_ONE_SHOT)


func exit_screen(animated := true, hide_when_finished := true) -> void:
	if screen_state == ScreenState.HIDDEN:
		return
	_transition_serial += 1
	_kill_transition()
	var target := _prepare_transition_target()
	_set_state(ScreenState.EXITING)
	set_interaction_enabled(false)

	var duration := _effective_duration(animated)
	if is_zero_approx(duration):
		_finish_exit(_transition_serial, hide_when_finished)
		return

	var serial := _transition_serial
	_transition = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	_transition.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_transition.tween_property(self, "modulate:a", 0.0, duration)
	if target != null:
		_transition.tween_property(
			target,
			"position",
			_transition_rest_position + Vector2(0.0, -slide_distance * 0.55),
			duration
		)
	_transition.finished.connect(
		func() -> void: _finish_exit(serial, hide_when_finished),
		CONNECT_ONE_SHOT
	)


func set_interaction_enabled(enabled: bool) -> void:
	if _interaction_enabled == enabled:
		if not enabled:
			_disable_descendant_focus()
		set_process_unhandled_input(enabled and screen_state == ScreenState.ACTIVE)
		return
	_interaction_enabled = enabled
	set_process_unhandled_input(enabled and screen_state == ScreenState.ACTIVE)
	if enabled:
		_restore_focus_modes()
	else:
		_disable_descendant_focus()
		var owner := get_viewport().gui_get_focus_owner()
		if owner != null and (owner == self or is_ancestor_of(owner)):
			owner.release_focus()


func is_interaction_enabled() -> bool:
	return _interaction_enabled


func cancel_transition(hide_screen := false) -> void:
	_transition_serial += 1
	_kill_transition()
	modulate.a = 1.0
	var target := _get_transition_target()
	if target != null:
		target.position = _transition_rest_position
	set_interaction_enabled(false)
	if hide_screen:
		visible = false
	_set_state(ScreenState.HIDDEN)


func grab_initial_focus() -> void:
	if not visible or not _interaction_enabled:
		return
	var requested := get_node_or_null(initial_focus_path) as Control
	if _can_focus(requested):
		requested.grab_focus()
		return
	var fallback := _find_first_focusable(self)
	if fallback != null:
		fallback.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not handle_cancel_action or screen_state != ScreenState.ACTIVE:
		return
	if event.is_action_pressed("ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()


func _finish_enter(serial: int) -> void:
	if serial != _transition_serial or not is_inside_tree():
		return
	_transition = null
	modulate.a = 1.0
	var target := _get_transition_target()
	if target != null:
		target.position = _transition_rest_position
	_set_state(ScreenState.ACTIVE)
	set_interaction_enabled(true)
	grab_initial_focus()
	transition_finished.emit(screen_state)


func _finish_exit(serial: int, hide_when_finished: bool) -> void:
	if serial != _transition_serial or not is_inside_tree():
		return
	_transition = null
	modulate.a = 1.0
	var target := _get_transition_target()
	if target != null:
		target.position = _transition_rest_position
	if hide_when_finished:
		visible = false
	_set_state(ScreenState.HIDDEN)
	transition_finished.emit(screen_state)


func _effective_duration(animated: bool) -> float:
	if not animated:
		return 0.0
	if _preferences != null:
		return _preferences.transition_duration(transition_duration)
	return transition_duration


func _kill_transition() -> void:
	if _transition != null and _transition.is_valid():
		_transition.kill()
	_transition = null


func _get_transition_target() -> Control:
	if transition_target_path.is_empty():
		return null
	return get_node_or_null(transition_target_path) as Control


## A transition can be interrupted by a rapid confirm/back input. In that case the
## target is between its rest and slide positions; never treat that transient value
## as the next animation's baseline.
func _prepare_transition_target() -> Control:
	var target := _get_transition_target()
	if target == null:
		return null
	if screen_state == ScreenState.HIDDEN or screen_state == ScreenState.ACTIVE:
		_transition_rest_position = target.position
	else:
		target.position = _transition_rest_position
	return target


func _set_state(next_state: ScreenState) -> void:
	if screen_state == next_state:
		return
	screen_state = next_state
	set_process_unhandled_input(_interaction_enabled and screen_state == ScreenState.ACTIVE)
	screen_state_changed.emit(screen_state)


func _disable_descendant_focus() -> void:
	_collect_focus_controls(self)
	for control in _saved_focus_controls:
		if is_instance_valid(control):
			control.focus_mode = Control.FOCUS_NONE


func _collect_focus_controls(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			var control := child as Control
			if control.focus_mode != Control.FOCUS_NONE and not _saved_focus_controls.has(control):
				_saved_focus_controls.append(control)
				_saved_focus_modes.append(control.focus_mode)
		_collect_focus_controls(child)


func _restore_focus_modes() -> void:
	for index in mini(_saved_focus_controls.size(), _saved_focus_modes.size()):
		var control := _saved_focus_controls[index]
		if is_instance_valid(control):
			control.focus_mode = _saved_focus_modes[index] as Control.FocusMode
	_saved_focus_controls.clear()
	_saved_focus_modes.clear()


func _find_first_focusable(node: Node) -> Control:
	for child in node.get_children():
		if child is Control:
			var control := child as Control
			if _can_focus(control):
				return control
		var nested := _find_first_focusable(child)
		if nested != null:
			return nested
	return null


func _can_focus(control: Control) -> bool:
	if control == null or not control.is_visible_in_tree():
		return false
	if control.focus_mode == Control.FOCUS_NONE:
		return false
	if control is BaseButton and (control as BaseButton).disabled:
		return false
	return true
