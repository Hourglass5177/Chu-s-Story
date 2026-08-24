extends RefCounted
class_name ProfessionDrawRequest

var request_id: int = 0
var player: PlayerClass = null
var cards: Array = []
var deck_kind: StringName = &""
var source_name: String = ""
var source_description: String = ""
var timeout_seconds: float = 15.0


func _init(
	p_player: PlayerClass = null,
	p_cards: Array = [],
	p_deck_kind: StringName = &"",
	p_source_name: String = "",
	p_source_description: String = ""
) -> void:
	player = p_player
	cards = p_cards.duplicate()
	deck_kind = p_deck_kind
	source_name = p_source_name
	source_description = p_source_description
