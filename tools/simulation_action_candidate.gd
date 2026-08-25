extends RefCounted
class_name SimulationActionCandidate

enum Kind { END_ACTION, USE_FOOD, USE_RETAINED_EVENT, TILE_ACTION, BUY_FOOD, REFRESH_SHOP, BUY_FEIYI, SELL_FEIYI }

var kind: Kind
var value
var utility: float
var legal: bool

func _init(p_kind: Kind, p_value = null, p_utility: float = 0.0, p_legal: bool = true) -> void:
	kind = p_kind
	value = p_value
	utility = p_utility
	legal = p_legal
