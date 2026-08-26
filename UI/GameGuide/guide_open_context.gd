extends RefCounted
class_name GuideOpenContext

enum Source {
	MAIN_MENU,
	HUD,
	PHASE,
	MAP_SECTION,
	CARD,
	PROFESSION,
	SHOP,
	MARKET,
	SCORE,
}

var source: Source = Source.MAIN_MENU
var topic_id: StringName = &"guide_home"
var object_kind: StringName = &""
var object_id: StringName = &""
var return_focus: WeakRef = null
var return_scroll: WeakRef = null
var scroll_offset: Vector2 = Vector2.ZERO


func _init(
	p_source: Source = Source.MAIN_MENU,
	p_topic_id: StringName = &"guide_home",
	p_object_kind: StringName = &"",
	p_object_id: StringName = &"",
	p_return_focus: Control = null
) -> void:
	source = p_source
	topic_id = p_topic_id
	object_kind = p_object_kind
	object_id = p_object_id
	return_focus = weakref(p_return_focus) if p_return_focus != null else null
	_capture_scroll_state(p_return_focus)


func get_return_focus() -> Control:
	return return_focus.get_ref() as Control if return_focus != null else null


func restore_scroll_state() -> void:
	var scroll := return_scroll.get_ref() as ScrollContainer if return_scroll != null else null
	if scroll == null or not is_instance_valid(scroll):
		return
	scroll.scroll_horizontal = roundi(scroll_offset.x)
	scroll.scroll_vertical = roundi(scroll_offset.y)


func _capture_scroll_state(control: Control) -> void:
	var current: Node = control
	while current != null:
		if current is ScrollContainer:
			var scroll := current as ScrollContainer
			return_scroll = weakref(scroll)
			scroll_offset = Vector2(scroll.scroll_horizontal, scroll.scroll_vertical)
			return
		current = current.get_parent()
