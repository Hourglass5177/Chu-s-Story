class_name FrontendNumberStepper
extends HBoxContainer

signal value_changed(value: int)
signal boundary_pressed(direction: int)

@export var caption := "玩家":
	set(value):
		caption = value
		_sync_view()

@export var minimum := 0:
	set(value):
		minimum = value
		if maximum < minimum:
			maximum = minimum
		current_value = clampi(current_value, minimum, maximum)
		_sync_view()

@export var maximum := 6:
	set(value):
		maximum = maxi(value, minimum)
		current_value = clampi(current_value, minimum, maximum)
		_sync_view()

@export var current_value := 1:
	set(value):
		current_value = clampi(value, minimum, maximum)
		_sync_view()

@export_range(1, 100, 1) var step_size := 1

@export var value_suffix := " 人":
	set(value):
		value_suffix = value
		_sync_view()

@onready var _caption_label: Label = %Caption
@onready var _decrease_button: Button = %Decrease
@onready var _value_label: Label = %Value
@onready var _increase_button: Button = %Increase


func _ready() -> void:
	_decrease_button.pressed.connect(_on_decrease_pressed)
	_increase_button.pressed.connect(_on_increase_pressed)
	_decrease_button.focus_neighbor_right = _increase_button.get_path()
	_increase_button.focus_neighbor_left = _decrease_button.get_path()
	_sync_view()


func set_bounds(new_minimum: int, new_maximum: int, emit_change := true) -> void:
	var old_value := current_value
	minimum = new_minimum
	maximum = maxi(new_maximum, new_minimum)
	current_value = clampi(current_value, minimum, maximum)
	_sync_view()
	if emit_change and old_value != current_value:
		value_changed.emit(current_value)


func set_value(new_value: int, emit_change := true) -> bool:
	var clamped := clampi(new_value, minimum, maximum)
	if clamped == current_value:
		_sync_view()
		return false
	current_value = clamped
	_sync_view()
	if emit_change:
		value_changed.emit(current_value)
	return true


func get_value() -> int:
	return current_value


func grab_default_focus() -> void:
	if not _increase_button.disabled:
		_increase_button.grab_focus()
	elif not _decrease_button.disabled:
		_decrease_button.grab_focus()


func _on_decrease_pressed() -> void:
	if current_value <= minimum:
		boundary_pressed.emit(-1)
		return
	set_value(current_value - step_size)


func _on_increase_pressed() -> void:
	if current_value >= maximum:
		boundary_pressed.emit(1)
		return
	set_value(current_value + step_size)


func _sync_view() -> void:
	if not is_node_ready():
		return
	_caption_label.text = caption
	_value_label.text = "%d%s" % [current_value, value_suffix]
	_decrease_button.disabled = current_value <= minimum
	_increase_button.disabled = current_value >= maximum
	_caption_label.visible = not caption.is_empty()
