extends RefCounted
class_name ProfessionSectionChoiceRequest

var request_id: int = 0
var player: PlayerClass = null
var options: Array[MapSection] = []
var source_name: String = ""
var source_description: String = ""
var timeout_seconds: float = 15.0
var optional: bool = true


func _init(
	p_player: PlayerClass = null,
	p_options: Array[MapSection] = [],
	p_source_name: String = "",
	p_source_description: String = ""
) -> void:
	player = p_player
	options.assign(p_options)
	source_name = p_source_name
	source_description = p_source_description
