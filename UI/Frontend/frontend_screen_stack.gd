class_name FrontendScreenStack
extends Control

## Small front-end screen stack. It coordinates visibility/focus only; pages keep
## their own data and communicate upward with explicit signals.

signal stack_changed(depth: int, top_screen: FrontendScreen)
signal root_back_requested

var _screens: Array[FrontendScreen] = []
var _overlays: Array[bool] = []
var _return_focus: Array[WeakRef] = []
var _transition_locked := false
var _preferences: FrontendUIPreferences


func set_ui_preferences(preferences: FrontendUIPreferences) -> void:
	_preferences = preferences
	for screen in _screens:
		if is_instance_valid(screen):
			screen.set_ui_preferences(preferences)


func set_root_screen(screen: FrontendScreen, animated := false) -> bool:
	clear_screens(true)
	return push_screen(screen, false, animated)


func push_screen(screen: FrontendScreen, overlay := false, animated := true) -> bool:
	if _transition_locked or screen == null or not is_instance_valid(screen):
		return false
	if _screens.has(screen):
		return false
	if screen.get_parent() != null and screen.get_parent() != self:
		return false
	var previous := get_top_screen()
	var focus_owner := get_viewport().gui_get_focus_owner()
	_return_focus.append(weakref(focus_owner) if focus_owner != null else weakref(self))
	if previous != null:
		previous.set_interaction_enabled(false)
		if not overlay:
			previous.visible = false
	_screens.append(screen)
	_overlays.append(overlay)
	if screen.get_parent() == null:
		add_child(screen)
	if _preferences != null:
		screen.set_ui_preferences(_preferences)
	var back_callback := _on_screen_back_requested.bind(screen)
	if not screen.back_requested.is_connected(back_callback):
		screen.back_requested.connect(back_callback)
	var wait_for_transition := _will_animate(screen, animated)
	if wait_for_transition:
		_transition_locked = true
		var on_entered := func(state: FrontendScreen.ScreenState) -> void:
			if state == FrontendScreen.ScreenState.ACTIVE:
				_transition_locked = false
		screen.transition_finished.connect(on_entered, CONNECT_ONE_SHOT)
	screen.enter_screen(animated)
	stack_changed.emit(_screens.size(), screen)
	return true


func pop_screen(animated := true) -> bool:
	if _transition_locked or _screens.size() <= 1:
		if _screens.size() <= 1:
			root_back_requested.emit()
		return false
	_transition_locked = true
	var departing: FrontendScreen = _screens.pop_back()
	var was_overlay: bool = _overlays.pop_back()
	var focus_ref: WeakRef = _return_focus.pop_back()
	var restore := func() -> void:
		var previous := get_top_screen()
		if previous == null:
			_transition_locked = false
			stack_changed.emit(0, null)
			return
		if was_overlay:
			previous.visible = true
			previous.set_interaction_enabled(true)
			_transition_locked = false
			_restore_prior_focus(previous, focus_ref)
		else:
			var wait_for_enter := _will_animate(previous, animated)
			if wait_for_enter:
				var on_reentered := func(state: FrontendScreen.ScreenState) -> void:
					if state != FrontendScreen.ScreenState.ACTIVE:
						return
					_transition_locked = false
					_restore_prior_focus(previous, focus_ref)
				previous.transition_finished.connect(on_reentered, CONNECT_ONE_SHOT)
			previous.enter_screen(animated)
			if not wait_for_enter:
				_transition_locked = false
				_restore_prior_focus(previous, focus_ref)
		stack_changed.emit(_screens.size(), previous)

	if not animated or departing.transition_duration <= 0.0 or (
		_preferences != null and _preferences.reduce_motion
	):
		departing.exit_screen(false)
		restore.call()
	else:
		var on_finished := func(state: FrontendScreen.ScreenState) -> void:
			if state == FrontendScreen.ScreenState.HIDDEN:
				restore.call()
		departing.transition_finished.connect(on_finished, CONNECT_ONE_SHOT)
		departing.exit_screen(true)
	return true


func replace_screen(screen: FrontendScreen, animated := true) -> bool:
	if _screens.is_empty():
		return push_screen(screen, false, animated)
	if _transition_locked or screen == null or _screens.has(screen):
		return false
	var old: FrontendScreen = _screens.pop_back()
	_overlays.pop_back()
	_return_focus.pop_back()
	old.exit_screen(false)
	return push_screen(screen, false, animated)


func clear_screens(hide := true) -> void:
	_transition_locked = false
	for screen in _screens:
		if is_instance_valid(screen):
			screen.cancel_transition(hide)
	_screens.clear()
	_overlays.clear()
	_return_focus.clear()
	stack_changed.emit(0, null)


func get_top_screen() -> FrontendScreen:
	return _screens.back() if not _screens.is_empty() else null


func get_depth() -> int:
	return _screens.size()


func is_transition_locked() -> bool:
	return _transition_locked


func _on_screen_back_requested(requesting_screen: FrontendScreen) -> void:
	if requesting_screen != get_top_screen():
		return
	pop_screen(true)


func _will_animate(screen: FrontendScreen, requested: bool) -> bool:
	if not requested or screen.transition_duration <= 0.0:
		return false
	return _preferences == null or not _preferences.reduce_motion


func _restore_prior_focus(screen: FrontendScreen, focus_ref: WeakRef) -> void:
	_apply_prior_focus.call_deferred(screen, focus_ref)


func _apply_prior_focus(screen: FrontendScreen, focus_ref: WeakRef) -> void:
	if screen != get_top_screen() or not is_instance_valid(screen) or not screen.is_visible_in_tree():
		return
	var prior_focus := focus_ref.get_ref() as Control
	if prior_focus != null and prior_focus.is_visible_in_tree() and prior_focus.focus_mode != Control.FOCUS_NONE:
		prior_focus.grab_focus()
	else:
		screen.grab_initial_focus()
