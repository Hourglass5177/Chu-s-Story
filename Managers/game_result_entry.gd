class_name GameResultEntry
extends RefCounted

## 单个玩家在游戏正式结束瞬间的只读结果快照。
## UI 不应继续读取 PlayerClass 的可变分数，以免结算动画期间出现漂移。

var _player_index: int = -1
var _player_name: String = ""
var _player_character: int = 0
var _portrait: Texture2D = null
var _alive: bool = true
var _score_breakdown: Dictionary = {}
var _achievements: Array = []
var _total_score: int = 0
var _rank: int = 0
var _is_winner: bool = false

var player_index: int:
	get:
		return _player_index

var player_name: String:
	get:
		return _player_name

var player_character: int:
	get:
		return _player_character

## 与 PlayerClass 的现有字段名保持只读兼容，便于结算 UI 直接复用职业映射。
var player_types: int:
	get:
		return _player_character

var portrait: Texture2D:
	get:
		return _portrait

var alive: bool:
	get:
		return _alive

var score_breakdown: Dictionary:
	get:
		return _score_breakdown.duplicate(true)

var achievements: Array:
	get:
		return _achievements.duplicate(true)

var total_score: int:
	get:
		return _total_score

var rank: int:
	get:
		return _rank

var is_winner: bool:
	get:
		return _is_winner

func _init(
	source_player: PlayerClass = null,
	breakdown: Dictionary = {},
	assigned_rank: int = 0,
	winner: bool = false
) -> void:
	if source_player != null:
		_player_index = source_player.player_index
		_player_name = source_player.player_name
		_player_character = int(source_player.player_types)
		_portrait = source_player.立绘精一
		_alive = source_player.alive
	_score_breakdown = breakdown.duplicate(true)
	_total_score = int(_score_breakdown.get("total_score", source_player.current_score if source_player != null else 0))
	_rank = assigned_rank
	_is_winner = winner
	var achievement_value: Variant = _score_breakdown.get(
		"achievements",
		_score_breakdown.get("owned_achievements", [])
	)
	if achievement_value is Array:
		for value: Variant in achievement_value as Array:
			if value is 成就牌:
				var card := value as 成就牌
				_achievements.append({
					"achievement_id": card.achievement_id,
					"card_name": card.card_name,
					"score_value": card.score_value,
					"description": card.description,
					"image_of_front": card.image_of_front,
				})
			elif value is Dictionary:
				_achievements.append((value as Dictionary).duplicate(true))
	_score_breakdown["achievements"] = _achievements.duplicate(true)
