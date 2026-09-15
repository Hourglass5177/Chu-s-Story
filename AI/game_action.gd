class_name GameAction
extends RefCounted

enum Kind { END_PHASE, MOVE, USE_FEIYI, USE_FOOD, USE_EVENT, COLLECT, WORK, OPEN_SHOP, BUY_FOOD, REFRESH_SHOP, CLOSE_SHOP, OPEN_MARKET, BUY_FEIYI, SELL_FEIYI, CLOSE_MARKET, INHERIT }

var kind: Kind
var actor: int
var target: int
var session: int
var epoch: int
var phase: int
var data: Dictionary

func _init(k: Kind = Kind.END_PHASE, p: int = -1, t: int = 0, details: Dictionary = {}) -> void:
	kind = k
	actor = p
	target = t
	data = details.duplicate(true)

func key() -> String:
	return "%d:%d:%d" % [actor, kind, target]

func copy() -> GameAction:
	var result := GameAction.new(kind, actor, target, data)
	result.session = session
	result.epoch = epoch
	result.phase = phase
	return result
