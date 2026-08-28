extends RefCounted

## 在独立 SubViewport 中按桌面系统的真实节奏驱动一次鼠标点击。
## mouse-down 与 mouse-up 之间必须经过帧和轻微位移，否则测试会掩盖
## BaseButton 因中途失焦而取消 press_attempt 的问题。

var _viewport: Viewport
var _tree: SceneTree
var _input_is_in_local_coords: bool


func _init(viewport: Viewport, tree: SceneTree) -> void:
	_viewport = viewport
	_tree = tree
	# 项目的根 Window 应用了全局 stretch transform；SubViewport 夹具则直接
	# 使用它自身的画布坐标。两者必须经过各自正确的 push_input 路径。
	_input_is_in_local_coords = viewport is Window


func hover(control: Control) -> Control:
	if not _is_usable(control):
		return null
	var position := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	motion.relative = Vector2(4.0, 2.0)
	motion.button_mask = 0
	_viewport.push_input(motion, _input_is_in_local_coords)
	await _tree.process_frame
	return _viewport.gui_get_hovered_control()


func click(control: Control, held_motion_delta := Vector2.ONE) -> Control:
	var hovered := await hover(control)
	if hovered != control:
		return hovered
	var position := control.get_global_rect().get_center()
	var pressed := InputEventMouseButton.new()
	pressed.button_index = MOUSE_BUTTON_LEFT
	pressed.position = position
	pressed.global_position = position
	pressed.pressed = true
	_viewport.push_input(pressed, _input_is_in_local_coords)
	await _tree.process_frame

	var release_position := position + held_motion_delta
	var held_motion := InputEventMouseMotion.new()
	held_motion.position = release_position
	held_motion.global_position = release_position
	held_motion.relative = held_motion_delta
	held_motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	_viewport.push_input(held_motion, _input_is_in_local_coords)
	await _tree.process_frame

	var released := InputEventMouseButton.new()
	released.button_index = MOUSE_BUTTON_LEFT
	released.position = release_position
	released.global_position = release_position
	released.pressed = false
	_viewport.push_input(released, _input_is_in_local_coords)
	await _tree.process_frame
	await _tree.process_frame
	return hovered


func _is_usable(control: Control) -> bool:
	return _viewport != null \
		and is_instance_valid(_viewport) \
		and control != null \
		and is_instance_valid(control) \
		and control.is_inside_tree()
