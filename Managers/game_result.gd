class_name GameResult
extends RefCounted

## 一局游戏在正式结束瞬间的只读结果快照。

enum EndReason {
	SCORE_LIMIT,
	ELIMINATION_LIMIT,
	BOTH,
	SOLO_DEFEAT,
}

var _end_reason: EndReason = EndReason.SCORE_LIMIT
var _turn_number: int = 0
var _entries: Array[GameResultEntry] = []
var _winner_entries: Array[GameResultEntry] = []
var _target_score: int = SessionSetup.DEFAULT_TARGET_SCORE

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

var target_score: int:
	get:
		return _target_score

func _init(
	reason: EndReason = EndReason.SCORE_LIMIT,
	ended_turn: int = 0,
	result_entries: Array[GameResultEntry] = [],
	configured_target_score: int = SessionSetup.DEFAULT_TARGET_SCORE
) -> void:
	_end_reason = reason
	_turn_number = ended_turn
	_target_score = configured_target_score
	_entries.assign(result_entries)
	for entry: GameResultEntry in _entries:
		if entry.is_winner:
			_winner_entries.append(entry)

func get_reason_text() -> String:
	match _end_reason:
		EndReason.SCORE_LIMIT:
			return "达到%d分" % _target_score
		EndReason.ELIMINATION_LIMIT:
			return "累计淘汰2人"
		EndReason.BOTH:
			return "胜利条件达成"
		EndReason.SOLO_DEFEAT:
			return "精力耗尽"
		_:
			return "游戏结束"

static func is_valid_end_reason(value: int) -> bool:
	return value in [EndReason.SCORE_LIMIT, EndReason.ELIMINATION_LIMIT, EndReason.BOTH, EndReason.SOLO_DEFEAT]

static func _copy_entries(source: Array[GameResultEntry]) -> Array[GameResultEntry]:
	var copied: Array[GameResultEntry] = []
	copied.assign(source)
	return copied
