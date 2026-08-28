class_name HeritageTaskUseCheck
extends RefCounted

var allowed: bool = false
var reason: StringName = &""
var message: String = ""


func _init(
		p_allowed: bool = false,
		p_reason: StringName = &"",
		p_message: String = ""
) -> void:
	allowed = p_allowed
	reason = p_reason
	message = p_message


static func allow(p_message: String = "") -> HeritageTaskUseCheck:
	return HeritageTaskUseCheck.new(true, &"allowed", p_message)


static func deny(p_reason: StringName, p_message: String) -> HeritageTaskUseCheck:
	return HeritageTaskUseCheck.new(false, p_reason, p_message)
