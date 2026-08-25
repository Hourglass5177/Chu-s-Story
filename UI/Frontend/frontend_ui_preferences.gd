class_name FrontendUIPreferences
extends Resource

## Public preference surface for future settings UI. This resource does not persist
## values and deliberately does not alter project-wide stretch settings.

signal ui_scale_changed(value: float)
signal reduce_motion_changed(enabled: bool)
signal ui_sound_enabled_changed(enabled: bool)
signal ui_feedback_requested(cue: StringName)

const MIN_UI_SCALE := 0.75
const MAX_UI_SCALE := 1.50

@export_range(MIN_UI_SCALE, MAX_UI_SCALE, 0.05) var ui_scale: float = 1.0:
	set(value):
		var next_value := clampf(value, MIN_UI_SCALE, MAX_UI_SCALE)
		if is_equal_approx(ui_scale, next_value):
			return
		ui_scale = next_value
		ui_scale_changed.emit(ui_scale)

@export var reduce_motion := false:
	set(value):
		if reduce_motion == value:
			return
		reduce_motion = value
		reduce_motion_changed.emit(reduce_motion)

@export var ui_sound_enabled := true:
	set(value):
		if ui_sound_enabled == value:
			return
		ui_sound_enabled = value
		ui_sound_enabled_changed.emit(ui_sound_enabled)


func transition_duration(base_duration: float) -> float:
	return 0.0 if reduce_motion else maxf(base_duration, 0.0)


func request_feedback(cue: StringName) -> void:
	if ui_sound_enabled:
		ui_feedback_requested.emit(cue)
