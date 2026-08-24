extends RefCounted
class_name EventChoiceRequest

enum ChoiceKind {
	确认,
	玩家,
	卡牌,
	格子,
	选项,
}

enum Presentation {
	默认,
	地图,
	研究所,
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
var source_name: String = ""
var source_description: String = ""
var presentation: Presentation = Presentation.默认
var multiple: bool = false
var min_selections: int = 0
var max_selections: int = 1
## 食物等外部系统只借用单次选择器，不会发出事件完整结算的
## interaction_finished；这类请求在提交后必须自行关闭事件遮罩。
var close_overlay_on_resolve: bool = false

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
