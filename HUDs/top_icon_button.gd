extends TextureButton
class_name HUDTopIconButton

@onready var hover_mask: TextureRect = get_node_or_null("mask") as TextureRect

var _pointer_inside := false
var _keyboard_focused := false
var _direction_navigation_engaged := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if texture_normal != null:
		var bitmap := BitMap.new()
		bitmap.create_from_image_alpha(texture_normal.get_image())
		texture_click_mask = bitmap
	if hover_mask != null:
		hover_mask.texture = texture_normal
		hover_mask.hide()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		if _direction_navigation_engaged:
			_direction_navigation_engaged = false
			_refresh_mask()
		return
	if event.is_action_pressed("ui_left") \
		or event.is_action_pressed("ui_right") \
		or event.is_action_pressed("ui_up") \
		or event.is_action_pressed("ui_down"):
		_direction_navigation_engaged = true
		# 方向键处理完成后焦点才可能移动到当前按钮。
		call_deferred(&"_refresh_mask")


func _on_mouse_entered() -> void:
	_pointer_inside = true
	_refresh_mask()


func _on_mouse_exited() -> void:
	_pointer_inside = false
	_refresh_mask()


func _on_focus_entered() -> void:
	_keyboard_focused = true
	_refresh_mask()


func _on_focus_exited() -> void:
	_keyboard_focused = false
	_refresh_mask()


func _on_button_down() -> void:
	if hover_mask != null:
		hover_mask.show()
		hover_mask.modulate = Color(0.0, 0.0, 0.0, 0.7)


func _on_button_up() -> void:
	_refresh_mask()


func _refresh_mask() -> void:
	if hover_mask == null:
		return
	hover_mask.visible = _pointer_inside or (_keyboard_focused and _direction_navigation_engaged)
	hover_mask.modulate = Color(0.0, 0.0, 0.0, 0.4)
