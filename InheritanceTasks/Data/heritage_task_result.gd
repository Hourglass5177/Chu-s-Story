class_name HeritageTaskResult
extends RefCounted

enum Status {
	SUCCESS,
	FAILURE,
	MANUAL_ABORT,
	TECHNICAL_ERROR,
	CANCELLED,
}

var status: Status = Status.CANCELLED
var task_id: StringName = &""
var reason: StringName = &""
var message: String = ""
var metrics: Dictionary = {}
var elapsed_seconds: float = 0.0


func _init(
		p_status: Status = Status.CANCELLED,
		p_task_id: StringName = &"",
		p_reason: StringName = &"",
		p_message: String = "",
		p_metrics: Dictionary = {}
) -> void:
	status = p_status
	task_id = p_task_id
	reason = p_reason
	message = p_message
	metrics = p_metrics.duplicate(true)


func is_success() -> bool:
	return status == Status.SUCCESS


static func success(
		p_task_id: StringName,
		p_metrics: Dictionary = {},
		p_message: String = "传承完成"
) -> HeritageTaskResult:
	return HeritageTaskResult.new(Status.SUCCESS, p_task_id, &"completed", p_message, p_metrics)


static func failure(
		p_task_id: StringName,
		p_reason: StringName = &"goal_not_met",
		p_message: String = "本次未能完成"
) -> HeritageTaskResult:
	return HeritageTaskResult.new(Status.FAILURE, p_task_id, p_reason, p_message)


static func manual_abort(
		p_task_id: StringName,
		p_message: String = "已退出传承任务"
) -> HeritageTaskResult:
	return HeritageTaskResult.new(Status.MANUAL_ABORT, p_task_id, &"manual_abort", p_message)


static func technical_error(
		p_task_id: StringName,
		p_reason: StringName,
		p_message: String
) -> HeritageTaskResult:
	return HeritageTaskResult.new(Status.TECHNICAL_ERROR, p_task_id, p_reason, p_message)


static func cancelled(
		p_task_id: StringName,
		p_reason: StringName = &"cancelled",
		p_message: String = "任务已取消"
) -> HeritageTaskResult:
	return HeritageTaskResult.new(Status.CANCELLED, p_task_id, p_reason, p_message)
