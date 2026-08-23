class_name GameResult
extends RefCounted

## 一局游戏在正式结束瞬间的只读结果快照。

enum EndReason {
	SCORE_LIMIT,
	ELIMINATION_LIMIT,
	BOTH,
}

var _end_reason: EndReason = EndReason.SCORE_LIMIT
var _turn_number: int = 0
var _entries: Array[GameResultEntry] = []
var _winner_entries: Array[GameResultEntry] = []

var end_reason: EndReason:
	get:
		return _end_reason

var turn_number: int:
	get:
		return _turn_number

var entries: Array[GameResultEntry]:
	get:
		return _copy_entries(_entries)

var winners: Array[GameResultEntry]:
	get:
		return _copy_entries(_winner_entries)

func _init(
	reason: EndReason = EndReason.SCORE_LIMIT,
	ended_turn: int = 0,
	result_entries: Array[GameResultEntry] = []
) -> void:
	_end_reason = reason
	_turn_number = ended_turn
	_entries.assign(result_entries)
	for entry: GameResultEntry in _entries:
		if entry.is_winner:
			_winner_entries.append(entry)

func get_reason_text() -> String:
	match _end_reason:
		EndReason.SCORE_LIMIT:
			return "达到20分"
		EndReason.ELIMINATION_LIMIT:
			return "累计淘汰2人"
		EndReason.BOTH:
			return "胜利条件达成"
		_:
			return "游戏结束"

static func is_valid_end_reason(value: int) -> bool:
	return value in [EndReason.SCORE_LIMIT, EndReason.ELIMINATION_LIMIT, EndReason.BOTH]

static func _copy_entries(source: Array[GameResultEntry]) -> Array[GameResultEntry]:
	var copied: Array[GameResultEntry] = []
	copied.assign(source)
	return copied
