extends RefCounted
class_name EventChoiceRequest

enum ChoiceKind {
	确认,
	玩家,
	卡牌,
	格子,
	选项,
}

var request_id: int = 0
var requester: PlayerClass = null
var title: String = "事件选择"
var prompt: String = ""
var kind: ChoiceKind = ChoiceKind.选项
var options: Array = []
var option_labels: PackedStringArray = []
var optional: bool = false
var timeout_seconds: float = 15.0

func _init(
	p_requester: PlayerClass = null,
	p_prompt: String = "",
	p_options: Array = [],
	p_labels: PackedStringArray = PackedStringArray(),
	p_optional: bool = false,
	p_kind: ChoiceKind = ChoiceKind.选项
) -> void:
	requester = p_requester
	prompt = p_prompt
	options = p_options
	option_labels = p_labels
	optional = p_optional
	kind = p_kind
